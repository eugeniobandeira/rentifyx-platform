# Consumed by rentifyx-identity-api/rentifyx-communications-api via
# terraform_remote_state to resolve the broker's bootstrap address. No IAM
# policy output anymore - the self-hosted broker (see
# .specs/features/self-hosted-kafka/) uses PLAINTEXT, nothing to grant access
# to.
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
# reach the self-hosted Kafka broker (its private IP is VPC-internal only).
output "vpc_id" {
  value       = module.network.vpc_id
  description = "VPC ID - app repos' EC2 instances must be provisioned here to reach the Kafka broker."
}

output "public_subnets" {
  value       = module.network.public_subnets
  description = "Public subnet IDs - app repos' EC2 instances go here (internet-facing, same VPC as the Kafka broker)."
}
