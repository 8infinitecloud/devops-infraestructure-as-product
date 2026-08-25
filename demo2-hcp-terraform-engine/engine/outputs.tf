# Outputs que consumen catalog-bootstrap/ y catalog-pipeline/ via terraform_remote_state.
# El modulo del motor ya los expone; aqui solo se re-exportan al nivel raiz.

output "parameter_parser_role_arn" {
  description = "Rol del terraform-parameter-parser. El Launch Role debe confiar en el."
  value       = module.terraform_cloud_reference_engine.parameter_parser_role_arn
}

output "send_apply_lambda_role_arn" {
  description = "Rol de la Lambda send-apply. El Launch Role debe confiar en el."
  value       = module.terraform_cloud_reference_engine.send_apply_lambda_role_arn
}

output "oidc_provider_arn" {
  description = "OIDC provider que establece la confianza con HCP Terraform (Dynamic Credentials)"
  value       = module.terraform_cloud_reference_engine.oidc_provider_arn
}

output "tfc_organization" {
  description = "Organizacion de HCP Terraform"
  value       = module.terraform_cloud_reference_engine.tfc_organization
}

output "tfc_hostname" {
  description = "Hostname de HCP Terraform"
  value       = module.terraform_cloud_reference_engine.tfc_hostname
}

output "example_portfolio_id" {
  description = "Portfolio que crea el propio motor para su producto de ejemplo"
  value       = aws_servicecatalog_portfolio.portfolio.id
}
