output "instance_ids" {
  value = { for k, i in aws_instance.web : k => i.id }
}

output "public_ips" {
  value = { for k, i in aws_instance.web : k => i.public_ip }
}

output "urls" {
  value = { for k, i in aws_instance.web : k => "http://${i.public_ip}" }
}

output "ami_id" {
  description = "AMI the data source resolved to (may differ from what's running, see ignore_changes)."
  value       = data.aws_ami.al2023.id
}
