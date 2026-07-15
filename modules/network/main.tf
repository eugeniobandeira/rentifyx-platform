data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  az_count = 2
  azs      = slice(data.aws_availability_zones.available.names, 0, local.az_count)

  common_tags = {
    Project     = var.project
    Environment = var.environment
    Service     = "platform"
  }
}

resource "aws_vpc" "this" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.environment}-vpc"
  })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.environment}-igw"
  })
}

resource "aws_subnet" "public" {
  count                   = local.az_count
  vpc_id                  = aws_vpc.this.id
  cidr_block              = "10.0.${count.index}.0/24"
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true
  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.environment}-public-${local.azs[count.index]}"
    Tier = "public"
  })
}

resource "aws_subnet" "private" {
  count             = local.az_count
  vpc_id            = aws_vpc.this.id
  cidr_block        = "10.0.${count.index + 10}.0/24"
  availability_zone = local.azs[count.index]
  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.environment}-private-${local.azs[count.index]}"
    Tier = "private"
  })
}

# Single shared NAT Gateway (not one per AZ) — deliberate cost trade-off, accepts a
# single point of failure. See PROJECT.md Constraints.
resource "aws_eip" "nat" {
  domain = "vpc"
  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.environment}-nat-eip"
  })
}

resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.environment}-nat"
  })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.environment}-public-rt"
  })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count          = local.az_count
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id
  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.environment}-private-rt"
  })
}

resource "aws_route" "private_nat" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this.id
}

resource "aws_route_table_association" "private" {
  count          = local.az_count
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
