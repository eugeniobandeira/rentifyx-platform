variable "prefix" {
  type        = string
  description = "Prefix for naming the IAM role (e.g. project-environment)."
}

variable "github_repo" {
  type        = string
  description = "GitHub repo allowed to assume this role, as \"owner/repo\"."
}

variable "create_oidc_provider" {
  type        = bool
  description = <<-EOT
    AWS allows only one IAM OIDC provider per account per issuer URL.
    rentifyx-identity-api's own iac/terraform/modules/github-actions module
    also creates a token.actions.githubusercontent.com provider - if that
    one was ever applied first, set this to false so this module looks up
    the existing provider instead of trying to create a duplicate (which
    would fail with EntityAlreadyExists).
  EOT
  default     = true
}

variable "state_bucket" {
  type        = string
  description = "S3 bucket holding Terraform state, for the CI role's backend access."
}

variable "state_bucket_key_prefix" {
  type        = string
  description = "Key prefix within the state bucket this role may read/write (e.g. \"platform/\")."
}

variable "dynamodb_lock_table" {
  type        = string
  description = "DynamoDB table used for Terraform state locking."
}
