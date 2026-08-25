# Infrastructure as a Product — Log de trabajo

Registro cronológico de decisiones, comandos y hallazgos. Cuenta AWS `058264353988`,
región `us-east-1`, org de HCP Terraform `8infinitecloud`.

---

## 0. Verificación de accesos (bloqueo declarado)

| Plataforma | Resultado |
|---|---|
| AWS | `arn:aws:iam::058264353988:user/hmunoz`, **AdministratorAccess**. 15 APIs probadas una a una (CFN, IAM, S3, Lambda, SFN, SQS, CodeBuild, CodePipeline, CodeConnections, Service Catalog, EC2, ECR, SSM, Logs): todas OK |
| GitHub | `8infinitecloud`, scopes `gist, project, read:org, repo, workflow` |
| HCP Terraform | Token de team `owners` (`api-team_2670286`), org `8infinitecloud`, `teams=true` (plan Essentials) |

**No me fié de los flags de permisos de HCP Terraform.** Verificación activa:

```bash
curl -X POST .../organizations/8infinitecloud/teams -d '{"data":{"type":"teams","attributes":{"name":"zz-permcheck-tmp"}}}'
# -> HTTP 201, luego DELETE -> HTTP 204
```

### Tooling
`sam 1.143.0` · `terraform 1.6.5` · `go 1.27.0` · `python 3.13.7` · `aws-cli 2.27.2` · `gh 2.47.0` · `jq 1.8.1`

**Docker daemon caído.** No bloquea: las 2 Lambdas Go usan `BuildMethod: makefile` (compilación
nativa con el Go local) y las Python compilan contra el `python3.13` del sistema. Solo impide
`sam build --use-container`.

---

## 1. Hallazgos que cambiaron el plan

### 1.1 Los repos no eran forks
`origin` de ambos clones apuntaba al upstream (`aws-samples/…`, `hashicorp/…`) y la cuenta no
tenía fork de ninguno. Confirmado por el usuario: *"no son forks, solo los clone y hice cambios locales"*.

**Decisión:** los clones son solo material fuente. Los demos se construyen en este repo
(`8infinitecloud/devops-infraestructure-as-product`). **Los clones se devolvieron intactos**
a su estado original — verificado: solo quedan los 2 archivos que el usuario ya tenía
modificados (`template.yaml`, `bin/bash/deploy-tre.sh`, migración py3.9 → py3.13).

### 1.2 Ya existía una conexión de CodeConnections autorizada
```
8infinitecloud  AVAILABLE  arn:aws:codestar-connections:us-east-1:058264353988:connection/4f7c1814-1665-42ea-9b37-c188cb60fcfd
```
**Esto elimina el paso manual de autorización en consola** previsto en la FASE 2. Las plantillas
la aceptan como parámetro `ConnectionArn`; si se deja vacío crean una nueva (que sí exigiría
autorización manual).

### 1.3 Restos de un intento anterior
- Service Catalog: portfolio `port-s2jeupfnqwaaq` "TFC Example Portfolio" ya existía.
- `aws-service-catalog-engine-for-tfc/terraform.tfstate`: serial 254, con ese portfolio dentro.
- HCP Terraform: workspace huérfano `058264353988-pp-xw6iwhnzk4ox2` (0 recursos).
- El OIDC provider de `app.terraform.io` **no existe** — el `EntityAlreadyExists` que anticipaba
  el usuario no se dará en este arranque. La lógica de import se deja igualmente preparada.

---

## 2. Gestión del token de HCP Terraform

El token llegó por chat en texto plano. Colocado en tres sitios según su uso, nunca en un archivo versionado:

| Sitio | Modo | Para qué |
|---|---|---|
| `~/.terraform.d/credentials.tfrc.json` | `0600` | Terraform CLI y provider `tfe` |
| `~/.config/aurex/tfe.env` | `0600`, dir `0700`, cargado desde `.zshrc` | `TFE_TOKEN` en la shell local |
| Secrets Manager `aurex/tfc/team-token` | — | Los pipelines, vía referencia `secrets-manager` de CodeBuild |

> ⚠️ **Rotar ese token al terminar el taller**: estuvo en texto plano en un chat.

---

## 3. Demo 1 — de SAM/CloudFormation a Terraform puro

### 3.1 Por qué

