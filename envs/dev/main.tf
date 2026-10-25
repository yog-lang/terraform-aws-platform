###############################################################################
# ROOT MODULE - this is where you run terraform plan/apply.
# It wires the three modules together like LEGO blocks.
###############################################################################

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  name = "${var.project}-${var.environment}"

  # Pick the first N AZs in the region.
  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  # Conditional expression: add an SSH rule only if admin_cidr is set.
  ingress_rules = concat(
    [
      {
        description = "HTTP from anywhere"
        port        = 80
        cidr_blocks = ["0.0.0.0/0"]
      }
    ],
    var.admin_cidr == null ? [] : [
      {
        description = "SSH from admin IP"
        port        = 22
        cidr_blocks = [var.admin_cidr]
      }
    ]
  )
}

module "network" {
  source = "../../modules/network"

  name                   = local.name
  vpc_cidr               = var.vpc_cidr
  azs                    = local.azs
  create_private_subnets = var.create_private_subnets
}

module "security" {
  source = "../../modules/security"

  name          = local.name
  vpc_id        = module.network.vpc_id # implicit dependency: network goes first
  ingress_rules = local.ingress_rules
}

module "compute" {
  source = "../../modules/compute"

  name               = local.name
  environment        = var.environment
  instances          = var.instances
  subnet_ids         = module.network.public_subnet_ids
  security_group_ids = [module.security.web_sg_id]
  tags               = var.instance_tags
}

# check block (Terraform 1.5+): runs on every plan/apply and WARNS (doesn't
# fail) if the website isn't reachable. Great for spotting "it applied fine
# but the app is broken".
check "website_is_up" {
  data "http" "first_instance" {
    url = values(module.compute.urls)[0]

    retry {
      attempts     = 5
      min_delay_ms = 10000
    }
  }

  assert {
    condition     = data.http.first_instance.status_code == 200
    error_message = "Website at ${values(module.compute.urls)[0]} returned ${data.http.first_instance.status_code}, expected 200. (nginx may still be installing - wait a minute and run plan again.)"
  }
}
