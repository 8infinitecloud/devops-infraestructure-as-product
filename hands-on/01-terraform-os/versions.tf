terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # >= 5.55 por aws_codeconnections_connection. Se acota al major 5 para que
      # los dos hands-on usen la misma familia de provider.
      version = ">= 5.55, < 6.62"
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.4"
    }
  }

  # El state local vale para el taller. Para multicuenta o para un pipeline,
  # descomenta un backend remoto:
  #
  # backend "s3" {
  #   bucket = "<tu-bucket-de-state>"
  #   key    = "aurex/demo1/terraform.tfstate"
  #   region = "us-east-1"
  # }
}

# ---------------------------------------------------------------------------
# El unico sitio donde se configura un provider.
#
# Para multicuenta, aqui se anadirian alias (uno por cuenta spoke) y se pasarian
# a los modulos con `providers = { aws = aws.spoke }`. Ningun modulo cambia.
# ---------------------------------------------------------------------------
provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project = "aurex-infrastructure-as-a-product"
      HandsOn = "01-terraform-os"
    }
  }
}
