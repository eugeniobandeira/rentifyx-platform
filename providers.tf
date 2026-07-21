provider "aws" {
  region = var.aws_region
}

# Topic creation is NOT managed by Terraform - the Mongey/kafka provider's
# aws-iam SASL mechanism fails authentication against MSK Serverless
# specifically ("Invalid authentication payload", confirmed 2026-07-20;
# root cause not found - AWS Console also has no topic management for
# Serverless clusters at all). Use kafka-ui instead (scripts/start-kafka-ui.sh,
# docs/kafka-ui.md) - it authenticates via the official Java
# aws-msk-iam-auth library, which is proven to work against this cluster.
