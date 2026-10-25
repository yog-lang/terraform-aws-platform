environment            = "prod"
vpc_cidr               = "10.20.0.0/16" # different range from dev, so they could be peered later
az_count               = 2
create_private_subnets = true

# Two servers, one per AZ, for high availability.
instances = {
  "web-1" = "t3.micro"
  "web-2" = "t3.micro"
}
