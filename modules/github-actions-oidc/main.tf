# ---------------------------------------------------------------------------
# GitHub Actions OIDC — lets the platform repo's CI workflow authenticate to
# AWS (to run `terraform init`/`plan`/`apply`) without long-lived access
# keys stored as GitHub secrets.
#
# Scope note: this role currently grants only what CI's terraform.yml needs
# today (init/validate against the S3+DynamoDB backend). It does NOT grant
# permission to create/modify the actual infrastructure (VPC, Kafka broker,
# etc.) - that's deliberately out of scope until a real `apply` workflow
# exists and its exact permission needs are known, rather than guessing a
# broad policy upfront.
# ---------------------------------------------------------------------------

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]

  # Well-known thumbprint for token.actions.githubusercontent.com
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = {
    ManagedBy = "terraform"
  }
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 0 : 1

  url = "https://token.actions.githubusercontent.com"
}

locals {
  oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn
}

resource "aws_iam_role" "github_ci" {
  name = "${var.prefix}-github-ci"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = local.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            # Both pull_request and push-to-main trigger terraform.yml.
            "token.actions.githubusercontent.com:sub" = [
              "repo:${var.github_repo}:ref:refs/heads/main",
              "repo:${var.github_repo}:pull_request",
            ]
          }
        }
      }
    ]
  })

  tags = {
    ManagedBy = "terraform"
  }
}

resource "aws_iam_role_policy" "terraform_backend" {
  name = "${var.prefix}-github-ci-backend"
  role = aws_iam_role.github_ci.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "StateBucketLocation"
        Effect   = "Allow"
        Action   = ["s3:GetBucketLocation"]
        Resource = "arn:aws:s3:::${var.state_bucket}"
      },
      {
        Sid      = "StateBucketList"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = "arn:aws:s3:::${var.state_bucket}"
        Condition = {
          StringLike = {
            "s3:prefix" = ["${var.state_bucket_key_prefix}*"]
          }
        }
      },
      {
        Sid    = "StateObjectReadWrite"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:PutObject"]
        Resource = [
          "arn:aws:s3:::${var.state_bucket}/${var.state_bucket_key_prefix}*",
        ]
      },
      {
        Sid      = "StateLock"
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
        Resource = "arn:aws:dynamodb:*:*:table/${var.dynamodb_lock_table}"
      }
    ]
  })
}
