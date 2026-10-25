# tflint = a spell-checker for Terraform. Catches unused variables, missing
# types, deprecated syntax, naming issues, etc.
#
# Run from the repo root:
#   tflint --init
#   tflint --recursive

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

# Optional: AWS-specific rules (invalid instance types, etc.).
# Uncomment and set the latest version from
# https://github.com/terraform-linters/tflint-ruleset-aws/releases
#
# plugin "aws" {
#   enabled = true
#   version = "X.Y.Z"
#   source  = "github.com/terraform-linters/tflint-ruleset-aws"
# }
