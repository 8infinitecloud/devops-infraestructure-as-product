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
        │  Hands-on 1               │       │  Hands-on 2               │
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
  terraform-os-engine/              motor Hands-on 1: SQS, Lambdas, Step Functions, CodeBuild
  hcp-terraform-engine/             motor Hands-on 2: envuelve el módulo de HashiCorp
  catalog-bootstrap-terraform-os/   Portfolio + Launch Role
  catalog-bootstrap-hcp-terraform/  Launch Role + acceso (el Portfolio lo crea el motor)
  catalog-pipeline/                 CodePipeline — UNO SOLO para los dos hands-on
  standard-environment/             el módulo de producto: red + almacenamiento + rol

hands-on/
  01-terraform-os/     compone engine + bootstrap + pipeline con un provider
  02-hcp-terraform/    igual, con el motor de HCP Terraform
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

`standard-environment` es **el mismo módulo para los dos hands-on**: ambas pipelines apuntan
a `modules/standard-environment`. No hay copia.

## Qué cambia entre los dos hands-on

|  | Hands-on 1 | Hands-on 2 |
|---|---|---|
| Motor | `aws-samples/service-catalog-engine-for-terraform-os` | `hashicorp/aws-service-catalog-engine-for-tfc` |
| Dónde corre el `apply` | Contenedor de AWS CodeBuild | Workspace de HCP Terraform |
| Dónde vive el state | Bucket S3 en tu cuenta | Workspace de HCP Terraform |
| Credenciales AWS | El motor asume el Launch Role | Dynamic Credentials vía OIDC |
| Tipo de producto | `EXTERNAL` | `TERRAFORM_CLOUD` |
| Colas SQS | `ServiceCatalogExternal*`, `ServiceCatalogTerraformOS*` | `ServiceCatalogTerraformCloud*` |

Los nombres de cola no colisionan, así que **ambos motores pueden convivir** en la misma
cuenta.

## Hands-on 1 — la reescritura

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
—solo para el Hands-on 2— `TFE_TOKEN`.

### Configuración

Cada hands-on necesita su `terraform.tfvars`, que **no está versionado**: identifica tu
cuenta, tu usuario y tu repositorio. Se parte del ejemplo:

```bash
cd hands-on/01-terraform-os
cp terraform.tfvars.example terraform.tfvars   # y rellena tus valores
```

Sin fichero, por entorno —que es lo que quieres en CI—, cualquier variable acepta el
prefijo `TF_VAR_`:

```bash
export TF_VAR_github_repository_id="mi-org/mi-repo"
export TF_VAR_grant_access_to_principal_arns='["arn:aws:iam::123456789012:user/yo"]'
```

Las credenciales **nunca** van en un `.tfvars`, ni siquiera en uno ignorado:

| Credencial | Dónde va |
|---|---|
| AWS | El cadena de proveedores estándar: `aws configure`, SSO o rol de instancia |
| HCP Terraform | `TFE_TOKEN` en el entorno, o `~/.terraform.d/credentials.tfrc.json` con `0600` |
| Infracost | Secrets Manager, por ARN en `infracost_api_key_secret_arn`. CodeBuild la resuelve en ejecución: no pasa por el state ni por el buildspec |

### Hands-on 1

```bash
cd modules/terraform-os-engine/lambda-functions && make bin   # ← imprescindible
cd ../../../hands-on/01-terraform-os && terraform init && terraform apply
```

Un solo `apply`: Terraform ordena motor → bootstrap → pipeline por dependencias.

`make bin` empaqueta las Lambdas (`pip install -r requirements.txt -t .` para Python,
`go build` para Go). Terraform no compila nada: `archive_file` lee `build/` en tiempo de
plan. Si se olvida, el `apply` falla con un mensaje explícito, no con un zip vacío.

### Hands-on 2

```bash
cd modules/hcp-terraform-engine/engine/lambda-functions && make bin
cd ../../../../hands-on/02-hcp-terraform && terraform init && terraform apply
```

Requiere `TFE_TOKEN` en el entorno.

## Limpieza

Siempre en orden inverso, y **terminando antes los productos aprovisionados** — si se
destruye el motor primero, no queda nada capaz de ejecutar el `destroy`:

