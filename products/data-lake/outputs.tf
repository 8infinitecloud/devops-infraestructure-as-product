# Lo que ve quien aprovisiona cuando el producto termina. En Service Catalog
# aparecen en la pestana Outputs; sin esto, el usuario recibe "listo" y tiene
# que ir a buscar los nombres a mano por la consola.

output "bucket_raw" {
  description = "Bucket de la zona RAW. Aqui se depositan los datos de origen."
  value       = aws_s3_bucket.raw.id
}

output "bucket_curated" {
  description = "Bucket de la zona CURATED. Aqui van los datos ya procesados."
  value       = aws_s3_bucket.curated.id
}

output "catalogo_glue" {
  description = "Base de datos del catalogo de Glue. Es lo que se consulta desde Athena."
  value       = aws_glue_catalog_database.this.name
}

output "crawler" {
  description = "Crawler que cataloga la zona RAW. Vacio si no se activo."
  value       = var.enable_crawler ? aws_glue_crawler.raw[0].name : ""
}

output "athena_workgroup" {
  description = "Workgroup de Athena para lanzar consultas. Vacio si no se activo."
  value       = var.enable_athena ? aws_athena_workgroup.this[0].name : ""
}

output "consulta_de_ejemplo" {
  description = "Copia esto en la consola de Athena para comprobar que el catalogo responde."
  value       = "SELECT * FROM \"${aws_glue_catalog_database.this.name}\".\"<tabla>\" LIMIT 10;"
}
