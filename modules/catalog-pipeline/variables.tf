# ---------------------------------------------------------------------------
# Este modulo sirve a los DOS motores. Lo unico que cambia entre ellos es el
# tipo de producto:
#
#   EXTERNAL        -> motor Terraform OS. Enruta a las colas
#                      ServiceCatalogExternal*OperationQueue.
#   TERRAFORM_CLOUD -> motor de HCP Terraform. Enruta a las colas
#                      ServiceCatalogTerraformCloud*OperationQueue.
#
# (TERRAFORM_OPEN_SOURCE existia hasta el 2023-12-14; AWS lo sustituyo por
#  EXTERNAL y ya no se acepta en CreateProduct.)
# ---------------------------------------------------------------------------

variable "product_type" {
  type        = string
  description = "Tipo de producto en Service Catalog"

  validation {
    condition     = contains(["EXTERNAL", "TERRAFORM_CLOUD"], var.product_type)
    error_message = "product_type debe ser EXTERNAL (motor Terraform OS) o TERRAFORM_CLOUD (motor HCP Terraform)."
  }
}

variable "name_prefix" {
  type        = string
  description = "Prefijo de los recursos. Permite que los dos hands-on convivan en la misma cuenta."
  default     = "aurex-catalog"
}

variable "portfolio_id" {
  type        = string
  description = "Portfolio donde se publica el producto"
}

variable "launch_role_arn" {
  type        = string
  description = "Launch Role que se asocia al producto via Launch Constraint"
}

variable "artifact_bucket_name" {
  type        = string
  description = "Bucket donde se publican los .tar.gz"
}

variable "existing_connection_arn" {
  type        = string
  description = <<-EOT
    ARN de una conexion de CodeConnections a GitHub YA AUTORIZADA.
    Si se deja vacio, Terraform crea una nueva, que nace en estado PENDING y
    hay que autorizar a mano una unica vez en la consola de AWS.
  EOT
  default     = ""
}

variable "connection_name" {
  type        = string
  description = "Nombre de la conexion a crear (solo si existing_connection_arn esta vacio)"
  default     = "aurex-github"
}

variable "github_repository_id" {
  type        = string
  description = "Repositorio en formato owner/repo"
}

variable "github_branch" {
  type        = string
  description = "Rama que dispara la pipeline"
  default     = "main"
}

variable "module_source_path" {
  type        = string
  description = "Ruta dentro del repo donde viven los .tf del modulo a publicar"
  default     = "hands-on/01-terraform-os/catalog-modules/standard-environment"
}

variable "product_name" {
  type        = string
  description = "Nombre del producto en Service Catalog"
  default     = "Standard Environment"
}

variable "product_owner" {
  type        = string
  description = "Propietario del producto"
  default     = "Plataforma Aurex"
}

variable "terraform_cli_version" {
  type        = string
  description = "Version de Terraform para fmt/validate en la etapa de Build"
  default     = "1.5.7"
}

variable "log_retention_days" {
  type        = number
  default     = 30
  description = "Retencion de los log groups de la pipeline"
}

# ---------------------------------------------------------------------------
# Etapa de inspeccion: seguridad, politica y coste.
#
# Es ADVISORY por diseno: los hallazgos se reportan pero no detienen la pipeline.
# Quien decide es la aprobacion manual de la etapa siguiente.
# ---------------------------------------------------------------------------

variable "policy_source_path" {
  type        = string
  description = "Ruta en el repo a las politicas Rego que evalua Conftest"
  default     = "policies"
}

variable "infracost_api_key_secret_arn" {
  type        = string
  description = <<-EOT
    ARN del secreto de Secrets Manager con la API key de Infracost.
    Formato esperado del secreto: {"api_key":"ico-..."}.
    Vacio = se omite la estimacion de coste.
  EOT
  default     = ""
}

variable "require_manual_approval" {
  type        = bool
  description = "Anade una aprobacion manual en CodePipeline antes de publicar el producto"
  default     = true
}

variable "approval_notification_arn" {
  type        = string
  description = "Topic SNS opcional al que notificar cuando haya una aprobacion pendiente"
  default     = ""
}
