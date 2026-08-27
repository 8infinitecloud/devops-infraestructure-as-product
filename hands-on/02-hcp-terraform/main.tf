# ---------------------------------------------------------------------------
# Hands-on 2 — motor de HCP Terraform. El apply corre en un workspace, no en AWS.
#
# ANTES de plan/apply:
#     cd ../../modules/hcp-terraform-engine/engine/lambda-functions && make bin
#
# Requiere TFE_TOKEN en el entorno (o ~/.terraform.d/credentials.tfrc.json).
# ---------------------------------------------------------------------------

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  artifact_bucket = "aurex-sc-artifacts-tfc-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.name}"

  # El catalogo, igual que en el Hands-on 1. Anadir un producto es anadir una
  # entrada aqui; ver el comentario largo en hands-on/01-terraform-os/main.tf.
  #
  # Sirve el MISMO modulo que el Hands-on 1 —products/standard-environment—, que
  # es justo lo que el taller quiere ensenar: el modulo no sabe que motor lo
  # ejecuta por debajo.
  productos = {
    standard-environment = {
      nombre      = "Standard Environment (HCP Terraform)"
      ruta        = "products/standard-environment"
      descripcion = "Red, almacenamiento y rol de acceso estandar. Aplicado en un workspace de HCP Terraform."
    }
  }
}

module "engine" {
  source = "../../modules/hcp-terraform-engine"

  tfc_organization  = var.tfc_organization
  tfc_team          = var.tfc_team
  tfc_hostname      = var.tfc_hostname
  terraform_version = var.terraform_version

  # El OIDC provider de app.terraform.io es un recurso IAM POR CUENTA.
  # En multicuenta, cada cuenta spoke necesitaria el suyo.
  provision_oidc_provider = true

  # La pipeline publica standard-environment; el de ejemplo del motor sobra.
  create_example_product = false
}

module "catalog_bootstrap" {
  source = "../../modules/catalog-bootstrap-hcp-terraform"

  # El motor ya crea el Portfolio: aqui se reutiliza, no se crea otro.
  portfolio_id         = module.engine.example_portfolio_id
  artifact_bucket_name = local.artifact_bucket

  engine_parameter_parser_role_arn = module.engine.parameter_parser_role_arn
  engine_send_apply_role_arn       = module.engine.send_apply_lambda_role_arn
  oidc_provider_arn                = module.engine.oidc_provider_arn
  tfc_organization                 = module.engine.tfc_organization
  tfc_hostname                     = module.engine.tfc_hostname

  grant_access_to_principal_arns = var.grant_access_to_principal_arns
}

module "catalog_shared" {
  source = "../../modules/catalog-shared"

  artifact_bucket_name    = local.artifact_bucket
  existing_connection_arn = var.existing_connection_arn
  connection_name         = "aurex-tfc-github"
}

module "catalog_pipeline" {
  source   = "../../modules/catalog-pipeline"
  for_each = local.productos

  # TERRAFORM_CLOUD enruta a las colas ServiceCatalogTerraformCloud* de este motor.
  product_type        = "TERRAFORM_CLOUD"
  name_prefix         = "aurex-tfc-${each.key}"
  product_name        = each.value.nombre
  product_description = each.value.descripcion

  # EL MISMO modulo que el Hands-on 1. Sin copiar, sin reescribir.
  module_source_path = each.value.ruta

  portfolio_id         = module.catalog_bootstrap.portfolio_id
  launch_role_arn      = module.catalog_bootstrap.launch_role_arn
  artifact_bucket_name = module.catalog_shared.artifact_bucket_name
  connection_arn       = module.catalog_shared.connection_arn

  github_repository_id  = var.github_repository_id
  github_branch         = var.github_branch
  terraform_cli_version = var.terraform_version

  # Etapa Inspect + aprobacion manual.
  #
  # OJO: aqui NO hay puerta de coste en el aprovisionamiento. El apply corre en
  # HCP Terraform, no en un CodeBuild de esta cuenta, asi que no hay donde
  # interceptar el plan. El equivalente seria una run task o una policy Sentinel
  # en el workspace. Queda documentado en el README.
  policy_source_path           = "policies"
  infracost_api_key_secret_arn = var.infracost_api_key_secret_arn
  require_manual_approval      = var.require_manual_approval
}
