# Infrastructure as a Product

Un catálogo de infraestructura autoservicio sobre **AWS Service Catalog**, con Terraform
como motor de aprovisionamiento.

Un equipo pide un entorno desde la consola de AWS, rellena cuatro campos y lo obtiene.
Sin tener permisos sobre EC2 ni S3, sin escribir Terraform, y sin esperar a que alguien
del equipo de plataforma le atienda.

![Arquitectura](docs/arquitectura.png)

Dos recorridos independientes sobre las mismas piezas:

**Publicar** — un `git push` al módulo dispara CodePipeline vía CodeConnections. Valida,
empaqueta el `.tar.gz`, lo sube a S3 y registra una versión nueva del producto en el
catálogo.

**Aprovisionar** — el usuario abre el asistente. Service Catalog invoca al *parameter
parser* en Go, que descarga el artefacto y saca los campos del formulario de las `variable`
del módulo. Al pulsar Launch, escribe en la cola SQS que corresponda —provision, update o
terminate— y una Step Function orquesta el `terraform apply` en CodeBuild, con el state en
su propio bucket. Al terminar, notifica el resultado y el tracer tag de vuelta.

```
        terraform init  →  plan -out  →  Infracost  →  apply tfplan
                                            │
                                    ¿supera el tope?
                                    aborta antes de crear nada
```

## Qué hay aquí

```
hands-on/01-terraform-os/     LA PLATAFORMA
  main.tf                     compone los cuatro módulos
  modules/
    engine/                   motor: SQS, Lambdas, Step Functions, CodeBuild
    catalog-bootstrap/        Portfolio, quién accede y con qué rol se aprovisiona
    catalog-shared/           bucket de artefactos + conexión a GitHub
    catalog-pipeline/         CodePipeline — UNA para todo el catálogo

products/                     LO QUE LA PLATAFORMA SIRVE
  standard-environment/       red, almacenamiento y rol de acceso
  data-lake/                  S3 por zonas, catálogo de Glue y Athena

policies/                     políticas de organización que evalúa la pipeline
scripts/bootstrap.sh          despliegue en un comando
```

La separación entre `hands-on/` y `products/` es el asunto del taller. Todo lo primero es
**cómo** se aprovisiona; lo segundo es **qué** se entrega. Un equipo consume lo segundo sin
saber nada de lo primero.

## Desplegar

> **¿Primera vez?** La [guía paso a paso](docs/paso-a-paso.md) recorre todo el ciclo —desde el
> fork hasta aprovisionar un entorno y limpiar— con los tiempos y las salidas reales de cada
> etapa. Unos 25 minutos.

Requiere credenciales de AWS. Todo lo demás lo resuelve el script.

```bash
./scripts/bootstrap.sh 01
```

Comprueba las herramientas e instala las que falten, empaqueta las Lambdas, **verifica la
arquitectura del binario Go** y aplica. Unos 4 minutos, 107 recursos.

Pensado para **AWS CloudShell**, donde las credenciales ya están puestas:

```bash
git clone https://github.com/8infinitecloud/devops-infraestructure-as-product.git
cd devops-infraestructure-as-product
./scripts/bootstrap.sh 01
```

> No hay `curl … | bash` a propósito. Este repo predica en `buildspec/inspect.yml` que una
> pipeline que audita seguridad no debería ejecutar scripts de una rama móvil.

```bash
./scripts/bootstrap.sh 01 plan      # ver qué haría
./scripts/bootstrap.sh 01 destroy   # desmontar, con confirmación
```

La primera vez crea `terraform.tfvars` desde el ejemplo y te para para que lo rellenes.

### Desde GitHub Actions

Actions → **Desplegar en AWS**. Acepta OIDC (variable `AWS_DEPLOY_ROLE_ARN`) o claves
(secrets `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`), y detecta cuál usar. El bucket del
state y la tabla de bloqueo los crea el propio workflow.

### El paso que no se puede automatizar

**La autorización de CodeConnections.** Terraform crea la conexión en estado `PENDING` y el
handshake OAuth no tiene API: hay que completarlo a mano, una vez.

> Consola → CodePipeline → Settings → Connections → *Update pending connection*

El script te avisa al terminar si queda pendiente. Por eso existe `existing_connection_arn`:
una vez autorizada, se reutiliza.

## Añadir un producto

El catálogo son **datos**. Una entrada en el mapa y una carpeta:

```hcl
productos = {
  standard-environment = { nombre = "Standard Environment", ruta = "products/standard-environment", ... }

  data-lake = {                                    # ← el producto nuevo
    nombre      = "Data Lake"
    ruta        = "products/data-lake"
    descripcion = "S3 por zonas, catálogo de Glue y Athena."
  }
}
```

`terraform apply` y ya. **No se crea infraestructura**: hay una sola pipeline para todo el
catálogo y el mapa le llega como variable de entorno. Verificado con un plan — 107 recursos
con un producto, 107 con dos.

| Campo | Para qué | Cuidado |
|---|---|---|
| **clave** | Identificador interno; nombra el `.tar.gz` | — |
| `nombre` | Cómo se ve en Service Catalog | Es la clave con la que Publish lo busca: cambiarlo crea uno **nuevo** en vez de versionar |
| `ruta` | Dónde viven los `.tf` | Acaban en la **raíz** del `.tar.gz`; lo exige el parameter parser |

