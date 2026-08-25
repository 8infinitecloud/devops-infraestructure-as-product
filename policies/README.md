# Políticas de organización (OPA / Conftest)

Aquí van las reglas que **ninguna herramienta trae de serie** porque son tuyas: qué etiquetas
son obligatorias, qué CIDR están prohibidos, qué debe documentar un módulo para entrar al
catálogo.

Checkov y TFLint cubren lo genérico (misconfiguraciones conocidas, sintaxis, argumentos
deprecados). Esto cubre lo específico de Aurex.

## Cómo se evalúan

En la etapa `Inspect` de la pipeline, contra los `.tf` del módulo:

```bash
conftest test --parser hcl2 --combine --policy policies/ modules/standard-environment/*.tf
```

Se parsea el HCL directamente porque en el momento de publicar **todavía no hay un
`terraform plan`**: el producto aún no se ha aprovisionado. Eso limita lo que se puede
comprobar a lo estructural — lo que está escrito en el código, no lo que resultaría de
aplicarlo.

Para reglas que necesiten valores resueltos (el CIDR real, el número de instancias), el
sitio correcto es el runner, sobre el `terraform plan -json` de cada aprovisionamiento.

## Severidades

- `deny`  — el hallazgo se reporta como fallo de política.
- `warn`  — se reporta como aviso.

Hoy la etapa es **advisory**: ni `deny` ni `warn` frenan la pipeline, solo se publican en el
reporte. Quien decide es la aprobación manual previa a `Publish`.

## Por qué `--combine`

Sin `--combine`, conftest evalúa **cada `.tf` por separado**. Una regla de módulo como
"debe declarar outputs" fallaría al mirar `variables.tf`, que obviamente no los tiene.
Con `--combine` el input pasa a ser una lista de `{path, contents}` con todos los archivos,
y las reglas ven el módulo completo. `policies/lib.rego` agrega esa lista.

## Probar los cambios

Las políticas se prueban contra dos fixtures: el módulo real (debe pasar limpio) y uno
deliberadamente malo (deben dispararse todas las reglas). Una política que aprueba todo no
sirve de nada:

```bash
conftest test --parser hcl2 --combine --policy policies/ --all-namespaces modules/standard-environment/*.tf
# -> 11 tests, 11 passed
```
