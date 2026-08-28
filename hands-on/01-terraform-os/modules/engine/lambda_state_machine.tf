# ---------------------------------------------------------------------------
# Lambdas que invocan las Step Functions.
#
# Tras pasar a CodeBuild solo quedan cuatro. Se eliminaron select-worker-host y
# poll-command-invocation (ya no hay flota que elegir ni polling que hacer), y
# con ellas send-apply-command y send-destroy-command, cuyo unico trabajo era
# construir el SSM SendCommand que ahora sustituye la integracion sincrona con
# CodeBuild.
# ---------------------------------------------------------------------------

# --- Get state file outputs --------------------------------------------------

resource "aws_iam_role" "get_state_file_outputs" {
  name_prefix        = "TFEngineGetStateOutputs-"
  path               = local.iam_path
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "get_state_file_outputs_basic" {
  role       = aws_iam_role.get_state_file_outputs.name
  policy_arn = local.lambda_basic_execution
}

resource "aws_iam_role_policy" "get_state_file_outputs_s3" {
  name = "S3StateFileReadPermissions"
  role = aws_iam_role.get_state_file_outputs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      # ListBucket sobre el bucket ademas de GetObject sobre los objetos: sin el,
      # pedir una clave que no existe devuelve 403 en vez de 404, porque S3 no
      # revela si el objeto falta o si no tienes permiso. El diagnostico cambia
      # por completo.
      Action = ["s3:GetObject", "s3:ListBucket"]
      Resource = [
        aws_s3_bucket.state.arn,
        "${aws_s3_bucket.state.arn}/*",
      ]
    }]
  })
}

resource "aws_iam_role_policy" "get_state_file_outputs_kms" {
  name = "KMSAccessPolicyForStateBucket"
  role = aws_iam_role.get_state_file_outputs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["kms:DescribeKey", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey"]
      Resource = [aws_kms_key.state_bucket.arn]
    }]
  })
}

resource "aws_lambda_function" "get_state_file_outputs" {
  function_name = "GetStateFileOutputsFunction"
  description   = "Lambda function that parses state file JSON from S3 state bucket to fetch record outputs"
  role          = aws_iam_role.get_state_file_outputs.arn

  filename         = data.archive_file.state_machine_lambdas.output_path
  source_code_hash = data.archive_file.state_machine_lambdas.output_base64sha256

  handler       = "get_state_file_outputs.parse"
  runtime       = "python3.13"
  timeout       = 60
  architectures = ["x86_64"]

  environment {
    variables = {
      STATE_BUCKET_NAME = aws_s3_bucket.state.bucket
    }
  }
}

# --- Notify* : devuelven el resultado a Service Catalog -----------------------

locals {
  notify_lambdas = {
    provision = {
      function_name = "NotifyProvisionResult"
      handler       = "notify_provision_result.notify"
      action        = "servicecatalog:NotifyProvisionProductEngineWorkflowResult"
      description   = "Lambda function that notifies Service Catalog of the provisioning results of this Engine"
    }
    update = {
      function_name = "NotifyUpdateResult"
      handler       = "notify_update_result.notify"
      action        = "servicecatalog:NotifyUpdateProvisionedProductEngineWorkflowResult"
      description   = "Lambda function that notifies Service Catalog of the update results of this Engine"
    }
    terminate = {
      function_name = "NotifyTerminateResult"
      handler       = "notify_terminate_result.notify"
      action        = "servicecatalog:NotifyTerminateProvisionedProductEngineWorkflowResult"
      description   = "Lambda function that notifies Service Catalog of the terminate results of this Engine"
    }
  }
}

resource "aws_iam_role" "notify" {
  for_each = local.notify_lambdas

  name_prefix        = "TFEngineNotify-"
  path               = local.iam_path
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "notify_basic" {
  for_each = aws_iam_role.notify

  role       = each.value.name
  policy_arn = local.lambda_basic_execution
}

resource "aws_iam_role_policy" "notify" {
  for_each = local.notify_lambdas

  name = "lambdaPermissions"
  role = aws_iam_role.notify[each.key].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = [each.value.action]
      Resource = "*"
    }]
  })
}

resource "aws_lambda_function" "notify" {
  for_each = local.notify_lambdas

  function_name = each.value.function_name
  description   = each.value.description
  role          = aws_iam_role.notify[each.key].arn

  filename         = data.archive_file.state_machine_lambdas.output_path
  source_code_hash = data.archive_file.state_machine_lambdas.output_base64sha256

  handler       = each.value.handler
  runtime       = "python3.13"
  timeout       = 300
  architectures = ["x86_64"]

  environment {
    variables = {
      SERVICE_CATALOG_ENDPOINT   = var.service_catalog_endpoint
      SERVICE_CATALOG_VERIFY_SSL = var.service_catalog_verify_ssl
    }
  }
}
