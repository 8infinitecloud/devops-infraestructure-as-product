# Contribuir

## Antes de abrir un PR

Lo que el CI comprueba, en el mismo orden en que falla:

```bash
# 1. Formato — sobre TODO el repo, no solo lo que tocaste
terraform fmt -check -recursive

# 2. Validacion — en cada directorio afectado
terraform -chdir=products/standard-environment init -backend=false
terraform -chdir=products/standard-environment validate

# 3. Tests
terraform test    # en products/<producto>/  (requiere Terraform >= 1.7)

# 4. Tests de las Lambdas afectadas
cd hands-on/01-terraform-os/modules/engine/lambda-functions/terraform_open_source_parameter_parser && go test ./...
cd hands-on/01-terraform-os/modules/engine/lambda-functions && python -m pytest -q
```

La etapa `Inspect` (Checkov, TFLint, Gitleaks, Conftest) es **advisory**: informa
pero no bloquea, ni aqui ni en CodePipeline. Eso es deliberado — quien decide
sobre un hallazgo es una persona en la aprobacion manual, no la herramienta. Lee
los reportes igualmente.

## Estructura

El hands-on lleva sus modulos dentro, en `hands-on/01-terraform-os/modules/`.
`products/` es lo que la plataforma sirve y se mantiene aparte: un producto no
sabe como se ejecuta por debajo.

Un modulo no configura providers ni backend: eso vive en el `main.tf` del
hands-on. Si un cambio te obliga a declarar un `provider` dentro de un modulo,
casi seguro va en el sitio equivocado.


## Codigo de terceros

`hands-on/01-terraform-os/modules/engine/` deriva del motor de referencia de AWS
y conserva su licencia Apache 2.0 (ver NOTICE).

- Toca lo minimo. Un diff pequeno contra el original es lo que permite adoptar
  mejoras de aguas arriba mas adelante.

## Politicas

Una regla nueva en `policies/` sin un caso que la dispare no vale. En el PR,
ensena el `.tf` que la regla **rechaza** y el que **acepta**:

```bash
conftest test --parser hcl2 --combine --all-namespaces \
  --policy policies products/standard-environment/*.tf
```

## Commits

Mensajes en castellano, en indicativo, describiendo el efecto y no el fichero
tocado. El historial del repo es el ejemplo: "Dos permisos que faltaban para la
etapa Inspect, encontrados desplegando" dice mas que "fix iam".

## Secretos

Nunca commitees `.tfvars` con credenciales ni claves de API. `.gitignore` cubre los patrones habituales y Gitleaks pasa por el repo
entero en cada PR, pero ninguna de las dos cosas es una red de seguridad de la
que fiarse.
