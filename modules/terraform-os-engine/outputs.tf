output "codebuild_service_role_arn" {
  description = "ARN del rol de CodeBuild que ejecuta Terraform. catalog-bootstrap/ lo necesita para la politica de confianza del Launch Role."
  value       = aws_iam_role.codebuild_runner.arn
}

output "codebuild_project_name" {
  description = "Nombre del proyecto de CodeBuild que ejecuta terraform apply/destroy"
  value       = aws_codebuild_project.terraform_runner.name
}

output "codebuild_project_arn" {
  description = "ARN del proyecto de CodeBuild"
  value       = aws_codebuild_project.terraform_runner.arn
}

output "parameter_parser_role_arns" {
  description = "ARNs de los roles del Parameter Parser. El Launch Role tambien debe confiar en ellos."
  value       = { for k, r in aws_iam_role.parameter_parser : k => r.arn }
}

output "terraform_state_bucket" {
  description = "Bucket S3 donde se guarda el state de cada producto aprovisionado"
  value       = aws_s3_bucket.state.bucket
}

output "manage_state_machine_arn" {
  description = "State machine de provision/update"
  value       = aws_sfn_state_machine.manage_provisioned_product.arn
}

output "terminate_state_machine_arn" {
  description = "State machine de terminate"
  value       = aws_sfn_state_machine.terminate_provisioned_product.arn
}

output "operation_queue_urls" {
  description = "Las 6 colas del contrato con Service Catalog"
  value       = { for k, q in aws_sqs_queue.operations : k => q.url }
}
