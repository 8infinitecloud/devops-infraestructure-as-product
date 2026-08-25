# Mejora pendiente: sustituir el polling de `poll-run-status` por webhooks

**Estado: NO implementada.** Se despliega con el polling tal y como viene el motor de
HashiCorp. Queda documentada aquí como mejora, según lo acordado: no bloquear el resto
del taller por esto.

## Qué hace hoy el motor

`provision_state_machine.tf` encadena:

```
Send apply  →  Wait (X s)  →  poll-run-status  →  Choice  ─┐
                  ▲                                        │  si sigue en curso
                  └────────────────────────────────────────┘
```

Cada vuelta es una invocación Lambda contra la API de HCP Terraform. Un `apply` de 10
minutos son decenas de invocaciones que casi siempre responden "sigue corriendo".

## Qué debería hacer

HCP Terraform sabe avisar por sí solo mediante **notification configurations**. El patrón:

1. La Step Function pasa a `.waitForTaskToken`: se detiene y guarda el token.
2. Al crear el workspace, el motor registra una notification configuration de tipo
   `generic` apuntando a un API Gateway propio, con un `token` compartido.
3. Cuando el run cambia de estado, HCP Terraform hace POST al API Gateway con la
   cabecera **`X-TFE-Notification-Signature`**: un **HMAC-SHA512** del cuerpo, con ese
   token como clave.
4. Una Lambda verifica la firma —comparación en tiempo constante— y, si el run llegó a
   estado terminal (`applied`, `errored`, `canceled`, `discarded`), llama a
   `SendTaskSuccess` o `SendTaskFailure` con el token guardado.

```
Send apply (.waitForTaskToken)  ⇢  [la SFN se duerme, coste cero]
                                        ▲
HCP Terraform ──POST firmado──▶ API Gateway ──▶ Lambda verifica HMAC ──┘
```

## Qué habría que tocar

| Archivo | Cambio |
|---|---|
| `engine/engine/provision_state_machine.tf` | `Send apply` pasa a `.waitForTaskToken`; fuera los estados `Wait`, `poll-run-status` y su `Choice` |
| `engine/engine/terminate_state_machine.tf`, `update_state_machine.tf` | Igual |
| `engine/engine/lambda-functions/send-apply/tfc_applier.go` | Crear la notification configuration del workspace y guardar el task token |
| **Nuevo** `engine/engine/webhook.tf` | `aws_apigatewayv2_api` + `aws_lambda_function` de recepción |
| **Nueva** `engine/engine/lambda-functions/run-webhook/` | Verificar HMAC-SHA512 y llamar a `SendTaskSuccess`/`SendTaskFailure` |
| `engine/engine/lambda-functions/poll-run-status/` | Se elimina |

## Por qué se pospuso

- Toca las **tres** state machines y la lógica en Go de `send-apply`, que el encargo pide
  no alterar más allá de lo necesario.
- Introduce un endpoint **público** en la cuenta: requiere pensar rate limiting, WAF y
  rotación del secreto de firma. Eso es trabajo de diseño, no de traducción.
- Un webhook perdido deja la Step Function colgada hasta su timeout. En producción hace
  falta un plan B (una regla de EventBridge que reconcilie runs huérfanos), y eso es
  precisamente lo que el polling da gratis.

## Cómo se validaría

1. Provisionar un producto y comprobar en la consola de Step Functions que la ejecución
   se queda en `Send apply` **sin invocaciones periódicas** de Lambda.
2. Contar invocaciones de `poll-run-status` en CloudWatch: deben ser **cero**.
3. Enviar un POST con firma inválida al API Gateway y confirmar que devuelve 403 y no
   reanuda la Step Function.
4. Comprobar que la ejecución termina con el mismo resultado que con polling.

## Referencia

- Notification configurations: https://developer.hashicorp.com/terraform/cloud-docs/api-docs/notification-configurations
- Verificación de la firma: la cabecera `X-TFE-Notification-Signature` es el HMAC-SHA512
  del cuerpo crudo, con el `token` de la notification configuration como clave.
