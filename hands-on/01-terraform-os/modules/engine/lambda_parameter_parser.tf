# ---------------------------------------------------------------------------
# Parameter Parser (Go, provided.al2).
# Service Catalog lo invoca para DescribeProvisioningParameters: descarga el
# artefacto del producto y extrae los bloques `variable` de los .tf.
# Hay dos instancias, una por tipo de producto (TERRAFORM_OPEN_SOURCE y EXTERNAL).
# El codigo Go no se toca.
# ---------------------------------------------------------------------------

locals {
  # Solo el de EXTERNAL: el legacy de TERRAFORM_OPEN_SOURCE se elimino con sus
  # colas. Ver la nota en sqs.tf.
  parameter_parsers = {
    external = {
      function_name = "ServiceCatalogExternalParameterParser"
      role_name     = "ServiceCatalogExternalParameterParserRole-${local.region}"
    }
  }
}

data "aws_iam_policy_document" "parameter_parser" {
  statement {
    effect    = "Allow"
    actions   = ["sts:AssumeRole"]
    resources = ["arn:${local.partition}:iam::*:role/*"]
  }

  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["arn:${local.partition}:s3:::*"]
    condition {
      test     = "StringEquals"
      variable = "s3:ExistingObjectTag/servicecatalog:provisioning"
      values   = ["true"]
    }
  }
}

resource "aws_iam_role" "parameter_parser" {
  for_each = local.parameter_parsers

  name               = each.value.role_name
  path               = local.iam_path
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "parameter_parser_basic" {
  for_each = aws_iam_role.parameter_parser

  role       = each.value.name
  policy_arn = local.lambda_basic_execution
}

resource "aws_iam_role_policy" "parameter_parser" {
  for_each = aws_iam_role.parameter_parser

  name   = "lambdaPermissions"
  role   = each.value.id
  policy = data.aws_iam_policy_document.parameter_parser.json
}

resource "aws_lambda_function" "parameter_parser" {
  for_each = local.parameter_parsers

  function_name = each.value.function_name
  role          = aws_iam_role.parameter_parser[each.key].arn

  filename         = data.archive_file.parameter_parser.output_path
  source_code_hash = data.archive_file.parameter_parser.output_base64sha256

  handler       = "bootstrap"
  runtime       = "provided.al2"
  memory_size   = var.parameter_parser_memory_size
  timeout       = 100
  architectures = ["x86_64"]
}

resource "aws_lambda_permission" "parameter_parser" {
  for_each = aws_lambda_function.parameter_parser

  statement_id  = "AllowServiceCatalogInvoke"
  action        = "lambda:InvokeFunction"
  function_name = each.value.function_name
  principal     = "servicecatalog.amazonaws.com"
}
