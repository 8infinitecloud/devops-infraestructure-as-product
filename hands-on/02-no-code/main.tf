# ---------------------------------------------------------------------------
# Hands-on 2 — el catalogo en HCP Terraform, sin motor
#
# El hands-on 1 monta el catalogo en AWS: Service Catalog, un motor con colas,
# Lambdas y Step Functions, y una pipeline que publica productos.
#
# Aqui no hay nada de eso. HCP Terraform ya trae catalogo (registro privado),
# formulario (no-code modules) y analisis (run tasks, policies, health). Este
# fichero solo lo configura.
#
# Es la comparacion honesta del taller: no "dos motores para lo mismo", sino
# "dos plataformas, y lo que tienes que construir en cada una".
# ---------------------------------------------------------------------------

data "tfe_organization" "this" {
  name = var.tfc_organization
}

# Agrupa los workspaces que crea el no-code module. Sin proyecto, cada
# aprovisionamiento aparece suelto en la organizacion.
resource "tfe_project" "catalogo" {
  organization = data.tfe_organization.this.name
  name         = var.project_name
  description  = "Workspaces creados desde el catalogo de productos de Aurex"
}

# --- Analisis de coste ------------------------------------------------------
#
# El equivalente al Infracost que el hands-on 1 mete a mano en el buildspec del
# runner. La diferencia: alli hay que instalarlo, fijarle la version y programar
# la puerta; aqui es una integracion que ya existe.

resource "tfe_organization_run_task" "infracost" {
  count = var.infracost_run_task_url != "" ? 1 : 0

  organization = data.tfe_organization.this.name
  name         = "infracost"
  url          = var.infracost_run_task_url
  hmac_key     = var.infracost_hmac_key
  enabled      = true
  description  = "Estimacion de coste sobre el plan, antes de aplicar"
}

resource "tfe_workspace_run_task" "infracost" {
  for_each = var.infracost_run_task_url != "" ? tfe_workspace.demo : {}

  workspace_id      = each.value.id
  task_id           = tfe_organization_run_task.infracost[0].id
  enforcement_level = var.infracost_enforcement

  # post_plan es la unica etapa con el plan completo disponible. En pre_plan
  # solo hay configuracion, y sin plan no se puede estimar nada.
  stages = ["post_plan"]
}

# --- Workspace de demostracion ----------------------------------------------
#
# Los workspaces del no-code los crea HCP al aprovisionar, y no se pueden
# preconfigurar desde aqui. Este es uno fijo para poder ENSENAR el run task, la
# deteccion de drift y la validacion continua sin depender de que alguien
# rellene el formulario en mitad de la charla.

resource "tfe_workspace" "demo" {
  for_each = toset(["data-lake-demo"])

  name         = each.value
  organization = data.tfe_organization.this.name
  project_id   = tfe_project.catalogo.id
  description  = "Workspace de demostracion del producto data-lake"

  # Sin esto no hay drift detection ni continuous validation: son las dos
  # mitades de Health, y es lo que el hands-on 1 no tiene de ninguna forma.
  assessments_enabled = true

  # El codigo lo sube el CLI o la API, no un repositorio conectado: igual que
  # hace el motor del hands-on 1, y por el mismo motivo — se aplica una version
  # publicada, no la punta de una rama.
  auto_apply = false
}
