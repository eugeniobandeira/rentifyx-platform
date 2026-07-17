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

module "eks" {
  source = "./modules/eks"

  project                 = var.project
  environment             = var.environment
  aws_region              = var.aws_region
  vpc_id                  = module.network.vpc_id
  private_subnets         = module.network.private_subnets
  eks_public_access_cidrs = var.eks_public_access_cidrs
}

module "kafka" {
  source = "./modules/kafka"

  project         = var.project
  environment     = var.environment
  aws_region      = var.aws_region
  cluster_name    = module.eks.cluster_name
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

module "observability" {
  source = "./modules/observability"

  project      = var.project
  environment  = var.environment
  aws_region   = var.aws_region
  cluster_name = module.eks.cluster_name
}
