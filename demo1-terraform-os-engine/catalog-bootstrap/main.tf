# ---------------------------------------------------------------------------
# catalog-bootstrap
#
# Portfolio de Service Catalog + Launch Role.
#
# El Launch Role es la pieza de confianza del sistema: Service Catalog se lo
# entrega al motor, y el motor lo asume para ejecutar terraform apply/destroy.
# Por eso su politica de confianza referencia el rol de CodeBuild que expone
# engine/, leido aqui via terraform_remote_state.
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

  codebuild_role_arn         = data.terraform_remote_state.engine.outputs.codebuild_service_role_arn
  parameter_parser_role_arns = values(data.terraform_remote_state.engine.outputs.parameter_parser_role_arns)

  artifact_bucket = var.artifact_bucket_name != "" ? var.artifact_bucket_name : "aurex-sc-artifacts-${local.account_id}-${local.region}"
}

resource "aws_servicecatalog_portfolio" "this" {
  name          = var.portfolio_name
  description   = "Productos Terraform estandar publicados por la plataforma"
  provider_name = var.portfolio_provider_name
}

resource "aws_servicecatalog_principal_portfolio_association" "this" {
  for_each = toset(var.grant_access_to_principal_arns)

  portfolio_id   = aws_servicecatalog_portfolio.this.id
  principal_arn  = each.value
  principal_type = "IAM"
}

# --- Launch Role -------------------------------------------------------------

data "aws_iam_policy_document" "launch_role_trust" {
  statement {
    sid     = "ServiceCatalogLaunch"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["servicecatalog.amazonaws.com"]
    }
  }

  statement {
    sid     = "EngineAssumesLaunchRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type = "AWS"
      # CodeBuild ejecuta terraform; el Parameter Parser descarga el artefacto
      identifiers = concat([local.codebuild_role_arn], local.parameter_parser_role_arns)
    }
  }
}

resource "aws_iam_role" "launch" {
  name               = "AurexServiceCatalogLaunchRole-${local.region}"
  description        = "Rol que el motor asume para aprovisionar los productos del Portfolio"
  assume_role_policy = data.aws_iam_policy_document.launch_role_trust.json
}

# Permisos que necesita el modulo standard-environment: red, almacenamiento y rol de acceso.
data "aws_iam_policy_document" "launch_role_permissions" {
  statement {
    sid    = "Networking"
    effect = "Allow"
    actions = [
      "ec2:CreateVpc", "ec2:DeleteVpc", "ec2:ModifyVpcAttribute",
      "ec2:DescribeVpcs", "ec2:DescribeVpcAttribute",
      "ec2:CreateSubnet", "ec2:DeleteSubnet", "ec2:DescribeSubnets", "ec2:ModifySubnetAttribute",
      "ec2:CreateInternetGateway", "ec2:DeleteInternetGateway",
      "ec2:AttachInternetGateway", "ec2:DetachInternetGateway", "ec2:DescribeInternetGateways",
      "ec2:CreateRouteTable", "ec2:DeleteRouteTable", "ec2:DescribeRouteTables",
      "ec2:CreateRoute", "ec2:DeleteRoute",
      "ec2:AssociateRouteTable", "ec2:DisassociateRouteTable",
      "ec2:DescribeAvailabilityZones", "ec2:DescribeAccountAttributes",
      "ec2:CreateTags", "ec2:DeleteTags", "ec2:DescribeTags",
      "ec2:DescribeNetworkAcls", "ec2:DescribeSecurityGroups",
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
      "s3:GetObject", "s3:PutObject", "s3:DeleteObject",
      "s3:GetObjectVersion", "s3:DeleteObjectVersion",
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

  # El motor descarga el artefacto del producto asumiendo este rol.
  statement {
    sid     = "ReadProvisioningArtifacts"
    effect  = "Allow"
    actions = ["s3:GetObject", "s3:GetObjectVersion", "s3:ListBucket"]
    resources = [
      "arn:${local.partition}:s3:::${local.artifact_bucket}",
      "arn:${local.partition}:s3:::${local.artifact_bucket}/*",
    ]
  }
}

resource "aws_iam_role_policy" "launch" {
  name   = "StandardEnvironmentProvisioning"
  role   = aws_iam_role.launch.id
  policy = data.aws_iam_policy_document.launch_role_permissions.json
}
