# ---------------------------------------------------------------------------
# Step Functions.
#
# La definicion ASL es la misma que usaba SAM (statemachine/*.json); las
# substituciones ${...} se resuelven con templatefile() en vez de con
# DefinitionSubstitutions.
#
# El cambio de fondo: donde antes habia
#   Select worker host -> Send apply command -> Wait -> Poll -> Choice
# ahora hay una sola tarea que invoca CodeBuild de forma sincrona
# (arn:aws:states:::codebuild:startBuild.sync) y espera a que el build termine.
# ---------------------------------------------------------------------------

locals {
  codebuild_sync_arn = "arn:${local.partition}:states:::codebuild:startBuild.sync"
  lambda_invoke_arn  = "arn:${local.partition}:states:::lambda:invoke"
}

# --- Politica comun de logging para ambas state machines ---------------------

data "aws_iam_policy_document" "sfn_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }
  }
}

locals {
  sfn_logging_actions = [
    "logs:CreateLogDelivery",
    "logs:GetLogDelivery",
    "logs:UpdateLogDelivery",
    "logs:DeleteLogDelivery",
    "logs:ListLogDeliveries",
    "logs:PutLogEvents",
    "logs:PutResourcePolicy",
    "logs:DescribeResourcePolicies",
    "logs:DescribeLogGroups",
  ]

  # La integracion .sync necesita gestionar una regla de EventBridge para
  # recibir el evento de finalizacion del build.
  codebuild_sync_rule_arn = "arn:${local.partition}:events:${local.region}:${local.account_id}:rule/StepFunctionsGetEventForCodeBuildStartBuildRule"
}

# --- Manage (provision / update) ---------------------------------------------

resource "aws_cloudwatch_log_group" "manage_state_machine" {
  name              = "/aws/vendedlogs/states/ManageProvisionedProductStateMachine"
  retention_in_days = var.log_retention_days
}

resource "aws_iam_role" "manage_state_machine" {
  name_prefix        = "TFEngineManageSM-"
  path               = local.iam_path
  assume_role_policy = data.aws_iam_policy_document.sfn_assume_role.json
}

resource "aws_iam_role_policy" "manage_state_machine" {
  name = "ManageStateMachinePermissions"
  role = aws_iam_role.manage_state_machine.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudwatchPermissions"
        Effect = "Allow"
        Action = local.sfn_logging_actions
        # Un bug interno de AWS impide acotar el recurso aqui.
        # https://repost.aws/questions/QURc2glxBETSe3Q6Y0UwcpQg
        Resource = "*"
      },
      {
        Sid    = "InvokeLambdas"
        Effect = "Allow"
        Action = ["lambda:InvokeFunction"]
        Resource = [
          aws_lambda_function.get_state_file_outputs.arn,
          aws_lambda_function.notify["provision"].arn,
          aws_lambda_function.notify["update"].arn,
        ]
      },
      {
        Sid      = "RunTerraformInCodeBuild"
        Effect   = "Allow"
        Action   = ["codebuild:StartBuild", "codebuild:StopBuild", "codebuild:BatchGetBuilds"]
        Resource = aws_codebuild_project.terraform_runner.arn
      },
      {
        Sid      = "CodeBuildSyncEventRule"
        Effect   = "Allow"
        Action   = ["events:PutTargets", "events:PutRule", "events:DescribeRule"]
        Resource = local.codebuild_sync_rule_arn
      },
    ]
  })
}

resource "aws_sfn_state_machine" "manage_provisioned_product" {
  name     = "ManageProvisionedProductStateMachine"
  type     = "STANDARD"
  role_arn = aws_iam_role.manage_state_machine.arn

  definition = templatefile("${path.module}/statemachine/manage_provisioned_product.json", {
    CodeBuildStartBuildSyncArn       = local.codebuild_sync_arn
    TerraformRunnerProjectName       = aws_codebuild_project.terraform_runner.name
    LambdaInvokeArn                  = local.lambda_invoke_arn
    GetStateFileOutputsFunctionArn   = aws_lambda_function.get_state_file_outputs.arn
    NotifyProvisionResultFunctionArn = aws_lambda_function.notify["provision"].arn
    NotifyUpdateResultFunctionArn    = aws_lambda_function.notify["update"].arn
  })

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.manage_state_machine.arn}:*"
    include_execution_data = true
    level                  = "ALL"
  }

  depends_on = [aws_iam_role_policy.manage_state_machine]
}

# --- Terminate ----------------------------------------------------------------

resource "aws_cloudwatch_log_group" "terminate_state_machine" {
  name              = "/aws/vendedlogs/states/TerminateProvisionedProductStateMachine"
  retention_in_days = var.log_retention_days
}

resource "aws_iam_role" "terminate_state_machine" {
  name_prefix        = "TFEngineTerminateSM-"
  path               = local.iam_path
  assume_role_policy = data.aws_iam_policy_document.sfn_assume_role.json
}

resource "aws_iam_role_policy" "terminate_state_machine" {
  name = "TerminateStateMachinePermissions"
  role = aws_iam_role.terminate_state_machine.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "CloudwatchPermissions"
        Effect   = "Allow"
        Action   = local.sfn_logging_actions
        Resource = "*"
      },
      {
        Sid      = "InvokeLambdas"
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = [aws_lambda_function.notify["terminate"].arn]
      },
      {
        Sid      = "RunTerraformInCodeBuild"
        Effect   = "Allow"
        Action   = ["codebuild:StartBuild", "codebuild:StopBuild", "codebuild:BatchGetBuilds"]
        Resource = aws_codebuild_project.terraform_runner.arn
      },
      {
        Sid      = "CodeBuildSyncEventRule"
        Effect   = "Allow"
        Action   = ["events:PutTargets", "events:PutRule", "events:DescribeRule"]
        Resource = local.codebuild_sync_rule_arn
      },
    ]
  })
}

resource "aws_sfn_state_machine" "terminate_provisioned_product" {
  name     = "TerminateProvisionedProductStateMachine"
  type     = "STANDARD"
  role_arn = aws_iam_role.terminate_state_machine.arn

  definition = templatefile("${path.module}/statemachine/terminate_provisioned_product.json", {
    CodeBuildStartBuildSyncArn       = local.codebuild_sync_arn
    TerraformRunnerProjectName       = aws_codebuild_project.terraform_runner.name
    LambdaInvokeArn                  = local.lambda_invoke_arn
    NotifyTerminateResultFunctionArn = aws_lambda_function.notify["terminate"].arn
  })

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.terminate_state_machine.arn}:*"
    include_execution_data = true
    level                  = "ALL"
  }

  depends_on = [aws_iam_role_policy.terminate_state_machine]
}
