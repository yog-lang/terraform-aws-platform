environment = "dev"
vpc_cidr    = "10.10.0.0/16"
az_count    = 2

instances = {
  "web-1" = "t3.micro"
}

# Uncomment and set to your IP (find it at https://checkip.amazonaws.com) to allow SSH:
# admin_cidr = "1.2.3.4/32"
