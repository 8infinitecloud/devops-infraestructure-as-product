variable "portfolio_id" {
  type        = string
  description = "Portfolio a reutilizar. El motor de HashiCorp ya crea el suyo al aplicar."
}

variable "launch_role_name" {
  type        = string
  description = "Nombre del Launch Role del producto standard-environment"
  default     = "AurexTfcStandardEnvironmentLaunchRole"
}

variable "grant_access_to_principal_arns" {
  type        = list(string)
  description = "ARNs de usuarios o roles IAM a los que dar acceso al Portfolio"
  default     = []
}

variable "artifact_bucket_name" {
  type        = string
  description = "Bucket donde la pipeline publica los .tar.gz"
}

# ---------------------------------------------------------------------------
# Datos del motor, recibidos como variables (no via terraform_remote_state).
# En multicuenta serian los del hub, y este modulo se aplicaria en el spoke.
# ---------------------------------------------------------------------------

variable "engine_parameter_parser_role_arn" {
  type        = string
  description = "Rol del terraform-parameter-parser del motor"
}

variable "engine_send_apply_role_arn" {
  type        = string
  description = "Rol de la Lambda send-apply del motor"
}

variable "oidc_provider_arn" {
  type        = string
  description = <<-EOT
    OIDC provider que establece la confianza con HCP Terraform.
    OJO en multicuenta: un OIDC provider es un recurso IAM POR CUENTA, asi que
    cada cuenta spoke necesita el suyo propio para app.terraform.io.
  EOT
}

variable "tfc_organization" {
  type        = string
  description = "Organizacion de HCP Terraform"
}

variable "tfc_hostname" {
  type        = string
  description = "Hostname de HCP Terraform"
  default     = "app.terraform.io"
}
