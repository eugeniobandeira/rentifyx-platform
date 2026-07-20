# Shared SES sender identity for the whole platform - rentifyx-identity-api
# and rentifyx-communications-api both send from this one verified
# identity (via terraform_remote_state), instead of each app repo owning
# its own aws_sesv2_email_identity and colliding on the same real AWS
# resource (SES identities are unique per account, not per-app).
resource "aws_sesv2_email_identity" "sender" {
  email_identity = var.ses_identity
}
