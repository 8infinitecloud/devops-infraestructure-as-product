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
#     terraform apply -var github_org=TU-ORG
#     gh variable set AWS_DEPLOY_ROLE_ARN --body "$(terraform output -raw role_arn)"
#
# El bucket del state y la tabla de bloqueo NO estan aqui: los crea el propio
# workflow si faltan, para que el camino de las claves no necesite ningun paso
# previo.
# ---------------------------------------------------------------------------

data "aws_partition" "current" {}

# --- Confianza con GitHub ----------------------------------------------------
# Sustituye a una clave de acceso: GitHub presenta un token firmado y AWS lo
# cambia por credenciales temporales de una hora.

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

data "aws_iam_policy_document" "assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
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
