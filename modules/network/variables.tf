variable "name" {
  description = "Name prefix for all network resources, e.g. tfplatform-dev."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC, e.g. 10.10.0.0/16."
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0)) && try(tonumber(split("/", var.vpc_cidr)[1]) <= 20, false)
    error_message = "vpc_cidr must be a valid CIDR with a prefix of /20 or bigger (e.g. 10.10.0.0/16)."
  }
}

variable "azs" {
  description = "Availability zones to spread subnets across."
  type        = list(string)

  validation {
    condition     = length(var.azs) >= 1 && length(var.azs) <= 4
    error_message = "Provide between 1 and 4 availability zones."
  }
}

variable "create_private_subnets" {
  description = "Create private subnets too (no NAT, so they have no internet access)."
  type        = bool
  default     = false
}
