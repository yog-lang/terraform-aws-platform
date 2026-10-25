###############################################################################
# SECURITY MODULE
#
# One security group for the web tier. A security group is a bouncer at the
# door: it only lets in traffic that's on the guest list (ingress rules).
#
# We use INLINE rules on purpose: Terraform then "owns" the full list of rules.
# If someone adds a rule by hand in the AWS console, `terraform plan` will
# spot it as DRIFT and offer to remove it. That's the drift lab (LABS.md).
###############################################################################

resource "aws_security_group" "web" {
  # name_prefix + create_before_destroy lets Terraform build the new SG first,
  # move instances over, then delete the old one (no "name already exists").
  name_prefix = "${var.name}-web-"
  description = "Web tier security group for ${var.name}"
  vpc_id      = var.vpc_id

  # dynamic block = a "for loop" that writes nested blocks for you.
  dynamic "ingress" {
    for_each = var.ingress_rules
    content {
      description = ingress.value.description
      from_port   = ingress.value.port
      to_port     = ingress.value.port
      protocol    = "tcp"
      cidr_blocks = ingress.value.cidr_blocks
    }
  }

  egress {
    description = "Allow all outbound (package installs, updates)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name}-web-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}
