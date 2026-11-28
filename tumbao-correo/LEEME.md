# tumbao-correo — el buzón de pagos@tumbaobaila.com

Recibe el correo que llega a `pagos@tumbaobaila.com` y lo guarda.

## Por qué existe

n8n cobra por ejecución: 2.500 al mes. El 30 de agosto se llegó a 2.494
faltando un día para el corte, y la ingesta de pagos —leer las alertas de
Bancolombia del correo— se lleva ella sola el **56%** de ese gasto: n8n
sondea Gmail, y cada correo que encuentra es una ejecución.

La idea es darle la vuelta. En vez de ir a buscar el correo, que el
correo llegue solo:

```
Bancolombia -> bailatumbao@gmail.com -> (filtro de Gmail reenvía)
            -> pagos@tumbaobaila.com -> Cloudflare -> este Worker
```

Cloudflare Email Routing no cobra por correo recibido.

## En qué va

**Paso 1 — hecho.** Recibir y guardar. Sirve para leer el código con el
que Gmail confirma la dirección de reenvío; sin ese código no se puede
terminar de configurar el otro lado.

**Paso 2 — pendiente, para el 1 de septiembre.** Parsear la alerta y
llamar a `registrar_pago_y_conciliar()` en Supabase, que es lo que hoy
hace el nodo "Registrar y conciliar" del workflow `Tumbao · Ingesta de
pagos`. El parser ya existe, está probado y es JavaScript puro sin nada
de n8n dentro: vive en el nodo "Parsear correo" y se mueve tal cual.

Se deja para el día 1 a propósito: ese día la cuota se renueva, así que
si algo sale mal hay 2.500 ejecuciones de red de seguridad en vez de
cero.

## Por qué un Worker aparte y no dentro de tumbao-caja

`tumbao-caja` es lo que mantiene viva la página: horarios, reservas,
comprobantes. Meterle un manejador de correo nuevo y a medio probar
arriesga lo único que no se puede caer. Cuando esto esté rodado se pueden
juntar; hoy no.

## Lo que se guarda

Alertas del banco: montos, quién paga y los últimos cuatro dígitos de la
cuenta. **Caduca a los 7 días y se borra solo** — eso no puede quedarse
en un KV para siempre. De sobra para depurar.

## Leer lo que llegó

```
GET https://tumbao-correo.damian3314.workers.dev/ultimos?llave=…
GET .../ultimos?llave=…&solo=codigo     # solo el código de Gmail
GET .../salud                            # sin llave, no enseña nada
```

La llave va como secreto (`LLAVE_BUZON`). Sin ella contesta 401. No se
deja abierto ni "porque nadie sabe la URL": ahí dentro hay nombres de
clientes y cuánto pagó cada uno.

## Lo que hay montado del lado de Cloudflare

- Email Routing activo en la zona `tumbaobaila.com`.
- Regla: `pagos@tumbaobaila.com` → Worker `tumbao-correo`.
- Registros que añadió Cloudflare al activarlo: 3 MX, un SPF y un DKIM.
  El dominio **no tenía ningún MX antes**, así que no le quitó el correo
  a nadie.

## Si hay que volver atrás

Basta con desactivar la regla de enrutamiento y quitar el filtro de
Gmail: la ingesta por n8n sigue existiendo y no se ha tocado.
