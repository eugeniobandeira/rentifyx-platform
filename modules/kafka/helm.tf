resource "kubernetes_namespace_v1" "kafka" {
  metadata {
    name = "kafka"
  }
}

resource "helm_release" "strimzi_operator" {
  name       = "strimzi-cluster-operator"
  repository = "oci://quay.io/strimzi-helm"
  chart      = "strimzi-kafka-operator"
  # Confirmed via Context7 docs (github.com/strimzi/strimzi-kafka-operator) 2026-07-15 —
  # verify a newer stable release isn't available before applying.
  version   = "0.45.0"
  namespace = kubernetes_namespace_v1.kafka.metadata[0].name

  depends_on = [aws_eks_node_group.kafka]
}
