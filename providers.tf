provider "aws" {
  region = var.aws_region
}

# MSK Serverless has no console/API topic management (Serverless clusters
# are explicitly unsupported by "Topic management" in the AWS Console) -
# topic creation has to go over the Kafka protocol itself, SASL/IAM
# authenticated. This provider uses the same AWS credentials as the aws
# provider above (default credential chain - instance role when applied
# from inside the VPC, named profile locally).
#
# The broker's DNS is VPC-private only (see rentifyx-platform ADR-002),
# so `terraform apply` for module.kafka_topics must run from somewhere
# with network access to it - not a laptop outside the VPC. See
# modules/kafka-topics/main.tf for the full explanation.
provider "kafka" {
  bootstrap_servers = [module.kafka.bootstrap_servers]
  tls_enabled       = true
  sasl_mechanism    = "aws-iam"
}