> **Una pipeline para todos tiene un precio:** si la validación de un producto falla, no se
> publica ninguno. Por eso `Validate` no se corta en el primer error — recorre el catálogo
> entero y lista todo lo roto. `Publish` sí continúa, porque un error transitorio de la API
> en el producto 3 no debe dejar sin publicar al 4.

### Antes de añadir uno: mira el Launch Role

Es el error más caro, porque aparece al final. El Launch Role está acotado a lo que
necesitan los productos actuales. Uno que cree RDS o EKS **pasa validate, pasa publish, y
falla al aprovisionar** — con el usuario ya delante del asistente.

Se amplía en `data.aws_iam_policy_document.launch_role_permissions`, en
`hands-on/01-terraform-os/modules/catalog-bootstrap/main.tf`.

## Gobierno del catálogo

Dos puertas, en momentos distintos, y la distinción importa:

| | Cuándo | Qué evalúa | ¿Bloquea? |
|---|---|---|---|
| **Pipeline — `Inspect`** | Al **publicar** | Checkov, TFLint, Gitleaks, Conftest sobre el HCL | No |
| **Runner — Infracost** | Al **aprovisionar** | El `plan` real, con los parámetros del usuario | **Sí** |

Al publicar todavía no hay `plan` posible: el producto no se ha aprovisionado y nadie ha
elegido parámetros. Solo se puede revisar lo estructural. El coste real solo se conoce en el
runner.

Por eso `Inspect` es **advisory** — informa, y decide una persona en la aprobación manual.

### La puerta de coste

```hcl
infracost_max_monthly_usd = "50"      # "0" = solo informa
```

El runner hace `plan -out=tfplan`, estima sobre ese plan, y si supera el tope **aborta antes
de crear nada**. Luego aplica exactamente el plan que estimó.

**Es fail-open a propósito.** Si hay límite pero la estimación falla —Infracost caído, key
inválida—, continúa. La alternativa convertiría una caída de Infracost en una caída del
catálogo entero. El coste es que la puerta se puede eludir rompiendo la herramienta, y por
eso el aviso es ruidoso en el log.

Requiere una API key gratuita en Secrets Manager, con formato `{"api_key":"ico-..."}`:

```hcl
infracost_api_key_secret_arn = "arn:aws:secretsmanager:...:secret:aurex/infracost-XXXXXX"
```

La clave **no pasa por el state**: CodeBuild la resuelve en ejecución.

### Versiones fijadas a propósito

Las herramientas de `Inspect` se instalan desde tarballs de release **con versión fijada**,
no con `curl | sh` de un script en `master`. Una pipeline que audita seguridad no debería
introducir el riesgo de cadena de suministro que se supone que detecta.

## Cuándo el catálogo tiene sentido

No siempre. Merece la pena cuando:

- Tus consumidores **viven en la consola de AWS** y no van a usar otra herramienta
- Necesitas que **no tengan permisos**: el Launch Role aprovisiona por ellos
- Tienes **multicuenta** con Organizations, o ya usas Service Catalog para CloudFormation

Si tu gente ya escribe Terraform y tiene acceso a una plataforma que ofrece formularios
sobre módulos, el catálogo añade una capa sin darte nada.

## Limpieza

Siempre en orden inverso, y **terminando antes los productos aprovisionados** — si se
destruye el motor primero, no queda nada capaz de ejecutar su `destroy`:

```bash
aws servicecatalog terminate-provisioned-product --provisioned-product-id <pp-...>
./scripts/bootstrap.sh 01 destroy
```

El producto de Service Catalog lo crea la pipeline por CLI, no Terraform, así que hay que
borrarlo aparte: constraint → desasociar → `delete-product`.

## Multicuenta

Los módulos están escritos para que hub-and-spoke sea un cambio en la composición, no un
rewrite. **No está probado end-to-end.** Tres restricciones documentadas por AWS:

1. **Un solo motor `EXTERNAL` por cuenta hub.** No se puede rodear.
2. **El Launch Role debe existir en cada spoke con el mismo nombre**, y el constraint debe
   usar `LocalRoleName` en vez de `RoleArn`.

   > ⚠️ `catalog-pipeline/buildspec/publish.yml` publica hoy `{"RoleArn": ...}`. Vale para
   > monocuenta; para hub-and-spoke hay que cambiarlo.
3. **Los nombres de Launch Role deben empezar por `SCLaunch`.** Los de este repo no lo
   cumplen: funciona en monocuenta porque el `iam:PassRole` se concede explícitamente.

Lo que ya juega a favor: el runner puede asumir roles en cualquier cuenta
(`arn:aws:iam::*:role/*`), y la clave del state ya empieza por la cuenta del usuario que
lanzó, así que los states quedan separados por spoke sin tocar nada.

## Contribuir y licencia

Ver [CONTRIBUTING.md](CONTRIBUTING.md) y [SECURITY.md](SECURITY.md).

Código propio bajo **Apache 2.0** ([LICENSE](LICENSE)).
`hands-on/01-terraform-os/modules/engine/` deriva del Terraform Reference Engine de AWS y
conserva su licencia Apache 2.0 — detalle en [NOTICE](NOTICE).
