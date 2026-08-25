terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # Acotado a la familia 5.x a proposito:
      #   - >= 5.55 porque catalog-pipeline usa aws_codeconnections_connection
      #   - <  6.0  porque el motor vendorizado se escribio contra 5.12 y no
      #             esta validado contra el major 6
      version = ">= 5.55, < 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5"
    }
    tfe = {
      source  = "hashicorp/tfe"
      version = ">= 0.45"
    }
  }

  # backend "s3" { ... }  para multicuenta o pipeline
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project = "aurex-infrastructure-as-a-product"
      HandsOn = "02-hcp-terraform"
    }
  }
}

# Lee el token de TFE_TOKEN o de ~/.terraform.d/credentials.tfrc.json
provider "tfe" {
  hostname = var.tfc_hostname
}
