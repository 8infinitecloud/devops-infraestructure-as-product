# Guía paso a paso

Desde clonar el repositorio hasta ver un entorno aprovisionado y volver a dejar la cuenta
limpia.

Total: **unos 25 minutos**, de los cuales 10 son esperas.

---

## Antes de empezar

**Una cuenta de AWS con permisos de administrador.** El despliegue crea roles y políticas
IAM, así que un usuario acotado no sirve.

**Un fork del repositorio.** No basta con clonar: la pipeline lee de *tu* repositorio a
través de CodeConnections, así que necesitas uno donde puedas hacer push.

1. Abre https://github.com/8infinitecloud/devops-infraestructure-as-product y pulsa **Fork**
2. Clona el tuyo:

```bash
git clone https://github.com/TU-USUARIO/devops-infraestructure-as-product.git
cd devops-infraestructure-as-product
```

Comprueba que el remoto apunta a tu fork y no al original:

```bash
git remote -v
```

**Herramientas:** `terraform >= 1.5`, `go`, `python3`, `make`, `rsync`, `git` y la AWS CLI.

```bash
terraform version && go version && python3 --version && aws sts get-caller-identity
```

---

## 1 · Configurar — 2 min

```bash
cd hands-on/01-terraform-os
cp terraform.tfvars.example terraform.tfvars
```

Solo hay **una variable obligatoria**:

```hcl
github_repository_id = "TU-USUARIO/devops-infraestructure-as-product"
```

Recomendable rellenar también quién podrá lanzar productos, o no verás el catálogo en la
consola:

```hcl
grant_access_to_principal_arns = ["arn:aws:iam::TU-CUENTA:user/TU-USUARIO"]
```

El resto tiene valores por defecto razonables.

---

## 2 · Desplegar — 4 min

**Primero las Lambdas.** Terraform no compila nada: el `archive_file` lee `build/` en tiempo
de plan, así que si te saltas este paso el `apply` falla con una precondición.

```bash
cd hands-on/01-terraform-os/modules/engine/lambda-functions
make bin
make verify
```

`make verify` comprueba que el binario Go quedó en **x86-64**.

```
OK: x86-64, coincide con architectures del aws_lambda_function
```

**Ahora sí:**

```bash
cd ../../..
terraform init
terraform apply
```

```
Apply complete! Resources: 107 added, 0 changed, 0 destroyed.
```

Si algo falla aquí suele ser por permisos IAM. El mensaje de AWS dice qué acción falta.

> **En sucesivos `apply` verás las tres Lambdas como modificadas** aunque no hayas tocado
> código. No es un error: `make bin` regenera los `.zip` y estos incorporan marcas de tiempo,
> así que el `source_code_hash` cambia. Terraform las vuelve a subir; son unos segundos.
> Si no cambiaste ninguna Lambda, puedes saltarte `make bin` y aplicar directamente.

---

## 3 · La conexión a GitHub — en consola

**No se puede automatizar.** El handshake OAuth con GitHub no tiene API: la conexión nace
en estado `PENDING` y alguien tiene que autorizarla a mano.

> Consola → **CodePipeline** → Settings → **Connections**
>
> 1. Selecciona la conexión pendiente
> 2. *Update pending connection*
> 3. Autoriza la app **AWS Connector for GitHub** y dale acceso a tu fork
> 4. El estado pasa a **`Available`**

Copia su ARN y guárdalo en `terraform.tfvars`:

```hcl
existing_connection_arn = "arn:aws:codeconnections:us-east-1:TU-CUENTA:connection/..."
```

A partir de ahí se reutiliza y **este paso no vuelve a aparecer**. Sin él, cada `destroy` y
`apply` crearía una conexión nueva que habría que autorizar otra vez.

## 4 · La pipeline arranca sola — 6 min

Al crearse, se ejecuta una vez.

```bash
aws codepipeline get-pipeline-state --name aurex-os-catalog-pipeline \
  --query 'stageStates[].{etapa:stageName,estado:latestExecution.status}' --output table
```

Cinco etapas:

