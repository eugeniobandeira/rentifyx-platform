module "github_actions_oidc" {
  source = "./modules/github-actions-oidc"

  prefix                  = "${var.project}-${var.environment}"
  github_repo             = var.github_repo
  create_oidc_provider    = var.create_github_oidc_provider
  state_bucket            = var.state_bucket
  state_bucket_key_prefix = "platform/"
  dynamodb_lock_table     = var.dynamodb_table
}

module "network" {
  source = "./modules/network"

  project     = var.project
  environment = var.environment
  aws_region  = var.aws_region
}

# EKS was removed 2026-07-17: nothing in this platform actually needs a
# Kubernetes cluster. rentifyx-identity-api deploys via its own EC2 module
# (not EKS), rentifyx-communications-api has no IaC yet, and Kafka now runs
# self-hosted (module.kafka - single EC2, KRaft, see
# .specs/features/self-hosted-kafka/) instead of Strimzi-on-EKS or MSK
# Serverless (both tried and replaced, in that order). If a real K8s
# workload need shows up later, re-add a dedicated module rather than
# reviving this one from git history - the old node-group/Strimzi/Helm
# setup was scoped around Kafka specifically, not general-purpose.

module "kafka" {
  source = "./modules/kafka"

  project         = var.project
  environment     = var.environment
  vpc_id          = module.network.vpc_id
  private_subnets = module.network.private_subnets
  vpc_cidr        = module.network.vpc_cidr
}

# Cross-repo, read-only: identity-api and communications-api each own their
# EC2 instance in their own Terraform state (this platform repo doesn't
# provision either). try() because ec2_public_dns is null whenever that
# repo's enable_ec2 = false, or the key doesn't exist yet if that repo has
# never been applied - same pattern identity-api itself uses to read this
# repo's outputs (see its main.tf kafka_ssm_parameter_path).
data "terraform_remote_state" "identity_api" {
  backend = "s3"

  config = {
    bucket = "rentifyx-tfstate-166613156216"
    key    = "identity-api/terraform.tfstate"
    region = "us-east-1"
  }
}

data "terraform_remote_state" "communications_api" {
  backend = "s3"

  config = {
    bucket = "rentifyx-tfstate-166613156216"
    key    = "communications-api/terraform.tfstate"
    region = "us-east-1"
  }
}

data "terraform_remote_state" "asset_registry_api" {
  backend = "s3"

  config = {
    bucket = "rentifyx-tfstate-166613156216"
    key    = "asset-registry-api/terraform.tfstate"
    region = "us-east-1"
  }
}

locals {
  identity_api_dns       = try(data.terraform_remote_state.identity_api.outputs.ec2_public_dns, null)
  communications_api_dns = try(data.terraform_remote_state.communications_api.outputs.ec2_public_dns, null)
  asset_registry_api_dns = try(data.terraform_remote_state.asset_registry_api.outputs.ec2_public_dns, null)
}

module "api_gateway" {
  source = "./modules/api-gateway"

  project                = var.project
  environment            = var.environment
  aws_region             = var.aws_region
  vpc_id                 = module.network.vpc_id
  subnet_ids             = module.network.private_subnets
  identity_api_uri       = local.identity_api_dns != null ? "http://${local.identity_api_dns}:8080" : ""
  communications_api_uri = local.communications_api_dns != null ? "http://${local.communications_api_dns}:8080" : ""
  asset_registry_api_uri = local.asset_registry_api_dns != null ? "http://${local.asset_registry_api_dns}:8080" : ""
}

module "cognito" {
  source = "./modules/cognito"

  project     = var.project
  environment = var.environment
  aws_region  = var.aws_region
}

module "ses" {
  source = "./modules/ses"

  ses_identity = var.ses_identity
}

module "observability" {
  source = "./modules/observability"

  project     = var.project
  environment = var.environment
  aws_region  = var.aws_region
}
