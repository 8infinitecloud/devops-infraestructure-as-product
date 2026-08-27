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

# La DLQ NO es legacy pese al nombre: la comparten las tres colas. Se conserva el
# nombre heredado a proposito — renombrarla la recrearia, y con ella se perderian
# los mensajes muertos que hubiera dentro esperando diagnostico.
resource "aws_sqs_queue" "dlq" {
  name              = "ServiceCatalogTerraformOSOperationsDLQ"
  kms_master_key_id = aws_kms_key.queue.id
}

# ---------------------------------------------------------------------------
# DESVIACION DEL MOTOR DE REFERENCIA DE AWS.
#
# El motor original crea todo por duplicado: una version para productos
# TERRAFORM_OPEN_SOURCE y otra para EXTERNAL. AWS retiro el primer tipo el
# 2023-12-14 y ya no se acepta en CreateProduct, asi que esa mitad no puede
# recibir nada: verificado en la cuenta, cero mensajes.
#
# Aqui se ha eliminado. Si alguna vez hay que reintroducirla —productos
# publicados antes de esa fecha—, hay que volver a anadir las tres colas, sus
# event source mappings, los permisos de los dos handlers y el parameter parser
# legacy.
# ---------------------------------------------------------------------------

locals {
  # Las 3 colas del contrato, una por operacion. Service Catalog las descubre por
  # NOMBRE EXACTO: renombrarlas rompe el enrutado sin dar ningun error visible.
  operation_queues = {
    external_provision = "ServiceCatalogExternalProvisionOperationQueue"
    external_update    = "ServiceCatalogExternalUpdateOperationQueue"
    external_terminate = "ServiceCatalogExternalTerminateOperationQueue"
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
