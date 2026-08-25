github_repository_id           = "8infinitecloud/devops-infraestructure-as-product"
github_branch                  = "main"
grant_access_to_principal_arns = ["arn:aws:iam::058264353988:user/hmunoz"]

# Conexion de CodeConnections ya AUTORIZADA. Vacio => Terraform crea una nueva
# que hay que autorizar a mano una unica vez en la consola.
existing_connection_arn = "arn:aws:codestar-connections:us-east-1:058264353988:connection/4f7c1814-1665-42ea-9b37-c188cb60fcfd"
