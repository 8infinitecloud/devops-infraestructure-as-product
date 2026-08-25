variable "region" {
  type        = string
  description = "Region de AWS"
  default     = "us-east-1"
}

variable "engine_state_path" {
  type        = string
  description = "Ruta al state de engine/. De ahi se leen el ARN del rol de CodeBuild y los del Parameter Parser."
  default     = "../engine/terraform.tfstate"
}

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

variable "grant_access_to_principal_arns" {
  type        = list(string)
  description = "ARNs de usuarios o roles IAM a los que dar acceso al Portfolio. Vacio = ninguno."
  default     = []
}

variable "artifact_bucket_name" {
  type        = string
  description = "Bucket donde catalog-pipeline/ publica los .tar.gz. El Launch Role necesita leerlo."
  default     = ""
}
