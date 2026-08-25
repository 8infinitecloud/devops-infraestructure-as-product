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

## 3. Demo 1 — reestructura del motor a CodeBuild

### 3.1 Qué se eliminó

**Red completa** (VPC, 3 NAT Gateways, 3 EIP, 6 subredes, IGW, tablas de rutas, SG, VPC endpoint de S3),
**cómputo EC2** (Auto Scaling Group, Launch Template, Instance Profile, rol del ASG) y **4 Lambdas**:

| Lambda | Por qué |
|---|---|
| `select-worker-host` | Pedido explícitamente. Ya no hay flota que elegir |
| `poll-command-invocation` | Pedido explícitamente. `.sync` sustituye al polling |
| `send-apply-command` | Su único trabajo era construir el `SSM SendCommand`. `startBuild.sync` lo hace directo |
| `send-destroy-command` | Ídem |

También `core/ssm_facade.py` y `core/cli.py`, que solo usaban esas cuatro.

> Las dos últimas no estaban en la lista original del encargo. Se eliminan porque, al invocar
> CodeBuild directamente desde Step Functions, se quedaban sin función alguna.

**Resultado: 104 → 54 recursos** en el template.

### 3.2 Qué se añadió

- `TerraformRunnerProject` — proyecto CodeBuild `NO_SOURCE` con buildspec inline.
- `TerraformRunnerLogGroup` — retención 30 días.
- `TerraformCodeBuildRole` — hereda las responsabilidades del antiguo rol del ASG:
  leer/escribir el state en S3 + KMS, y `sts:AssumeRole` sobre el Launch Role.
- Parámetros `TerraformRunnerComputeType`, `TerraformRunnerTimeoutInMinutes`, `TerraformRunnerConcurrentBuildLimit`.
- Sección `Outputs` con `CodeBuildServiceRoleArn` (pedido explícitamente), `CodeBuildProjectName`,
  `ParameterParserRoleArn`, `TerraformStateBucketName` y los ARN de ambas state machines.

**Sin `VpcConfig`** en ninguna Lambda ni en CodeBuild, tal y como se pidió.

`TerraformCliVersion` pasa de `1.2.8` a **`1.5.7`** (última release con licencia MPL, y alineada
con el `1.5.4` por defecto del motor de la Demo 2).

### 3.3 Step Functions

`Generate Tracer Tag → Select worker host → Send apply command → Wait → Poll → Choice → Get state file outputs`

pasa a ser

`Generate Tracer Tag → Run Terraform apply (codebuild:startBuild.sync) → Get state file outputs`

Los parámetros viajan como `EnvironmentVariablesOverride`, usando los intrínsecos
`States.Format` y `States.JsonToString`. El error de un build se captura con
`Catch: States.ALL → Convert error structure`, que mantiene `isWrapperError: true` para
**no romper el contrato con Service Catalog**: el fallo de Terraform se notifica como fallo del
producto, pero la state machine termina en `Succeeded` porque la notificación sí funcionó.

Grafo validado: 0 destinos rotos, 0 estados inalcanzables, y las substituciones `${...}` del JSON
coinciden exactamente con las declaradas en `DefinitionSubstitutions`.

### 3.4 El buildspec reproduce los overrides — verificado, no asumido

Se reescribió `terraform_runner` (Python) como bash + `jq` dentro del buildspec. Para comprobar
que la equivalencia es real, se ejecutaron **ambas implementaciones con los mismos inputs** y se
compararon las salidas:

```
backend_override.tf.json  : IDÉNTICO
provider_override.tf.json : IDÉNTICO
variable_override.tf.json : IDÉNTICO
```

Incluye el caso borde de `write_variable_override`: un parámetro cuyo valor es JSON anidado se
decodifica (`fromjson? // .value` en jq ≡ `json.loads` con fallback a string en Python).

### 3.5 Bugs heredados del upstream que hubo que corregir

| # | Problema | Efecto | Fix |
|---|---|---|---|
| 1 | `GOARACH=amd64` (typo de `GOARCH`) en `build-ExternalParameterParser` | En un Mac ARM compilaba la Lambda para **aarch64** mientras el template declara `x86_64` → "exec format error" en runtime | Corregido el typo. Verificado con `file`: ambos binarios ahora `x86-64` |
| 2 | 3 × `!ImportValue TerraformEngineBootstrapBucketArn` en policies marcadas "temporary" | El changeset fallaba con `AWS::EarlyValidation::ResourceExistenceCheck`: ese export no existe. Servía para alojar el wheel de `terraform_runner`, innecesario con CodeBuild | Bloques de policy eliminados |
| 3 | `AWSLambdaVPCAccessExecutionRole` en 6 roles | Sin VPC ya no aplica | → `AWSLambdaBasicExecutionRole`, deduplicando las listas |
| 4 | `AccessControl: Private` + 2 `DependsOn` redundantes | Warnings de lint heredados | Corregidos |

### 3.6 Limpieza de la carpeta de Lambdas

Se eliminaron paquetes vendorizados (`boto3/`, `botocore/`, `urllib3/`, `dateutil/`, `jmespath/`,
`s3transfer/`, `bin/`) que había dejado un `pip install -t` local y que **no estaban versionados**.
SAM los reinstala desde `requirements.txt`; dejarlos habría empaquetado un boto3 antiguo duplicado.

Backup previo en el scratchpad. **Verificación posterior: 49/49 tests unitarios pasan**
(42 en `state_machine_lambdas`, 7 en `provisioning-operations-handler`).

### 3.7 Contrato con Service Catalog: intacto

Sin cambios en las 3 colas SQS, el formato de mensajes, `DescribeProvisioningParameters`,
`Notify*EngineWorkflowResult`, la lógica de los handlers SQS ni el Parameter Parser en Go.

---

## 4. Comandos ejecutados

```bash
# Verificación
aws sts get-caller-identity
gh auth status
curl -H "Authorization: Bearer $TFE_TOKEN" https://app.terraform.io/api/v2/account/details

# Demo 1 — motor
cd demo1-terraform-os-engine/engine
sam validate --region us-east-1 --lint      # -> valid SAM Template
sam build                                    # -> Build Succeeded
sam deploy                                   # stack aurex-demo1-terraform-engine

# Tests
pytest lambda-functions/state_machine_lambdas          # 42 passed
pytest lambda-functions/provisioning-operations-handler # 7 passed

# Módulo
cd demo1-terraform-os-engine/catalog-modules/standard-environment
terraform fmt -check -recursive && terraform init -backend=false && terraform validate
```