| Etapa | Qué hace | Tarda |
|---|---|---|
| `Source` | Trae el repo por CodeConnections | ~20 s |
| `BuildValidate` | `fmt`, `validate` y empaqueta cada producto | ~1 min |
| `Inspect` | Checkov, TFLint, Gitleaks, Conftest | ~3 min |
| `Approve` | **Espera a que apruebes** | — |
| `Publish` | Sube a S3 y registra el producto | ~30 s |

`Inspect` tarda porque instala las cuatro herramientas con versión fijada.

---

## 5 · Revisar y aprobar — la parte interesante

`Inspect` es **advisory**: informa, no bloquea. Quien decide eres tú. Es el momento de mirar
qué encontró:

```bash
aws logs tail /aws/codebuild/aurex-os-catalog-inspect --since 15m --format short \
  | grep -E 'Passed checks|FAILED for resource|tests,'
```

En una ejecución limpia del producto `standard-environment`:

```
Conftest   11 tests, 11 passed        ← tus políticas de organización
Gitleaks   sin secretos
Checkov    21 pasan, 7 fallan
```

Los 7 de Checkov merecen mirarse uno a uno. Dos son legítimos —VPC sin flow logs, y el
security group por defecto sin restringir—; los otros cinco son opinables para un entorno de
taller. **Esa lectura es justo lo que la puerta pide de ti.**

Para aprobar:

```bash
TOKEN=$(aws codepipeline get-pipeline-state --name aurex-os-catalog-pipeline \
  --query "stageStates[?stageName=='Approve'].actionStates[0].latestExecution.token" --output text)

aws codepipeline put-approval-result --pipeline-name aurex-os-catalog-pipeline \
  --stage-name Approve --action-name RevisarHallazgos \
  --result summary="Revisado",status=Approved --token "$TOKEN"
```

---

## 6 · Comprobar que el producto existe

```bash
aws servicecatalog search-products-as-admin \
  --portfolio-id $(terraform -chdir=hands-on/01-terraform-os output -raw portfolio_id) \
  --query 'ProductViewDetails[].ProductViewSummary.{producto:Name,tipo:Type}' --output table
```

El tipo debe ser **`EXTERNAL`**: es lo que hace que enrute a las colas del motor.

---

## 7 · Aprovisionar — 3 min

Aquí es donde el catálogo demuestra lo que vale.

> Consola → **Service Catalog** → Products → *Standard Environment* → **Launch**

Los campos del formulario **no están configurados en ninguna parte**. Los saca una Lambda en
Go leyendo los bloques `variable` del módulo. Cambia una `description` en el `.tf`, publica,
y el texto cambia en el asistente.

Mientras corre:

```bash
aws logs tail /aws/codebuild/TerraformEngineRunner --follow --format short
```

Verás `init`, `plan`, la tabla de costes de Infracost si la configuraste, y `apply`. Si el
coste supera `infracost_max_monthly_usd`, **aborta antes de crear nada**.

Al terminar, el producto queda `AVAILABLE` y sus outputs aparecen en la consola.

---

## 8 · Verificar el camino que siguió

Un solo mensaje, en una sola cola, y la DLQ vacía:

```bash
for q in Provision Update Terminate; do
  printf "%-12s " "$q"
  aws cloudwatch get-metric-statistics --namespace AWS/SQS --metric-name NumberOfMessagesSent \
    --dimensions Name=QueueName,Value=ServiceCatalogExternal${q}OperationQueue \
    --start-time "$(date -u -v-1H +%Y-%m-%dT%H:%M:%S)" --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
    --period 3600 --statistics Sum --query 'Datapoints[0].Sum' --output text
done
```

> **Si algo se queda colgado en `UNDER_CHANGE` sin logs**, mira la DLQ
> (`ServiceCatalogTerraformOSOperationsDLQ`). Es el único sitio donde queda rastro de un
> aprovisionamiento que ni siquiera llegó a arrancar.

---

## 9 · Añadir un segundo producto — 2 min

La demostración corta. En `hands-on/01-terraform-os/main.tf`:

```hcl
data-lake = {
  nombre      = "Data Lake"
  ruta        = "products/data-lake"
  descripcion = "S3 por zonas, catálogo de Glue y Athena."
}
```

