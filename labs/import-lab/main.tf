###############################################################################
# IMPORT LAB  (see LABS.md, Lab 5)
#
# Scenario: someone created an S3 bucket by hand in the console. You need to
# bring it under Terraform WITHOUT deleting and recreating it.
#
# This folder uses LOCAL state on purpose, so you can't break dev/prod.
###############################################################################

terraform {
  required_version = ">= 1.11.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "ap-south-1"
}

# STEP 2 of the lab: uncomment this block and put your bucket name in "id".
#
# import {
#   to = aws_s3_bucket.legacy
#   id = "REPLACE-WITH-YOUR-BUCKET-NAME"
# }

# STEP 3: run
#   terraform plan -generate-config-out=generated.tf
# Terraform will WRITE the resource block for you into generated.tf.
