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
  description = <<-EOT
    CIDR blocks allowed to reach the EKS public API endpoint. Defaults to
    loopback only (127.0.0.1/32) - deliberately non-functional. Override in
    terraform.tfvars (gitignored) with your real IP(s). Never 0.0.0.0/0.
  EOT
  default     = ["127.0.0.1/32"]
}

variable "kubeconfig_path" {
  type        = string
  description = "Path to kubeconfig for Kubernetes/Helm providers."
  default     = "~/.kube/config"
}
