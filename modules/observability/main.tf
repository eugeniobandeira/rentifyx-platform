data "aws_caller_identity" "current" {}

# CloudWatch Logs needs explicit key-policy grants to use a customer-managed
# KMS key - without this the log group creation fails with AccessDenied.
data "aws_iam_policy_document" "otel_kms" {
  #checkov:skip=CKV_AWS_109:AWS's own default-generated KMS key policy grants the account root full admin so the account can never be permanently locked out of the key; Resource:"*" in a key's own resource-based policy means "this key", not every key in the account
  #checkov:skip=CKV_AWS_111:same key policy as CKV_AWS_109 above - required root-admin grant, not an unconstrained IAM identity policy
  #checkov:skip=CKV_AWS_356:same key policy as CKV_AWS_109 above - Resource:"*" is inherent to how KMS key (resource-based) policies work, not a wildcard across resources
  statement {
    sid       = "AllowAccountRootAdmin"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  statement {
    sid    = "AllowCloudWatchLogs"
    effect = "Allow"
    actions = [
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*",
    ]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["logs.${var.aws_region}.amazonaws.com"]
    }

    condition {
      test     = "ArnEquals"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/rentifyx/${var.project}/${var.environment}/otel"]
    }
  }
}

resource "aws_kms_key" "otel" {
  description             = "Encrypts ${var.project}-${var.environment} OTel CloudWatch log group"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.otel_kms.json
}

resource "aws_kms_alias" "otel" {
  name          = "alias/${var.project}-${var.environment}-otel"
  target_key_id = aws_kms_key.otel.key_id
}

resource "aws_cloudwatch_log_group" "otel" {
  name = "/rentifyx/${var.project}/${var.environment}/otel"
  # 1 year minimum retention (CKV_AWS_338)
  retention_in_days = 365
  kms_key_id        = aws_kms_key.otel.arn
}
