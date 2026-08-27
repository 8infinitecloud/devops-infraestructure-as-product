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

## Codigo de terceros

Los directorios `modules/terraform-os-engine/` y `modules/hcp-terraform-engine/`
derivan de los motores de referencia de AWS y de HashiCorp (ver NOTICE). Si el
fallo es del motor original y no de la adaptacion, reportalo tambien aguas
arriba: es donde se arregla para todo el mundo.

## Que NO hay aqui

Este repo no tiene despliegue en produccion ni proceso de release. No hay
versiones soportadas: se trabaja sobre `main`.
