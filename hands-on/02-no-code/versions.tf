terraform {
  required_version = ">= 1.5"

  required_providers {
    tfe = {
      source  = "hashicorp/tfe"
      version = "~> 0.60"
    }
  }
}

# El token NO va aqui. Se toma de TFE_TOKEN o de
# ~/.terraform.d/credentials.tfrc.json, igual que en el resto del taller.
provider "tfe" {
  hostname = var.tfc_hostname
}
