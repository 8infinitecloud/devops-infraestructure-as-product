# ---------------------------------------------------------------------------
# Hands-on 1 — motor Terraform OS, ejecucion en AWS CodeBuild.
#
# ANTES de plan/apply:
#     cd ../../modules/terraform-os-engine/lambda-functions && make bin
#
# Terraform no compila nada: archive_file lee build/ en tiempo de plan.
# ---------------------------------------------------------------------------

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  # El nombre del bucket es determinista, asi que se puede pasar a los modulos
  # que lo necesitan sin crear una dependencia circular: catalog-bootstrap
  # concede permisos sobre el, catalog-pipeline lo crea.
  artifact_bucket = "aurex-sc-artifacts-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.name}"
}

module "engine" {
  source = "../../modules/terraform-os-engine"

  terraform_cli_version = var.terraform_cli_version
}

module "catalog_bootstrap" {
  source = "../../modules/catalog-bootstrap-terraform-os"

  portfolio_name       = "Aurex Standard Environments"
  launch_role_name     = "AurexServiceCatalogLaunchRole-${data.aws_region.current.name}"
  artifact_bucket_name = local.artifact_bucket

  # Los ARNs del motor viajan como variables, no por terraform_remote_state.
  # En multicuenta estos serian los del hub y este modulo se aplicaria en el spoke.
  engine_codebuild_role_arn         = module.engine.codebuild_service_role_arn
  engine_parameter_parser_role_arns = values(module.engine.parameter_parser_role_arns)

  grant_access_to_principal_arns = var.grant_access_to_principal_arns
}

module "catalog_pipeline" {
  source = "../../modules/catalog-pipeline"

  # EXTERNAL enruta a las colas ServiceCatalogExternal* de este motor.
  product_type = "EXTERNAL"
  name_prefix  = "aurex-os-catalog"
  product_name = "Standard Environment"

  portfolio_id         = module.catalog_bootstrap.portfolio_id
  launch_role_arn      = module.catalog_bootstrap.launch_role_arn
  artifact_bucket_name = local.artifact_bucket

  github_repository_id    = var.github_repository_id
  github_branch           = var.github_branch
  existing_connection_arn = var.existing_connection_arn
  module_source_path      = "modules/standard-environment"
  terraform_cli_version   = var.terraform_cli_version
}
