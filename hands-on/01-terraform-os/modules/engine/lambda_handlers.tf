# ---------------------------------------------------------------------------
# Lambdas handler de SQS. Una por flujo (provision/update y terminate).
# Comparten codigo fuente; solo cambia la state machine que arrancan.
# Su logica interna NO se toca: solo se traduce la definicion de SAM a Terraform.
# ---------------------------------------------------------------------------

# --- Handler de provision + update ------------------------------------------

resource "aws_iam_role" "provisioning_handler" {
  name_prefix        = "TFEngineProvisionHandler-"
  path               = local.iam_path
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "provisioning_handler_managed" {
  for_each = toset([local.xray_write_only, local.lambda_basic_execution])

  role       = aws_iam_role.provisioning_handler.name
  policy_arn = each.value
}

resource "aws_iam_role_policy" "provisioning_handler_sqs" {
  name = "AllowSqs"
  role = aws_iam_role.provisioning_handler.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
      Resource = [
        aws_sqs_queue.operations["external_provision"].arn,
        aws_sqs_queue.operations["external_update"].arn,
      ]
    }]
  })
}

resource "aws_iam_role_policy" "provisioning_handler_kms" {
  name = "AllowKmsDecrypt"
  role = aws_iam_role.provisioning_handler.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["kms:Decrypt"]
      Resource = [aws_kms_key.queue.arn]
    }]
  })
}

resource "aws_iam_role_policy" "provisioning_handler_states" {
  name = "AllowStepFunction"
  role = aws_iam_role.provisioning_handler.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["states:StartExecution"]
      Resource = [aws_sfn_state_machine.manage_provisioned_product.arn]
    }]
  })
}

resource "aws_lambda_function" "provisioning_handler" {
  function_name = "TerraformEngineProvisioningHandlerLambda"
  description   = "Function to process the SQS queue and trigger the provisioning state machine"
  role          = aws_iam_role.provisioning_handler.arn

  filename         = data.archive_file.provisioning_operations_handler.output_path
  source_code_hash = data.archive_file.provisioning_operations_handler.output_base64sha256

  handler       = "provisioning_operations_handler.handle_sqs_records"
  runtime       = "python3.13"
  timeout       = 30
  memory_size   = 256
  architectures = ["x86_64"]

  environment {
    variables = {
      STATE_MACHINE_ARN = aws_sfn_state_machine.manage_provisioned_product.arn
    }
  }
}

resource "aws_lambda_event_source_mapping" "provisioning_handler" {
  for_each = toset(["external_provision", "external_update"])

  event_source_arn                   = aws_sqs_queue.operations[each.key].arn
  function_name                      = aws_lambda_function.provisioning_handler.arn
  batch_size                         = 10
  enabled                            = true
  function_response_types            = ["ReportBatchItemFailures"]
  maximum_batching_window_in_seconds = 0
}

# --- Handler de terminate ----------------------------------------------------

resource "aws_iam_role" "terminate_handler" {
  name_prefix        = "TFEngineTerminateHandler-"
  path               = local.iam_path
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "terminate_handler_managed" {
  for_each = toset([local.xray_write_only, local.lambda_basic_execution])

  role       = aws_iam_role.terminate_handler.name
  policy_arn = each.value
}

resource "aws_iam_role_policy" "terminate_handler_sqs" {
  name = "AllowSqs"
  role = aws_iam_role.terminate_handler.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
      Resource = [
        aws_sqs_queue.operations["external_terminate"].arn,
      ]
    }]
  })
}

resource "aws_iam_role_policy" "terminate_handler_kms" {
  name = "AllowKmsDecrypt"
  role = aws_iam_role.terminate_handler.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["kms:Decrypt"]
      Resource = [aws_kms_key.queue.arn]
    }]
  })
}

resource "aws_iam_role_policy" "terminate_handler_states" {
  name = "AllowStepFunction"
  role = aws_iam_role.terminate_handler.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["states:StartExecution"]
      Resource = [aws_sfn_state_machine.terminate_provisioned_product.arn]
    }]
  })
}

resource "aws_lambda_function" "terminate_handler" {
  function_name = "TerraformEngineTerminateHandlerLambda"
  description   = "Function to process the Terminate SQS queue and trigger the terminate state machine"
  role          = aws_iam_role.terminate_handler.arn

  filename         = data.archive_file.provisioning_operations_handler.output_path
  source_code_hash = data.archive_file.provisioning_operations_handler.output_base64sha256

  handler       = "provisioning_operations_handler.handle_sqs_records"
  runtime       = "python3.13"
  timeout       = 30
  memory_size   = 256
  architectures = ["x86_64"]

  environment {
    variables = {
      STATE_MACHINE_ARN = aws_sfn_state_machine.terminate_provisioned_product.arn
    }
  }
}

resource "aws_lambda_event_source_mapping" "terminate_handler" {
  for_each = toset(["external_terminate"])

  event_source_arn                   = aws_sqs_queue.operations[each.key].arn
  function_name                      = aws_lambda_function.terminate_handler.arn
  batch_size                         = 10
  enabled                            = true
  function_response_types            = ["ReportBatchItemFailures"]
  maximum_batching_window_in_seconds = 0
}
