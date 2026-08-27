# Copyright IBM Corp. 2023, 2025
# SPDX-License-Identifier: MPL-2.0

terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      # Relajado de "5.12.0" exacto a ">= 5.12".
      #
      # Un pin exacto en un modulo HIJO impide componerlo: catalog-pipeline usa
      # aws_codeconnections_connection, que no existe hasta ~5.55. Es un cambio
      # de restriccion, no de logica; el motor sigue siendo el de HashiCorp.
      version = ">= 5.12"
    }
    tfe = {
      source  = "hashicorp/tfe"
      version = "0.45.0"
    }
  }
}
