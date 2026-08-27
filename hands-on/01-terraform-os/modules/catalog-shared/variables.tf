variable "artifact_bucket_name" {
  type        = string
  description = "Nombre del bucket de artefactos. Global en todo AWS, asi que conviene incluir cuenta y region."
}

variable "existing_connection_arn" {
  type        = string
  description = <<-EOT
    ARN de una conexion de CodeConnections a GitHub YA AUTORIZADA.
    Vacio => se crea una nueva, que nace en estado PENDING y hay que autorizar a
    mano una unica vez en la consola de AWS.
  EOT
  default     = ""
}

variable "connection_name" {
  type        = string
  description = "Nombre de la conexion a crear (solo si existing_connection_arn esta vacio)"
  default     = "aurex-github"
}
