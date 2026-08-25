variable "region" {
  type        = string
  description = "Region de AWS"
  default     = "us-east-1"
}

variable "bootstrap_state_path" {
  type        = string
  description = "Ruta al state de catalog-bootstrap/. De ahi se leen el Portfolio ID y el Launch Role."
  default     = "../catalog-bootstrap/terraform.tfstate"
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
  default     = "demo1-terraform-os-engine/catalog-modules/standard-environment"
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