Las dos demos del taller usaban tooling distinto: la Demo 1 iba con SAM y la Demo 2 ya estaba en
Terraform. Se reescribió la Demo 1 a Terraform para que el taller enseñe **un solo tooling de punta
a punta** y la comparación entre motores sea limpia: lo único que cambia entre demos es el motor,
no la forma de desplegarlo.

> Antes de retirar SAM se llegó a desplegar el stack de CloudFormation hasta `CREATE_COMPLETE`,
> así que la arquitectura estaba validada; la migración fue de tooling, no de diseño.

### 3.2 Traducción recurso a recurso

| SAM / CloudFormation | Terraform |
|---|---|
| `AWS::Serverless::Function` | `aws_lambda_function` + `data.archive_file` |
| `AWS::Serverless::StateMachine` | `aws_sfn_state_machine` (misma definición ASL) |
| `DefinitionSubstitutions` | `templatefile()` sobre el mismo JSON |
| `AWS::SQS::Queue` | `aws_sqs_queue` (`for_each` sobre las 6 colas) |
| `AWS::SQS::QueuePolicy` | `aws_sqs_queue_policy` |
| `AWS::KMS::Key` | `aws_kms_key` + `data.aws_iam_policy_document` |
| `AWS::IAM::Role` + `Policies` | `aws_iam_role` + `aws_iam_role_policy` (1:1) |
| `ManagedPolicyArns` | `aws_iam_role_policy_attachment` |
| `AWS::Lambda::EventSourceMapping` | `aws_lambda_event_source_mapping` |
| `AWS::Lambda::Permission` | `aws_lambda_permission` |
| `AWS::CodeBuild::Project` | `aws_codebuild_project` |
| `AWS::S3::Bucket` (+ propiedades) | `aws_s3_bucket` + recursos `_versioning`, `_logging`, `_public_access_block`, `_server_side_encryption_configuration` |
| `sam build` | `lambda-functions/Makefile` |

**Total: 87 recursos de Terraform.**

### 3.3 Empaquetado de las Lambdas

Terraform no compila nada: `data.archive_file` lee `lambda-functions/build/` **en tiempo de plan**.
Por eso `make bin` va siempre antes de `terraform plan/apply` — el mismo patrón que ya usaba el
motor de HashiCorp en la Demo 2.

```makefile
python:  # por cada Lambda: copia fuentes (sin tests) + pip install -r requirements.txt -t build/<name>
go:      # GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -o build/terraform-parameter-parser/bootstrap
verify:  # comprueba con file(1) que el binario es x86-64, no el del host
```

`lambda_packaging.tf` añade una `precondition` que falla con un mensaje claro si alguien olvidó
ejecutar `make bin`, en vez de producir un zip vacío.

### 3.4 EC2 → CodeBuild

Se eliminaron VPC, 3 NAT Gateways, 3 EIP, 6 subredes, IGW, tablas de rutas, security group,
VPC endpoint de S3, Auto Scaling Group, Launch Template e Instance Profile. En su lugar, un único
`aws_codebuild_project` sin `vpc_config`.

Las Step Functions pasan de

```
Generate Tracer Tag → Select worker host → Send apply command → Wait → Poll → Choice → Get state file outputs
```

a

```
Generate Tracer Tag → Run Terraform apply (codebuild:startBuild.sync) → Get state file outputs
```

Se eliminaron `select-worker-host` y `poll-command-invocation` (pedido explícito) y también
`send-apply-command` y `send-destroy-command`: su único trabajo era construir el `SSM SendCommand`
que la integración síncrona sustituye. Con ellas se fueron `core/ssm_facade.py` y `core/cli.py`.

**Se preserva `isWrapperError: true`**, de modo que un fallo de Terraform se notifica a Service
Catalog como fallo del producto pero la state machine termina en `Succeeded` — porque la
notificación sí funcionó. El contrato con Service Catalog no cambia.

### 3.5 El buildspec reproduce los overrides — verificado, no asumido

`terraform_runner` (Python) se reescribió como bash + `jq`. Para comprobar la equivalencia se
ejecutaron **ambas implementaciones con los mismos inputs** y se compararon:

```
backend_override.tf.json  : IDÉNTICO
provider_override.tf.json : IDÉNTICO
variable_override.tf.json : IDÉNTICO
```

Incluye el caso borde de `write_variable_override`: un parámetro cuyo valor es JSON anidado se
decodifica (`fromjson? // .value` en jq ≡ `json.loads` con fallback a string en Python).

