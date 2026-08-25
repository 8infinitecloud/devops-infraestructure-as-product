# ---------------------------------------------------------------------------
# catalog-pipeline
#
# GitHub -> Build/Validate -> Publish en Service Catalog. Un solo modulo para
# los dos motores; ver la variable product_type.
#
#   Source          CodeConnections trae el repo
#   Build/Validate  terraform fmt -check + terraform validate + empaquetado
#                   .tar.gz con los .tf en la RAIZ (lo exige el parameter parser)
#   Publish         create-product la primera vez, create-provisioning-artifact
#                   despues, + asociacion al portfolio + launch constraint
# ---------------------------------------------------------------------------

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.name

  portfolio_id    = var.portfolio_id
  launch_role_arn = var.launch_role_arn

  create_connection = var.existing_connection_arn == ""
  connection_arn    = local.create_connection ? aws_codeconnections_connection.github[0].arn : var.existing_connection_arn
}

# --- Conexion a GitHub -------------------------------------------------------

resource "aws_codeconnections_connection" "github" {
  count = local.create_connection ? 1 : 0

  name          = var.connection_name
  provider_type = "GitHub"
}

# --- Bucket de artefactos ----------------------------------------------------
# Guarda tanto los artefactos internos de CodePipeline como los .tar.gz
# publicados que Service Catalog entrega al motor.

resource "aws_s3_bucket" "artifacts" {
  bucket        = var.artifact_bucket_name
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "artifacts" {
  statement {
    sid     = "DenyInsecureCommunications"
    effect  = "Deny"
    actions = ["s3:*"]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    resources = [aws_s3_bucket.artifacts.arn, "${aws_s3_bucket.artifacts.arn}/*"]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  # Service Catalog descarga el artefacto publicado para entregarlo al motor.
  statement {
    sid       = "AllowServiceCatalogRead"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.artifacts.arn}/*"]
    principals {
      type        = "Service"
      identifiers = ["servicecatalog.amazonaws.com"]
    }
  }
}

resource "aws_s3_bucket_policy" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  policy = data.aws_iam_policy_document.artifacts.json
}
