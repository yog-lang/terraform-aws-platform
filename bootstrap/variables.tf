variable "project" {
  description = "Short project name, used as a prefix for resource names."
  type        = string
  default     = "tfplatform"

  validation {
    condition     = can(regex("^[a-z0-9-]{3,20}$", var.project))
    error_message = "project must be 3-20 chars: lowercase letters, numbers, hyphens (S3 bucket naming rules)."
  }
}

variable "region" {
  description = "AWS region for everything."
  type        = string
  default     = "ap-south-1" # Mumbai
}

variable "budget_email" {
  description = "Email for budget alerts. Leave empty to skip creating the budget."
  type        = string
  default     = ""
}

variable "monthly_budget_usd" {
  description = "Monthly budget in USD before you get an alert."
  type        = number
  default     = 10
}

variable "github_repo" {
  description = "GitHub repo in 'owner/name' format allowed to deploy via OIDC. Empty = skip."
  type        = string
  default     = ""

  validation {
    condition     = var.github_repo == "" || can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repo))
    error_message = "github_repo must look like 'owner/repo'."
  }
}
