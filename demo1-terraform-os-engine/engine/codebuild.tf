# ---------------------------------------------------------------------------
# Motor de ejecucion de Terraform.
#
# Sustituye al Auto Scaling Group de EC2 + VPC + NAT Gateway + SSM Run Command
# del motor original. El buildspec reproduce exactamente los overrides que
# escribia el paquete terraform_runner:
#   - backend_override.tf.json   (backend S3, key = <accountId>/<provisionedProductId>)
#   - provider_override.tf.json  (region, assume_role al launch role, default_tags)
#   - variable_override.tf.json  (parametros de aprovisionamiento)
#
# Sin vpc_config: el runner necesita salida a internet para descargar Terraform y
# los providers, y sin VPC no hace falta NAT Gateway.
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "codebuild_runner" {
  name              = "/aws/codebuild/TerraformEngineRunner"
  retention_in_days = var.log_retention_days
}

data "aws_iam_policy_document" "codebuild_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["codebuild.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "codebuild_runner" {
  name               = "TerraformExecutionRole-${local.region}"
  path               = local.iam_path
  assume_role_policy = data.aws_iam_policy_document.codebuild_assume_role.json
  description        = "Rol que ejecuta terraform apply/destroy en CodeBuild para Service Catalog"
}

resource "aws_iam_role_policy" "codebuild_runner_logs" {
  name = "CloudWatchLogsPolicy"
  role = aws_iam_role.codebuild_runner.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = [
        aws_cloudwatch_log_group.codebuild_runner.arn,
        "${aws_cloudwatch_log_group.codebuild_runner.arn}:*",
      ]
    }]
  })
}

resource "aws_iam_role_policy" "codebuild_runner_state" {
  name = "S3AndKmsStateAccess"
  role = aws_iam_role.codebuild_runner.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
        Resource = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["kms:DescribeKey", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey"]
        Resource = [aws_kms_key.state_bucket.arn]
      },
    ]
  })
}

resource "aws_iam_role_policy" "codebuild_runner_assume_launch_role" {
  name = "LaunchRoleAssumptionPolicy"
  role = aws_iam_role.codebuild_runner.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["sts:AssumeRole"]
      Resource = "arn:${local.partition}:iam::*:role/*"
    }]
  })
}

resource "aws_codebuild_project" "terraform_runner" {
  name                   = "TerraformEngineRunner"
  description            = "Ejecuta terraform apply/destroy para AWS Service Catalog"
  service_role           = aws_iam_role.codebuild_runner.arn
  build_timeout          = var.runner_timeout_minutes
  concurrent_build_limit = var.runner_concurrent_build_limit

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    type            = "LINUX_CONTAINER"
    compute_type    = var.runner_compute_type
    image           = "aws/codebuild/standard:7.0"
    privileged_mode = false

    environment_variable {
      name  = "TF_STATE_BUCKET"
      value = aws_s3_bucket.state.bucket
    }
    environment_variable {
      name  = "TF_VERSION"
      value = var.terraform_cli_version
    }

    # Valores por defecto; la Step Function los sobreescribe en cada build
    environment_variable {
      name  = "ACTION"
      value = "apply"
    }
    environment_variable {
      name  = "PP_DESCRIPTOR"
      value = "unset"
    }
    environment_variable {
      name  = "LAUNCH_ROLE_ARN"
      value = "unset"
    }
    environment_variable {
      name  = "ARTIFACT_PATH"
      value = "unset"
    }
    environment_variable {
      name  = "ARTIFACT_PARAMETERS"
      value = "[]"
    }
    environment_variable {
      name  = "TAGS_JSON"
      value = "[]"
    }
    environment_variable {
      name  = "TRACER_TAG_JSON"
      value = "{}"
    }
  }

  logs_config {
    cloudwatch_logs {
      status     = "ENABLED"
      group_name = aws_cloudwatch_log_group.codebuild_runner.name
    }
  }

  source {
    type      = "NO_SOURCE"
    buildspec = file("${path.module}/buildspec/terraform-runner.yml")
  }
}
