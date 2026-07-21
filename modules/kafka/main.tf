# ---------------------------------------------------------------------------
# Self-hosted Kafka (KRaft mode, single broker) - replaces AWS MSK Serverless
# (removed 2026-07-21). MSK Serverless billed per cluster-hour + per
# partition-hour + storage, which was expensive to keep running for a study
# project only spun up occasionally to test/demo the notification flow. A
# single EC2 instance running apache/kafka's official Docker image in KRaft
# combined mode (broker + controller in one process, no Zookeeper) costs a
# fraction of that and is sufficient for this project's scale/reliability
# needs. See .specs/features/self-hosted-kafka/ for the full spec/design.
#
# Trade-offs accepted (documented, not bugs): single broker, no replication -
# if this instance dies, Kafka dies with it; no persistent EBS-backed log
# dir - topics/messages are lost on instance replacement (acceptable since
# infra is destroyed/recreated per test session anyway); PLAINTEXT only, no
# SASL/TLS - the security group (VPC-CIDR-scoped) is the entire trust
# boundary, matching the project's existing "no public broker exposure"
# posture.
# ---------------------------------------------------------------------------

resource "aws_security_group" "kafka" {
  name        = "${var.project}-${var.environment}-kafka-broker"
  description = "Self-hosted Kafka broker, PLAINTEXT, VPC-internal only"
  vpc_id      = var.vpc_id

  tags = {
    Project     = var.project
    Environment = var.environment
    Service     = "platform"
  }
}

# Same VPC-CIDR-scoping rationale as the previous MSK security group: rentifyx-identity-api/
# rentifyx-communications-api's EC2 instances live in this same VPC (their own Terraform state)
# but their security groups can't be referenced here directly without a circular cross-repo
# apply-ordering dependency.
resource "aws_vpc_security_group_ingress_rule" "kafka_broker_vpc" {
  security_group_id = aws_security_group.kafka.id
  description       = "Kafka broker port, any client within this VPC"

  cidr_ipv4   = var.vpc_cidr
  from_port   = 9092
  to_port     = 9092
  ip_protocol = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "kafka_all" {
  security_group_id = aws_security_group.kafka.id
  description       = "Allow all outbound"

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"
}

resource "aws_iam_role" "kafka" {
  name = "${var.project}-${var.environment}-kafka-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "ec2.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    ManagedBy = "terraform"
  }
}

resource "aws_iam_role_policy_attachment" "kafka_ssm" {
  role       = aws_iam_role.kafka.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "kafka" {
  name = "${var.project}-${var.environment}-kafka-ec2-profile"
  role = aws_iam_role.kafka.name
}

data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "kafka" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = "t3.micro"
  iam_instance_profile   = aws_iam_instance_profile.kafka.name
  vpc_security_group_ids = [aws_security_group.kafka.id]
  subnet_id              = var.private_subnets[0]

  user_data = base64encode(templatefile("${path.module}/userdata.sh.tpl", {}))

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    encrypted   = true
  }

  tags = {
    Name        = "${var.project}-${var.environment}-kafka-broker"
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  # data.aws_ami's most_recent lookup re-resolves to a newer AMI ID every time
  # AWS publishes a patched al2023 image, which would otherwise force a
  # replace on every plan. AMI updates should be a deliberate redeploy, not
  # accidental churn from an unrelated apply - same fix already applied to
  # both app repos' modules/ec2.
  lifecycle {
    ignore_changes = [ami]
  }
}
