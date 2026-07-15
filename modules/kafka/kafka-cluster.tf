resource "kubernetes_manifest" "kafka_node_pool" {
  manifest = {
    apiVersion = "kafka.strimzi.io/v1beta2"
    kind       = "KafkaNodePool"
    metadata = {
      name      = "kraft-dual-role"
      namespace = kubernetes_namespace_v1.kafka.metadata[0].name
      labels = {
        "strimzi.io/cluster" = "rentifyx-shared"
      }
    }
    spec = {
      replicas = 1
      roles    = ["controller", "broker"]
      storage = {
        type = "jbod"
        volumes = [
          {
            id          = 0
            type        = "persistent-claim"
            size        = "15Gi"
            class       = kubernetes_storage_class_v1.kafka_gp3.metadata[0].name
            deleteClaim = false
          }
        ]
      }
      template = {
        pod = {
          affinity = {
            nodeAffinity = {
              requiredDuringSchedulingIgnoredDuringExecution = {
                nodeSelectorTerms = [
                  {
                    matchExpressions = [
                      {
                        key      = "workload"
                        operator = "In"
                        values   = ["kafka"]
                      }
                    ]
                  }
                ]
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    helm_release.strimzi_operator,
    kubernetes_storage_class_v1.kafka_gp3,
    aws_eks_node_group.kafka,
  ]
}

resource "kubernetes_manifest" "kafka_cluster" {
  manifest = {
    apiVersion = "kafka.strimzi.io/v1beta2"
    kind       = "Kafka"
    metadata = {
      name      = "rentifyx-shared"
      namespace = kubernetes_namespace_v1.kafka.metadata[0].name
      annotations = {
        "strimzi.io/node-pools" = "enabled"
        "strimzi.io/kraft"      = "enabled"
      }
    }
    spec = {
      kafka = {
        version = "3.9.0" # confirmed supported by Strimzi 0.45.0 via Context7, see helm.tf
        listeners = [
          {
            name = "plain"
            port = 9092
            type = "internal"
            tls  = false
          }
        ]
        config = {
          "offsets.topic.replication.factor"         = 1
          "transaction.state.log.replication.factor" = 1
          "transaction.state.log.min.isr"            = 1
          "default.replication.factor"               = 1
          "min.insync.replicas"                      = 1
        }
      }
      entityOperator = {
        topicOperator = {}
      }
    }
  }

  depends_on = [kubernetes_manifest.kafka_node_pool]
}
