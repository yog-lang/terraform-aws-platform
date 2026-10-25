# Native Terraform tests (terraform test, 1.6+).
# mock_provider means NO real AWS calls - runs in seconds, costs nothing.
#
# Run from modules/network:
#   terraform init
#   terraform test

mock_provider "aws" {}

variables {
  name     = "unit-test"
  vpc_cidr = "10.50.0.0/16"
  azs      = ["ap-south-1a", "ap-south-1b"]
}

run "creates_one_public_subnet_per_az" {
  command = plan

  assert {
    condition     = length(aws_subnet.public) == 2
    error_message = "Expected one public subnet per AZ."
  }

  assert {
    condition     = aws_subnet.public["ap-south-1a"].cidr_block == "10.50.0.0/24"
    error_message = "First public subnet should be 10.50.0.0/24."
  }
}

run "no_private_subnets_by_default" {
  command = plan

  assert {
    condition     = length(aws_subnet.private) == 0
    error_message = "Private subnets should be off by default."
  }
}

run "private_subnets_when_enabled" {
  command = plan

  variables {
    create_private_subnets = true
  }

  assert {
    condition     = aws_subnet.private["ap-south-1b"].cidr_block == "10.50.101.0/24"
    error_message = "Private subnets should start at offset 100."
  }
}

run "rejects_bad_cidr" {
  command = plan

  variables {
    vpc_cidr = "not-a-cidr"
  }

  # We EXPECT validation to fail here - that's the test passing.
  expect_failures = [var.vpc_cidr]
}
