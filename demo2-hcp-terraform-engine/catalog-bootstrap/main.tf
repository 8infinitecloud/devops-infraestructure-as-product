# ---------------------------------------------------------------------------
# catalog-bootstrap — Demo 2
#
# El motor de HashiCorp ya crea su propio "TFC Example Portfolio" al aplicar,
# asi que aqui NO se crea un portfolio nuevo: se reutiliza ese, y esta carpeta
# se limita a lo que el modulo no trae de serie:
#
#   1. Acceso al Portfolio para el principal que va a lanzar el producto
#   2. Un Launch Role para el producto standard-environment que publica
#      catalog-pipeline/ (el motor solo crea el de SU producto de ejemplo)
# ---------------------------------------------------------------------------

data "terraform_remote_state" "engine" {
  backend = "local"
  config = {
    path = var.engine_state_path
  }
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.region

  portfolio_id              = data.terraform_remote_state.engine.outputs.example_portfolio_id
  parameter_parser_role_arn = data.terraform_remote_state.engine.outputs.parameter_parser_role_arn
  send_apply_role_arn       = data.terraform_remote_state.engine.outputs.send_apply_lambda_role_arn
  oidc_provider_arn         = data.terraform_remote_state.engine.outputs.oidc_provider_arn
  tfc_organization          = data.terraform_remote_state.engine.outputs.tfc_organization
  tfc_hostname              = data.terraform_remote_state.engine.outputs.tfc_hostname

  artifact_bucket = var.artifact_bucket_name != "" ? var.artifact_bucket_name : "aurex-sc-artifacts-tfc-${local.account_id}-${local.region}"
}

# --- 1. Acceso al Portfolio --------------------------------------------------

resource "aws_servicecatalog_principal_portfolio_association" "this" {
  for_each = toset(var.grant_access_to_principal_arns)

  portfolio_id   = local.portfolio_id
  principal_arn  = each.value
  principal_type = "IAM"
}

# --- 2. Launch Role para el producto standard-environment --------------------

data "aws_iam_openid_connect_provider" "tfc" {
  arn = local.oidc_provider_arn
}

data "aws_iam_policy_document" "launch_role_trust" {
  statement {
    sid     = "AllowServiceCatalogToAssume"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["servicecatalog.amazonaws.com"]
    }
  }

  # send-apply y el parameter parser lo asumen para descargar el artefacto de S3.
  # Se usa el root de la cuenta con condicion sobre PrincipalArn (patron del motor
  # de HashiCorp): evita depender del sufijo exacto del nombre del rol.
  statement {
    sid     = "AllowEngineLambdasToAssume"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
    }
    condition {
      test     = "StringLike"
      variable = "aws:PrincipalArn"
      values   = ["${local.send_apply_role_arn}*", "${local.parameter_parser_role_arn}*"]
    }
  }

  # Dynamic Credentials: el run de HCP Terraform asume este rol via OIDC.
  #
  # El motor acota el 'sub' al project = ID del producto. Aqui el producto lo crea
  # catalog-pipeline/ despues, asi que el project va con comodin. Es una
  # relajacion consciente y acotada a esta organizacion de HCP Terraform.
  statement {
    sid     = "AllowTfcRunsViaOidc"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.tfc_hostname}:aud"
      values   = [one(data.aws_iam_openid_connect_provider.tfc.client_id_list)]
    }
    condition {
      test     = "StringLike"
      variable = "${local.tfc_hostname}:sub"
      values   = ["organization:${local.tfc_organization}:project:*:workspace:*:run_phase:*"]
    }
  }
}

resource "aws_iam_role" "launch" {
  name               = "AurexTfcStandardEnvironmentLaunchRole"
  description        = "Launch Role del producto standard-environment sobre el motor de HCP Terraform"
  assume_role_policy = data.aws_iam_policy_document.launch_role_trust.json
}

data "aws_iam_policy_document" "launch_role_permissions" {
  # Descarga del artefacto de aprovisionamiento
  statement {
    sid       = "S3AccessToProvisioningObjects"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "s3:ExistingObjectTag/servicecatalog:provisioning"
      values   = ["true"]
    }
  }

  statement {
    sid     = "ReadPublishedArtifacts"
    effect  = "Allow"
    actions = ["s3:GetObject", "s3:GetObjectVersion", "s3:ListBucket"]
    resources = [
      "arn:${local.partition}:s3:::${local.artifact_bucket}",
      "arn:${local.partition}:s3:::${local.artifact_bucket}/*",
    ]
  }

  # Service Catalog crea un Resource Group por producto asumiendo este rol
  statement {
    sid    = "ResourceGroups"
    effect = "Allow"
    actions = [
      "resource-groups:CreateGroup", "resource-groups:DeleteGroup", "resource-groups:GetGroup",
      "resource-groups:GetGroupQuery", "resource-groups:ListGroupResources",
      "resource-groups:UpdateGroup", "resource-groups:Tag", "resource-groups:Untag",
      "resource-groups:GetTags",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "Tagging"
    effect = "Allow"
    actions = [
      "tag:GetResources", "tag:GetTagKeys", "tag:GetTagValues",
      "tag:TagResources", "tag:UntagResources",
    ]
    resources = ["*"]
  }

  # --- Permisos del modulo standard-environment: red, almacenamiento, rol ---

  statement {
    sid    = "Networking"
    effect = "Allow"
    actions = [
      "ec2:CreateVpc", "ec2:DeleteVpc", "ec2:ModifyVpcAttribute",
      "ec2:CreateSubnet", "ec2:DeleteSubnet", "ec2:ModifySubnetAttribute",
      "ec2:CreateInternetGateway", "ec2:DeleteInternetGateway",
      "ec2:AttachInternetGateway", "ec2:DetachInternetGateway",
      "ec2:CreateRouteTable", "ec2:DeleteRouteTable",
      "ec2:CreateRoute", "ec2:DeleteRoute",
      "ec2:AssociateRouteTable", "ec2:DisassociateRouteTable",
      "ec2:CreateTags", "ec2:DeleteTags",
      "ec2:Describe*",
      "ec2:DeleteNetworkInterface", "ec2:DetachNetworkInterface",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "Storage"
    effect = "Allow"
    actions = [
      "s3:CreateBucket", "s3:DeleteBucket", "s3:ListBucket",
      "s3:GetBucket*", "s3:PutBucket*", "s3:DeleteBucketPolicy",
      "s3:GetEncryptionConfiguration", "s3:PutEncryptionConfiguration",
      "s3:GetLifecycleConfiguration", "s3:PutLifecycleConfiguration",
      "s3:GetAccelerateConfiguration", "s3:GetReplicationConfiguration",
      "s3:PutObject", "s3:DeleteObject", "s3:DeleteObjectVersion",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AccessRole"
    effect = "Allow"
    actions = [
      "iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:PassRole",
      "iam:TagRole", "iam:UntagRole", "iam:ListRoleTags",
      "iam:PutRolePolicy", "iam:GetRolePolicy", "iam:DeleteRolePolicy",
      "iam:ListRolePolicies", "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole",
    ]
    resources = ["arn:${local.partition}:iam::${local.account_id}:role/*-environment-access"]
  }

  statement {
    sid       = "CallerIdentity"
    effect    = "Allow"
    actions   = ["sts:GetCallerIdentity"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "launch" {
  name   = "StandardEnvironmentProvisioning"
  role   = aws_iam_role.launch.id
  policy = data.aws_iam_policy_document.launch_role_permissions.json
}
