# ---------------------------------------------------------------------------
# standard-environment
#
# Modulo de ejemplo del taller "Infrastructure as a Product" (Aurex).
# Entrega tres cosas que cualquier equipo necesita para arrancar:
#   1. Red          -> VPC + subredes + salida a internet
#   2. Almacenamiento -> bucket S3 cifrado y privado
#   3. Rol de acceso  -> rol IAM que da acceso de lectura a ese bucket
#
# El mismo modulo se aprovisiona con los dos motores del taller:
#   - Hands-on 1: Terraform OS + AWS CodeBuild
#   - Hands-on 2: HCP Terraform (Terraform Cloud)
#
# NOTA: la region, el assume_role del launch role y las default_tags NO se
# declaran aqui. Los inyecta el motor en tiempo de ejecucion mediante
# provider_override.tf.json.
# ---------------------------------------------------------------------------

terraform {
  required_version = ">= 1.3"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5"
    }
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

locals {
  name = var.environment_name

  common_tags = {
    Module      = "standard-environment"
    Environment = var.environment_name
    CostCenter  = var.cost_center
    ManagedBy   = "aws-service-catalog"
  }

  az_names = slice(data.aws_availability_zones.available.names, 0, var.subnet_count)
}

# --- 1. Red ----------------------------------------------------------------

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, { Name = "${local.name}-vpc" })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = merge(local.common_tags, { Name = "${local.name}-igw" })
}

resource "aws_subnet" "this" {
  count = var.subnet_count

  vpc_id            = aws_vpc.this.id
  availability_zone = local.az_names[count.index]
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)

  tags = merge(local.common_tags, { Name = "${local.name}-subnet-${count.index + 1}" })
}

resource "aws_route_table" "this" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge(local.common_tags, { Name = "${local.name}-rt" })
}

resource "aws_route_table_association" "this" {
  count = var.subnet_count

  subnet_id      = aws_subnet.this[count.index].id
  route_table_id = aws_route_table.this.id
}

# --- 2. Almacenamiento ------------------------------------------------------

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "this" {
  bucket        = "${local.name}-storage-${data.aws_caller_identity.current.account_id}-${random_id.bucket_suffix.hex}"
  force_destroy = true

  tags = merge(local.common_tags, { Name = "${local.name}-storage" })
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = var.enable_bucket_versioning ? "Enabled" : "Suspended"
  }
}

# --- 3. Rol de acceso -------------------------------------------------------

resource "aws_iam_role" "access" {
  name        = "${local.name}-environment-access"
  description = "Da acceso de lectura al almacenamiento del entorno ${local.name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "access" {
  name = "${local.name}-storage-read"
  role = aws_iam_role.access.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:ListBucket"]
      Resource = [aws_s3_bucket.this.arn, "${aws_s3_bucket.this.arn}/*"]
    }]
  })
}