---

## 4. Problemas encontrados y cómo se resolvieron

| # | Síntoma | Causa real | Solución |
|---|---|---|---|
| 1 | `sam build` producía un binario ARM | `GOARACH` (typo de `GOARCH`) en el Makefile upstream: en un Mac Apple Silicon compilaba para el host, no para `x86_64` como declara la Lambda | Corregido el typo. `make verify` lo comprueba con `file(1)` en cada build |
| 2 | Changeset fallaba con `AWS::EarlyValidation::ResourceExistenceCheck` | 3 policies marcadas "temporary" importaban `TerraformEngineBootstrapBucketArn`, un export inexistente. Alojaba el wheel de `terraform_runner`, innecesario con CodeBuild | Bloques eliminados |
| 3 | Idem, segunda vuelta | Log groups `/aws/vendedlogs/states/*` huérfanos de un intento anterior | Borrados antes de aplicar |
| 4 | Pipeline: `Unable to use Connection ... insufficient permissions` | La pipeline se autoejecuta al crearse, antes de que la política IAM propague. `simulate-principal-policy` confirmó que el permiso era correcto | Relanzar la ejecución |
| 5 | Publish: `Value 'TERRAFORM_OPEN_SOURCE' failed to satisfy constraint` | **AWS retiró ese `productType` el 2023-12-14** y lo sustituyó por `EXTERNAL` | Publicar como `EXTERNAL`. El motor ya escuchaba ese flujo: las colas `ServiceCatalogExternal*` y el `ExternalParameterParser` existían para eso |
| 6 | Publish: `Product type EXTERNAL requires DisableTemplateValidation set to true` | Requisito de la API para productos EXTERNAL | Añadido al `provisioning-artifact-parameters` |
| 7 | Runner: `aws s3 cp` → `ParamValidation: Invalid argument type` | Service Catalog entrega la ruta como **`S3://`** en mayúsculas. El Python original troceaba el string (case-insensitive); `aws s3 cp` exige `s3://` | Separar bucket y key a mano y usar `aws s3api get-object`, replicando `artifact_manager.download_artifact` |
| 8 | Producto en `ERROR` con el `apply` correcto | Service Catalog crea un **Resource Group** por producto asumiendo el Launch Role | Añadidos `resource-groups:*` y `tag:*` al Launch Role |
| 9 | `terraform destroy` fallaba al borrar subredes | Faltaba `ec2:DescribeNetworkInterfaces` | Concedido `ec2:Describe*` (solo lectura) + `DeleteNetworkInterface`/`DetachNetworkInterface`, en vez de ir añadiendo acciones una a una |

---

## 5. Demo 1 — resultado de las pruebas E2E

| Prueba | Resultado |
|---|---|
| `make bin` + arquitectura del binario Go | OK — `x86-64`, coincide con lo declarado |
| Tests unitarios Python | **49/49 pasan** (42 state_machine_lambdas + 7 provisioning-operations-handler) |
| `terraform validate` (engine, bootstrap, pipeline, módulo) | OK en los cuatro |
| `terraform apply` engine | **87 recursos** creados |
| `terraform apply` catalog-bootstrap | 4 recursos. Portfolio `port-v3ogqn5le7mns` |
| `terraform apply` catalog-pipeline | 14 recursos |
| Pipeline: Source (GitHub) | **Succeeded** |
| Pipeline: Build/Validate | **Succeeded** — `fmt -check`, `validate`, y `.tf` verificados en la raíz del `.tar.gz` |
| Pipeline: Publish | **Succeeded** — producto `prod-gsvtnjlcyhsce`, versión `v20260825-120238-3e2d8bd`, asociado al portfolio, Launch Constraint creado |
| `DescribeProvisioningParameters` (parser Go) | **OK** — extrajo las 5 variables del módulo con descripciones y defaults |
| Aprovisionamiento del producto | **AVAILABLE** |
| Step Functions `ManageProvisionedProductStateMachine` | **SUCCEEDED** |
| Recursos reales en AWS | VPC `vpc-0ee92c5f7291415e6` (10.40.0.0/16), 2 subredes en 2 AZ, bucket `aurexdemo1-storage-…`, rol `aurexdemo1-environment-access` |
| Record outputs devueltos a Service Catalog | `vpc_id`, `subnet_ids`, `storage_bucket_name`, `access_role_arn` |
| `TerminateProvisionedProduct` | **OK** — `terraform destroy` vía CodeBuild eliminó la VPC y el bucket |

