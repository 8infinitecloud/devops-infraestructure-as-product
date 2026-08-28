# ---------------------------------------------------------------------------
# Estas variables SON la interfaz del producto.
#
# El parameter parser las lee del .tf y las convierte en los campos del
# formulario —el asistente de Service Catalog, o el de un no-code module—. La
# `description` es el unico texto que lee quien aprovisiona: una vacia deja un
# campo con nombre tecnico y nada mas.
# ---------------------------------------------------------------------------

variable "environment_name" {
  type        = string
  description = "Nombre corto del data lake. Prefija todos los recursos creados. Solo minusculas, numeros y guiones."
  default     = "analitica"

  validation {
    # Los nombres de bucket S3 no admiten mayusculas ni guiones bajos, y esto
    # va como prefijo. Fallar aqui, en el plan, es mucho mas barato que fallar
    # a mitad del apply con media infraestructura creada.
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,20}[a-z0-9]$", var.environment_name))
    error_message = "Entre 3 y 22 caracteres: minusculas, numeros y guiones. No puede empezar ni acabar en guion."
  }
}

variable "cost_center" {
  type        = string
  description = "Centro de coste al que se imputa el data lake. Se aplica como etiqueta a todos los recursos."
  default     = "not-assigned"
}

variable "raw_retention_days" {
  type        = number
  description = "Dias que se conservan los datos en la zona RAW antes de borrarse. 0 = sin caducidad."
  default     = 90

  validation {
    condition     = var.raw_retention_days >= 0 && var.raw_retention_days <= 3650
    error_message = "Entre 0 y 3650 dias (10 anos)."
  }
}

variable "enable_crawler" {
  type        = bool
  description = "Crea un crawler de Glue que cataloga automaticamente lo que llegue a la zona RAW."
  default     = true
}

variable "crawler_schedule" {
  type        = string
  description = "Cada cuanto se ejecuta el crawler, en formato cron de AWS. Vacio = solo bajo demanda."
  default     = "cron(0 2 * * ? *)"
}

variable "enable_athena" {
  type        = bool
  description = "Crea un workgroup de Athena para consultar el catalogo con SQL."
  default     = true
}
