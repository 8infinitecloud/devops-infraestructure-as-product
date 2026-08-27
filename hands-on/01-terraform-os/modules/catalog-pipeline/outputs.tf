output "pipeline_name" {
  description = "Nombre de la pipeline del catalogo"
  value       = aws_codepipeline.this.name
}

output "productos" {
  description = "Productos que publica esta pipeline"
  value       = { for k, v in var.productos : k => v.nombre }
}
