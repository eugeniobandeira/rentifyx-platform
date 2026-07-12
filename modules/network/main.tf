resource "aws_vpc" "this" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name        = "${var.project}-${var.environment}-vpc"
    Project     = var.project
    Environment = var.environment
    Service     = "platform"
  }
}

output "vpc_id" {
  value = aws_vpc.this.id
}

output "private_subnets" {
  value = []
}
