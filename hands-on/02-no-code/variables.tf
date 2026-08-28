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

# --- Run tasks --------------------------------------------------------------
#
# Un mapa en vez de una variable por herramienta: asi enchufar Snyk, Prisma o
# una Lambda propia es una entrada mas, no codigo nuevo. Vacio => ninguno, y el
# hands-on despliega igual.
#
# Van DOS variables a proposito. Terraform no admite valores `sensitive` como
# clave de un for_each, asi que las claves HMAC —que son credenciales— viajan en
# un mapa aparte marcado como sensible.

variable "run_tasks" {
  type = map(object({
    url               = string
    description       = optional(string, "")
    enforcement_level = optional(string, "advisory")
    stages            = optional(list(string), ["post_plan"])
  }))

  description = <<-EOT
    Run tasks a configurar, por nombre. Ejemplo:

        run_tasks = {
          infracost = {
            url         = "https://dashboard.infracost.io/tfc/run-tasks/..."
            description = "Coste estimado sobre el plan"
          }
          snyk = {
            url               = "https://api.snyk.io/v1/tf-cloud/..."
            description       = "Seguridad de la infraestructura declarada"
            enforcement_level = "advisory"
          }
        }

    enforcement_level:
      advisory   se ve el hallazgo, el run continua   <- por defecto
      mandatory  el apply NO ocurre

    Por defecto advisory: en una demo, algo que bloquea sin avisar es peor que un
    hallazgo visible. Para un catalogo de verdad conviene mandatory — en el camino
    no-code NO hay aprobacion manual, asi que este seria el unico freno entre el
    hallazgo y el apply.

    stages: post_plan es la unica etapa con el plan completo disponible. En
    pre_plan solo hay configuracion, y sin plan no se puede estimar ni analizar
    casi nada.
  EOT

  default = {}

  validation {
    condition = alltrue([
      for t in var.run_tasks : contains(["advisory", "mandatory"], t.enforcement_level)
    ])
    error_message = "enforcement_level debe ser advisory o mandatory."
  }

  validation {
    condition = alltrue([
      for t in var.run_tasks : alltrue([
        for e in t.stages : contains(["pre_plan", "post_plan", "pre_apply", "post_apply"], e)
      ])
    ])
    error_message = "stages solo admite pre_plan, post_plan, pre_apply o post_apply."
  }
}

variable "run_task_hmac_keys" {
  type        = map(string)
  description = <<-EOT
    Clave HMAC de cada run task, con la misma clave del mapa `run_tasks`.
    Es con lo que el servicio firma sus llamadas de vuelta: sin verificarla,
    cualquiera podria hacerse pasar por el y aprobar un run.

    Aparte de `run_tasks` porque Terraform no admite valores sensibles como clave
    de un for_each.
  EOT
  default     = {}
  sensitive   = true
}
