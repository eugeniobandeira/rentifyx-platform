terraform {
  # Terraform disallows variable references inside a backend block - it must
  # be resolvable before any variables are read, so this can't use
  # var.state_bucket etc. Shared state bucket/lock table across all
  # rentifyx-* repos, verified against real AWS (aws s3 ls / dynamodb
  # list-tables under the rentifyx-admin account) 2026-07-17:
  # bucket "rentifyx-tfstate" (holds identity-api/terraform.tfstate today),
  # lock table "rentifyx-tflock". This is foundational shared infra, not
  # specific to one service, so platform is the canonical place its name is
  # documented. terraform.tfvars.example's state_bucket/dynamodb_table
  # values ("rentifyx-platform-tfstate" / "rentifyx-tf-locks") don't exist in
  # AWS - stale/aspirational, not the real resource.
  backend "s3" {
    bucket         = "rentifyx-tfstate"
    key            = "platform/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "rentifyx-tflock"
    encrypt        = true
  }
}
