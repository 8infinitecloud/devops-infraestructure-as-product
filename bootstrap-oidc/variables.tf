variable "region" {
  type        = string
  description = "Region para el provider. El rol y el proveedor OIDC son globales."
  default     = "us-east-1"
}

variable "github_org" {
  type        = string
  description = "Organizacion o usuario de GitHub"
}

variable "github_repo" {
  type        = string
  description = "Nombre del repositorio, sin la organizacion"
  default     = "devops-infraestructure-as-product"
}

variable "github_branch" {
  type        = string
  description = <<-EOT
    Unica rama desde la que se puede asumir el rol.

    Es EL control de acceso, no un detalle: un workflow en cualquier otra rama, o
    en un fork, no obtiene credenciales. Los permisos del rol son amplios; lo que
    acota el riesgo es esta condicion.
  EOT
  default     = "main"
}

variable "existing_oidc_provider_arn" {
  type        = string
  description = <<-EOT
    ARN de un proveedor OIDC de GitHub que YA exista en la cuenta.

    Es un recurso POR CUENTA y AWS solo admite uno por URL: si ya hay uno —de
    otro proyecto, de otro repositorio— crear otro falla con EntityAlreadyExists.
    Es un fallo muy comun porque no se ve venir: el proveedor es global y no
    aparece en ningun sitio del taller.

    Comprueba si lo tienes:

        aws iam list-open-id-connect-providers

    Vacio => se crea uno nuevo.
  EOT
  default     = ""
}

variable "role_name" {
  type        = string
  description = "Nombre del rol que asumen los workflows"
  default     = "aurex-github-actions"
}

variable "policy_arns" {
  type        = list(string)
  description = <<-EOT
    Politicas que se asocian al rol.

    Por defecto AdministratorAccess, y conviene entender por que antes de
    aceptarlo: el taller crea roles y politicas IAM —el Launch Role de Service
    Catalog, los del motor, el de CodeBuild—, asi que el rol necesita iam:* de
    todas formas. Acotar el resto por servicio daria una lista tan larga que
    dejaria de ser auditable sin reducir el riesgo real.

    Para una cuenta que no sea de taller, pon aqui una politica acotada.
  EOT
  default     = ["arn:aws:iam::aws:policy/AdministratorAccess"]
}
