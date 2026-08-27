output "artifact_bucket_name" {
  description = "Nombre del bucket de artefactos"
  value       = aws_s3_bucket.artifacts.bucket
}

output "artifact_bucket_arn" {
  description = "ARN del bucket de artefactos"
  value       = aws_s3_bucket.artifacts.arn
}

output "connection_arn" {
  description = "ARN de la conexion a GitHub, se haya creado aqui o venga dada"
  value       = local.create_connection ? aws_codeconnections_connection.github[0].arn : var.existing_connection_arn
}

output "connection_needs_authorization" {
  description = <<-EOT
    true => la conexion se acaba de crear y nace en estado PENDING. Hay que
    autorizarla A MANO una unica vez en la consola de CodeConnections; hasta
    entonces ninguna pipeline puede leer del repositorio.
  EOT
  value       = local.create_connection
}
