variable "portfolio_name" {
  type        = string
  description = "Nombre visible del Portfolio en Service Catalog"
  default     = "Aurex Standard Environments"
}

variable "portfolio_provider_name" {
  type        = string
  description = "Equipo que publica el Portfolio"
  default     = "Plataforma Aurex"
}

variable "launch_role_name" {
  type        = string
  description = "Nombre del Launch Role. Debe ser unico por cuenta."
  default     = "AurexServiceCatalogLaunchRole"
}

# ---------------------------------------------------------------------------
# ARNs del motor.
#
# Se reciben como variables, NO via terraform_remote_state. Esto es lo que hace
# que el modulo sirva tambien en multicuenta: en un montaje hub-and-spoke estos
# ARNs son del hub y este modulo se aplica en la cuenta spoke con otro provider.
# ---------------------------------------------------------------------------

variable "engine_codebuild_role_arn" {
  type        = string
  description = "Rol de CodeBuild del motor. Ejecuta terraform apply asumiendo el Launch Role."
}

variable "engine_parameter_parser_role_arns" {
  type        = list(string)
  description = "Roles del Parameter Parser. Asumen el Launch Role para descargar el artefacto."
}

variable "grant_access_to_principal_arns" {
  type        = list(string)
  description = "ARNs de usuarios o roles IAM a los que dar acceso al Portfolio"
  default     = []
}

variable "artifact_bucket_name" {
  type        = string
  description = "Bucket donde la pipeline publica los .tar.gz. El Launch Role necesita leerlo."
}
