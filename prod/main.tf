module "network" {
  source = "../modules/network"

  project     = var.project
  environment = var.environment
  aws_region  = var.aws_region
}

module "eks" {
  source = "../modules/eks"

  project         = var.project
  environment     = var.environment
  aws_region      = var.aws_region
  vpc_id          = module.network.vpc_id
  private_subnets = module.network.private_subnets
}

module "kafka" {
  source = "../modules/kafka"

  project         = var.project
  environment     = var.environment
  aws_region      = var.aws_region
  cluster_name    = module.eks.cluster_name
  vpc_id          = module.network.vpc_id
  private_subnets = module.network.private_subnets
}

module "api_gateway" {
  source = "../modules/api-gateway"

  project     = var.project
  environment = var.environment
  aws_region  = var.aws_region
  vpc_id      = module.network.vpc_id
  subnet_ids  = module.network.private_subnets
}

module "cognito" {
  source = "../modules/cognito"

  project     = var.project
  environment = var.environment
  aws_region  = var.aws_region
}

module "observability" {
  source = "../modules/observability"

  project      = var.project
  environment  = var.environment
  aws_region   = var.aws_region
  cluster_name = module.eks.cluster_name
}
