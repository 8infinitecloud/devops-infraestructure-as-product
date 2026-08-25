# Infrastructure as a Product — Taller Aurex

Dos motores de aprovisionamiento para **AWS Service Catalog**, desplegados con el
**mismo tooling** (Terraform puro) y sirviendo **el mismo módulo**.

Ese es el punto del taller: cuando la infraestructura se trata como producto, el módulo
que consume un equipo no depende de cómo se ejecuta por debajo.

```
                     ┌─────────────────────────────┐
                     │   standard-environment      │
                     │   red · almacenamiento ·    │
                     │   rol de acceso             │
                     └──────────────┬──────────────┘
                                    │  el MISMO módulo
                    ┌───────────────┴───────────────┐
                    ▼                               ▼
        ┌───────────────────────┐       ┌───────────────────────┐
        │  Demo 1               │       │  Demo 2               │
        │  Terraform OS         │       │  HCP Terraform        │
        │  apply en CodeBuild   │       │  apply en un workspace│
        │  state en S3          │       │  state en HCP         │
        │  producto EXTERNAL    │       │  producto TERRAFORM_  │
        │                       │       │  CLOUD                │
        └───────────────────────┘       └───────────────────────┘
```

## Estructura

Cada demo tiene las mismas 4 carpetas:

| Carpeta | Qué contiene |
|---|---|
| `engine/` | El motor: colas SQS, Lambdas, Step Functions y el cómputo que ejecuta Terraform |
| `catalog-bootstrap/` | Portfolio de Service Catalog y Launch Role |
| `catalog-pipeline/` | CodeConnections + CodePipeline: Source → Build/Validate → Publish |
| `catalog-modules/` | El módulo `standard-environment` |

`demo2-hcp-terraform-engine/catalog-modules/` **no duplica el módulo**: apunta al de la
Demo 1. Ver su `README.md`.

## Qué cambia entre las dos demos

|  | Demo 1 | Demo 2 |
|---|---|---|
| Motor | `aws-samples/service-catalog-engine-for-terraform-os` | `hashicorp/aws-service-catalog-engine-for-tfc` |
| Dónde corre el `apply` | Contenedor de AWS CodeBuild | Workspace de HCP Terraform |
| Dónde vive el state | Bucket S3 en tu cuenta | Workspace de HCP Terraform |
| Credenciales AWS | El motor asume el Launch Role | Dynamic Credentials vía OIDC |
| Tipo de producto | `EXTERNAL` | `TERRAFORM_CLOUD` |
| Colas SQS | `ServiceCatalogExternal*`, `ServiceCatalogTerraformOS*` | `ServiceCatalogTerraformCloud*` |

Los nombres de cola no colisionan, así que **ambos motores pueden convivir** en la misma
cuenta.

## Demo 1 — la reescritura

El motor de AWS venía en SAM/CloudFormation y ejecutaba Terraform en un **Auto Scaling
Group de EC2** dentro de una VPC con 3 NAT Gateways, orquestado por SSM Run Command con
polling manual desde Step Functions.

Se reescribió entero:

- **SAM → Terraform puro**, recurso a recurso (87 recursos).
- **EC2 + VPC + NAT + SSM → un `aws_codebuild_project`**. Fuera la VPC, las 6 subredes,
  los 3 NAT Gateways, las 3 EIP, el ASG y el Launch Template.
- **Polling → `codebuild:startBuild.sync`**. Las Lambdas `select-worker-host` y
  `poll-command-invocation` desaparecen; con ellas `send-apply-command` y
  `send-destroy-command`, que solo construían el `SSM SendCommand`.

El buildspec reproduce los tres overrides que escribía el paquete `terraform_runner`
(`backend_override.tf.json`, `provider_override.tf.json`, `variable_override.tf.json`).
La equivalencia **se verificó ejecutando ambas implementaciones con los mismos inputs**:
salidas byte-idénticas.

**El contrato con Service Catalog no cambia**: las mismas colas, el mismo formato de
mensajes, `DescribeProvisioningParameters` y `Notify*EngineWorkflowResult` intactos.

## Cómo desplegar

Requisitos: `terraform >= 1.5`, `go`, `python3`, `aws-cli`, credenciales de AWS y
—solo para la Demo 2— `TFE_TOKEN`.

### Demo 1

```bash
cd demo1-terraform-os-engine/engine/lambda-functions && make bin   # ← imprescindible
cd .. && terraform init && terraform apply

cd ../catalog-bootstrap && terraform init && terraform apply
cd ../catalog-pipeline  && terraform init && terraform apply
```

`make bin` empaqueta las Lambdas (`pip install -r requirements.txt -t .` para Python,
`go build` para Go). Terraform no compila nada: `archive_file` lee `build/` en tiempo de
plan. Si se olvida, el `apply` falla con un mensaje explícito, no con un zip vacío.

### Demo 2

```bash
cd demo2-hcp-terraform-engine/engine/engine/lambda-functions && make bin
cd ../.. && terraform init && terraform apply

cd ../catalog-bootstrap && terraform init && terraform apply
cd ../catalog-pipeline  && terraform init && terraform apply
```

## Limpieza

Siempre en orden inverso, y **terminando antes los productos aprovisionados** — si se
destruye el motor primero, no queda nada capaz de ejecutar el `destroy`:

```bash
aws servicecatalog terminate-provisioned-product --provisioned-product-id <pp-...>
cd catalog-pipeline  && terraform destroy
cd ../catalog-bootstrap && terraform destroy
cd ../engine         && terraform destroy
```

El producto de Service Catalog lo crea la pipeline por CLI, no Terraform, así que hay que
borrarlo aparte (constraint → desasociar → `delete-product`).

## Documentación

- **[`WORKSHOP-LOG.md`](WORKSHOP-LOG.md)** — historial completo: cada decisión, cada
  comando, y los 9 problemas que hubo que resolver para que el E2E funcionara.
- **[`demo2-hcp-terraform-engine/MEJORA-PENDIENTE-webhook.md`](demo2-hcp-terraform-engine/MEJORA-PENDIENTE-webhook.md)** —
  diseño para sustituir el polling de `poll-run-status` por webhooks con firma HMAC-SHA512.
