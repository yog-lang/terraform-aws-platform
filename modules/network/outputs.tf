output "vpc_id" {
  value = aws_vpc.this.id
}

output "vpc_cidr" {
  value = aws_vpc.this.cidr_block
}

# A splat-style "for" expression turning the map of subnets into a list of IDs.
output "public_subnet_ids" {
  value = [for s in aws_subnet.public : s.id]
}

output "private_subnet_ids" {
  value = [for s in aws_subnet.private : s.id]
}

output "public_subnets_by_az" {
  description = "Map of AZ => subnet ID."
  value       = { for az, s in aws_subnet.public : az => s.id }
}
