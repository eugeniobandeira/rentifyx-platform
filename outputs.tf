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
