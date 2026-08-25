output "portfolio_id" {
  value = module.catalog_bootstrap.portfolio_id
}

output "launch_role_arn" {
  value = module.catalog_bootstrap.launch_role_arn
}

output "oidc_provider_arn" {
  value = module.engine.oidc_provider_arn
}

output "tfc_organization" {
  value = module.engine.tfc_organization
}

output "pipeline_name" {
  value = module.catalog_pipeline.pipeline_name
}

output "artifact_bucket" {
  value = module.catalog_pipeline.artifact_bucket
}
