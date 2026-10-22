variable "github_oidc_subject" {
  type        = string
  description = "Exact GitHub OIDC sub for this repository's main branch; verify the claim format for your repository."
  validation {
    condition     = endswith(var.github_oidc_subject, ":ref:refs/heads/main") && startswith(var.github_oidc_subject, "repo:alnutile") && !strcontains(var.github_oidc_subject, "*")
    error_message = "Use the exact main-branch subject, without wildcards."
  }
}
data "aws_caller_identity" "current" {}
locals {
  oidc_provider_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"
}
resource "aws_iam_role" "deploy" {
  name = "agent-hub-github-deploy"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect = "Allow", Principal = { Federated = local.oidc_provider_arn }, Action = "sts:AssumeRoleWithWebIdentity",
    Condition = { StringEquals = {
      "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com",
      "token.actions.githubusercontent.com:sub" = var.github_oidc_subject
    } }
  }] })
}
resource "aws_iam_role_policy" "deploy" {
  role = aws_iam_role.deploy.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = ["ecr:GetAuthorizationToken"], Resource = "*" },
    { Effect = "Allow", Action = ["ecr:BatchCheckLayerAvailability", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart", "ecr:CompleteLayerUpload", "ecr:PutImage", "ecr:DescribeImages"], Resource = aws_ecr_repository.hub.arn },
    { Effect = "Allow", Action = ["ssm:SendCommand"], Resource = [aws_instance.hub.arn, "arn:aws:ssm:${var.region}::document/AWS-RunShellScript"] },
    { Effect = "Allow", Action = ["ssm:GetCommandInvocation"], Resource = "*" }
  ] })
}
output "deploy_role_arn" { value = aws_iam_role.deploy.arn }
