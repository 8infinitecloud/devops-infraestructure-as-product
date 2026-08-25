# --- Rol compartido por los dos proyectos de CodeBuild -----------------------

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
  name_prefix        = "aurex-tfc-catalog-build-"
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
        Resource = "arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:/aws/codebuild/aurex-tfc-catalog-*"
      },
      {
        Sid      = "Artifacts"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject", "s3:ListBucket"]
        Resource = [aws_s3_bucket.artifacts.arn, "${aws_s3_bucket.artifacts.arn}/*"]
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
  name              = "/aws/codebuild/aurex-tfc-catalog-validate"
  retention_in_days = var.log_retention_days
}

resource "aws_codebuild_project" "validate" {
  name          = "aurex-tfc-catalog-validate"
  description   = "terraform fmt -check + terraform validate + empaquetado del modulo"
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
      name  = "MODULE_PATH"
      value = var.module_source_path
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
  name              = "/aws/codebuild/aurex-tfc-catalog-publish"
  retention_in_days = var.log_retention_days
}

resource "aws_codebuild_project" "publish" {
  name          = "aurex-tfc-catalog-publish"
  description   = "Sube el artefacto a S3 y publica una nueva version del producto en Service Catalog"
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
      value = aws_s3_bucket.artifacts.bucket
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
      name  = "PRODUCT_NAME"
      value = var.product_name
    }
    environment_variable {
      name  = "PRODUCT_OWNER"
      value = var.product_owner
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
  name_prefix        = "aurex-tfc-catalog-pipeline-"
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
        Resource = [aws_s3_bucket.artifacts.arn, "${aws_s3_bucket.artifacts.arn}/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["codebuild:StartBuild", "codebuild:BatchGetBuilds"]
        Resource = [aws_codebuild_project.validate.arn, aws_codebuild_project.publish.arn]
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
  name     = "aurex-tfc-catalog-pipeline"
  role_arn = aws_iam_role.pipeline.arn

  artifact_store {
    type     = "S3"
    location = aws_s3_bucket.artifacts.bucket
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
