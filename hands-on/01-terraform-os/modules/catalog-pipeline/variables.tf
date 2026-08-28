variable "product_type" {
  type        = string
  description = <<-EOT
    Tipo de producto en Service Catalog. Determina a que colas enruta el motor:
    EXTERNAL va a las ServiceCatalogExternal*.

    AWS retiro TERRAFORM_OPEN_SOURCE el 2023-12-14 en favor de EXTERNAL.
  EOT
  default     = "EXTERNAL"

  validation {
    condition     = var.product_type == "EXTERNAL"
    error_message = "Solo se admite EXTERNAL."
  }
}

variable "name_prefix" {
  type        = string
  description = "Prefijo de los recursos. Permite que los dos hands-on convivan en la misma cuenta."
  default     = "aurex-catalog"
}

variable "productos" {
  type = map(object({
    nombre      = string
    ruta        = string
    descripcion = optional(string, "Publicado por CodePipeline desde el repositorio del catalogo.")
  }))
  description = <<-EOT
    El catalogo entero. UNA sola pipeline publica todos.

      clave  -> identificador interno. Nombra el .tar.gz dentro del artefacto.
      nombre -> como se ve en Service Catalog. Es la clave con la que Publish
                busca el producto: cambiarlo crea uno NUEVO en vez de anadir una
                version al que ya habia.
      ruta   -> donde viven los .tf, desde la raiz del repositorio.

    Consecuencia de tener una sola pipeline: si la validacion de UN producto
    falla, no se publica NINGUNO. Es el precio de la simplicidad, y es
    deliberado; para aislarlos haria falta una pipeline por producto.
  EOT

  validation {
    condition     = length(var.productos) > 0
    error_message = "Hace falta al menos un producto."
  }
}

variable "portfolio_id" {
  type        = string
  description = "Portfolio donde se publica el producto"
}

variable "launch_role_arn" {
  type        = string
  description = "Launch Role que se asocia al producto via Launch Constraint"
}

variable "artifact_bucket_name" {
  type        = string
  description = "Bucket donde se publican los .tar.gz. Lo crea `catalog-shared`, aqui solo se usa."
}

variable "connection_arn" {
  type        = string
  description = "ARN de la conexion de CodeConnections. Lo expone `catalog-shared`."
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

variable "product_owner" {
  type        = string
  description = "Propietario del producto"
  default     = "Plataforma Aurex"
}

variable "terraform_cli_version" {
  type        = string
  description = "Version de Terraform para fmt/validate en la etapa de Build"
  default     = "1.5.7"
}

variable "trigger_file_paths" {
  type        = list(string)
  description = <<-EOT
    Rutas cuyo cambio dispara la pipeline.

    Vacio => se derivan del catalogo: la ruta de cada producto mas la de las
    politicas. Es lo que se quiere casi siempre, y evita tener que acordarse de
    tocar el filtro al anadir un producto.

    Sin filtro, CUALQUIER commit a la rama —un README, un .gitignore— publica una
    version nueva de todos los productos. Se ve enseguida en el historial de
    versiones y ensucia el catalogo.

    Para volver al comportamiento de disparar siempre: ["**"].
  EOT
  default     = []
}

variable "trigger_extra_paths" {
  type        = list(string)
  description = <<-EOT
    Rutas ADICIONALES que disparan la pipeline, ademas de las que se derivan del
    catalogo.

    El caso tipico es el fichero donde vive el mapa `productos`: anadir un
    producto es un cambio del catalogo y deberia publicarlo, pero ese fichero no
    esta bajo products/ y sin esto el push no dispararia nada.

    Cuidado con lo que se mete aqui: si el fichero contiene ademas otra
    configuracion —limites de coste, version de Terraform— cualquier retoque
    republicaria todos los productos sin que haya cambiado ninguno.
  EOT
  default     = []
}

variable "log_retention_days" {
  type        = number
  default     = 30
  description = "Retencion de los log groups de la pipeline"
}

# ---------------------------------------------------------------------------
# Etapa de inspeccion: seguridad, politica y coste.
#
# Es ADVISORY por diseno: los hallazgos se reportan pero no detienen la pipeline.
# Quien decide es la aprobacion manual de la etapa siguiente.
# ---------------------------------------------------------------------------

variable "policy_source_path" {
  type        = string
  description = "Ruta en el repo a las politicas Rego que evalua Conftest"
  default     = "policies"
}

variable "infracost_api_key_secret_arn" {
  type        = string
  description = <<-EOT
    ARN del secreto de Secrets Manager con la API key de Infracost.
    Formato esperado del secreto: {"api_key":"ico-..."}.
    Vacio = se omite la estimacion de coste.
  EOT
  default     = ""
}

variable "require_manual_approval" {
  type        = bool
  description = "Anade una aprobacion manual en CodePipeline antes de publicar el producto"
  default     = true
}

variable "approval_notification_arn" {
  type        = string
  description = "Topic SNS opcional al que notificar cuando haya una aprobacion pendiente"
  default     = ""
}
