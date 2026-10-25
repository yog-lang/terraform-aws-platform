# Modules declare WHICH providers they need, but never configure them
# (no region, no credentials). The root module (envs/dev, envs/prod) does that.
terraform {
  required_version = ">= 1.11.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }
}
