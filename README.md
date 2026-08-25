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

Módulos reutilizables por un lado, entornos que los componen por otro.

```
modules/
  terraform-os-engine/              motor Demo 1: SQS, Lambdas, Step Functions, CodeBuild
  hcp-terraform-engine/             motor Demo 2: envuelve el módulo de HashiCorp
  catalog-bootstrap-terraform-os/   Portfolio + Launch Role
  catalog-bootstrap-hcp-terraform/  Launch Role + acceso (el Portfolio lo crea el motor)
  catalog-pipeline/                 CodePipeline — UNO SOLO para las dos demos
  standard-environment/             el módulo de producto: red + almacenamiento + rol

live/
  demo1/    compone engine + bootstrap + pipeline con un provider
  demo2/    igual, con el motor de HCP Terraform
```

Tres reglas que hacen que esto componga:

- **Ningún módulo declara `provider`.** Solo `required_providers`. El provider lo
  configura el root. Eso es lo que permitirá añadir multicuenta con
  `providers = { aws = aws.spoke }` sin tocar un módulo.
- **Ningún módulo lee `terraform_remote_state`.** Los ARNs del motor entran como
  variables. La versión anterior leía `../engine/terraform.tfstate` con backend local:
  funcionaba en una máquina y en ninguna otra.
- **`catalog-pipeline` es un solo módulo.** Antes había dos copias que solo diferían en
  el tipo de producto; ahora es la variable `product_type` (`EXTERNAL` para el motor
  Terraform OS, `TERRAFORM_CLOUD` para el de HCP Terraform).

