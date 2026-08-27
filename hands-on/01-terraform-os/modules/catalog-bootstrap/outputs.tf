output "portfolio_id" {
  description = "ID del Portfolio. catalog-pipeline/ lo usa en el paso de Publish."
  value       = aws_servicecatalog_portfolio.this.id
}

output "portfolio_name" {
  description = "Nombre visible del Portfolio"
  value       = aws_servicecatalog_portfolio.this.name
}

output "launch_role_arn" {
  description = "ARN del Launch Role, para el Launch Constraint del producto"
  value       = aws_iam_role.launch.arn
}

output "launch_role_name" {
  description = "Nombre del Launch Role"
  value       = aws_iam_role.launch.name
}
