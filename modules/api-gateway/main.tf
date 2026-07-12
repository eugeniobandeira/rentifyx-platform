resource "aws_apigatewayv2_api" "http_api" {
  name          = "${var.project}-${var.environment}-http-api"
  protocol_type = "HTTP"
}

output "api_id" {
  value = aws_apigatewayv2_api.http_api.id
}
