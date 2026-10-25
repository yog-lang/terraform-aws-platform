###############################################################################
# BOOTSTRAP STACK
#
# Think of this as "building the locker before you put stuff in it".
# Terraform needs a safe place to keep its state file (its memory of what it
# built). That place has to exist BEFORE the real stacks can use it, so we
# create it here, once, using LOCAL state.
#
# What this creates:
#   1. S3 bucket for remote state (versioned, encrypted, private)
#   2. A monthly AWS budget alert so you never get a surprise bill
#   3. (optional) GitHub OIDC role so CI can run Terraform without access keys
###############################################################################

data "aws_caller_identity" "current" {}

locals {
  # Account ID makes the bucket name globally unique without guessing.
  state_bucket_name = "${var.project}-tfstate-${data.aws_caller_identity.current.account_id}"
}

# ---------------------------------------------------------------------------
# 1. Remote state bucket
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "tfstate" {
  bucket = local.state_bucket_name

  # Lets "terraform destroy" empty the bucket (all old versions) at cleanup time.
  force_destroy = true

  # Safety catch: Terraform will REFUSE to delete this bucket.
  # Interview point: lifecycle meta-arguments can't use variables, so to
  # really delete it you must edit this line (see README "Cleanup").
  lifecycle {
    prevent_destroy = true
  }
}

# Versioning = "undo button" for state. If state gets corrupted you can roll
# back to an older version of the file.
resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

# State files can contain secrets (DB passwords, etc.), so encrypt at rest.
resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Nobody on the internet should ever be able to read your state.
resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Keep old state versions for 90 days, then clean them up (saves money).
resource "aws_s3_bucket_lifecycle_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }

  depends_on = [aws_s3_bucket_versioning.tfstate]
}

# ---------------------------------------------------------------------------
# 2. Budget alert (cost guardrail)
# ---------------------------------------------------------------------------
resource "aws_budgets_budget" "monthly" {
  count = var.budget_email == "" ? 0 : 1

  name         = "${var.project}-monthly-budget"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  # Warn when AWS FORECASTS you'll cross 80% of the budget
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.budget_email]
  }

  # And again when you ACTUALLY cross 100%
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_email]
  }
}

# ---------------------------------------------------------------------------
# 3. GitHub Actions OIDC (optional)
#
# Instead of storing AWS access keys in GitHub (long-lived = risky), GitHub
# gets a short-lived token per pipeline run and swaps it for temporary AWS
# credentials. Like a hotel key card that expires at checkout, instead of a
# house key that works forever.
# ---------------------------------------------------------------------------
resource "aws_iam_openid_connect_provider" "github" {
  count = var.github_repo == "" ? 0 : 1

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]

  # AWS no longer relies on these for GitHub, but older provider versions
  # still expect a value, so we pass GitHub's published thumbprints.
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]
}

data "aws_iam_policy_document" "github_trust" {
  count = var.github_repo == "" ? 0 : 1

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github[0].arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Only YOUR repo can assume this role
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:*"]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  count = var.github_repo == "" ? 0 : 1

  name               = "${var.project}-github-actions"
  assume_role_policy = data.aws_iam_policy_document.github_trust[0].json
}

# For a learning project we give admin. In a real company you'd scope this
# down (least privilege) - be ready to say that in the interview.
resource "aws_iam_role_policy_attachment" "github_actions_admin" {
  count = var.github_repo == "" ? 0 : 1

  role       = aws_iam_role.github_actions[0].name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
