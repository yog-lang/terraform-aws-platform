output "state_bucket_name" {
  description = "Put this in backend.hcl at the repo root."
  value       = aws_s3_bucket.tfstate.bucket
}

output "region" {
  value = var.region
}

output "github_actions_role_arn" {
  description = "Add this as the AWS_ROLE_ARN secret in your GitHub repo."
  value       = try(aws_iam_role.github_actions[0].arn, "not created (github_repo was empty)")
}

output "next_step" {
  value = <<-EOT

    Bootstrap done. Now create backend.hcl in the repo root with:

      bucket       = "${aws_s3_bucket.tfstate.bucket}"
      region       = "${var.region}"
      encrypt      = true
      use_lockfile = true

  EOT
}
