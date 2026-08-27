# Contribuir

## Antes de abrir un PR

Lo que el CI comprueba, en el mismo orden en que falla:

```bash
# 1. Formato — sobre TODO el repo, no solo lo que tocaste
terraform fmt -check -recursive

# 2. Validacion — en cada directorio afectado
terraform -chdir=modules/standard-environment init -backend=false
terraform -chdir=modules/standard-environment validate

# 3. Tests de las Lambdas afectadas
cd modules/hcp-terraform-engine/engine/lambda-functions && go test ./...
cd modules/terraform-os-engine/lambda-functions/terraform_open_source_parameter_parser && go test ./...
cd modules/terraform-os-engine/lambda-functions && python -m pytest -q
```

La etapa `Inspect` (Checkov, TFLint, Gitleaks, Conftest) es **advisory**: informa
pero no bloquea, ni aqui ni en CodePipeline. Eso es deliberado — quien decide
sobre un hallazgo es una persona en la aprobacion manual, no la herramienta. Lee
los reportes igualmente.

## Estructura

`modules/` son piezas reutilizables; `hands-on/` las compone. Un modulo no
configura providers ni backend: eso vive en el hands-on. Si un cambio te obliga a
declarar un `provider` dentro de `modules/`, casi seguro va en el sitio
equivocado.

## Codigo de terceros

`modules/terraform-os-engine/` y `modules/hcp-terraform-engine/` derivan de los
motores de AWS y de HashiCorp y conservan sus licencias (ver NOTICE).

- Toca lo minimo. Un diff pequeno contra el original es lo que permite adoptar
  mejoras de aguas arriba mas adelante.
- `modules/hcp-terraform-engine/` es **MPL-2.0**, copyleft por fichero: lo que
  modifiques ahi sigue siendo MPL-2.0 aunque el resto del repo sea Apache-2.0.
- Explica en el PR por que el cambio no cabia fuera del codigo vendorizado.

## Politicas

Una regla nueva en `policies/` sin un caso que la dispare no vale. En el PR,
ensena el `.tf` que la regla **rechaza** y el que **acepta**:

```bash
conftest test --parser hcl2 --combine --all-namespaces \
  --policy policies modules/standard-environment/*.tf
```

## Commits

Mensajes en castellano, en indicativo, describiendo el efecto y no el fichero
tocado. El historial del repo es el ejemplo: "Dos permisos que faltaban para la
etapa Inspect, encontrados desplegando" dice mas que "fix iam".

## Secretos

Nunca commitees `.tfvars` con credenciales, tokens de HCP Terraform ni claves de
API. `.gitignore` cubre los patrones habituales y Gitleaks pasa por el repo
entero en cada PR, pero ninguna de las dos cosas es una red de seguridad de la
que fiarse.
