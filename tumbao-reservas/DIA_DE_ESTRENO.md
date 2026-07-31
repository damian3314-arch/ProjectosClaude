# Día de estreno

Qué mirar el día que entran los primeros clientes reales, qué hacer si
algo se ve raro, y qué **no** hay que tocar ese día.

Escrito el 31 de julio de 2026, con el sistema ya publicado en
`tumbaobaila.com`.

---

## 1. Las dos direcciones

| Para quién | Dirección |
|---|---|
| Clientes | https://tumbaobaila.com |
| Recepción | https://tumbaobaila.com/admin |

El panel pide el token una sola vez por navegador y lo guarda ahí. Si
recepción usa un computador distinto al tuyo, **cada uno necesita
pegarlo la primera vez**. Se emiten tokens separados con
`select crear_token_admin('recepcion');` — conviene uno por persona,
para poder revocar el de alguien sin tumbar el de los demás.

`tumbao.pages.dev` sigue viva y sirve exactamente la misma página. Si
algún día el dominio da problemas, esa dirección es el plan B inmediato.

---

## 2. Lo que pasa cuando alguien reserva

```
elige clase  ->  deja nombre y celular  ->  paga por Bre-B
                                              |
                                    sube la captura (opcional)
                                              |
                                    OCR llena hora/referencia/valor
                                              |
                          espera hasta 3 minutos mirando una barra
                                              |
              ┌───────────────────────────────┴───────────────────┐
     llegó el correo del banco                        no llegó a tiempo
     y el monto casa con una sola reserva             o casa con varias
              |                                                   |
      se confirma sola                              queda en la cola del
      (el cliente ve "Pago confirmado")             panel, y el cliente ve
                                                    "no pudimos confirmarlo
                                                     automáticamente, comparte
                                                     el soporte por WhatsApp"
```

**El cupo se aparta desde el primer clic**, no cuando se confirma el
pago. Nadie le puede quitar el puesto a alguien mientras paga.

**Que caiga en la cola no es un error.** Pasa siempre que dos personas
pagan el mismo monto en la misma ventana: el sistema no adivina, prefiere
preguntar. Se resuelve en el panel en dos clics.

---

## 3. Qué revisar durante el día

### Cada tanto, en el panel

- **Tablero** — cuántos cupos quedan por clase. Si un número se ve
  imposible, contrástalo con la lista de puerta antes de vender.
- **Reservas por confirmar** — la cola. Ojalá esté corta. Si empieza a
  crecer sin parar, es señal de que la conciliación automática dejó de
  funcionar (ver §4).
- **Lista de puerta** — al abrir la sala. Se marca quién entró.

### En el correo

`bailatumbao@gmail.com` recibe un aviso automático si la importación de
afiliados o la ingesta de pagos fallan. **Si llega un correo de "Avisos
Tumbao", léelo ese día**, no al siguiente: los dos fallos que cubre
tienen consecuencias silenciosas.

---

## 4. Si algo se ve mal

### "La página no muestra clases"

Primero comprueba si es la página o es n8n:

```
curl -s "https://barragan.app.n8n.cloud/webhook/tumbao/clases?tipo=suelta" | head -c 200
```

Si eso responde con clases, el problema es el navegador del cliente
(caché). Si no responde, el problema es n8n o Supabase.

### "Alguien pagó y no se le confirmó"

Es el caso normal descrito arriba. Búscalo en **Reservas por confirmar**
por nombre o celular, compara con el comprobante que te mandó, y
confirma. Si te equivocaste, **Deshacer** lo revierte — tienes 15
minutos y un solo uso por reserva.

### "El cupo no cuadra con la realidad"

El aforo se calcula como `30 − afiliados activos a esa hora ese día`, y
los sábados va partido 15 afiliados / 15 sueltas. Si el número está raro,
lo más probable es que la importación nocturna no corriera. Revisa el
correo por un aviso de fallo.

### "Un cliente dice que la página se quedó cargando"

El aviso del banco tarda de 1 a 2 minutos y la barra espera 3. Si el
correo llega justo después del corte, la reserva cae en la cola y
**se confirma sola** cuando el correo entre — el sistema sigue
buscándola. El cliente no pierde el cupo en ningún caso.

---

## 5. Lo que NO hay que hacer ese día

- **No aplicar migraciones de Supabase.** Ni las que estén pendientes ni
  ninguna nueva. Si algo falta, se aguanta hasta mañana.
- **No tocar los workflows de n8n.** Publicar una versión nueva mientras
  hay gente reservando es la forma más fácil de romper el día.
- **No migrar a n8n v3.** Sale en octubre de 2026, no corre prisa
  (ver `SIGUIENTE_VERSION.md`).
- **No borrar reservas ni pagos a mano en Supabase.** Si algo sobra, se
  rechaza desde el panel, que sí libera el cupo correctamente.

---

## 6. Estado verificado el 31 de julio

Lo que se probó contra producción, no de memoria:

| Prueba | Resultado |
|---|---|
| `/clases` suelta y miembro | 200, 38 clases, reparto del sábado activo |
| `/estado` con código inexistente | 404 limpio, no revienta |
| `/estado?vencido=1` | 404 limpio |
| `/comprobante` con código inexistente | 404 limpio |
| `/reservar` con celular corto | 400, no crea reserva |
| `/reservar` sin habeas data | 400, no crea reserva |
| `/reservar` con señuelo anti-bot | 200 falso, no crea reserva |
| Cupos después de las tres pruebas | sin mover |
| OCR del comprobante | lee hora, referencia, pagador y valor |
| Correo de aviso de fallo | enviado y confirmado por Gmail |
| Las seis funciones de admin | responden y rechazan token inválido |

**No se probó** el camino completo de una reserva real, porque crearla
consume un cupo de verdad. Es lo primero que conviene hacer tú, con tu
propio celular, antes de que llegue el primer cliente.

---

## 7. Un problema conocido, ya mitigado

El 28 de julio a las 21:59 un cliente real perdió una consulta de estado:

```
401 PGRST303 "JWT issued at future"
```

Es un desajuste de reloj transitorio entre n8n y Supabase. La llave está
bien; simplemente a veces el token se ve emitido "en el futuro" y
PostgREST lo rechaza.

Desde hoy, los nodos que se pueden repetir sin consecuencia reintentan
tres veces antes de darse por vencidos. **`tomar_cupo` queda sin
reintento a propósito**: no es idempotente, y repetirlo después de un
timeout crearía una segunda reserva y se comería dos cupos — que es
exactamente lo que este sistema existe para evitar. Ahí es preferible
que falle visible y la persona reintente.
