provider "aws" {
  region = var.aws_region
}

# Topic creation is NOT managed by Terraform. Historically (through
# 2026-07-20) this was because the Mongey/kafka provider's aws-iam SASL
# mechanism failed authentication against MSK Serverless specifically. As of
# 2026-07-21 the broker is self-hosted (KRaft, PLAINTEXT - see
# .specs/features/self-hosted-kafka/) with KAFKA_AUTO_CREATE_TOPICS_ENABLE
# set, so topics still don't need declarative management - they're created
# automatically on first produce, same as MSK Serverless's own behavior.
# kafka-ui (scripts/start-kafka-ui.sh, docs/kafka-ui.md) remains the way to
# inspect/manage topics, now connecting PLAINTEXT with no SASL config.
