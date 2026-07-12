resource "aws_cognito_user_pool" "this" {
  name = "${var.project}-${var.environment}-user-pool"
}

output "user_pool_id" {
  value = aws_cognito_user_pool.this.id
}
