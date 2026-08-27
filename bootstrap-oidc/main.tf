# ---------------------------------------------------------------------------
# OPCIONAL. Solo hace falta si vas a desplegar con OIDC.
#
# El workflow `Desplegar en AWS` acepta dos formas de autenticarse y elige sola:
#
#   Con la variable AWS_DEPLOY_ROLE_ARN puesta  -> OIDC     (necesita esto)
#   Sin ella, con los secrets de claves         -> claves   (no necesita nada)
#
# Se aplica UNA vez por cuenta, desde tu maquina, con tus credenciales. Rompe el
# circulo: GitHub Actions necesita un rol para entrar en la cuenta, y ese rol no
# se lo puede crear a si mismo.
#
#     cd bootstrap-oidc
#     terraform init
#
#     # Si tu cuenta YA tiene el proveedor OIDC de GitHub, pasalo:
#     aws iam list-open-id-connect-providers
#     terraform apply -var github_org=TU-ORG \
#       -var existing_oidc_provider_arn=arn:aws:iam::<cuenta>:oidc-provider/token.actions.githubusercontent.com
#
#     # Si no lo tiene, se crea solo:
#     terraform apply -var github_org=TU-ORG
#     gh variable set AWS_DEPLOY_ROLE_ARN --body "$(terraform output -raw role_arn)"
#
# El bucket del state y la tabla de bloqueo NO estan aqui: los crea el propio
# workflow si faltan, para que el camino de las claves no necesite ningun paso
# previo.
# ---------------------------------------------------------------------------

data "aws_partition" "current" {}

locals {
  create_provider = var.existing_oidc_provider_arn == ""
  provider_arn = local.create_provider ? (
    aws_iam_openid_connect_provider.github[0].arn
  ) : var.existing_oidc_provider_arn
}

# --- Confianza con GitHub ----------------------------------------------------
# Sustituye a una clave de acceso: GitHub presenta un token firmado y AWS lo
# cambia por credenciales temporales de una hora.
#
# OJO: esto NO crea "el OIDC de GitHub" —ese es de GitHub y existe siempre—. Lo
# que crea es el registro de que TU CUENTA confia en ese emisor. Es un recurso
# por cuenta, y solo cabe uno por URL: si ya lo tienes de otro proyecto, pasa su
# ARN en existing_oidc_provider_arn o el apply falla.

resource "aws_iam_openid_connect_provider" "github" {
  count = local.create_provider ? 1 : 0

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]

  # AWS ya no valida esta huella para GitHub —confia en la CA publica— pero el
  # argumento sigue siendo obligatorio.
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

data "aws_iam_policy_document" "assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.provider_arn]
    }

    # Sin esta condicion, CUALQUIER repositorio de GitHub podria asumir el rol.
    # El `aud` solo comprueba que el token va dirigido a STS; quien acota de
    # verdad es el `sub`.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_org}/${var.github_repo}:ref:refs/heads/${var.github_branch}"]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name                 = var.role_name
  description          = "Despliega el taller desde ${var.github_org}/${var.github_repo}, rama ${var.github_branch}"
  assume_role_policy   = data.aws_iam_policy_document.assume.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "github_actions" {
  for_each = toset(var.policy_arns)

  role       = aws_iam_role.github_actions.name
  policy_arn = each.value
}
