# Demo 2 — taller "Infrastructure as a Product" (Aurex)
# El token de HCP Terraform NO va aqui: se lee de la variable de entorno TFE_TOKEN
# (cargada desde ~/.config/aurex/tfe.env) o de ~/.terraform.d/credentials.tfrc.json.

tfc_organization = "8infinitecloud"
tfc_team         = "aurex-service-catalog"

# 1.5.7 es la ultima release con licencia MPL; misma version que usa la Demo 1.
terraform_version = "1.5.7"

token_rotation_interval_in_days = 30

# El OIDC provider de app.terraform.io NO existe en esta cuenta (verificado con
# aws iam list-open-id-connect-providers), asi que el modulo debe crearlo.
# Si en algun momento falla con EntityAlreadyExists, poner esto a false o
# importar el provider existente al state.
provision_oidc_provider = true
