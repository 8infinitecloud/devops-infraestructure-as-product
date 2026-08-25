# ---------------------------------------------------------------------------
# Bucket del state de Terraform. Un objeto por producto aprovisionado, con la
# clave "<accountId>/<provisionedProductId>" que escribe backend_override.tf.json.
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "logging" {
  bucket        = "sc-terraform-engine-logging-${local.account_id}-${local.region}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "logging" {
  bucket                  = aws_s3_bucket.logging.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logging" {
  bucket = aws_s3_bucket.logging.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

data "aws_iam_policy_document" "logging" {
  statement {
    sid       = "S3ServerAccessLogsPolicy"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.logging.arn}/*"]
    principals {
      type        = "Service"
      identifiers = ["logging.s3.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }

  statement {
    sid     = "DenyInsecureCommunications"
    effect  = "Deny"
    actions = ["s3:*"]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    resources = [aws_s3_bucket.logging.arn, "${aws_s3_bucket.logging.arn}/*"]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "logging" {
  bucket = aws_s3_bucket.logging.id
  policy = data.aws_iam_policy_document.logging.json
}

data "aws_iam_policy_document" "state_bucket_key" {
  statement {
    sid     = "Enable KMS actions to principals in this account with IAM permissions"
    effect  = "Allow"
    actions = ["kms:*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
    }
    resources = ["*"]
  }
}

resource "aws_kms_key" "state_bucket" {
  description             = "A symmetric encryption KMS key for the Terraform state bucket"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.state_bucket_key.json

  tags = { Name = "TerraformStateBucketKey" }
}

resource "aws_s3_bucket" "state" {
  bucket = "sc-terraform-engine-state-${local.account_id}-${local.region}"

  # El taller se destruye al final; sin esto el destroy fallaria por objetos versionados.
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.state_bucket.arn
    }
  }
}

resource "aws_s3_bucket_logging" "state" {
  bucket        = aws_s3_bucket.state.id
  target_bucket = aws_s3_bucket.logging.id
  target_prefix = "sc-terraform-engine-state/log"
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "state_bucket" {
  statement {
    sid     = "DenyInsecureCommunications"
    effect  = "Deny"
    actions = ["s3:*"]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    resources = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  statement {
    sid       = "AllowReadOnlyS3AccessForDesignatedRole"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"]
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.get_state_file_outputs.arn]
    }
  }

  statement {
    sid       = "AllowAllS3AccessForDesignatedRole"
    effect    = "Allow"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"]
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.codebuild_runner.arn]
    }
  }

  statement {
    sid       = "DenyEveryoneElseExceptDesignatedRoles"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = ["${aws_s3_bucket.state.arn}/*"]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    condition {
      test     = "ArnNotEquals"
      variable = "aws:PrincipalArn"
      values = [
        aws_iam_role.get_state_file_outputs.arn,
        aws_iam_role.codebuild_runner.arn,
      ]
    }
  }
}

resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = data.aws_iam_policy_document.state_bucket.json
}
