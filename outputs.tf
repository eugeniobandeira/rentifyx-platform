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

# Confirmed the hard way against real AWS 2026-07-24: a VPC-attached Lambda
# placed in a public subnet gets ZERO internet egress - Lambda ENIs never
# get a public IP regardless of the subnet's IGW route, so every AWS public
# API call (DynamoDB, Rekognition, SQS, Bedrock) timed out, while the
# same-VPC Kafka broker (private IP) was at least reachable. Private
# subnets route through the NAT gateway module.network already creates -
# app repos' Lambdas belong here, not in public_subnets.
output "private_subnets" {
  value       = module.network.private_subnets
  description = "Private subnet IDs (NAT egress) - VPC-attached Lambdas in app repos go here, not public_subnets, since Lambda ENIs never get a public IP."
}

output "api_gateway_endpoint" {
  value       = module.api_gateway.api_endpoint
  description = "Public invoke URL for the shared HTTP API Gateway. Routes: /identity/{proxy+}, /communications/{proxy+} (asset-registry-api pending deploy)."
}
