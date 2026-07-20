output "identity_arn" {
  description = "ARN of the shared SES email identity"
  value       = aws_sesv2_email_identity.sender.arn
}
