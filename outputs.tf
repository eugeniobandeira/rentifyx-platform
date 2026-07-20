# Consumed by rentifyx-identity-api/rentifyx-communications-api via
# terraform_remote_state, so each service's own IaC can attach the Kafka
# client policy to its own runtime IAM role without this repo needing to
# know anything about those roles.
output "kafka_client_iam_policy_json" {
  value       = module.kafka.client_iam_policy_json
  description = "Attach to a consumer/producer service's own IAM role to grant MSK access."
}

output "kafka_cluster_arn" {
  value = module.kafka.cluster_arn
}

output "kafka_ssm_parameter_path" {
  value = module.kafka.ssm_parameter_path
}

# Consumed by rentifyx-identity-api/rentifyx-communications-api via
# terraform_remote_state - one shared SES sender identity instead of each
# app repo owning its own colliding aws_sesv2_email_identity.
output "ses_identity_arn" {
  value       = module.ses.identity_arn
  description = "ARN of the shared SES email identity."
}

# Consumed by rentifyx-identity-api/rentifyx-communications-api via
# terraform_remote_state - their EC2 instances need to live in this VPC to
# reach the MSK Serverless cluster (its DNS/network is VPC-internal only).
output "vpc_id" {
  value       = module.network.vpc_id
  description = "VPC ID - app repos' EC2 instances must be provisioned here to reach MSK."
}

output "public_subnets" {
  value       = module.network.public_subnets
  description = "Public subnet IDs - app repos' EC2 instances go here (internet-facing, same VPC as MSK)."
}
