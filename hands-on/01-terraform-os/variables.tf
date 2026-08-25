variable "region" {
  type        = string
  description = "Region de AWS"
  default     = "us-east-1"
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

variable "existing_connection_arn" {
  type        = string
  description = "Conexion de CodeConnections ya autorizada. Vacio = crear una nueva (nacera en PENDING)."
  default     = ""
}

variable "grant_access_to_principal_arns" {
  type        = list(string)
  description = "Quien puede lanzar productos del Portfolio"
  default     = []
}

variable "terraform_cli_version" {
  type        = string
  description = "Version de Terraform que usa el runner y la validacion"
  default     = "1.5.7"
}

variable "infracost_api_key_secret_arn" {
  type        = string
  description = "ARN del secreto de Secrets Manager con la API key de Infracost. Vacio = sin estimacion de coste."
  default     = ""
}

variable "require_manual_approval" {
  type        = bool
  description = "Aprobacion manual en CodePipeline antes de publicar el producto"
  default     = true
}

variable "infracost_max_monthly_usd" {
  type        = string
  description = "Coste mensual maximo por producto aprovisionado. \"0\" = advisory."
  default     = "0"
}
