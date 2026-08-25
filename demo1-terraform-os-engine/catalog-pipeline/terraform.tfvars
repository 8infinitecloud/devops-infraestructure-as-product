github_repository_id = "8infinitecloud/devops-infraestructure-as-product"
github_branch        = "main"
module_source_path   = "demo1-terraform-os-engine/catalog-modules/standard-environment"

# Conexion de CodeConnections ya AUTORIZADA en la cuenta (estado AVAILABLE).
# Reutilizarla evita el paso manual de autorizacion en la consola.
# Para demostrar el flujo completo en el taller, dejar esta variable vacia:
# Terraform creara una nueva conexion en estado PENDING que habra que autorizar.
existing_connection_arn = "arn:aws:codestar-connections:us-east-1:058264353988:connection/4f7c1814-1665-42ea-9b37-c188cb60fcfd"