`standard-environment` es **el mismo módulo para las dos demos**: ambas pipelines apuntan
a `modules/standard-environment`. No hay copia.

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
cd modules/terraform-os-engine/lambda-functions && make bin   # ← imprescindible
cd ../../../live/demo1 && terraform init && terraform apply
```

Un solo `apply`: Terraform ordena motor → bootstrap → pipeline por dependencias.

`make bin` empaqueta las Lambdas (`pip install -r requirements.txt -t .` para Python,
`go build` para Go). Terraform no compila nada: `archive_file` lee `build/` en tiempo de
plan. Si se olvida, el `apply` falla con un mensaje explícito, no con un zip vacío.

### Demo 2

```bash
cd modules/hcp-terraform-engine/engine/lambda-functions && make bin
cd ../../../../live/demo2 && terraform init && terraform apply
```

Requiere `TFE_TOKEN` en el entorno.

## Limpieza

Siempre en orden inverso, y **terminando antes los productos aprovisionados** — si se
destruye el motor primero, no queda nada capaz de ejecutar el `destroy`:

```bash
aws servicecatalog terminate-provisioned-product --provisioned-product-id <pp-...>
cd live/demo1 && terraform destroy   # el orden inverso lo resuelve Terraform
```

El producto de Service Catalog lo crea la pipeline por CLI, no Terraform, así que hay que
borrarlo aparte (constraint → desasociar → `delete-product`).

## Documentación

- **[`WORKSHOP-LOG.md`](WORKSHOP-LOG.md)** — historial completo: cada decisión, cada
  comando, y los 9 problemas que hubo que resolver para que el E2E funcionara.
- **[`docs/MEJORA-PENDIENTE-webhook.md`](docs/MEJORA-PENDIENTE-webhook.md)** —
  diseño para sustituir el polling de `poll-run-status` por webhooks con firma HMAC-SHA512.


## Sobre multicuenta

Los módulos están escritos para que hub-and-spoke sea un cambio en `live/`, no un
rewrite: se añaden alias de provider y se pasan con `providers = {}`. **No está
implementado ni probado end-to-end** — hay una sola cuenta en la organización.

### Compartir productos EXTERNAL: verificado

La duda que quedaba —si los productos `EXTERNAL` se comparten entre cuentas como los de
CloudFormation— **está resuelta: sí.** Comprobado de dos formas:

- La documentación de AWS lo cubre explícitamente: el tutorial oficial de productos
  Terraform termina en *"Step 8: Share portfolio with end user (spoke account)"*, usando
  organization sharing desde la cuenta hub.
- Empíricamente en esta cuenta: se creó un portfolio con un producto `EXTERNAL` dentro y
  se compartió con `create-portfolio-share`, tanto a la organización completa como a una
  OU. Ambos aceptados (`Accepted: True`, `SharePrincipals: True`). Después se limpió todo
  y se restauró `organizations-access` a `DISABLED`, como estaba.

### Las restricciones reales

**1. Un solo motor EXTERNAL por cuenta hub.**

> *"You can only use one `EXTERNAL` provisioning engine per Service Catalog hub account.
> This limit is because `EXTERNAL` can only be routed to one engine in an account."*

Es la restricción más dura y no se puede rodear: si quieres dos motores EXTERNAL, van en
cuentas hub distintas. No afecta a tener las dos demos a la vez, porque la Demo 2 usa
`TERRAFORM_CLOUD`, que es otro tipo de producto y otras colas — de hecho convivieron sin
problema durante las pruebas.

**2. El Launch Role debe existir en CADA cuenta spoke, con el mismo nombre.**

> *"After creating the launch role in your AWS Service Catalog administrator account, you
> must also create an identical launch role in the AWS Service Catalog end user account.
> The role in the end user account must have the same name and include the same policy."*

Y por eso el launch constraint debe usar **`LocalRoleName`**, no `RoleArn`: así resuelve
al rol homónimo de cada cuenta en vez de apuntar al del hub.

> ⚠️ **`modules/catalog-pipeline/buildspec/publish.yml` publica hoy `{"RoleArn": ...}`.**
> Vale para monocuenta; para hub-and-spoke hay que cambiarlo a `{"LocalRoleName": ...}`.

**3. Los nombres de Launch Role deben empezar por `SCLaunch`.**

> *"Launch role names **must** begin with 'SCLaunch' followed by the desired role name."*

Los de este repo (`AurexServiceCatalogLaunchRole-…`) no lo cumplen. Funcionan en
monocuenta porque el `iam:PassRole` se concede explícitamente, pero el prefijo importa
para las políticas gestionadas de end-user de AWS.

**4. La confianza del rol en el spoke apunta al hub.** AWS documenta este patrón, con el
root de la cuenta hub y una condición sobre `aws:PrincipalArn`:

```json
{ "Principal": { "AWS": "arn:aws:iam::<HUB>:root" },
  "Condition": { "ArnLike": { "aws:PrincipalArn": [
      "arn:aws:iam::<HUB>:role/TerraformEngine/TerraformExecutionRole*",
      "arn:aws:iam::<HUB>:role/TerraformEngine/ServiceCatalogExternalParameterParserRole*" ] } } }
```

`catalog-bootstrap-hcp-terraform` ya usa esa forma. `catalog-bootstrap-terraform-os` pone
los ARN de rol directos en `Principal` — equivalente en monocuenta, pero conviene
alinearlo con la forma documentada.

**5. Terraform no puede hacer `for_each` sobre un provider.** N cuentas son N root modules
y N applies, orquestados desde CI. No se puede expresar en un solo apply.

**6. La Demo 2 necesita un OIDC provider de `app.terraform.io` en cada cuenta spoke** — es
un recurso IAM por cuenta.

### Un detalle a vigilar

El motor keya el state de Terraform en `{identity.awsAccountId}/{provisionedProductId}`,
que en multicuenta sería justo lo que quieres: el state namespaceado por cuenta spoke,
guardado en el bucket del hub. Empíricamente ese campo llega poblado. Pero la
documentación del contrato EXTERNAL marca `identity` como *"currently not used"*, así que
conviene verificarlo antes de apoyarse en él.

### Lo que juega a favor

El motor ya está diseñado para esto. El rol de CodeBuild tiene `sts:AssumeRole` sobre
`arn:aws:iam::*:role/*`, las colas viven en el hub y ahí llegan las peticiones de todas
las cuentas, y el backend S3 usa las credenciales del hub mientras el provider `aws` asume
el Launch Role del spoke: **el state se queda en el hub y los recursos aterrizan en el
spoke.**
