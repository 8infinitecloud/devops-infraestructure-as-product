# Estas variables se convierten automaticamente en parametros de aprovisionamiento
# de AWS Service Catalog: el terraform-parameter-parser (Go) lee los bloques
# `variable` de los .tf en la raiz del artefacto y expone name/description/default
# via la API DescribeProvisioningParameters.

variable "environment_name" {
  type        = string
  description = "Nombre corto del entorno. Prefija todos los recursos creados."
  default     = "demo"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,20}$", var.environment_name))
    error_message = "environment_name debe ser minusculas, numeros o guiones, entre 2 y 21 caracteres."
  }
}

variable "vpc_cidr" {
  type        = string
  description = "Bloque CIDR de la VPC del entorno."
  default     = "10.20.0.0/16"
}

variable "subnet_count" {
  type        = number
  description = "Numero de subredes a crear, repartidas entre zonas de disponibilidad."
  default     = 2

  validation {
    condition     = var.subnet_count >= 1 && var.subnet_count <= 3
    error_message = "subnet_count debe estar entre 1 y 3."
  }
}

variable "enable_bucket_versioning" {
  type        = bool
  description = "Activa el versionado en el bucket de almacenamiento del entorno."
  default     = true
}

variable "cost_center" {
  type        = string
  description = "Centro de coste al que se imputa el entorno. Se aplica como etiqueta."
  default     = "not-assigned"
}
