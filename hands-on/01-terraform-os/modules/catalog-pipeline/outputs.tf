output "pipeline_name" {
  description = "Nombre de la pipeline"
  value       = aws_codepipeline.this.name
}

output "product_name" {
  description = "Producto de Service Catalog que publica esta pipeline"
  value       = var.product_name
}

output "module_source_path" {
  description = "Ruta del modulo que empaqueta esta pipeline"
  value       = var.module_source_path
}
