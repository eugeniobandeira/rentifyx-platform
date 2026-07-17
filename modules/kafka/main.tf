# ---------------------------------------------------------------------------
# Amazon MSK Serverless - replaces the previous Strimzi-on-EKS setup
# (helm.tf/kafka-cluster.tf/storage.tf/iam.tf/security.tf/topics.tf,
# removed 2026-07-17). Fully managed: no node group, no Kubernetes operator,
# no EBS storage class to maintain. Chosen specifically to let
# rentifyx-identity-api/rentifyx-communications-api get real, shared Kafka
# without this repo's EKS module (which nothing else in this platform
# actually needs - identity-api deploys via its own EC2 module, not EKS).
#
# Topics are NOT declared here: MSK Serverless doesn't support declarative
# topic management via the AWS provider (no aws_msk_topic resource exists),
# and auto.create.topics.enable is always on for Serverless clusters and
# can't be disabled - topics get created automatically the first time a
# producer writes to them. See rentifyx-communications-api's
# RetryTopicChain constants for the exact topic names this platform's
# producers/consumers expect.
# ---------------------------------------------------------------------------

resource "aws_security_group" "msk" {
  #checkov:skip=CKV2_AWS_5:actually attached, via aws_msk_serverless_cluster.this's vpc_config.security_group_ids below - checkov's static graph analysis doesn't associate that block with this SG
  name        = "${var.project}-${var.environment}-kafka-msk"
  description = "MSK Serverless SASL/IAM broker access, VPC-internal only"
  vpc_id      = var.vpc_id

  tags = {
    Project     = var.project
    Environment = var.environment
    Service     = "platform"
  }
}

resource "aws_vpc_security_group_ingress_rule" "msk_sasl_iam" {
  security_group_id = aws_security_group.msk.id
  description       = "SASL/IAM broker port, cluster-internal only"

  referenced_security_group_id = aws_security_group.msk.id
  from_port                    = 9098
  to_port                      = 9098
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "msk_all" {
  security_group_id = aws_security_group.msk.id
  description       = "Allow all outbound (broker-to-broker, AWS API calls)"

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"
}

resource "aws_msk_serverless_cluster" "this" {
  cluster_name = "${var.project}-${var.environment}-kafka"

  client_authentication {
    sasl {
      iam {
        enabled = true
      }
    }
  }

  vpc_config {
    subnet_ids         = var.private_subnets
    security_group_ids = [aws_security_group.msk.id]
  }

  tags = {
    Project     = var.project
    Environment = var.environment
    Service     = "platform"
  }
}

# Policy JSON for producer/consumer clients (rentifyx-identity-api,
# rentifyx-communications-api) to attach to their own EC2 instance IAM
# roles in their own repos - this module doesn't attach it to anything
# itself, since it doesn't own those services' roles.
data "aws_iam_policy_document" "kafka_client" {
  statement {
    sid    = "MSKConnect"
    effect = "Allow"
    actions = [
      "kafka-cluster:Connect",
      "kafka-cluster:AlterCluster",
      "kafka-cluster:DescribeCluster",
    ]
    resources = [aws_msk_serverless_cluster.this.arn]
  }

  statement {
    sid    = "MSKTopicReadWrite"
    effect = "Allow"
    actions = [
      "kafka-cluster:*Topic*",
      "kafka-cluster:WriteData",
      "kafka-cluster:ReadData",
    ]
    resources = ["arn:aws:kafka:${var.aws_region}:*:topic/${aws_msk_serverless_cluster.this.cluster_name}/*"]
  }

  statement {
    sid    = "MSKGroup"
    effect = "Allow"
    actions = [
      "kafka-cluster:AlterGroup",
      "kafka-cluster:DescribeGroup",
    ]
    resources = ["arn:aws:kafka:${var.aws_region}:*:group/${aws_msk_serverless_cluster.this.cluster_name}/*"]
  }
}
