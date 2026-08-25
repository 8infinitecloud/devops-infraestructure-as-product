variable "region" {
  type        = string
  default     = "us-east-1"
  description = "Region de AWS"
}

variable "tfc_organization" {
  type        = string
  description = "Organizacion de HCP Terraform"
}

variable "tfc_team" {
  type        = string
  default     = "aurex-service-catalog"
  description = "Team que el motor crea para aprovisionar"
}

variable "tfc_hostname" {
  type        = string
  default     = "app.terraform.io"
  description = "Hostname de HCP Terraform"
}

variable "github_repository_id" {
  type        = string
  description = "Repositorio en formato owner/repo"
}

variable "github_branch" {
  type        = string
  default     = "main"
  description = "Rama que dispara la pipeline"
}

variable "existing_connection_arn" {
  type        = string
  default     = ""
  description = "Conexion de CodeConnections ya autorizada. Vacio = crear una nueva."
}

variable "grant_access_to_principal_arns" {
  type        = list(string)
  default     = []
  description = "Quien puede lanzar productos del Portfolio"
}

variable "terraform_version" {
  type        = string
  default     = "1.5.7"
  description = "Version de Terraform en los workspaces de HCP Terraform"
}
