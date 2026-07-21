# MSK Serverless has no console/API-based topic management (confirmed via
# AWS Console: "Topic management requires Amazon MSK Provisioned running
# version 3.6.0 or later. Serverless clusters are currently not supported.")
# - topics can only be created over the Kafka protocol itself, authenticated
# via SASL/IAM. This module is the declarative alternative to doing that by
# hand with kafka-topics.sh.
#
# Partition counts below match rentifyx-communications-api's F-09 reliability
# design (.specs/features/e04-f09-reliability/) and
# rentifyx-identity-api's outbox-kafka-notifications feature - see
# Domain/Constants/RetryTopicChain.cs (comms-api) and
# Domain/Constants/KafkaTopics.cs (identity-api) for the exact topic name
# strings these must match.
#
# replication_factor is required by the provider schema but MSK Serverless
# always replicates 3x internally regardless of what's set here - the value
# is accepted and ignored, not actually honored.

locals {
  topics = {
    "notification-requested"           = 3
    "notification-requested-retry-5s"  = 3
    "notification-requested-retry-1m"  = 3
    "notification-requested-retry-10m" = 3
    "notification-requested-dlq"       = 3
    "user-lifecycle-events"            = 3
  }
}

resource "kafka_topic" "this" {
  for_each = local.topics

  name               = each.key
  partitions         = each.value
  replication_factor = 3
}
