output "api_id" {
  value = aws_apigatewayv2_api.http_api.id
}

output "api_endpoint" {
  description = "Invoke URL for the $default stage"
  value       = aws_apigatewayv2_stage.default.invoke_url
}
