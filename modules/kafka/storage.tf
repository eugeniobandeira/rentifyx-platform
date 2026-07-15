resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name  = var.cluster_name
  addon_name    = "aws-ebs-csi-driver"
  addon_version = null # let AWS pick the default compatible version for the cluster's Kubernetes version

  depends_on = [aws_eks_node_group.kafka]
}

resource "kubernetes_storage_class_v1" "kafka_gp3" {
  metadata {
    name = "kafka-gp3"
  }

  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Retain"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true

  parameters = {
    type = "gp3"
  }

  depends_on = [aws_eks_addon.ebs_csi_driver]
}
