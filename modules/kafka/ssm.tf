resource "aws_ssm_parameter" "kafka_bootstrap_servers" {
  name        = "/rentifyx/platform/kafka/bootstrap-servers"
  description = "Self-hosted Kafka PLAINTEXT bootstrap address for rentifyx-identity-api and rentifyx-communications-api"
  type        = "SecureString"
  key_id      = "alias/aws/ssm"
  value       = "${aws_instance.kafka.private_ip}:9092"
}
