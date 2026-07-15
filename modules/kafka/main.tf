resource "aws_eks_node_group" "kafka" {
  cluster_name    = var.cluster_name
  node_group_name = "${var.project}-${var.environment}-kafka"
  node_role_arn   = aws_iam_role.kafka_node_group.arn
  subnet_ids      = var.private_subnets

  ami_type       = "AL2023_ARM_64_STANDARD"
  instance_types = ["t4g.small"]
  capacity_type  = "ON_DEMAND"
  disk_size      = 20

  scaling_config {
    desired_size = 1
    max_size     = 1
    min_size     = 1
  }

  labels = {
    workload = "kafka"
  }

  depends_on = [
    aws_iam_role_policy_attachment.kafka_node_worker_policy,
    aws_iam_role_policy_attachment.kafka_node_cni_policy,
    aws_iam_role_policy_attachment.kafka_node_ecr_read_policy,
  ]
}
