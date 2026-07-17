resource "aws_cognito_user_pool" "this" {
  name = "${var.project}-${var.environment}-user-pool"
}
