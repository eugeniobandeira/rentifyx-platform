output "ssm_parameter_path" {
  value = aws_ssm_parameter.kafka_bootstrap_servers.name
}

output "broker_instance_id" {
  value = aws_instance.kafka.id
}
