# ---------------------------------------------------------------------------
# Data Lake serverless
#
# Tres zonas en S3, un catalogo de Glue que las indexa, y Athena para
# consultarlas con SQL. Sin servidores, sin clusteres: se paga por consulta y
# por almacenamiento.
#
#     RAW        lo que llega tal cual, con caducidad
#      │  crawler de Glue lo cataloga
#      ▼
#   CATALOGO     tablas y esquemas descubiertos
#      │
#      ▼
#   ATHENA       SQL sobre los ficheros, sin moverlos
#
# NO declara `provider` ni `backend`: los pone quien ejecuta. En Service Catalog
# el motor los inyecta; en un no-code module de HCP, la region va como variable
# de entorno del workspace. Ver products/README.md.
# ---------------------------------------------------------------------------

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

locals {
  prefijo = "${var.environment_name}-datalake"

  # Los nombres de bucket son globales en TODO AWS. Sin la cuenta en el nombre,
  # dos personas aprovisionando el mismo producto colisionarian.
  sufijo = "${data.aws_caller_identity.current.account_id}-${data.aws_region.current.region}"

  etiquetas = {
    Producto      = "data-lake"
    Entorno       = var.environment_name
    CostCenter    = var.cost_center
    GestionadoPor = "service-catalog"
  }
}

# --- Zonas de almacenamiento ------------------------------------------------

resource "aws_s3_bucket" "raw" {
  bucket = "${local.prefijo}-raw-${local.sufijo}"

  # El taller se monta y desmonta; sin esto el destroy falla si quedan objetos.
  force_destroy = true

  tags = merge(local.etiquetas, { Zona = "raw" })
}

resource "aws_s3_bucket" "curated" {
  bucket        = "${local.prefijo}-curated-${local.sufijo}"
  force_destroy = true

  tags = merge(local.etiquetas, { Zona = "curated" })
}

# Athena escribe aqui los resultados de cada consulta. Va aparte de los datos a
# proposito: es informacion derivada y desechable, con su propia caducidad.
resource "aws_s3_bucket" "athena_results" {
  count = var.enable_athena ? 1 : 0

  bucket        = "${local.prefijo}-athena-${local.sufijo}"
  force_destroy = true

  tags = merge(local.etiquetas, { Zona = "athena-results" })
}

# --- Seguridad de los buckets, identica en los tres -------------------------

locals {
  buckets = merge(
    {
      raw     = aws_s3_bucket.raw.id
      curated = aws_s3_bucket.curated.id
    },
    var.enable_athena ? { athena = aws_s3_bucket.athena_results[0].id } : {}
  )
}

