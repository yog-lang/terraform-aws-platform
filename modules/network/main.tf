###############################################################################
# NETWORK MODULE
#
# Builds: VPC -> Internet Gateway -> public subnets (+ optional private
# subnets) -> route table.
#
# Analogy: the VPC is your plot of land, subnets are rooms, the internet
# gateway is the front door, and the route table is the signboard saying
# "to reach the internet, go through the front door".
#
# No NAT gateway on purpose: it costs ~USD 30+/month even when idle.
###############################################################################

locals {
  # Turn ["ap-south-1a", "ap-south-1b"] into { "ap-south-1a" = 0, "ap-south-1b" = 1 }
  # We use the AZ NAME as the for_each key (stable) and the index only to
  # carve out a CIDR. Interview point: for_each keys should be stable values,
  # not list positions.
  az_index = { for idx, az in var.azs : az => idx }
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.name}-vpc"
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.name}-igw"
  }
}

# cidrsubnet("10.10.0.0/16", 8, 0) = 10.10.0.0/24
# cidrsubnet("10.10.0.0/16", 8, 1) = 10.10.1.0/24  ... and so on
resource "aws_subnet" "public" {
  for_each = local.az_index

  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, each.value)
  availability_zone       = each.key
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.name}-public-${each.key}"
    Tier = "public"
  }
}

# Conditional resource creation: an empty map means "create nothing".
# Private subnets start at .100 so they never collide with public ones.
resource "aws_subnet" "private" {
  for_each = var.create_private_subnets ? local.az_index : {}

  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, each.value + 100)
  availability_zone = each.key

  tags = {
    Name = "${var.name}-private-${each.key}"
    Tier = "private"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name = "${var.name}-public-rt"
  }
}

# for_each over another resource's map: one association per public subnet.
resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}
