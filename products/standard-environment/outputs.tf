# Estos outputs los recoge el motor y los devuelve a Service Catalog como
# "record outputs", visibles en la consola del producto aprovisionado.

output "vpc_id" {
  description = "Identificador de la VPC del entorno"
  value       = aws_vpc.this.id
}

output "subnet_ids" {
  description = "Identificadores de las subredes creadas"
  value       = join(",", aws_subnet.this[*].id)
}

output "storage_bucket_name" {
  description = "Nombre del bucket S3 de almacenamiento del entorno"
  value       = aws_s3_bucket.this.bucket
}

output "access_role_arn" {
  description = "ARN del rol IAM que da acceso al almacenamiento del entorno"
  value       = aws_iam_role.access.arn
}
