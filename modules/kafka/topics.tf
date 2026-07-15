locals {
  # Exact names from rentifyx-communications-api/.specs/features/e04-f09-reliability/design.md
  # (RetryTopicChain constants) — do not rename without updating that repo's consumers.
  notification_topics = [
    "notification-requested",
    "notification-requested-retry-5s",
    "notification-requested-retry-1m",
    "notification-requested-retry-10m",
    "notification-requested-dlq",
  ]
}

resource "kubernetes_manifest" "notification_topics" {
  for_each = toset(local.notification_topics)

  manifest = {
    apiVersion = "kafka.strimzi.io/v1beta2"
    kind       = "KafkaTopic"
    metadata = {
      name      = each.value
      namespace = kubernetes_namespace_v1.kafka.metadata[0].name
      labels = {
        "strimzi.io/cluster" = "rentifyx-shared"
      }
    }
    spec = {
      partitions = 1
      replicas   = 1
    }
  }

  depends_on = [kubernetes_manifest.kafka_cluster]
}
