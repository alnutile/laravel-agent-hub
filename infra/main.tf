terraform {
  required_version = ">= 1.10, < 2.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
  backend "s3" {}
}
provider "aws" {
  region = var.region
  default_tags { tags = { Project = "agent-hub", ManagedBy = "Terraform" } }
}
variable "region" { type = string }
variable "vpc_id" { type = string }
variable "subnet_id" {
  type        = string
  description = "Existing private subnet with outbound HTTPS/NAT for package installs, ECR, SSM and Secrets Manager."
}
variable "instance_type" { default = "t3.small" }
data "aws_ssm_parameter" "ami" { name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64" }
resource "aws_ecr_repository" "hub" {
  name                 = "agent-hub"
  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration { scan_on_push = true }
  encryption_configuration { encryption_type = "AES256" }
}
resource "aws_secretsmanager_secret" "runtime" {
  name                    = "agent-hub/runtime"
  recovery_window_in_days = 7
  # Populate the value outside Terraform. Never create a secret_version here.
}
resource "aws_cloudwatch_log_group" "hub" {
  name              = "/agent-hub/runtime"
  retention_in_days = 14
}
resource "aws_security_group" "hub" {
  name   = "agent-hub-private"
  vpc_id = var.vpc_id
  # No inbound rules. Pilot access is through SSM port forwarding.
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
resource "aws_iam_role" "host" {
  name               = "agent-hub-host"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" }, Action = "sts:AssumeRole" }] })
}
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.host.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
resource "aws_iam_role_policy" "runtime" {
  role = aws_iam_role.host.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = ["ecr:GetAuthorizationToken"], Resource = "*" },
    { Effect = "Allow", Action = ["ecr:BatchCheckLayerAvailability", "ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage"], Resource = aws_ecr_repository.hub.arn },
    { Effect = "Allow", Action = ["secretsmanager:GetSecretValue"], Resource = aws_secretsmanager_secret.runtime.arn },
    { Effect = "Allow", Action = ["logs:CreateLogStream", "logs:PutLogEvents"], Resource = "${aws_cloudwatch_log_group.hub.arn}:*" }
  ] })
}
resource "aws_iam_instance_profile" "host" {
  name = "agent-hub-host"
  role = aws_iam_role.host.name
}
resource "aws_instance" "hub" {
  ami                         = data.aws_ssm_parameter.ami.value
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [aws_security_group.hub.id]
  associate_public_ip_address = false
  iam_instance_profile        = aws_iam_instance_profile.host.name
  metadata_options { http_tokens = "required" }
  root_block_device {
    volume_size           = 30
    encrypted             = true
    delete_on_termination = false
  }
  user_data_replace_on_change = true
  user_data                   = <<-EOF
    #!/bin/bash
    set -euo pipefail
    dnf install -y docker
    systemctl enable --now docker
    systemctl enable --now amazon-ssm-agent
  EOF
  tags                        = { Name = "agent-hub-poc" }
  lifecycle { prevent_destroy = true }
}
output "instance_id" { value = aws_instance.hub.id }
output "ecr_url" { value = aws_ecr_repository.hub.repository_url }
output "runtime_secret_arn" { value = aws_secretsmanager_secret.runtime.arn }
output "log_group" { value = aws_cloudwatch_log_group.hub.name }
