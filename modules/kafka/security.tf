data "aws_eks_cluster" "this" {
  name = var.cluster_name
}

resource "aws_security_group_rule" "kafka_broker_ingress" {
  type              = "ingress"
  from_port         = 9092
  to_port           = 9092
  protocol          = "tcp"
  security_group_id = data.aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
  self              = true
  description       = "Kafka broker traffic, cluster-internal only (no auth configured, see design.md Out of Scope)"
}
