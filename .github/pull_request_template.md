## Que cambia

<!-- Una frase. Que hace distinto el sistema despues de este PR. -->

## Por que

<!-- El problema, no la solucion. Si viene de un issue, enlazalo: Closes #N -->

## Alcance

- [ ] Modulos (`modules/`)
- [ ] Hands-on (`hands-on/`)
- [ ] Politicas de organizacion (`policies/`)
- [ ] Pipeline / CI
- [ ] Solo documentacion

## Comprobaciones

- [ ] `terraform fmt -check -recursive` pasa
- [ ] `terraform validate` pasa en los directorios afectados
- [ ] Tests de las Lambdas afectadas en verde (`go test ./...` / `pytest`)
- [ ] Si toca `policies/`: hay un caso que la regla nueva **rechaza** y otro que **acepta**

## Impacto en el catalogo

<!-- Marca lo que aplique y explicalo. Un cambio en un modulo publicado crea una
     version nueva del producto en Service Catalog: no es un cambio interno. -->

- [ ] Publica una version nueva de un producto de Service Catalog
- [ ] Cambia permisos IAM (rol de lanzamiento, rol de CodeBuild, rol del motor)
- [ ] Cambia la superficie de red o el cifrado del modulo `standard-environment`
- [ ] Nada de lo anterior

## Notas para quien revise

<!-- Lo que no se ve en el diff: por que se descarto otra opcion, que queda
     pendiente, que hay que mirar con lupa. -->
