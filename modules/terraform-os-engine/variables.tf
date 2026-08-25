variable "name_prefix" {
  type        = string
  description = "Prefijo para los recursos con nombre generado. Permite varias instancias del motor en la misma cuenta."
  default     = "TFEngine"
}

variable "service_catalog_endpoint" {
  type        = string
  description = "Endpoint que el motor usa para llamar a Service Catalog. Vacio = el de la region."
  default     = ""
}

variable "service_catalog_verify_ssl" {
  type        = string
  description = "Verificacion SSL contra el endpoint de Service Catalog"
  default     = "True"
}

variable "terraform_cli_version" {
  type        = string
  description = "Version de Terraform CLI que instala el proyecto de CodeBuild. 1.5.7 es la ultima con licencia MPL."
  default     = "1.5.7"
}

variable "parameter_parser_memory_size" {
  type        = number
  description = "Memoria (MB) de las Lambdas Parameter Parser en Go"
  default     = 1024

  validation {
    condition     = var.parameter_parser_memory_size >= 128 && var.parameter_parser_memory_size <= 10240
    error_message = "La memoria debe estar entre 128 y 10240 MB."
  }
}

variable "runner_compute_type" {
  type        = string
  description = "Tamano del contenedor de CodeBuild que ejecuta Terraform"
  default     = "BUILD_GENERAL1_SMALL"

  validation {
    condition     = contains(["BUILD_GENERAL1_SMALL", "BUILD_GENERAL1_MEDIUM", "BUILD_GENERAL1_LARGE"], var.runner_compute_type)
    error_message = "runner_compute_type debe ser SMALL, MEDIUM o LARGE."
  }
}

variable "runner_timeout_minutes" {
  type        = number
  description = "Timeout de cada terraform apply/destroy en CodeBuild"
  default     = 60
}

variable "runner_concurrent_build_limit" {
  type        = number
  description = "Builds simultaneos maximos. Equivale al tamano del antiguo Auto Scaling Group."
  default     = 10
}

variable "log_retention_days" {
  type        = number
  description = "Retencion de los log groups del motor"
  default     = 30
}
