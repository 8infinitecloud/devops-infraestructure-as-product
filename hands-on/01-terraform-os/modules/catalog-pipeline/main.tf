# ---------------------------------------------------------------------------
# catalog-pipeline
#
# UNA pipeline por producto. GitHub -> Validate -> Inspect -> Publish.
# Un solo modulo para los dos motores; ver la variable product_type.
#
#   Source          CodeConnections trae el repo
#   Build/Validate  terraform fmt -check + terraform validate + empaquetado
#                   .tar.gz con los .tf en la RAIZ (lo exige el parameter parser)
#   Inspect         Checkov, TFLint, Gitleaks, Conftest, Infracost — advisory
#   Publish         create-product la primera vez, create-provisioning-artifact
#                   despues, + asociacion al portfolio + launch constraint
#
# Este modulo esta pensado para instanciarse con for_each, uno por producto. Por
# eso NO crea ni el bucket de artefactos ni la conexion a GitHub: esos son UNO
# para todo el catalogo y viven en `catalog-shared`. Todo lo que si crea lleva
# `name_prefix`, que debe ser distinto en cada instancia.
# ---------------------------------------------------------------------------

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.name

  portfolio_id    = var.portfolio_id
  launch_role_arn = var.launch_role_arn
  connection_arn  = var.connection_arn
}
