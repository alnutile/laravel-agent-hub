# One-time account-admin bootstrap. Application deployment remains in Actions.
terraform {
  required_version = ">= 1.10, < 2.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
}
provider "aws" {
  region              = "us-east-1"
  allowed_account_ids = ["415017828442"]
  default_tags { tags = { Project = "agent-hub", ManagedBy = "Terraform" } }
}
locals {
  account = "415017828442"
  region  = "us-east-1"
  subject = "repo:alnutile@365385/laravel-agent-hub@1430214342:ref:refs/heads/main"
  bucket  = "agent-hub-tfstate-${local.account}-${local.region}"
  roles = [
    "arn:aws:iam::${local.account}:role/agent-hub-host",
    "arn:aws:iam::${local.account}:role/agent-hub-github-deploy"
  ]
}
resource "aws_s3_bucket" "state" {
  bucket = local.bucket
  lifecycle { prevent_destroy = true }
}
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration { status = "Enabled" }
}
resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}
resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect    = "Deny", Principal = "*", Action = "s3:*",
    Resource  = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"],
    Condition = { Bool = { "aws:SecureTransport" = "false" } }
  }] })
}
resource "aws_vpc" "hub" {
  cidr_block           = "10.87.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "agent-hub" }
}
resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.hub.id
  cidr_block        = "10.87.0.0/24"
  availability_zone = "us-east-1a"
  tags              = { Name = "agent-hub-nat" }
}
resource "aws_subnet" "private" {
  vpc_id                  = aws_vpc.hub.id
  cidr_block              = "10.87.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = false
  tags                    = { Name = "agent-hub-private" }
}
resource "aws_internet_gateway" "hub" {
  vpc_id = aws_vpc.hub.id
}
resource "aws_eip" "nat" { domain = "vpc" }
resource "aws_nat_gateway" "hub" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id
  depends_on    = [aws_internet_gateway.hub]
}
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.hub.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.hub.id
  }
}
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.hub.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.hub.id
  }
}
resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}
resource "aws_iam_role" "provisioner" {
  name = "agent-hub-terraform-provisioner"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect    = "Allow", Action = "sts:AssumeRoleWithWebIdentity",
    Principal = { Federated = "arn:aws:iam::${local.account}:oidc-provider/token.actions.githubusercontent.com" },
    Condition = { StringEquals = {
      "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com",
      "token.actions.githubusercontent.com:sub" = local.subject
    } }
  }] })
}
resource "aws_iam_role_policy" "provisioner" {
  role = aws_iam_role.provisioner.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = ["sts:GetCallerIdentity", "ec2:Describe*"], Resource = "*" },
    { Effect = "Allow", Action = ["ssm:GetParameter"], Resource = "arn:aws:ssm:${local.region}::parameter/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64" },
    # Backend initialization enumerates workspace prefixes as well as the state key.
    # Listing this dedicated bucket reveals keys only; object reads stay scoped below.
    { Effect = "Allow", Action = ["s3:ListBucket"], Resource = aws_s3_bucket.state.arn },
    { Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject"], Resource = ["${aws_s3_bucket.state.arn}/agent-hub/poc.tfstate", "${aws_s3_bucket.state.arn}/agent-hub/poc.tfstate.tflock"] },
    { Effect = "Allow", Action = ["s3:DeleteObject"], Resource = "${aws_s3_bucket.state.arn}/agent-hub/poc.tfstate.tflock" },
    { Effect = "Allow", Action = ["iam:CreateRole", "iam:GetRole", "iam:DeleteRole", "iam:UpdateAssumeRolePolicy", "iam:TagRole", "iam:UntagRole", "iam:ListRolePolicies", "iam:ListAttachedRolePolicies", "iam:GetRolePolicy", "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:ListInstanceProfilesForRole"], Resource = local.roles },
    { Effect = "Allow", Action = ["iam:AttachRolePolicy", "iam:DetachRolePolicy"], Resource = local.roles[0], Condition = { ArnEquals = { "iam:PolicyARN" = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore" } } },
    { Effect = "Allow", Action = ["iam:CreateInstanceProfile", "iam:GetInstanceProfile", "iam:DeleteInstanceProfile", "iam:AddRoleToInstanceProfile", "iam:RemoveRoleFromInstanceProfile", "iam:TagInstanceProfile", "iam:UntagInstanceProfile"], Resource = "arn:aws:iam::${local.account}:instance-profile/agent-hub-host" },
    { Effect = "Allow", Action = ["iam:PassRole"], Resource = local.roles[0], Condition = { StringEquals = { "iam:PassedToService" = "ec2.amazonaws.com" } } },
    { Effect = "Allow", Action = ["ecr:CreateRepository", "ecr:DescribeRepositories", "ecr:DeleteRepository", "ecr:ListTagsForResource", "ecr:TagResource", "ecr:UntagResource", "ecr:PutImageTagMutability", "ecr:PutImageScanningConfiguration"], Resource = "arn:aws:ecr:${local.region}:${local.account}:repository/agent-hub" },
    { Effect = "Allow", Action = ["secretsmanager:CreateSecret", "secretsmanager:DescribeSecret", "secretsmanager:DeleteSecret", "secretsmanager:RestoreSecret", "secretsmanager:TagResource", "secretsmanager:UntagResource", "secretsmanager:UpdateSecret"], Resource = "arn:aws:secretsmanager:${local.region}:${local.account}:secret:agent-hub/runtime-??????" },
    { Effect = "Allow", Action = ["logs:DescribeLogGroups"], Resource = "*" },
    { Effect = "Allow", Action = ["logs:CreateLogGroup", "logs:DeleteLogGroup", "logs:PutRetentionPolicy", "logs:DeleteRetentionPolicy", "logs:ListTagsForResource", "logs:TagResource", "logs:UntagResource"], Resource = ["arn:aws:logs:${local.region}:${local.account}:log-group:/agent-hub/runtime", "arn:aws:logs:${local.region}:${local.account}:log-group:/agent-hub/runtime:*"] },
    { Effect = "Allow", Action = ["ec2:CreateSecurityGroup"], Resource = aws_vpc.hub.arn },
    { Effect = "Allow", Action = ["ec2:CreateSecurityGroup"], Resource = "arn:aws:ec2:${local.region}:${local.account}:security-group/*", Condition = { StringEquals = { "aws:RequestTag/Project" = "agent-hub" } } },
    { Effect = "Allow", Action = ["ec2:RunInstances"], Resource = ["arn:aws:ec2:${local.region}::image/*", "arn:aws:ec2:${local.region}:${local.account}:network-interface/*", "arn:aws:ec2:${local.region}:${local.account}:volume/*", "arn:aws:ec2:${local.region}:${local.account}:security-group/*", aws_subnet.private.arn] },
    { Effect = "Allow", Action = ["ec2:RunInstances"], Resource = "arn:aws:ec2:${local.region}:${local.account}:instance/*", Condition = { StringEquals = { "aws:RequestTag/Project" = "agent-hub" } } },
    { Effect = "Allow", Action = ["ec2:CreateTags"], Resource = ["arn:aws:ec2:${local.region}:${local.account}:instance/*", "arn:aws:ec2:${local.region}:${local.account}:volume/*", "arn:aws:ec2:${local.region}:${local.account}:security-group/*"], Condition = { StringEquals = { "ec2:CreateAction" = ["RunInstances", "CreateSecurityGroup"] } } },
    { Effect = "Allow", Action = ["ec2:CreateTags", "ec2:DeleteTags", "ec2:TerminateInstances", "ec2:StopInstances", "ec2:StartInstances", "ec2:ModifyInstanceAttribute", "ec2:ModifyInstanceMetadataOptions", "ec2:AuthorizeSecurityGroupEgress", "ec2:RevokeSecurityGroupEgress", "ec2:DeleteSecurityGroup"], Resource = ["arn:aws:ec2:${local.region}:${local.account}:instance/*", "arn:aws:ec2:${local.region}:${local.account}:security-group/*"], Condition = { StringEquals = { "ec2:ResourceTag/Project" = "agent-hub" } } }
  ] })
}
output "region" { value = local.region }
output "state_bucket" { value = aws_s3_bucket.state.id }
output "vpc_id" { value = aws_vpc.hub.id }
output "subnet_id" { value = aws_subnet.private.id }
output "terraform_role_arn" { value = aws_iam_role.provisioner.arn }
output "github_oidc_subject" { value = local.subject }
