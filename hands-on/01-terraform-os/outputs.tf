output "codebuild_service_role_arn" {
  description = "Rol que ejecuta terraform. En multicuenta, el Launch Role del spoke debe confiar en el."
  value       = module.engine.codebuild_service_role_arn
}

output "portfolio_id" {
  value = module.catalog_bootstrap.portfolio_id
}

output "launch_role_arn" {
  value = module.catalog_bootstrap.launch_role_arn
}

output "pipeline_name" {
  value = module.catalog_pipeline.pipeline_name
}

output "artifact_bucket" {
  value = module.catalog_pipeline.artifact_bucket
}

output "connection_needs_authorization" {
  description = "Si es true, autoriza la conexion a mano en la consola de CodeConnections"
  value       = module.catalog_pipeline.connection_needs_authorization
}
