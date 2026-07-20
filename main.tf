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
# on MSK Serverless (module.kafka) instead of Strimzi-on-EKS. If a real K8s
# workload need shows up later, re-add a dedicated module rather than
# reviving this one from git history - the old node-group/Strimzi/Helm
# setup was scoped around Kafka specifically, not general-purpose.

module "kafka" {
  source = "./modules/kafka"

  project         = var.project
  environment     = var.environment
  aws_region      = var.aws_region
  vpc_id          = module.network.vpc_id
  private_subnets = module.network.private_subnets
}

module "api_gateway" {
  source = "./modules/api-gateway"

  project     = var.project
  environment = var.environment
  aws_region  = var.aws_region
  vpc_id      = module.network.vpc_id
  subnet_ids  = module.network.private_subnets
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
