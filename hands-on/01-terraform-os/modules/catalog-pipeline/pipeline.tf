locals {
  # El catalogo viaja a los buildspecs como JSON en una variable de entorno.
  # Cambiar el mapa `productos` cambia este valor, y eso vuelve a desplegar los
  # proyectos de CodeBuild: no hace falta tocar nada mas para anadir un producto.
  products_json = jsonencode(var.productos)

  # Todos los proyectos de CodeBuild que la pipeline debe poder arrancar.
  codebuild_projects = {
    validate = aws_codebuild_project.validate
    inspect  = aws_codebuild_project.inspect
    publish  = aws_codebuild_project.publish
  }
}

# --- Rol compartido por los proyectos de CodeBuild ---------------------------

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

resource "aws_iam_role" "codebuild" {
  name_prefix        = "sc-build-"
  assume_role_policy = data.aws_iam_policy_document.codebuild_assume_role.json
}

resource "aws_iam_role_policy" "codebuild" {
  name = "PipelineBuildPermissions"
  role = aws_iam_role.codebuild.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "Logs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:/aws/codebuild/${var.name_prefix}-*"
      },
      {
        # La seccion `reports:` del buildspec crea report groups para que
        # Checkov y TFLint se vean como reportes nativos en la consola.
        # Sin estos permisos la fase UPLOAD_ARTIFACTS falla DESPUES de que el
        # build haya pasado, que despista bastante al diagnosticar.
        Sid    = "TestReports"
        Effect = "Allow"
        Action = [
          "codebuild:CreateReportGroup",
          "codebuild:CreateReport",
          "codebuild:UpdateReport",
          "codebuild:BatchPutTestCases",
          "codebuild:BatchPutCodeCoverages",
        ]
        Resource = "arn:${local.partition}:codebuild:${local.region}:${local.account_id}:report-group/${var.name_prefix}-*"
      },
      {
        Sid      = "Artifacts"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject", "s3:ListBucket"]
        Resource = ["arn:${local.partition}:s3:::${var.artifact_bucket_name}", "arn:${local.partition}:s3:::${var.artifact_bucket_name}/*"]
      },
      {
        Sid    = "ServiceCatalogPublishing"
        Effect = "Allow"
        Action = [
          "servicecatalog:CreateProduct",
          "servicecatalog:CreateProvisioningArtifact",
          "servicecatalog:DescribeProductAsAdmin",
          "servicecatalog:SearchProductsAsAdmin",
          "servicecatalog:AssociateProductWithPortfolio",
          "servicecatalog:ListConstraintsForPortfolio",
          "servicecatalog:CreateConstraint",
          "servicecatalog:DescribeProvisioningArtifact",
          "servicecatalog:ListProvisioningArtifacts",
        ]
        Resource = "*"
      },
      {
        Sid      = "PassLaunchRole"
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = local.launch_role_arn
        Condition = {
          StringEquals = { "iam:PassedToService" = "servicecatalog.amazonaws.com" }
        }
      },
    ]
  })
}

# --- Etapa Build / Validate --------------------------------------------------

resource "aws_cloudwatch_log_group" "validate" {
  name              = "/aws/codebuild/${var.name_prefix}-validate"
  retention_in_days = var.log_retention_days
}

resource "aws_codebuild_project" "validate" {
  name          = "${var.name_prefix}-validate"
  description   = "fmt + validate + empaquetado de TODOS los productos del catalogo"
  service_role  = aws_iam_role.codebuild.arn
  build_timeout = 20

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    type         = "LINUX_CONTAINER"
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = "aws/codebuild/standard:7.0"

    environment_variable {
      name  = "TF_VERSION"
      value = var.terraform_cli_version
    }
    environment_variable {
      name  = "PRODUCTS_JSON"
      value = local.products_json
    }
  }

  logs_config {
    cloudwatch_logs {
      status     = "ENABLED"
      group_name = aws_cloudwatch_log_group.validate.name
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = file("${path.module}/buildspec/validate.yml")
  }
}

# --- Etapa Publish -----------------------------------------------------------

resource "aws_cloudwatch_log_group" "publish" {
  name              = "/aws/codebuild/${var.name_prefix}-publish"
  retention_in_days = var.log_retention_days
}

resource "aws_codebuild_project" "publish" {
  name          = "${var.name_prefix}-publish"
  description   = "Sube los artefactos a S3 y publica una version nueva de cada producto"
  service_role  = aws_iam_role.codebuild.arn
  build_timeout = 20

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    type         = "LINUX_CONTAINER"
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = "aws/codebuild/standard:7.0"

    environment_variable {
      name  = "ARTIFACT_BUCKET"
      value = var.artifact_bucket_name
    }
    environment_variable {
      name  = "PORTFOLIO_ID"
      value = local.portfolio_id
    }
    environment_variable {
      name  = "LAUNCH_ROLE_ARN"
      value = local.launch_role_arn
    }
    environment_variable {
      name  = "PRODUCT_OWNER"
      value = var.product_owner
    }
    environment_variable {
      name  = "PRODUCT_TYPE"
      value = var.product_type
    }
  }

  logs_config {
    cloudwatch_logs {
      status     = "ENABLED"
      group_name = aws_cloudwatch_log_group.publish.name
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = file("${path.module}/buildspec/publish.yml")
  }
}

