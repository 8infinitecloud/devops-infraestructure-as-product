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

# Una fila por producto del catalogo, para ver de un vistazo que pipeline
# publica que modulo.
output "catalogo" {
  description = "Productos publicados y la pipeline que los construye"
  value = {
    for k, m in module.catalog_pipeline : k => {
      producto = m.product_name
      pipeline = m.pipeline_name
      modulo   = m.module_source_path
    }
  }
}

output "connection_needs_authorization" {
  description = "Si es true, autoriza la conexion a mano en la consola de CodeConnections"
  value       = module.catalog_shared.connection_needs_authorization
}