---

## 6. Demo 2 — motor de HCP Terraform

### 6.1 Qué se hizo

Ya estaba en Terraform, así que no hubo traducción de tooling. El trabajo fue **alinear la
estructura** a las mismas 4 carpetas de la Demo 1:

- `engine/` — el módulo de HashiCorp **sin cambios de arquitectura**. Se añadió únicamente
  un `outputs.tf` en el módulo raíz para re-exportar los ARNs que necesitan las otras carpetas.
- `catalog-bootstrap/` — **no crea Portfolio**: reutiliza el "TFC Example Portfolio" que el propio
  motor crea al aplicar. Aporta solo el acceso al Portfolio y el Launch Role del producto
  `standard-environment`, que el motor no cubre (solo crea el de *su* producto de ejemplo).
- `catalog-pipeline/` — mismo patrón que la Demo 1, publicando como `TERRAFORM_CLOUD`.
- `catalog-modules/` — **no duplica el módulo**: un README apunta al de la Demo 1.

### 6.2 Decisión sobre el Launch Role y OIDC

El motor acota el `sub` del token OIDC al **ID del producto** como nombre de proyecto:

```
organization:<org>:project:<productId>:workspace:*:run_phase:*
```

Aquí el producto lo crea `catalog-pipeline/` *después* de que exista el rol, así que el
proyecto va con comodín. Es una relajación consciente, acotada a esta organización de HCP
Terraform, y queda anotada porque en producción convendría invertir el orden: crear el
producto en `catalog-bootstrap/` y que la pipeline solo añada versiones.

### 6.3 La mejora del webhook: no implementada, documentada

Se despliega con el polling de `poll-run-status` tal y como viene. El diseño completo del
reemplazo por webhooks (notification configurations con firma HMAC-SHA512 → API Gateway →
`.waitForTaskToken`) está en `demo2-hcp-terraform-engine/MEJORA-PENDIENTE-webhook.md`,
con el alcance del cambio, por qué se pospuso y cómo se validaría.

### 6.4 Problema encontrado

| Síntoma | Causa | Solución |
|---|---|---|
| `InvalidRequestException: a secret with this name is already scheduled for deletion` | El secreto `terraform-cloud-credentials-for-service-catalog-engine` de un intento del 2026-08-24 estaba en ventana de recuperación, bloqueando el nombre | `delete-secret --force-delete-without-recovery` y reintento |

El `EntityAlreadyExists` del OIDC provider que se anticipaba **no se dio**: se verificó antes con
`aws iam list-open-id-connect-providers` que no existía ninguno para `app.terraform.io`. La lógica
de import queda documentada por si reaparece.

### 6.5 Resultado de las pruebas E2E

| Prueba | Resultado |
|---|---|
| `make bin` (7 Lambdas en Go, arm64) | OK |
| `terraform apply` engine | **135 recursos**. Team `aurex-service-catalog` creado en HCP Terraform, OIDC provider creado |
| `terraform apply` catalog-bootstrap | 3 recursos. Reutiliza el portfolio `port-lefekjdiwz6q4` del motor |
| `terraform apply` catalog-pipeline | 14 recursos |
| Pipeline: Source / Build-Validate / Publish | **Succeeded las 3** — producto `prod-4xc5xszrhiriq`, versión `v20260825-130354-aa19bdb` |
| `DescribeProvisioningParameters` | **OK** — el parser del motor de HashiCorp leyó **el mismo módulo** de la Demo 1 y extrajo las mismas 5 variables |
| Aprovisionamiento | **AVAILABLE** |
| Workspace en HCP Terraform | `058264353988-pp-znx2rcggrcgws`, Terraform 1.5.7, **16 recursos** |
| Run en HCP Terraform | `run-sLdjvdgKerFciP8Z` → **applied** |
| Recursos reales en AWS | VPC `vpc-03abfb14b2d19b918` (10.50.0.0/16), 2 subredes en 2 AZ, bucket `aurexdemo2-storage-…`, rol `aurexdemo2-environment-access` |
| Record outputs | `vpc_id`, `subnet_ids`, `storage_bucket_name`, `access_role_arn` |

### 6.6 La demostración del taller

