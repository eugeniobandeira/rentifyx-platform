locals {
  # Bootstrap service name convention confirmed via Context7 (strimzi docs,
  # con-configuration-points-listener-names.adoc): <cluster_name>-kafka-bootstrap
  kafka_bootstrap_servers = "rentifyx-shared-kafka-bootstrap.${kubernetes_namespace_v1.kafka.metadata[0].name}.svc.cluster.local:9092"
}

resource "aws_ssm_parameter" "kafka_bootstrap_servers" {
  name        = "/rentifyx/platform/kafka/bootstrap-servers"
  description = "Internal Kafka bootstrap address for rentifyx-identity-api and rentifyx-communications-api"
  type        = "SecureString"
  key_id      = "alias/aws/ssm"
  value       = local.kafka_bootstrap_servers

  depends_on = [kubernetes_manifest.kafka_cluster]
}
