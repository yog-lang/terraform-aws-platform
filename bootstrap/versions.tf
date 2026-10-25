terraform {
  # 1.11+ gives us native S3 state locking (use_lockfile) - no DynamoDB needed.
  required_version = ">= 1.11.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # NOTE: no backend block here on purpose. The bootstrap stack uses LOCAL
  # state (terraform.tfstate in this folder) because the bucket it creates
  # doesn't exist yet. Chicken-and-egg problem - classic interview question.
}

provider "aws" {
  region = var.region

  # Every resource gets these tags automatically - no copy-paste needed.
  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
      Stack     = "bootstrap"
    }
  }
}
