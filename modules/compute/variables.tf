variable "name" {
  description = "Name prefix."
  type        = string
}

variable "environment" {
  description = "Environment name shown on the web page."
  type        = string
}

variable "instances" {
  description = "Map of instance name => instance type, e.g. { web-1 = \"t3.micro\" }."
  type        = map(string)

  # Cost guardrail: only small, cheap instance types allowed.
  validation {
    condition     = alltrue([for t in values(var.instances) : contains(["t2.micro", "t3.micro", "t3.small"], t)])
    error_message = "Only t2.micro, t3.micro or t3.small are allowed in this project (keeps costs low)."
  }

  validation {
    condition     = length(var.instances) >= 1 && length(var.instances) <= 4
    error_message = "Create between 1 and 4 instances."
  }
}

variable "subnet_ids" {
  description = "Subnets to spread instances across."
  type        = list(string)
}

variable "security_group_ids" {
  description = "Security groups to attach."
  type        = list(string)
}

variable "tags" {
  description = "Extra tags for the instances (on top of provider default_tags)."
  type        = map(string)
  default     = {}
}
