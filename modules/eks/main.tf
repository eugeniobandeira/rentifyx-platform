data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "secrets_kms" {
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
    sid    = "AllowEKSClusterRole"
    effect = "Allow"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:CreateGrant",
    ]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.cluster.arn]
    }
  }
}

resource "aws_kms_key" "secrets" {
  description             = "Envelope-encrypts ${var.project}-${var.environment} EKS Kubernetes secrets"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.secrets_kms.json
}

resource "aws_kms_alias" "secrets" {
  name          = "alias/${var.project}-${var.environment}-eks-secrets"
  target_key_id = aws_kms_key.secrets.key_id
}

resource "aws_eks_cluster" "this" {
  name     = "${var.project}-${var.environment}-eks"
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    subnet_ids = var.private_subnets

    endpoint_private_access = true
    # Public endpoint stays enabled (no VPN/bastion module exists yet for
    # private-only kubectl/terraform access to the cluster - module.kafka's
    # kubernetes_manifest resources need it, as would any GitHub Actions
    # deploy workflow, since Actions runners aren't in this VPC). Restricted
    # to var.eks_public_access_cidrs instead of the open internet
    # (CKV_AWS_38, actually fixed). CKV_AWS_39 ("public endpoint disabled")
    # stays failing - a real, accepted trade-off, not silently suppressed -
    # until a VPN/bastion/self-hosted-runner exists to move traffic inside
    # the VPC.
    endpoint_public_access = true
    public_access_cidrs    = var.eks_public_access_cidrs
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  encryption_config {
    resources = ["secrets"]
    provider {
      key_arn = aws_kms_key.secrets.arn
    }
  }

  depends_on = [aws_iam_role_policy_attachment.cluster_policy]
}
