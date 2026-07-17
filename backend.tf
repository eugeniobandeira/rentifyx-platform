terraform {
  # Terraform disallows variable references inside a backend block - it must
  # be resolvable before any variables are read, so this can't use
  # var.state_bucket etc. Shared state bucket/lock table across all
  # rentifyx-* repos, verified against real AWS under the rentifyx-admin
  # profile (account 166613156216 - the account this project is actually
  # standardizing on; a separate, now-decommissioned account
  # (480831398199) had a differently-named bucket that was a red herring,
  # corrected 2026-07-17):
  # bucket "rentifyx-tfstate-166613156216" (already holds
  # identity-api/terraform.tfstate), lock table "rentifyx-tflock". This is
  # foundational shared infra, not specific to one service, so platform is
  # the canonical place its name is documented. terraform.tfvars.example's
  # state_bucket/dynamodb_table values ("rentifyx-platform-tfstate" /
  # "rentifyx-tf-locks") don't exist in AWS - stale/aspirational, not the
  # real resource.
  backend "s3" {
    bucket         = "rentifyx-tfstate-166613156216"
    key            = "platform/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "rentifyx-tflock"
    encrypt        = true
  }
}
