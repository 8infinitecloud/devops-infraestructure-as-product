variable "tfc_organization" {
  type        = string
  description = "Organizacion de HCP Terraform"
}

variable "tfc_hostname" {
  type        = string
  description = "Hostname de HCP Terraform"
  default     = "app.terraform.io"
}

variable "project_name" {
  type        = string
  description = "Proyecto que agrupa los workspaces creados desde el no-code module"
  default     = "aurex-catalogo"
}

# --- Run task de Infracost --------------------------------------------------
# Mismo idioma que el resto del repo: vacio => no se configura nada. Asi el
# hands-on despliega aunque no tengas cuenta de Infracost.

variable "infracost_run_task_url" {
  type        = string
  description = <<-EOT
    URL del run task de Infracost.
    Se obtiene en Infracost Cloud: Org Settings -> Integrations -> Terraform Cloud.
    Vacio => no se configura el run task.
  EOT
  default     = ""
}

variable "infracost_hmac_key" {
  type        = string
  description = "Clave HMAC con la que Infracost firma sus llamadas. La da la misma pantalla."
  default     = ""
  sensitive   = true
}

variable "infracost_enforcement" {
  type        = string
  description = <<-EOT
    Que pasa si Infracost falla.

      advisory   se ve el hallazgo, el run continua
      mandatory  el apply NO ocurre

    Por defecto advisory: en una demo, algo que bloquea sin avisar es peor que un
    hallazgo visible. Para un catalogo de verdad conviene mandatory — en el camino
    no-code NO hay aprobacion manual, asi que este seria el unico freno entre el
    hallazgo y el apply.
  EOT
  default     = "advisory"

  validation {
    condition     = contains(["advisory", "mandatory"], var.infracost_enforcement)
    error_message = "Debe ser advisory o mandatory."
  }
}
