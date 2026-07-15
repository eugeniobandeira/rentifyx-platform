resource "aws_apigatewayv2_api" "http_api" {
  name          = "${var.project}-${var.environment}-http-api"
  protocol_type = "HTTP"
}
