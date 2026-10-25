output "vpc_id" {
  value = module.network.vpc_id
}

output "public_subnets_by_az" {
  value = module.network.public_subnets_by_az
}

output "web_sg_id" {
  description = "Used in the drift lab."
  value       = module.security.web_sg_id
}

output "instance_ids" {
  value = module.compute.instance_ids
}

output "website_urls" {
  description = "Open these in your browser."
  value       = module.compute.urls
}
