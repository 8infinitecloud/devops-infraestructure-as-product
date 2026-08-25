# ---------------------------------------------------------------------------
# Colas SQS: el contrato con Service Catalog.
# Nombres, timeouts y redrive se mantienen EXACTAMENTE como en la version SAM;
# Service Catalog descubre estas colas por nombre.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "queue_key" {
  # Replica la politica por defecto de KMS
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

  statement {
    sid    = "Enable AWS Service Catalog to send messages"
    effect = "Allow"
    actions = [
      "kms:DescribeKey",
      "kms:Decrypt",
      "kms:ReEncrypt",
      "kms:GenerateDataKey",
    ]
    principals {
      type        = "Service"
      identifiers = ["servicecatalog.amazonaws.com"]
    }
    resources = ["*"]
  }
}

resource "aws_kms_key" "queue" {
  description             = "A symmetric encryption KMS key for SQS queues"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.queue_key.json

  tags = { Name = "TerraformEngineSQSEncryptionKey" }
}

resource "aws_sqs_queue" "dlq" {
  name              = "ServiceCatalogTerraformOSOperationsDLQ"
  kms_master_key_id = aws_kms_key.queue.id
}

locals {
  # Las 6 colas del contrato: 3 para productos TERRAFORM_OPEN_SOURCE y 3 para EXTERNAL
  operation_queues = {
    terraform_provision = "ServiceCatalogTerraformOSProvisionOperationQueue"
    terraform_update    = "ServiceCatalogTerraformOSUpdateOperationQueue"
    terraform_terminate = "ServiceCatalogTerraformOSTerminateOperationQueue"
    external_provision  = "ServiceCatalogExternalProvisionOperationQueue"
    external_update     = "ServiceCatalogExternalUpdateOperationQueue"
    external_terminate  = "ServiceCatalogExternalTerminateOperationQueue"
  }
}

resource "aws_sqs_queue" "operations" {
  for_each = local.operation_queues

  name                       = each.value
  visibility_timeout_seconds = 180
  kms_master_key_id          = aws_kms_key.queue.id

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 5
  })
}

data "aws_iam_policy_document" "operation_queues" {
  statement {
    sid    = "Enable AWS Service Catalog to send messages to the queue"
    effect = "Allow"
    actions = [
      "sqs:SendMessage",
      "sqs:GetQueueUrl",
    ]
    principals {
      type        = "Service"
      identifiers = ["servicecatalog.amazonaws.com"]
    }
    resources = [for q in aws_sqs_queue.operations : q.arn]
  }

  statement {
    sid    = "Enable AWS Service Catalog encryption/decryption permissions when sending message to queue"
    effect = "Allow"
    actions = [
      "kms:DescribeKey",
      "kms:Decrypt",
      "kms:ReEncrypt",
      "kms:GenerateDataKey",
    ]
    principals {
      type        = "Service"
      identifiers = ["servicecatalog.amazonaws.com"]
    }
    resources = [aws_kms_key.queue.arn]
  }
}

resource "aws_sqs_queue_policy" "operations" {
  for_each = aws_sqs_queue.operations

  queue_url = each.value.id
  policy    = data.aws_iam_policy_document.operation_queues.json
}
