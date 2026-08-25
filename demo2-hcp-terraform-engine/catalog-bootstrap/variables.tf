variable "region" {
  type        = string
  default     = "us-east-1"
  description = "Region de AWS"
}

variable "engine_state_path" {
  type        = string
  default     = "../engine/terraform.tfstate"
  description = "State de engine/. De ahi salen los roles del motor, el OIDC provider y el portfolio."
}

variable "grant_access_to_principal_arns" {
  type        = list(string)
  default     = []
  description = "ARNs de usuarios o roles IAM a los que dar acceso al Portfolio"
}

variable "artifact_bucket_name" {
  type        = string
  default     = ""
  description = "Bucket donde catalog-pipeline/ publica los .tar.gz"
}
