###############################################################################
# COMPUTE MODULE
#
# EC2 web servers running nginx, one per entry in var.instances.
# Uses for_each (not count) so removing "web-1" never renumbers "web-2".
###############################################################################

# Data source = "go look something up", it doesn't create anything.
# Finds the latest Amazon Linux 2023 image so we never hard-code an AMI ID.
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  # Stable order of instance names, used to spread them across subnets.
  instance_names = sort(keys(var.instances))
}

resource "aws_instance" "web" {
  for_each = var.instances

  ami           = data.aws_ami.al2023.id
  instance_type = each.value

  # element() wraps around: 3 instances over 2 subnets => a, b, a
  subnet_id              = element(var.subnet_ids, index(local.instance_names, each.key))
  vpc_security_group_ids = var.security_group_ids

  # templatefile() renders the startup script with our variables.
  user_data = templatefile("${path.module}/templates/user_data.sh.tftpl", {
    instance_name = each.key
    environment   = var.environment
  })
  # If the script changes, rebuild the server (otherwise it'd only run once).
  user_data_replace_on_change = true

  # IMDSv2 only - blocks a classic SSRF credential-theft trick.
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    volume_type = "gp3"
    encrypted   = true
  }

  # merge(): extra tags from the caller, but Name/Role always win.
  tags = merge(var.tags, {
    Name = "${var.name}-${each.key}"
    Role = "web"
  })

  lifecycle {
    # A new Amazon Linux AMI is published every few weeks. Without this,
    # every plan after a release would want to REPLACE all servers.
    ignore_changes = [ami]

    # Checked AFTER apply: fail loudly if the server didn't get a public IP.
    postcondition {
      condition     = self.public_ip != null && self.public_ip != ""
      error_message = "Instance ${each.key} has no public IP. Is it in a public subnet?"
    }
  }
}
