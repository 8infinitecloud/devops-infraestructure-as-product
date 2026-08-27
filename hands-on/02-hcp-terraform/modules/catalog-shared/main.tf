# ---------------------------------------------------------------------------
# catalog-shared
#
# Lo que comparten TODAS las pipelines del catalogo: el bucket de artefactos y
# la conexion a GitHub.
#
# Vivian dentro de catalog-pipeline, y por eso el modulo no se podia instanciar
# dos veces: dos pipelines pedian crear el mismo bucket. Los nombres de bucket
# son globales en todo AWS, asi que no es una colision de nombres de recurso de
# Terraform —que se arregla con un prefijo— sino un `apply` que falla.
#
# La regla que sale de ahi: si un recurso es UNO para todo el catalogo, no puede
# vivir en un modulo que se instancia POR PRODUCTO.
# ---------------------------------------------------------------------------

locals {
  create_connection = var.existing_connection_arn == ""
}

# --- Conexion a GitHub -------------------------------------------------------

resource "aws_codeconnections_connection" "github" {
  count = local.create_connection ? 1 : 0

  name          = var.connection_name
  provider_type = "GitHub"
}

# --- Bucket de artefactos ----------------------------------------------------
# Guarda los artefactos internos de CodePipeline y los .tar.gz publicados que
# Service Catalog entrega al motor.

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
