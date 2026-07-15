resource "aws_cloudwatch_log_group" "otel" {
  name              = "/rentifyx/${var.project}/${var.environment}/otel"
  retention_in_days = 14
}