El mismo `standard-environment`, sin una línea distinta, aprovisionado por los dos motores:

| | Demo 1 | Demo 2 |
|---|---|---|
| Ejecuta el apply | Contenedor de CodeBuild | Workspace de HCP Terraform |
| State | S3 `sc-terraform-engine-state-…` | Workspace de HCP Terraform |
| Credenciales | El motor asume el Launch Role | Dynamic Credentials vía OIDC |
| Tipo de producto | `EXTERNAL` | `TERRAFORM_CLOUD` |
| VPC creada | `10.40.0.0/16` | `10.50.0.0/16` |
| Parámetros expuestos | Los mismos 5 | Los mismos 5 |

---

## 7. FASE 4 — Limpieza

### Orden seguido

En ambas demos: **terminar el producto aprovisionado primero**. Si se destruye el motor
antes, no queda nada capaz de ejecutar el `destroy` y los recursos se quedan huérfanos.
Después, el producto de Service Catalog (lo crea la pipeline por CLI, no Terraform:
constraint → desasociar → `delete-product`). Y por último `terraform destroy` en orden
inverso.

| Demo | catalog-pipeline | catalog-bootstrap | engine | Total |
|---|---|---|---|---|
| Demo 1 | 14 | 4 | 87 | **105** |
| Demo 2 | 14 | 3 | 96 | **113** |

**218 recursos destruidos.** `terraform state list` devuelve 0 en las seis carpetas.

### Verificación final

| Recurso | Estado |
|---|---|
| Stacks CloudFormation | vacío |
| Lambdas del taller | vacío |
| Step Functions | vacío |
| Colas SQS `ServiceCatalog*` | vacío |
| Proyectos CodeBuild | vacío |
| Pipelines | vacío |
| EC2 (activas o paradas) | vacío |
| NAT Gateways | vacío |
| VPCs del módulo | vacío |
| Roles IAM del taller | vacío |
| Buckets S3 del taller | vacío |
| Portfolios | solo `samples` (preexistente, ajeno) |
| Workspaces en HCP Terraform | solo `lab-resources-serverless`, `lab-infragraph-connector`, `dev` (tuyos) |
| Teams en HCP Terraform | solo `owners`. El `aurex-service-catalog` que creó el motor desapareció con el destroy |
| OIDC providers | solo el de GitHub Actions. El de `app.terraform.io` se creó y se destruyó con el motor |

### Restos limpiados que no eran de este trabajo

- Portfolio `port-s2jeupfnqwaaq` "TFC Example Portfolio" (23-ago). Hubo que **desasociar el
  principal antes** de poder borrarlo.
- Workspace huérfano `058264353988-pp-xw6iwhnzk4ox2` en HCP Terraform (24-ago).
- Producto aprovisionado `test-tfc-bucket-1787546133`.
- Resource group `SC-058264353988-pp-xw6iwhnzk4ox2`.
- Secreto `terraform-cloud-credentials-for-service-catalog-engine` en ventana de recuperación.
- Stack y bucket `aws-sam-cli-managed-default`, creados por el `sam deploy` previo a la
  migración. El borrado del stack falló primero porque el bucket tenía **10 versiones de
  objeto**; hubo que vaciarlas una a una antes de reintentar.

### Lo que NO se pudo limpiar

**`pp-ojclw6uitaxtg` (`test-s3-website-1787541361`)** — atascado en `UNDER_CHANGE` desde el
**2026-08-23**, dos días antes de este trabajo. Service Catalog rechaza terminarlo:

```
ValidationException: Can't terminate provisioned product because it's still under
change or its status does not allow further operation
```

Es un **registro de Service Catalog sin recursos detrás**: no hay buckets, ni VPCs, ni
instancias asociadas — verificado. No genera coste. El motor que lo creó ya no existe, así
que el registro no puede avanzar por sí solo. Requiere abrir un caso con soporte de AWS.

### Pendiente para el usuario

El token de HCP Terraform llegó por chat en texto plano. **Conviene rotarlo.** Sigue
almacenado en:
- `~/.terraform.d/credentials.tfrc.json` (0600)
- `~/.config/aurex/tfe.env` (0600)
- Secrets Manager `aurex/tfc/team-token`

Ninguna de las dos pipelines acabó consumiéndolo: en la Demo 2 el token solo hace falta en
local, para que el provider `tfe` cree el team y el workspace durante el `apply`.