resource "aws_s3_bucket_public_access_block" "this" {
  for_each = local.buckets

  bucket                  = each.value
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  for_each = local.buckets

  bucket = each.value
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "this" {
  for_each = local.buckets

  bucket = each.value
  versioning_configuration {
    status = "Enabled"
  }
}

# Sin esto, los objetos se pueden pedir por HTTP en claro. Lo exige CIS —y el
# sentido comun para un lake con datos de negocio—, y es la misma politica que
# llevan los buckets de la propia plataforma en el Hands-on 1.
data "aws_iam_policy_document" "solo_tls" {
  for_each = local.buckets

  statement {
    sid     = "DenyInsecureCommunications"
    effect  = "Deny"
    actions = ["s3:*"]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    resources = [
      "arn:${data.aws_partition.current.partition}:s3:::${each.value}",
      "arn:${data.aws_partition.current.partition}:s3:::${each.value}/*",
    ]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "solo_tls" {
  for_each = local.buckets

  bucket = each.value
  policy = data.aws_iam_policy_document.solo_tls[each.key].json
}

# Solo la zona RAW caduca: es la que crece sin control. CURATED es el resultado
# del trabajo y no se tira sola.
resource "aws_s3_bucket_lifecycle_configuration" "raw" {
  count = var.raw_retention_days > 0 ? 1 : 0

  bucket = aws_s3_bucket.raw.id

  rule {
    id     = "caducidad-raw"
    status = "Enabled"

    filter {}

    expiration {
      days = var.raw_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

# --- Catalogo de Glue -------------------------------------------------------

resource "aws_glue_catalog_database" "this" {
  name        = replace("${local.prefijo}_catalogo", "-", "_")
  description = "Catalogo de datos del data lake ${var.environment_name}"
}

# --- Crawler ----------------------------------------------------------------
# Recorre la zona RAW y descubre esquemas solo. Sin el, cada tabla habria que
# declararla a mano.

data "aws_iam_policy_document" "crawler_trust" {
  count = var.enable_crawler ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["glue.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "crawler" {
  count = var.enable_crawler ? 1 : 0

  # El sufijo lo exige el Launch Role del catalogo, que solo permite crear roles
  # que casen `*-environment-access`. Es una restriccion deliberada: impide que
  # un producto se fabrique un rol arbitrario.
  name               = "${local.prefijo}-crawler-environment-access"
  assume_role_policy = data.aws_iam_policy_document.crawler_trust[0].json
  tags               = local.etiquetas
}

resource "aws_iam_role_policy_attachment" "crawler_glue" {
  count = var.enable_crawler ? 1 : 0

  role       = aws_iam_role.crawler[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

# Acceso acotado a la zona RAW y nada mas. El crawler no tiene por que ver
# CURATED ni los resultados de Athena.
resource "aws_iam_role_policy" "crawler_s3" {
  count = var.enable_crawler ? 1 : 0

  name = "LecturaZonaRaw"
  role = aws_iam_role.crawler[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:ListBucket"]
      Resource = [aws_s3_bucket.raw.arn, "${aws_s3_bucket.raw.arn}/*"]
    }]
  })
}

resource "aws_glue_crawler" "raw" {
  count = var.enable_crawler ? 1 : 0

  name          = "${local.prefijo}-raw"
  database_name = aws_glue_catalog_database.this.name
  role          = aws_iam_role.crawler[0].arn
  description   = "Cataloga automaticamente lo que llegue a la zona RAW"

  # Vacio = solo bajo demanda. Un schedule mal puesto es de los pocos sitios de
  # este modulo donde se puede gastar dinero sin darse cuenta.
  schedule = var.crawler_schedule != "" ? var.crawler_schedule : null

  s3_target {
    path = "s3://${aws_s3_bucket.raw.id}/"
  }

  # Si alguien borra ficheros, la tabla se marca obsoleta en vez de desaparecer:
  # perder el esquema es peor que tener una tabla vacia.
  schema_change_policy {
    delete_behavior = "DEPRECATE_IN_DATABASE"
    update_behavior = "UPDATE_IN_DATABASE"
  }

  tags = local.etiquetas
}

# --- Athena -----------------------------------------------------------------

resource "aws_athena_workgroup" "this" {
  count = var.enable_athena ? 1 : 0

  name        = local.prefijo
  description = "Consultas SQL sobre el catalogo de ${var.environment_name}"
  tags        = local.etiquetas

  configuration {
    # Que la ubicacion de resultados NO se pueda sobrescribir desde el cliente:
    # sin esto, cualquiera puede mandar los resultados a un bucket suyo y sacar
    # datos del lake sin dejar rastro aqui.
    enforce_workgroup_configuration = true

    result_configuration {
      output_location = "s3://${aws_s3_bucket.athena_results[0].id}/resultados/"

      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }
  }
}

# ---------------------------------------------------------------------------
# Invariantes del data lake
#
# Se evaluan en cada plan y apply, y ademas de forma PERIODICA si el workspace
# tiene activada la continuous validation de HCP Terraform. Ahi esta su valor:
# no comprueban que el codigo este bien —de eso van los tests— sino que lo
# desplegado SIGA cumpliendo semanas despues.
#
# Si alguien quita el bloqueo de acceso publico desde la consola, el refresh
# periodico lo detecta y estas comprobaciones fallan con un mensaje legible, en
# vez de aparecer como un diff crudo en un plan que nadie mira.
#
# Fallan como AVISO, no como error: no bloquean el apply. Es deliberado —
# avisar de una desviacion no deberia impedir corregirla.
# ---------------------------------------------------------------------------

check "ningun_bucket_es_publico" {
  assert {
    condition = alltrue([
      for b in aws_s3_bucket_public_access_block.this :
      b.block_public_acls && b.block_public_policy && b.ignore_public_acls && b.restrict_public_buckets
    ])
    error_message = "Algun bucket del data lake perdio el bloqueo de acceso publico. Revisa si se toco desde la consola."
  }
}

check "solo_se_habla_por_tls" {
  assert {
    condition     = length(aws_s3_bucket_policy.solo_tls) == length(local.buckets)
    error_message = "Algun bucket del data lake se quedo sin la politica que obliga a HTTPS."
  }
}

check "todo_cifrado_en_reposo" {
  assert {
    condition = alltrue([
      for c in aws_s3_bucket_server_side_encryption_configuration.this :
      length(c.rule) > 0
    ])
    error_message = "Algun bucket del data lake se quedo sin cifrado en reposo."
  }
}

check "raw_caduca_si_se_pidio" {
  assert {
    # Con retencion 0 no hay regla que comprobar: la condicion se cumple sola.
    condition = var.raw_retention_days == 0 || (
      length(aws_s3_bucket_lifecycle_configuration.raw) == 1 &&
      alltrue([
        for lc in aws_s3_bucket_lifecycle_configuration.raw :
        one(lc.rule).status == "Enabled"
      ])
    )
    error_message = "Se pidio caducidad en la zona RAW pero la regla de ciclo de vida no esta activa: los datos se acumularian sin limite."
  }
}

check "athena_no_puede_sacar_datos_fuera" {
  assert {
    # Se recorre la lista en vez de indexar: `||` y `&&` NO cortocircuitan en
    # Terraform, asi que `aws_athena_workgroup.this[0]` revienta con Athena
    # desactivada. Sobre una lista vacia, alltrue() devuelve true.
    condition = alltrue([
      for w in aws_athena_workgroup.this :
      w.configuration[0].enforce_workgroup_configuration
    ])
    error_message = "El workgroup de Athena dejo de forzar su configuracion: cualquiera podria redirigir los resultados a un bucket propio."
  }
}
