output "pipeline_name" {
  description = "Nombre de la pipeline"
  value       = aws_codepipeline.this.name
}

output "artifact_bucket" {
  description = "Bucket donde se publican los .tar.gz de los productos"
  value       = aws_s3_bucket.artifacts.bucket
}

output "connection_arn" {
  description = "Conexion de CodeConnections en uso"
  value       = local.connection_arn
}

output "connection_needs_authorization" {
  description = "Si es true, hay que autorizar la conexion a mano en la consola de CodeConnections"
  value       = local.create_connection
}
