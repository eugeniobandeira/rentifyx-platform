variable "aws_region" {
  type        = string
  description = "AWS region where resources will be created."
}

variable "project" {
  type        = string
  description = "Project name used for tags and naming."
}

variable "environment" {
  type        = string
  description = "Environment name (prod)."
}

variable "state_bucket" {
  type        = string
  description = "S3 bucket name for Terraform state."
}

variable "dynamodb_table" {
  type        = string
  description = "DynamoDB table name for Terraform state locking."
}

variable "github_repo" {
  type        = string
  description = "GitHub repo (\"owner/repo\") allowed to assume the CI OIDC role."
  default     = "eugeniobandeira/rentifyx-platform"
}

variable "create_github_oidc_provider" {
  type        = bool
  description = <<-EOT
    Whether this repo's Terraform should create the shared
    token.actions.githubusercontent.com OIDC provider. AWS allows only one
    per account - if rentifyx-identity-api's own github-actions module was
    applied first, set this to false so platform reuses the existing
    provider instead of failing with EntityAlreadyExists.
  EOT
  default     = true
}

variable "eks_public_access_cidrs" {
  type        = list(string)
  description = "CIDR blocks allowed to reach the EKS public API endpoint. No default - must be set explicitly (e.g. in terraform.tfvars, gitignored) to avoid an accidental 0.0.0.0/0."
}

variable "kubeconfig_path" {
  type        = string
  description = "Path to kubeconfig for Kubernetes/Helm providers."
  default     = "~/.kube/config"
}
