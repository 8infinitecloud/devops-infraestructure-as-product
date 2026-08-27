# Copyright IBM Corp. 2023, 2025
# SPDX-License-Identifier: MPL-2.0
#
# ---------------------------------------------------------------------------
# Envoltorio del motor de HCP Terraform.
#
# ./engine/ es el modulo de HashiCorp SIN MODIFICAR. Este archivo solo lo
# instancia, crea el Portfolio y expone los outputs que necesitan los demas
# modulos. No hay provider blocks: los pasa el root module.
# ---------------------------------------------------------------------------

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
    random = {
      source  = "hashicorp/random"
      version = "3.5.1"
    }
    tfe = {
      source  = "hashicorp/tfe"
      version = "0.45.0"
    }
  }
}

# This module provisions the Terraform Cloud Reference Engine. If you would like to provision the Reference Engine
# without the example product, you can use this module in your own terraform configuration/workspace.
module "terraform_cloud_reference_engine" {
  source = "./engine"

  tfc_organization                 = var.tfc_organization
  tfc_team                         = var.tfc_team
  tfc_aws_audience                 = var.tfc_aws_audience
  tfc_hostname                     = var.tfc_hostname
  cloudwatch_log_retention_in_days = var.cloudwatch_log_retention_in_days
  enable_xray_tracing              = var.enable_xray_tracing
  token_rotation_interval_in_days  = var.token_rotation_interval_in_days
  terraform_version                = var.terraform_version
  provision_oidc_provider          = var.provision_oidc_provider
}

# Creates an AWS Service Catalog Portfolio to house the example product
resource "aws_servicecatalog_portfolio" "portfolio" {
  name          = var.portfolio_name
  description   = "Example Portfolio created via AWS Service Catalog Engine for TFC"
  provider_name = "HashiCorp Examples"
}

# An example product
module "example_product" {
  source = "./example-product"

  # El producto de ejemplo del motor no hace falta para el taller: la pipeline
  # publica standard-environment. Se deja disponible para demostrar el motor
  # por si solo, sin pipeline.
  count = var.create_example_product ? 1 : 0

  # ARNs of Lambda functions that need to be able to assume the IAM Launch Role
  parameter_parser_role_arn  = module.terraform_cloud_reference_engine.parameter_parser_role_arn
  send_apply_lambda_role_arn = module.terraform_cloud_reference_engine.send_apply_lambda_role_arn

  # AWS Service Catalog portfolio you would like to add this product to
  service_catalog_portfolio_ids = [aws_servicecatalog_portfolio.portfolio.id]

  # Variables for authentication to AWS via Dynamic Credentials
  tfc_hostname     = module.terraform_cloud_reference_engine.tfc_hostname
  tfc_organization = module.terraform_cloud_reference_engine.tfc_organization
  tfc_provider_arn = module.terraform_cloud_reference_engine.oidc_provider_arn

}
