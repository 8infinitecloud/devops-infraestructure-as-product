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
  description = <<-EOT
    Builds simultaneos maximos. Equivale al tamano del antiguo Auto Scaling Group
    del motor original de AWS.

    Es el cuello de botella del aprovisionamiento: el que hace el numero N+1 no
    falla, espera. Con un taller de 30 personas lanzando a la vez, 10 los pondria
    en cola de tres en tres.

    TOPE: no puede superar la cuota de cuenta de CodeBuild para el compute_type
    que use el runner. Para BUILD_GENERAL1_SMALL son 60 por defecto. Ponerlo mas
    alto no da un aviso: hace fallar el apply. Comprueba la tuya con

        aws service-quotas list-service-quotas --service-code codebuild \
          --query 'Quotas[?contains(QuotaName, `Linux/Small`)].Value'

    y pide un aumento en la consola de Service Quotas si necesitas mas.
  EOT
  default     = 60
}

variable "log_retention_days" {
  type        = number
  description = "Retencion de los log groups del motor"
  default     = 30
}

# ---------------------------------------------------------------------------
# Puerta de coste en tiempo de aprovisionamiento.
#
# A diferencia de la pipeline, aqui ya existe un terraform plan con los
# parametros que eligio el usuario final, asi que la estimacion es la del
# despliegue real y no la del modulo con sus valores por defecto.
# ---------------------------------------------------------------------------

variable "infracost_api_key_secret_arn" {
  type        = string
  description = "ARN del secreto con la API key de Infracost, formato {\"api_key\":\"ico-...\"}. Vacio = sin estimacion."
  default     = ""
}

variable "infracost_max_monthly_usd" {
  type        = string
  description = <<-EOT
    Coste mensual maximo (USD) por producto aprovisionado.
    "0" = advisory: se estima y se registra, pero no se bloquea.
    Cualquier otro valor ABORTA el aprovisionamiento antes de crear recursos.
  EOT
  default     = "0"
}
