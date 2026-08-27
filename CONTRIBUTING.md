# Contribuir

## Antes de abrir un PR

Lo que el CI comprueba, en el mismo orden en que falla:

```bash
# 1. Formato — sobre TODO el repo, no solo lo que tocaste
terraform fmt -check -recursive

# 2. Validacion — en cada directorio afectado
terraform -chdir=products/standard-environment init -backend=false
terraform -chdir=products/standard-environment validate

# 3. Tests de las Lambdas afectadas
cd hands-on/02-hcp-terraform/modules/engine/engine/lambda-functions && go test ./...
cd hands-on/01-terraform-os/modules/engine/lambda-functions/terraform_open_source_parameter_parser && go test ./...
cd hands-on/01-terraform-os/modules/engine/lambda-functions && python -m pytest -q
```

La etapa `Inspect` (Checkov, TFLint, Gitleaks, Conftest) es **advisory**: informa
pero no bloquea, ni aqui ni en CodePipeline. Eso es deliberado — quien decide
sobre un hallazgo es una persona en la aprobacion manual, no la herramienta. Lee
los reportes igualmente.

## Estructura

Cada hands-on es **autosuficiente**: lleva sus modulos dentro, en
`hands-on/NN-*/modules/`, aunque se repitan entre demos. Son demos distintas y se
leen y se copian por separado.

Lo unico compartido es `products/`, y es deliberado: que el MISMO modulo lo sirvan
los dos motores es lo que el taller demuestra. Si lo duplicas, la demo deja de
demostrar nada.

Un modulo no configura providers ni backend: eso vive en el `main.tf` del
hands-on. Si un cambio te obliga a declarar un `provider` dentro de un modulo,
casi seguro va en el sitio equivocado.

Ojo con la duplicacion: `catalog-pipeline` y `catalog-shared` existen dos veces.
Un arreglo en uno casi siempre hay que llevarlo al otro.

## Codigo de terceros

`hands-on/01-terraform-os/modules/engine/` y `hands-on/02-hcp-terraform/modules/engine/` derivan de los
motores de AWS y de HashiCorp y conservan sus licencias (ver NOTICE).

- Toca lo minimo. Un diff pequeno contra el original es lo que permite adoptar
  mejoras de aguas arriba mas adelante.
- `hands-on/02-hcp-terraform/modules/engine/` es **MPL-2.0**, copyleft por fichero: lo que
  modifiques ahi sigue siendo MPL-2.0 aunque el resto del repo sea Apache-2.0.
- Explica en el PR por que el cambio no cabia fuera del codigo vendorizado.

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

Nunca commitees `.tfvars` con credenciales, tokens de HCP Terraform ni claves de
API. `.gitignore` cubre los patrones habituales y Gitleaks pasa por el repo
entero en cada PR, pero ninguna de las dos cosas es una red de seguridad de la
que fiarse.