```bash
aws servicecatalog terminate-provisioned-product --provisioned-product-id <pp-...>
cd hands-on/01-terraform-os && terraform destroy   # el orden inverso lo resuelve Terraform
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
cuentas hub distintas. No afecta a tener los dos hands-on a la vez, porque el Hands-on 2 usa
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

**6. La Hands-on 2 necesita un OIDC provider de `app.terraform.io` en cada cuenta spoke** — es
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

## Añadir un producto al catálogo

El catálogo son **datos**. Añadir un producto es añadir una entrada al mapa `productos`
de `hands-on/01-terraform-os/main.tf` y crear su carpeta bajo `modules/`:

```hcl
locals {
  productos = {
    standard-environment = {
      nombre      = "Standard Environment"
      ruta        = "modules/standard-environment"
      descripcion = "Red, almacenamiento y rol de acceso estándar."
    }

    data-lake = {                                    # ← el producto nuevo
      nombre      = "Data Lake"
      ruta        = "modules/data-lake"
      descripcion = "Bucket con catálogo Glue y permisos de lectura."
    }
  }
}
```

`terraform apply` y ya: de esa entrada salen una CodePipeline, sus tres proyectos de
CodeBuild, sus log groups y sus dos roles. No se copia ni una línea de HCL.

| Campo | Para qué | Cuidado |
|---|---|---|
| **clave** | Prefijo de los recursos AWS (`aurex-os-<clave>-*`) | Cambiarla **destruye y recrea** la pipeline |
| `nombre` | Cómo se ve en Service Catalog | Es la clave con la que Publish busca el producto: cambiarlo crea uno **nuevo** en vez de versionar el que había |
| `ruta` | Dónde viven los `.tf`, desde la raíz del repo | Los `.tf` acaban en la **raíz** del `.tar.gz`; lo exige el parameter parser |

### Antes de añadir uno: mira el Launch Role

Es el error más caro, porque aparece al final. El Launch Role de `catalog-bootstrap` está
acotado a lo que necesita `standard-environment` — VPC, S3, y roles IAM que casen
`*-environment-access`. Un producto que cree RDS o EKS **pasa validate, pasa publish, y
falla al aprovisionar**, cuando el usuario final ya le dio a "Launch".

Si el producto nuevo toca servicios distintos, hay que ampliar
`data.aws_iam_policy_document.launch_role_permissions` en
`modules/catalog-bootstrap-terraform-os/main.tf`.

### ¿Y productos en OTROS repositorios?

Se puede, pero no sale gratis. `github_repository_id` ya es variable del módulo, así que
moverla al mapa es una línea. Lo que cuesta es lo de alrededor:

- **Las políticas viven aquí.** `policy_source_path = "policies"` se resuelve dentro del
  artefacto del `Source`. Si la pipeline trae un repo externo, `policies/` no está ahí y la
  etapa Inspect no evalúa nada. Hace falta un segundo source action, o publicar las
  políticas a S3.
- **La conexión cubre una organización.** Repos bajo la misma org de GitHub reutilizan la
  conexión sin coste. Otra org = otra conexión y otra autorización manual en consola.

Por eso el taller mantiene los productos en este repo: enseña el patrón sin pagar esa
complejidad.

## Gobierno del catálogo: inspección y coste

Un producto de catálogo necesita puertas de calidad, igual que cualquier otro producto.
Aquí hay **dos**, y confundirlas es el error habitual:

| | Puerta de publicación | Puerta de aprovisionamiento |
|---|---|---|
| Dónde | Etapa `Inspect` de `catalog-pipeline` | `TerraformEngineRunner`, antes del `apply` |
| Qué ve | El módulo con sus valores **por defecto** | El `terraform plan` real, con los parámetros del usuario |
| Pregunta | ¿Este producto entra al catálogo? | ¿Este despliegue concreto se permite? |
| Herramientas | Checkov, TFLint, Gitleaks, Conftest, Infracost (indicativo) | Infracost sobre el plan |

**Por qué importa la distinción.** Si estimas el coste solo al publicar, lo haces con
`subnet_count = 2` y el CIDR por defecto. Si el usuario aprovisiona con otra cosa, tu
estimación no lo vio. El coste solo se gobierna de verdad en la segunda puerta.

### Etapa `Inspect`

```
Source → BuildValidate → Inspect → Approve → Publish
```

- **Checkov** — misconfiguraciones. Emite JUnit, así que aparece como reporte nativo en la
  consola de CodeBuild, no enterrado en el log.
- **TFLint** — argumentos deprecados, tipos inválidos, reglas del provider AWS.
- **Gitleaks** — secretos commiteados. Escanea el repo entero, no solo el módulo.
- **Conftest/OPA** — las políticas de Aurex, en [`policies/`](policies/). Es lo que
  distingue este pipeline de uno genérico.
- **Infracost** — estimación indicativa del módulo.

**Es advisory por diseño: ningún hallazgo detiene la pipeline.** Los reportes se publican y
quien decide es la aprobación manual de la etapa `Approve`. Los chequeos informan, la
persona decide. Para hacerla bloqueante, quita los `|| true` y el `exit 0` de
`modules/catalog-pipeline/buildspec/inspect.yml`.

### Puerta de coste en el aprovisionamiento

El runner pasa de `apply` directo a **`plan` → estimar → `apply` del plan guardado**. Se
aplica el plan que se costeó, no otro.

```hcl
infracost_max_monthly_usd = "0"    # advisory: estima y registra
infracost_max_monthly_usd = "50"   # aborta antes de crear nada si se pasa
```

> **Asimetría a tener en cuenta:** el hands-on 02 **no tiene esta puerta**. Su `apply` corre
> en un workspace de HCP Terraform, no en un CodeBuild de esta cuenta, así que no hay dónde
> interceptar el plan. El equivalente sería una *run task* o una policy **Sentinel** en el
> workspace.

### Requisitos

Infracost necesita una API key (gratuita) en Secrets Manager, con formato
`{"api_key":"ico-..."}`. CodeBuild la resuelve en ejecución: no viaja en el buildspec, ni en
el state, ni en los logs.

```hcl
infracost_api_key_secret_arn = "arn:aws:secretsmanager:...:secret:aurex/infracost-XXXX"
```

Sin ella, la estimación se omite y el resto de la inspección funciona igual.

### Infracost nunca detiene nada por fallar

Está blindado a propósito, y en el runner importa más que en la pipeline: un fallo ahí no
rompería un build, rompería **el aprovisionamiento de un usuario final**. Verificado con
ocho escenarios simulados:

| Escenario | Resultado |
|---|---|
| Sin API key | Se omite, continúa |
| Sin API key pero con límite configurado | Continúa, avisa que la puerta no se aplicó |
| API key presente pero binario no instalado | Continúa con aviso |
| Coste 12.34, límite 50 | Continúa |
| **Coste 250, límite 50** | **Aborta antes de crear nada** ← el único caso |
| Coste 250, límite 0 | Continúa (advisory) |
| Infracost caído / API key inválida | Continúa con aviso |
| Infracost devuelve `null` | Continúa sin comparar |

**Es fail-open deliberado.** Si hay límite pero la estimación falla, se continúa. La
alternativa —bloquear cuando no se puede estimar— convertiría cualquier caída de Infracost
en una caída del catálogo entero. El coste de esta decisión es que la puerta se puede eludir
rompiendo la herramienta, y por eso el aviso es ruidoso y queda en el log del build. Si
alguna vez necesitas fail-closed, el sitio es la rama `elif [ "${LIMIT}" != "0" ]` de
`modules/terraform-os-engine/buildspec/terraform-runner.yml`.

### Versiones fijadas a propósito

Las herramientas se instalan desde tarballs de release **con versión fijada**, no con
`curl | sh` de un script en `master`. Una pipeline que audita seguridad no debería
introducir el mismo riesgo de cadena de suministro que se supone que detecta.

## Repositorio: CI, contribución y licencia

Las mismas puertas de la pipeline corren también en GitHub Actions
(`.github/workflows/ci.yml`), con la misma división de responsabilidades:

| Trabajo | Qué hace | ¿Bloquea? |
|---|---|---|
| `validate` | `terraform fmt -check` sobre todo el repo y `terraform validate` en los 6 módulos y los 2 hands-on | Sí |
| `test-go` | `go vet` y `go test -race` en los dos módulos Go (versiones distintas, cada una sale de su `go.mod`) | Sí |
| `test-python` | `pytest` sobre las Lambdas del motor Terraform OS | Sí |
| `inspect` | Checkov, TFLint, Conftest y Gitleaks | **No** |

Que `inspect` no bloquee es la misma decisión, y por el mismo motivo, que en
`buildspec/inspect.yml`: sobre un hallazgo decide una persona, no la herramienta. Si el CI
de GitHub bloqueara y la pipeline no, el mismo commit tendría dos veredictos distintos.

Terraform está fijado a la **misma versión** que `terraform_cli_version` de la pipeline
(1.5.7). Si divergen, `fmt -check` puede discrepar entre GitHub y CodeBuild sobre el mismo
código.

- **Contribuir:** [CONTRIBUTING.md](CONTRIBUTING.md)
- **Vulnerabilidades:** [SECURITY.md](SECURITY.md) — reporte privado, nunca un issue público.

### Licencia

Código propio bajo **Apache 2.0** ([LICENSE](LICENSE)). Los dos motores son código
vendorizado y **conservan la suya**:

| Directorio | Origen | Licencia |
|---|---|---|
| `modules/terraform-os-engine/` | Terraform Reference Engine, de AWS | Apache 2.0 |
| `modules/hcp-terraform-engine/` | AWS Service Catalog Engine for TFC, de HashiCorp/IBM | **MPL 2.0** |

La MPL 2.0 es copyleft **por fichero**: lo que modifiques dentro de
`modules/hcp-terraform-engine/` sigue siendo MPL 2.0 aunque el resto del repo sea Apache.
El detalle completo, en [NOTICE](NOTICE).
