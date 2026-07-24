resource "aws_apigatewayv2_api" "http_api" {
  name          = "${var.project}-${var.environment}-http-api"
  protocol_type = "HTTP"
}

# Pass-through routing only: this gateway does not validate JWTs or API keys.
# Each backend service still enforces its own auth (identity-api = JWT,
# communications-api = API key). Centralizing auth here would require
# identity-api to expose a JWKS endpoint first (it currently only holds an
# RS256 PEM key in Secrets Manager) - deferred until that exists.
#
# Integrations point directly at each service's public EC2 DNS (no VPC
# Link/NLB): both services run as a single public-subnet EC2 instance today,
# so a private VPC Link would need a new NLB + target group per service
# before it could work. Revisit once either service moves behind a real
# load balancer.

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http_api.id
  name        = "$default"
  auto_deploy = true
}

# --- identity-api -----------------------------------------------------

resource "aws_apigatewayv2_integration" "identity_api" {
  count = var.identity_api_uri != "" ? 1 : 0

  api_id                 = aws_apigatewayv2_api.http_api.id
  integration_type       = "HTTP_PROXY"
  integration_method     = "ANY"
  integration_uri        = "${var.identity_api_uri}/{proxy}"
  payload_format_version = "1.0"
}

resource "aws_apigatewayv2_route" "identity_api" {
  count = var.identity_api_uri != "" ? 1 : 0

  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "ANY /identity/{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.identity_api[0].id}"
}

# --- communications-api -------------------------------------------------

resource "aws_apigatewayv2_integration" "communications_api" {
  count = var.communications_api_uri != "" ? 1 : 0

  api_id                 = aws_apigatewayv2_api.http_api.id
  integration_type       = "HTTP_PROXY"
  integration_method     = "ANY"
  integration_uri        = "${var.communications_api_uri}/{proxy}"
  payload_format_version = "1.0"
}

resource "aws_apigatewayv2_route" "communications_api" {
  count = var.communications_api_uri != "" ? 1 : 0

  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "ANY /communications/{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.communications_api[0].id}"
}

# --- asset-registry-api --------------------------------------------------
# No deploy exists yet for this service (no EC2/IaC - see
# rentifyx-asset-registry-api/iac/README.md). Route stays wired up but
# dormant: var.asset_registry_api_uri defaults to "", so count = 0 and
# nothing is created until the service has a real URI to point at.

resource "aws_apigatewayv2_integration" "asset_registry_api" {
  count = var.asset_registry_api_uri != "" ? 1 : 0

  api_id                 = aws_apigatewayv2_api.http_api.id
  integration_type       = "HTTP_PROXY"
  integration_method     = "ANY"
  integration_uri        = "${var.asset_registry_api_uri}/{proxy}"
  payload_format_version = "1.0"
}

resource "aws_apigatewayv2_route" "asset_registry_api" {
  count = var.asset_registry_api_uri != "" ? 1 : 0

  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "ANY /assets/{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.asset_registry_api[0].id}"
}
