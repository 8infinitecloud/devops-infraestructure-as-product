output "portfolio_id" {
  description = "Portfolio del motor, reutilizado. catalog-pipeline/ lo usa en el Publish."
  value       = local.portfolio_id
}

output "launch_role_arn" {
  description = "Launch Role del producto standard-environment"
  value       = aws_iam_role.launch.arn
}

output "tfc_organization" {
  description = "Organizacion de HCP Terraform"
  value       = local.tfc_organization
}
