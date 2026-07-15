output "bootstrap_servers" {
  value = local.kafka_bootstrap_servers
}

output "ssm_parameter_path" {
  value = aws_ssm_parameter.kafka_bootstrap_servers.name
}
