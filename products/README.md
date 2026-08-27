# Productos del catálogo

Aquí vive **lo que la plataforma sirve**. Cada hands-on lleva su propia plataforma dentro,
en `hands-on/NN-*/modules/`.

Esta carpeta es **lo único que los dos hands-on comparten**, y no es casualidad: es
exactamente lo que el taller demuestra.

Esa separación es el asunto del taller. Un producto no sabe qué motor lo ejecuta por
debajo: `standard-environment` es exactamente el mismo módulo en el Hands-on 1 (Terraform
OS, apply en CodeBuild) y en el Hands-on 2 (HCP Terraform, apply en un workspace). No hay
copia, no hay variante, no hay `if`.

## Añadir un producto

Una carpeta aquí y una entrada en el mapa `productos` del hands-on:

```hcl
productos = {
  standard-environment = { nombre = "Standard Environment", ruta = "products/standard-environment", ... }
  data-lake            = { nombre = "Data Lake",            ruta = "products/data-lake",            ... }
}
```

No crea infraestructura: hay **una sola pipeline** para todo el catálogo y el mapa le llega
como variable de entorno. El detalle completo, en el README de la raíz.

## Qué debe cumplir un producto

- **Los `.tf` en la raíz de la carpeta.** El parameter parser de Service Catalog los busca
  en la raíz del `.tar.gz`, no en un subdirectorio.
- **Sin bloque `provider` ni `backend`.** Los pone quien ejecuta —el motor—, no el producto.
  Si necesitas declarar un provider aquí, casi seguro el cambio va en otro sitio.
- **Cada `variable` con su `description`.** Es lo que el usuario final ve como parámetro en
  el asistente de Service Catalog. Una variable sin descripción es un campo en blanco
  delante de alguien que no conoce el módulo.
- **Que pase las políticas.** `conftest test --parser hcl2 --combine --policy policies
  products/<tu-producto>/*.tf`

## El Launch Role

Es lo que más cuesta diagnosticar. El rol con el que Service Catalog aprovisiona está
acotado a lo que necesita `standard-environment`: VPC, S3 y roles IAM que casen
`*-environment-access`.

Un producto que cree RDS o EKS **pasa validate, pasa publish, y falla al aprovisionar** —
con el usuario final ya delante del asistente. Si el producto nuevo toca otros servicios,
amplía `data.aws_iam_policy_document.launch_role_permissions` en
`hands-on/01-terraform-os/modules/catalog-bootstrap/main.tf`.
