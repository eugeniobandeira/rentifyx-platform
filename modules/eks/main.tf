resource "aws_eks_cluster" "this" {
  name     = "${var.project}-${var.environment}-eks"
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    subnet_ids = var.private_subnets
  }

  depends_on = [aws_iam_role_policy_attachment.cluster_policy]
}
