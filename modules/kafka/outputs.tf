output "bootstrap_servers" {
  value     = aws_msk_serverless_cluster.this.bootstrap_brokers_sasl_iam
  sensitive = true
}

output "ssm_parameter_path" {
  value = aws_ssm_parameter.kafka_bootstrap_servers.name
}

output "cluster_arn" {
  value = aws_msk_serverless_cluster.this.arn
}

output "client_iam_policy_json" {
  description = "Attach to a consumer/producer service's own IAM role (in its own repo) to grant MSK access."
  value       = data.aws_iam_policy_document.kafka_client.json
}
