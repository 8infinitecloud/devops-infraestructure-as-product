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

output "artifact_bucket" {
  value = module.catalog_shared.artifact_bucket_name
}

output "catalogo" {
  description = "Productos que publica la pipeline"
  value = {
    pipeline  = module.catalog_pipeline.pipeline_name
    productos = module.catalog_pipeline.productos
  }
}

output "connection_needs_authorization" {
  description = "Si es true, autoriza la conexion a mano en la consola de CodeConnections"
  value       = module.catalog_shared.connection_needs_authorization
}