```bash
terraform -chdir=hands-on/01-terraform-os apply
```

No hace falta volver a compilar: no cambió ninguna Lambda.

Ahora **haz commit y push**. El fichero que acabas de tocar está en las rutas que disparan
la pipeline, así que se publica sola:

```bash
git commit -am "Anade el producto Data Lake al catalogo" && git push
```

Si prefieres no depender del push, arráncala a mano:

```bash
aws codepipeline start-pipeline-execution --name aurex-os-catalog-pipeline
```

La pipeline recorre **los dos productos**: valida y empaqueta cada uno, los inspecciona, y
tras tu aprobación publica una versión nueva de ambos.

**Cero recursos nuevos.** Solo cambia una variable de entorno en CodeBuild — 107 recursos con
un producto y 107 con dos.

> El `data-lake` crea Glue y Athena, y **el Launch Role no los cubre**. Pasará validate,
> pasará publish, y fallará al aprovisionar. Es el fallo más caro del catálogo y aquí se ve
> en directo: hay que ampliar `launch_role_permissions` en `catalog-bootstrap`.

---

## 10 · Limpiar

**El orden importa.** Si destruyes el motor primero, no queda nada capaz de ejecutar el
`destroy` de los productos: sus recursos quedan huérfanos en la cuenta, pagando y sin nada
que los gestione.

### Primero, en la consola de Service Catalog

Esta parte es manual. Los productos aprovisionados y el producto del catálogo **no están en
Terraform**, así que `destroy` no se los lleva.

> **1. Terminar lo aprovisionado**
>
> Service Catalog → **Provisioned products** → cada uno → *Actions* → **Terminate**
>
> Espera a que desaparezcan. Es lo que dispara el `destroy` de sus recursos a través del
> motor, y por eso el motor tiene que seguir vivo.

> **2. Quitar el producto del catálogo**
>
> Service Catalog → **Portfolios** → *Aurex Standard Environments*
>
> - Pestaña **Constraints** → borra el *Launch constraint*
> - Pestaña **Products** → *Remove product* del portfolio
> - Después, Service Catalog → **Products** → borra el producto

Lo crea la pipeline con la CLI, no Terraform. Por eso hay que quitarlo aquí.

### Después, el resto

```bash
terraform -chdir=hands-on/01-terraform-os destroy
```

> **Si te saltaste el paso anterior, `destroy` falla así:**
>
> ```
> Error: deleting Service Catalog Portfolio (port-...): ResourceInUseException:
> Portfolio port-... still has associated Products
> ```
>
> No es un error de Terraform: el producto **no es suyo**, lo creó la pipeline con la CLI,
> así que no sabe que hay algo dentro del portfolio.
>
> El `destroy` se para limpio —borra todo lo demás y no deja nada a medias—, así que basta
> con desasociar el producto y repetirlo. Los IDs salen de aquí:
>
> ```bash
> PORTFOLIO=$(aws servicecatalog list-portfolios --query 'PortfolioDetails[0].Id' --output text)
> PRODUCTO=$(aws servicecatalog search-products-as-admin --portfolio-id "$PORTFOLIO" \
>              --query 'ProductViewDetails[0].ProductViewSummary.ProductId' --output text)
> CONSTRAINT=$(aws servicecatalog list-constraints-for-portfolio --portfolio-id "$PORTFOLIO" \
>              --query 'ConstraintDetails[0].ConstraintId' --output text)
>
> aws servicecatalog delete-constraint --id "$CONSTRAINT"
> aws servicecatalog disassociate-product-from-portfolio --product-id "$PRODUCTO" --portfolio-id "$PORTFOLIO"
> aws servicecatalog delete-product --id "$PRODUCTO"
> ```
>
> Y repites el `destroy`.

Queda fuera a propósito:

- **La conexión de CodeConnections** — consérvala. Volver a autorizarla es manual.
- **El secreto de Infracost**, si lo creaste.

## Qué cuesta si lo dejas puesto

Casi todo es pago por uso y sin tráfico no cobra. Lo que sí tiene coste fijo son las **dos
claves KMS del motor**, alrededor de **1 USD/mes cada una**.
