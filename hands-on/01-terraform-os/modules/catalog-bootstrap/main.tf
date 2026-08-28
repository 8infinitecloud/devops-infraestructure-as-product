# ---------------------------------------------------------------------------
# catalog-bootstrap (motor Terraform OS)
#
# Portfolio de Service Catalog + Launch Role.
#
# El Launch Role es la pieza de confianza del sistema: Service Catalog se lo
# entrega al motor, y el motor lo asume para ejecutar terraform apply/destroy.
# Por eso su politica de confianza referencia los roles del motor, que llegan
# como variables.
# ---------------------------------------------------------------------------

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.name

  codebuild_role_arn         = var.engine_codebuild_role_arn
  parameter_parser_role_arns = var.engine_parameter_parser_role_arns

  artifact_bucket = var.artifact_bucket_name
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
  name               = var.launch_role_name
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
      "ec2:CreateTags", "ec2:DeleteTags",
      # El provider consulta muchas mas APIs Describe de las que se ven a simple
      # vista (ENIs al borrar subredes, prefix lists, security group rules...).
      # Describe* es solo lectura, asi que se concede en bloque en vez de ir
      # anadiendo acciones una a una segun fallan.
      "ec2:Describe*",
      # Necesarias para que el destroy pueda vaciar las subredes
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

  # Service Catalog crea un Resource Group por producto aprovisionado, y lo hace
  # asumiendo ESTE rol. Sin estos permisos el apply de Terraform funciona pero el
  # producto acaba en ERROR: "not authorized to create the resource group".
  # https://docs.aws.amazon.com/servicecatalog/latest/adminguide/getstarted-launchrole-Terraform.html
  statement {
    sid    = "ServiceCatalogResourceGroup"
    effect = "Allow"
    actions = [
      "resource-groups:CreateGroup",
      "resource-groups:DeleteGroup",
      "resource-groups:GetGroup",
      "resource-groups:GetGroupQuery",
      "resource-groups:ListGroupResources",
      "resource-groups:UpdateGroup",
      "resource-groups:Tag",
      "resource-groups:Untag",
      "resource-groups:GetTags",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ResourceTagging"
    effect = "Allow"
    actions = [
      "tag:GetResources",
      "tag:TagResources",
      "tag:UntagResources",
      "tag:GetTagKeys",
      "tag:GetTagValues",
    ]
    resources = ["*"]
  }

  # --- Permisos del producto data-lake --------------------------------------
  #
  # Cada producto que entra al catalogo puede necesitar servicios nuevos aqui, y
  # es el trabajo que mas se olvida: el fallo no aparece al publicar sino al
  # APROVISIONAR, con el usuario final delante del asistente.

  # Adjuntar politicas GESTIONADAS al rol que crea el producto. Va con condicion
  # sobre iam:PolicyARN a proposito: sin ella, un producto podria adjuntarse
  # AdministratorAccess al rol que el mismo crea, y el Launch Role existe
  # precisamente para impedir esa escalada.
  #
  # Cada producto que necesite otra politica gestionada la anade a esta lista.
  statement {
    sid       = "AdjuntarPoliticasGestionadasPermitidas"
    effect    = "Allow"
    actions   = ["iam:AttachRolePolicy", "iam:DetachRolePolicy"]
    resources = ["arn:${local.partition}:iam::${local.account_id}:role/*-environment-access"]
    condition {
      test     = "ArnEquals"
      variable = "iam:PolicyARN"
      values = [
        "arn:${local.partition}:iam::aws:policy/service-role/AWSGlueServiceRole",
      ]
    }
  }

  statement {
    sid    = "CatalogoGlue"
    effect = "Allow"
    actions = [
      "glue:CreateDatabase", "glue:DeleteDatabase", "glue:GetDatabase", "glue:GetDatabases",
      "glue:UpdateDatabase",
      "glue:CreateCrawler", "glue:DeleteCrawler", "glue:GetCrawler", "glue:GetCrawlers",
      "glue:UpdateCrawler", "glue:StartCrawler", "glue:StopCrawler",
      "glue:GetTable", "glue:GetTables", "glue:DeleteTable",
      "glue:TagResource", "glue:UntagResource", "glue:GetTags",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "WorkgroupAthena"
    effect = "Allow"
    actions = [
      "athena:CreateWorkGroup", "athena:DeleteWorkGroup", "athena:GetWorkGroup",
      "athena:UpdateWorkGroup", "athena:ListWorkGroups",
      "athena:TagResource", "athena:UntagResource", "athena:ListTagsForResource",
    ]
    resources = ["*"]
  }

  # El crawler de Glue necesita que le pasen su rol. La condicion no es opcional:
  # sin ella este permiso dejaria entregar CUALQUIER rol de la cuenta a Glue, y
  # el recurso ya esta acotado a los que el propio producto puede crear.
  statement {
    sid       = "PassRoleSoloAGlue"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = ["arn:${local.partition}:iam::${local.account_id}:role/*-environment-access"]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["glue.amazonaws.com"]
    }
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
