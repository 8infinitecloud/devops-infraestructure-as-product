# Copyright IBM Corp. 2023, 2025
# SPDX-License-Identifier: MPL-2.0


data "tfe_organization" "organization" {
  name = var.tfc_organization
}

resource "tfe_team" "provisioning_team" {
  name         = var.tfc_team
  organization = data.tfe_organization.organization.name
  organization_access {
    manage_projects   = true
    manage_workspaces = true
  }
}

resource "tfe_team_token" "test_team_token" {
  team_id = tfe_team.provisioning_team.id
}

resource "aws_secretsmanager_secret" "team_token_values" {
  name = "terraform-cloud-credentials-for-service-catalog-engine"

  # Anadido sobre el modulo upstream.
  #
  # Por defecto, destroy deja el secreto en ventana de recuperacion 30 dias, y
  # el nombre queda BLOQUEADO: el siguiente apply falla con
  #   "a secret with this name is already scheduled for deletion".
  # Para un taller que se monta y desmonta en cada pase eso lo hace
  # irrepetible. Con 0 el destroy lo purga y el motor vuelve a desplegarse.
  #
  # En produccion querrias el valor por defecto: esto renuncia a poder
  # recuperar el secreto tras borrarlo.
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "tfc_credentials" {
  secret_id = aws_secretsmanager_secret.team_token_values.id
  secret_string = jsonencode({
    hostname = var.tfc_hostname
    id       = tfe_team.provisioning_team.id
    token    = tfe_team_token.test_team_token.token
  })
}
