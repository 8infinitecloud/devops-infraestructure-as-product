# Politica de seguridad

Este repositorio es material de taller: despliega infraestructura real (IAM, red,
almacenamiento) en una cuenta de AWS. Un fallo aqui se traduce en permisos o en
superficie de red en la cuenta de quien lo ejecute.

## Reportar una vulnerabilidad

**No abras un issue publico.** Usa el reporte privado de GitHub:

> [Security → Advisories → Report a vulnerability](https://github.com/8infinitecloud/devops-infraestructure-as-product/security/advisories/new)

Incluye que se puede conseguir con el fallo, como reproducirlo y sobre que
version. No hace falta una prueba de concepto armada: la descripcion del camino
es suficiente.

## Alcance

Entra dentro:

- Permisos IAM mas amplios de lo necesario en cualquier rol del repo — rol de
  lanzamiento de Service Catalog, rol de CodeBuild, roles del motor.
- Que un producto del catalogo pueda escalar privilegios sobre lo que su rol de
  lanzamiento permite.
- Secretos expuestos: en el state, en logs de CodeBuild, en variables de entorno.
- Fallos en la verificacion de firma o en la autenticacion contra HCP Terraform.
- Reglas de `policies/` que se pueden esquivar de forma trivial.

No entra:

- Hallazgos de Checkov o TFLint que **ya salen** en la etapa `Inspect` de la
  pipeline y que estan aceptados de forma consciente para el taller. Si crees
  que uno esta mal aceptado, abre un issue normal y lo discutimos.
- El coste de lo que despliegues.

## Dependencias

Dependabot esta activado **solo para avisos de seguridad**: salta cuando una
dependencia tiene un CVE, no cuando simplemente hay version nueva. Por eso no
hay `.github/dependabot.yml` en el repo — su presencia es lo que activa los
bumps rutinarios.

Es una decision, no un olvido. Casi todas las dependencias del repo estan en
`hands-on/01-terraform-os/modules/engine/` y `hands-on/02-hcp-terraform/modules/engine/`, que son codigo
vendorizado: actualizar el SDK de AWS del motor de HashiCorp por nuestra cuenta
va en contra de lo que pide CONTRIBUTING.md, porque esa decision se toma aguas
arriba. Un PR automatico al mes proponiendo justo eso es ruido que acaba
tapando el aviso que si importa.

Un CVE es otra cosa: ahi hay que actuar, y para eso siguen activos los avisos y
las actualizaciones automaticas de seguridad.

## Codigo de terceros

Los directorios `hands-on/01-terraform-os/modules/engine/` y `hands-on/02-hcp-terraform/modules/engine/`
derivan de los motores de referencia de AWS y de HashiCorp (ver NOTICE). Si el
fallo es del motor original y no de la adaptacion, reportalo tambien aguas
arriba: es donde se arregla para todo el mundo.

## Que NO hay aqui

Este repo no tiene despliegue en produccion ni proceso de release. No hay
versiones soportadas: se trabaja sobre `main`.