# --- CodePipeline ------------------------------------------------------------

data "aws_iam_policy_document" "pipeline_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["codepipeline.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "pipeline" {
  name_prefix        = "sc-pipeline-"
  assume_role_policy = data.aws_iam_policy_document.pipeline_assume_role.json
}

resource "aws_iam_role_policy" "pipeline" {
  name = "PipelineExecution"
  role = aws_iam_role.pipeline.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject", "s3:GetBucketVersioning", "s3:ListBucket"]
        Resource = ["arn:${local.partition}:s3:::${var.artifact_bucket_name}", "arn:${local.partition}:s3:::${var.artifact_bucket_name}/*"]
      },
      {
        Effect = "Allow"
        Action = ["codebuild:StartBuild", "codebuild:BatchGetBuilds"]
        # Se deriva de local.codebuild_projects para que anadir un proyecto no
        # pueda olvidarse aqui: es justo el fallo que tuvo la etapa Inspect.
        Resource = values(local.codebuild_projects)[*].arn
      },
      {
        Effect   = "Allow"
        Action   = ["codestar-connections:UseConnection", "codeconnections:UseConnection"]
        Resource = local.connection_arn
      },
    ]
  })
}

resource "aws_codepipeline" "this" {
  name     = "${var.name_prefix}-pipeline"
  role_arn = aws_iam_role.pipeline.arn

  artifact_store {
    type     = "S3"
    location = var.artifact_bucket_name
  }

  stage {
    name = "Source"
    action {
      name             = "GitHub"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["SourceCode"]

      configuration = {
        ConnectionArn    = local.connection_arn
        FullRepositoryId = var.github_repository_id
        BranchName       = var.github_branch
        DetectChanges    = "true"
      }
    }
  }

  stage {
    name = "BuildValidate"
    action {
      name             = "TerraformValidate"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["SourceCode"]
      output_artifacts = ["PackagedProduct"]

      configuration = {
        ProjectName = aws_codebuild_project.validate.name
      }
    }
  }

  stage {
    name = "Inspect"
    action {
      name             = "SecurityPolicyAndCost"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["SourceCode"]
      output_artifacts = ["InspectionReports"]

      configuration = {
        ProjectName = aws_codebuild_project.inspect.name
      }
    }
  }

  # Los chequeos automaticos informan; aqui decide una persona.
  dynamic "stage" {
    for_each = var.require_manual_approval ? [1] : []
    content {
      name = "Approve"
      action {
        name     = "RevisarHallazgos"
        category = "Approval"
        owner    = "AWS"
        provider = "Manual"
        version  = "1"

        configuration = merge(
          {
            CustomData = "Revisa los reportes de la etapa Inspect (Checkov, TFLint, Gitleaks, Conftest, Infracost) antes de publicar el producto en Service Catalog."
          },
          var.approval_notification_arn != "" ? { NotificationArn = var.approval_notification_arn } : {}
        )
      }
    }
  }

  stage {
    name = "Publish"
    action {
      name            = "ServiceCatalogPublish"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["PackagedProduct"]

      configuration = {
        ProjectName = aws_codebuild_project.publish.name
      }
    }
  }

  depends_on = [aws_iam_role_policy.pipeline]
}

# --- Etapa Inspect ----------------------------------------------------------

resource "aws_cloudwatch_log_group" "inspect" {
  name              = "/aws/codebuild/${var.name_prefix}-inspect"
  retention_in_days = var.log_retention_days
}

resource "aws_codebuild_project" "inspect" {
  name          = "${var.name_prefix}-inspect"
  description   = "Checkov, TFLint, Gitleaks, Conftest e Infracost sobre todos los productos"
  service_role  = aws_iam_role.codebuild.arn
  build_timeout = 30

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    type         = "LINUX_CONTAINER"
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = "aws/codebuild/standard:7.0"

    environment_variable {
      name  = "PRODUCTS_JSON"
      value = local.products_json
    }
    environment_variable {
      name  = "POLICY_PATH"
      value = var.policy_source_path
    }

    # La API key nunca viaja en el buildspec ni en el state: CodeBuild la
    # resuelve desde Secrets Manager en tiempo de ejecucion.
    dynamic "environment_variable" {
      for_each = var.infracost_api_key_secret_arn != "" ? [1] : []
      content {
        name  = "INFRACOST_API_KEY"
        value = "${var.infracost_api_key_secret_arn}:api_key"
        type  = "SECRETS_MANAGER"
      }
    }
  }

  logs_config {
    cloudwatch_logs {
      status     = "ENABLED"
      group_name = aws_cloudwatch_log_group.inspect.name
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = file("${path.module}/buildspec/inspect.yml")
  }
}

resource "aws_iam_role_policy" "codebuild_infracost_secret" {
  count = var.infracost_api_key_secret_arn != "" ? 1 : 0

  name = "ReadInfracostApiKey"
  role = aws_iam_role.codebuild.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = var.infracost_api_key_secret_arn
    }]
  })
}
