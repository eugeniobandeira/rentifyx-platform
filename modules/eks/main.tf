resource "aws_eks_cluster" "this" {
  name     = "${var.project}-${var.environment}-eks"
  role_arn = var.cluster_role_arn

  vpc_config {
    subnet_ids = var.private_subnets
  }
}

output "cluster_name" {
  value = aws_eks_cluster.this.name
}
