variable "project" {
  type    = string
  default = "tfplatform"
}

variable "environment" {
  type = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging or prod."
  }
}

variable "region" {
  type    = string
  default = "ap-south-1"
}

variable "vpc_cidr" {
  type = string
}

variable "az_count" {
  description = "How many availability zones to use."
  type        = number
  default     = 2
}

variable "create_private_subnets" {
  type    = bool
  default = false
}

variable "instances" {
  description = "Map of instance name => instance type."
  type        = map(string)
}

variable "admin_cidr" {
  description = "Your public IP as x.x.x.x/32 to allow SSH. null = no SSH."
  type        = string
  default     = null
}

variable "instance_tags" {
  description = "Extra tags for the web servers."
  type        = map(string)
  default     = {}
}
