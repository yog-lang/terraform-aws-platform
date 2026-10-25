# PARTIAL backend config: only the "key" (path inside the bucket) lives here.
# Bucket name and region come from ../../backend.hcl at init time:
#
#   terraform init -backend-config=../../backend.hcl
#
# Why? Backend blocks can't use variables, so this keeps the bucket name out
# of the code and lets dev and prod share one backend.hcl.
terraform {
  backend "s3" {
    key = "prod/terraform.tfstate"
  }
}
