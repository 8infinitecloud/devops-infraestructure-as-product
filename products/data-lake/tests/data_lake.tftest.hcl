# Tests del modulo. Se ejecutan con `terraform test` (Terraform >= 1.7).
#
# Usan `mock_provider`, asi que NO necesitan credenciales de AWS ni crean nada:
# corren en el CI de GitHub en cada PR. Comprueban que el modulo hace lo que su
# interfaz promete, que es lo que un consumidor del catalogo da por hecho.

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_data "aws_region" {
    defaults = { region = "us-east-1" }
  }

  # Sin esto el mock devuelve un `json` cualquiera y el aws_iam_role lo rechaza
  # al validar. No importa el contenido: solo que sea JSON valido.
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
}

# --- Comportamiento por defecto ---------------------------------------------

run "por_defecto_crea_el_lake_completo" {
  command = plan

  assert {
    condition     = length(aws_glue_crawler.raw) == 1
    error_message = "Con los valores por defecto deberia crearse el crawler."
  }

  assert {
    condition     = length(aws_athena_workgroup.this) == 1
    error_message = "Con los valores por defecto deberia crearse el workgroup de Athena."
  }

  assert {
    condition     = length(aws_s3_bucket_lifecycle_configuration.raw) == 1
    error_message = "Con retencion de 90 dias deberia existir la regla de caducidad en RAW."
  }

  assert {
    # Tres zonas: raw, curated y los resultados de Athena.
    condition     = length(aws_s3_bucket_public_access_block.this) == 3
    error_message = "Los tres buckets deben tener bloqueo de acceso publico."
  }
}

# --- Los flags apagan de verdad ---------------------------------------------

run "sin_crawler_ni_athena" {
  command = plan

  variables {
    enable_crawler = false
    enable_athena  = false
  }

  assert {
    condition     = length(aws_glue_crawler.raw) == 0
    error_message = "Con enable_crawler=false no debe crearse el crawler."
  }

  assert {
    condition     = length(aws_iam_role.crawler) == 0
    error_message = "Sin crawler tampoco debe crearse su rol IAM."
  }

  assert {
    condition     = length(aws_athena_workgroup.this) == 0
    error_message = "Con enable_athena=false no debe crearse el workgroup."
  }

  assert {
    # Sin Athena sobra su bucket de resultados: quedan solo raw y curated.
    condition     = length(aws_s3_bucket_public_access_block.this) == 2
    error_message = "Sin Athena deberian quedar dos buckets, no tres."
  }
}

run "sin_caducidad_en_raw" {
  command = plan

  variables {
    raw_retention_days = 0
  }

  assert {
    condition     = length(aws_s3_bucket_lifecycle_configuration.raw) == 0
    error_message = "Con retencion 0 no debe crearse ninguna regla de caducidad."
  }
}

# --- El catalogo siempre existe ---------------------------------------------

run "el_catalogo_de_glue_no_es_opcional" {
  command = plan

  variables {
    enable_crawler = false
    enable_athena  = false
  }

  assert {
    # Sin catalogo no hay data lake, solo carpetas. No depende de ningun flag.
    condition     = aws_glue_catalog_database.this.name != ""
    error_message = "El catalogo de Glue debe crearse siempre."
  }
}
