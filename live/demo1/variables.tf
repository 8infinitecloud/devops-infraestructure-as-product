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
