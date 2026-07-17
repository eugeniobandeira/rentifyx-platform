output "role_arn" {
  value       = aws_iam_role.github_ci.arn
  description = "ARN to configure as the AWS_DEPLOY_ROLE_ARN GitHub secret."
}
