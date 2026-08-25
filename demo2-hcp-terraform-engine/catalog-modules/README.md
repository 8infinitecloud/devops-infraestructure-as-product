# catalog-modules — Demo 2

**Esta carpeta no contiene un módulo propio, y es intencionado.**

La Demo 2 reutiliza **exactamente el mismo** módulo que la Demo 1:

```
../../demo1-terraform-os-engine/catalog-modules/standard-environment/
```

Ese es precisamente el punto del taller: el mismo módulo Terraform, sin una sola línea
modificada, se aprovisiona con dos motores distintos.

| | Demo 1 | Demo 2 |
|---|---|---|
| Motor | Terraform OS + AWS CodeBuild | HCP Terraform (Terraform Cloud) |
| Dónde corre el `apply` | Contenedor de CodeBuild en tu cuenta | Workspace de HCP Terraform |
| Dónde vive el state | Bucket S3 `sc-terraform-engine-state-…` | Workspace de HCP Terraform |
| Credenciales AWS | El motor asume el Launch Role | Dynamic Credentials vía OIDC |
| Módulo | `standard-environment` | **el mismo** `standard-environment` |

La pipeline de esta demo (`../catalog-pipeline/`) apunta a esa misma ruta mediante el
parámetro `ModuleSourcePath`, así que ambas publican el mismo código fuente.

## Lo que cambia entre las dos demos

Nada del módulo. Lo único que difiere es **cómo llega el módulo al motor**:

- **Demo 1**: la pipeline empaqueta los `.tf` en un `.tar.gz` con los archivos en la raíz y
  lo registra como `provisioning-artifact` de tipo `TERRAFORM_OPEN_SOURCE`.
- **Demo 2**: mismo empaquetado y mismo registro, pero el producto es de tipo
  `EXTERNAL`, y quien ejecuta el `apply` es un workspace de HCP Terraform creado al vuelo
  por el motor de HashiCorp.

En ambos casos, el `terraform-parameter-parser` (Go) lee los bloques `variable` de los `.tf`
para exponerlos vía `DescribeProvisioningParameters`.
