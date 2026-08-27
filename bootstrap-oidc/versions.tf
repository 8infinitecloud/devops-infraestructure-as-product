terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40, < 6.0"
    }
  }

  # State LOCAL, a proposito, y es el unico sitio del repo donde lo sera siempre.
  #
  # Esto crea el rol que permite a GitHub Actions entrar en la cuenta. Guardarlo
  # en el bucket remoto que crea el propio workflow seria el huevo y la gallina:
  # el bucket no existe hasta que el workflow corre, y el workflow no corre hasta
  # que existe el rol.
  #
  # Consecuencia practica: guarda `bootstrap-oidc/terraform.tfstate` si algun dia
  # quieres destruir esto. Si lo pierdes, se recupera importando dos recursos.
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project = "aurex-infrastructure-as-a-product"
      Fase    = "bootstrap-oidc"
    }
  }
}
