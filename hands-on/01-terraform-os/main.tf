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
  # concede permisos sobre el, catalog-shared lo crea.
  artifact_bucket = "aurex-sc-artifacts-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.name}"

  # -------------------------------------------------------------------------
  # EL CATALOGO.
  #
  # Anadir un producto es anadir una entrada aqui y crear su carpeta bajo
  # `products/`. Nada mas: NO se crea infraestructura nueva. La pipeline es UNA
  # para todo el catalogo y recibe este mapa como JSON.
  #
  # Eso es la tesis del taller: el catalogo son DATOS, no codigo copiado.
  #
  #   clave  -> identificador interno. Nombra el .tar.gz dentro del artefacto.
  #   nombre -> como se ve en Service Catalog. Es la clave con la que la etapa
  #             Publish busca el producto, asi que cambiarlo crea uno NUEVO en
  #             vez de publicar una version del que ya habia.
  #   ruta   -> donde viven los .tf, relativo a la raiz del repositorio.
  #
  # ANTES de anadir un producto, lee el Launch Role de `catalog-bootstrap`: sus
  # permisos estan acotados a lo que necesita standard-environment. Un producto
  # que cree RDS o EKS pasa validate, pasa publish, y falla al APROVISIONAR, que
  # es el sitio mas caro para enterarse.
  # -------------------------------------------------------------------------
  productos = {
    standard-environment = {
      nombre      = "Standard Environment"
      ruta        = "products/standard-environment"
      descripcion = "Red, almacenamiento y rol de acceso estandar."
    }
  }
}

module "engine" {
  source = "./modules/engine"

  terraform_cli_version = var.terraform_cli_version

  # Puerta de coste en el aprovisionamiento, sobre el plan real.
  # Con "0" estima y registra pero no bloquea; ponle un tope para que aborte.
  infracost_api_key_secret_arn = var.infracost_api_key_secret_arn
  infracost_max_monthly_usd    = var.infracost_max_monthly_usd
}

module "catalog_bootstrap" {
  source = "./modules/catalog-bootstrap"

  portfolio_name       = "Aurex Standard Environments"
  launch_role_name     = "AurexServiceCatalogLaunchRole-${data.aws_region.current.name}"
  artifact_bucket_name = local.artifact_bucket

  # Los ARNs del motor viajan como variables, no por terraform_remote_state.
  # En multicuenta estos serian los del hub y este modulo se aplicaria en el spoke.
  engine_codebuild_role_arn         = module.engine.codebuild_service_role_arn
  engine_parameter_parser_role_arns = values(module.engine.parameter_parser_role_arns)

  grant_access_to_principal_arns = var.grant_access_to_principal_arns
}

# ---------------------------------------------------------------------------
# Lo que comparten TODAS las pipelines: el bucket de artefactos y la conexion a
# GitHub. Uno para todo el catalogo, no uno por producto.
# ---------------------------------------------------------------------------

module "catalog_shared" {
  source = "./modules/catalog-shared"

  artifact_bucket_name    = local.artifact_bucket
  existing_connection_arn = var.existing_connection_arn
  connection_name         = "aurex-os-github"
}

# ---------------------------------------------------------------------------
# Una pipeline por producto del catalogo.
# ---------------------------------------------------------------------------

module "catalog_pipeline" {
  source = "./modules/catalog-pipeline"

  # UNA sola pipeline para todo el catalogo. Anadir un producto es anadir una
  # entrada al mapa `productos` de arriba: no crea infraestructura nueva, solo
  # cambia la variable de entorno que reciben los proyectos de CodeBuild.
  productos = local.productos

  product_type = "EXTERNAL"
  name_prefix  = "aurex-os-catalog"

  portfolio_id         = module.catalog_bootstrap.portfolio_id
  launch_role_arn      = module.catalog_bootstrap.launch_role_arn
  artifact_bucket_name = module.catalog_shared.artifact_bucket_name
  connection_arn       = module.catalog_shared.connection_arn

  github_repository_id  = var.github_repository_id
  github_branch         = var.github_branch
  terraform_cli_version = var.terraform_cli_version

  policy_source_path           = "policies"
  infracost_api_key_secret_arn = var.infracost_api_key_secret_arn
  require_manual_approval      = var.require_manual_approval
}
