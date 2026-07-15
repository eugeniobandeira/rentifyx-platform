data "aws_iam_policy_document" "kafka_node_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "kafka_node_group" {
  name               = "${var.project}-${var.environment}-kafka-node-group"
  assume_role_policy = data.aws_iam_policy_document.kafka_node_assume_role.json
}

resource "aws_iam_role_policy_attachment" "kafka_node_worker_policy" {
  role       = aws_iam_role.kafka_node_group.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "kafka_node_cni_policy" {
  role       = aws_iam_role.kafka_node_group.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "kafka_node_ecr_read_policy" {
  role       = aws_iam_role.kafka_node_group.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "kafka_node_ebs_csi_policy" {
  role       = aws_iam_role.kafka_node_group.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}
