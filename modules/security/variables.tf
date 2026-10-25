variable "name" {
  description = "Name prefix."
  type        = string
}

variable "vpc_id" {
  description = "VPC to create the security group in."
  type        = string
}

variable "ingress_rules" {
  description = "List of TCP ingress rules."
  type = list(object({
    description = string
    port        = number
    cidr_blocks = list(string)
  }))

  validation {
    condition     = alltrue([for r in var.ingress_rules : r.port > 0 && r.port < 65536])
    error_message = "Every port must be between 1 and 65535."
  }

  # Guardrail: never open SSH to the whole internet.
  validation {
    condition     = !anytrue([for r in var.ingress_rules : r.port == 22 && contains(r.cidr_blocks, "0.0.0.0/0")])
    error_message = "SSH (22) must not be open to 0.0.0.0/0. Use your own IP, e.g. 1.2.3.4/32."
  }
}
