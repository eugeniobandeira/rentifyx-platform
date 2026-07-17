resource "aws_ssm_parameter" "kafka_bootstrap_servers" {
  name        = "/rentifyx/platform/kafka/bootstrap-servers"
  description = "MSK Serverless SASL/IAM bootstrap address for rentifyx-identity-api and rentifyx-communications-api"
  type        = "SecureString"
  key_id      = "alias/aws/ssm"
  value       = aws_msk_serverless_cluster.this.bootstrap_brokers_sasl_iam
}
