# ---------------------------------------------------------------------------
# Empaquetado.
#
# archive_file lee lo que hay en lambda-functions/build/ EN TIEMPO DE PLAN.
# Ese directorio lo genera el Makefile (pip install -r requirements.txt -t . para
# Python, go build para Go). Por eso hay que ejecutar SIEMPRE:
#
#     cd lambda-functions && make bin
#
# antes de terraform plan/apply. Es el mismo patron que usa el motor de HashiCorp
# en la Demo 2.
# ---------------------------------------------------------------------------

resource "terraform_data" "build_check" {
  # Falla temprano y con un mensaje claro si alguien olvido ejecutar make bin.
  lifecycle {
    precondition {
      condition = alltrue([
        for d in ["provisioning-operations-handler", "state_machine_lambdas", "terraform-parameter-parser"] :
        can(fileset("${local.lambda_build_dir}/${d}", "**")) && length(fileset("${local.lambda_build_dir}/${d}", "**")) > 0
      ])
      error_message = "Faltan artefactos de build. Ejecuta: cd lambda-functions && make bin"
    }
  }
}

data "archive_file" "provisioning_operations_handler" {
  type        = "zip"
  source_dir  = "${local.lambda_build_dir}/provisioning-operations-handler"
  output_path = "${path.module}/.build/provisioning-operations-handler.zip"
}

data "archive_file" "state_machine_lambdas" {
  type        = "zip"
  source_dir  = "${local.lambda_build_dir}/state_machine_lambdas"
  output_path = "${path.module}/.build/state_machine_lambdas.zip"
}

data "archive_file" "parameter_parser" {
  type        = "zip"
  source_dir  = "${local.lambda_build_dir}/terraform-parameter-parser"
  output_path = "${path.module}/.build/terraform-parameter-parser.zip"
}
