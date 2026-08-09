# Cheo — el hijo de Tumbao

Agente de feedback para tumbaobaila.com. Vive como burbuja en la página y
tiene página propia con link directo. Recibe **texto, notas de voz y fotos**,
conversa como una persona —mensajitos cortos, no párrafos—, saca el contexto
que hay detrás de cada queja, y **cada lunes a las 7am manda un reporte
consolidado** a `bailatumbao@gmail.com`.

Todo está funcionando y probado en producción. Falta **un solo paso** de tu
lado: subir dos archivos y pegar una línea. Está abajo.

---

## Lo único que falta hacer

1. Sube estos dos archivos a tumbaobaila.com, donde vive el `index.html`:
   - `web/cheo.js`
   - `web/cheo.html`

2. En el `index.html` de tumbaobaila.com, antes de `</body>`, pega:

   ```html
   <script src="/cheo.js" defer></script>
   ```

Con eso aparece la burbuja abajo a la derecha. No hay que instalar nada más:
`cheo.js` no tiene dependencias, no necesita build, y habla directo con n8n.

**El link directo de Cheo** (el que comparte el bot de WhatsApp) queda en
`https://tumbaobaila.com/cheo.html`.

### Texto sugerido para el bot de WhatsApp

> ¡Claro que sí! Te dejo el link de Cheo para que nos cuentes con calma:
> https://tumbaobaila.com/cheo.html
> Él lee todo y se lo pasa al equipo.

---

## Cómo funciona, en una foto

```
Burbuja / página  ──POST /tumbao/cheo──────────►  n8n  ──►  Supabase (historial)
                                                    │
                                                    └──►  OpenAI (responde como Cheo)

cada 30 min   ──►  clasifica las conversaciones que se enfriaron
lunes 7am     ──►  consolida la semana ──► correo a bailatumbao@gmail.com
```

La memoria de la conversación vive en Supabase, no en n8n. Por eso una
persona puede volver días después y Cheo retoma donde quedaron.

---

## Las piezas

### Supabase (`sql/01_cheo.sql`)

Proyecto `tumbao-reservas` (`fobpccreihcylpsullhu`). Tres tablas nuevas,
aditivas: **no toca** clases, reservas, pagos, membresías, asistencias ni caja.

| Tabla | Qué guarda |
|---|---|
| `cheo_conversaciones` | Una fila por charla, más su clasificación (tipo, tema, urgencia, acción sugerida) |
| `cheo_mensajes` | Cada turno, en orden |
| `cheo_reportes` | Un reporte por semana, con el HTML que se envió |

RLS prendido y sin políticas, igual que el resto del esquema: solo entra
`service_role` desde n8n. **La página nunca habla con Supabase**, así que la
llave nunca sale del servidor.

### n8n

| Workflow | Qué hace |
|---|---|
| [`Tumbao · Cheo (chat)`](https://barragan.app.n8n.cloud/workflow/ivsapLSekRV9sFv8) | Los tres webhooks que consume la página |
| [`Tumbao · Cheo (insights)`](https://barragan.app.n8n.cloud/workflow/YcOzbznaDK2sx5qF) | Clasifica cada 30 min y manda el reporte los lunes |
| [`Tumbao · Cheo (voz y fotos)`](https://barragan.app.n8n.cloud/workflow/rxSWOKCPlASpl1bM) | Transcribe notas de voz y mira fotos |
| [`Tumbao · Cheo (vista previa)`](https://barragan.app.n8n.cloud/workflow/yp8ANcYd2ioJ542k) | URL para probar sin tocar el sitio real |

Ambos con el workflow de avisos de fallo enganchado y `timezone`
`America/Bogota`, así que la hora del cron es literal.

**Endpoints:**

```
POST /tumbao/cheo            { sesion_id, mensaje, medio }  ó  { sesion_id, saludo: true }
                             -> { mensajes: [...] }  varios globos cortos
POST /tumbao/cheo/historial  { sesion_id }        -> lo ya dicho, sin llamar al modelo
POST /tumbao/cheo/contacto   { sesion_id, nombre, telefono, habeas }
POST /tumbao/cheo/voz        { audio: dataURL }   -> { texto }
POST /tumbao/cheo/foto       { imagen: dataURL }  -> { descripcion }
```

`medio` es `texto`, `voz` o `foto`, y queda guardado en cada mensaje. Sirve para
saber si la gente prefiere hablar a escribir: sale contado en el reporte semanal.

Base: `https://barragan.app.n8n.cloud/webhook`

### Web (`web/`)

- `cheo.js` — un archivo, sin dependencias. Sirve para la burbuja y para la
  página propia (`data-modo="pagina"`).
- `cheo.html` — la página de Cheo, la del link directo.
- `demo.html` — página de prueba local para ver cómo queda la burbuja encima
  de un sitio.

Para probar en local: `cd web && python3 -m http.server 8765` y abre
`http://localhost:8765/demo.html`.

**Personalización sin tocar código**, con atributos en el `<script>`:

```html
<script src="/cheo.js"
        data-acento="#c2410c"
        data-api="https://barragan.app.n8n.cloud/webhook"
        data-voz="0"
        data-foto="0"
        defer></script>
```

`data-voz="0"` o `data-foto="0"` esconden esos botones. El micrófono además se
esconde solo si el navegador no sabe grabar o la página no está en HTTPS.

También puedes abrirlo desde un botón propio: `<button onclick="Cheo.abrir()">`.

---

## Decisiones que vale la pena conocer

**La llamada al modelo se hace al abrir la burbuja, no al cargar la página.**
Si fuera al cargar, cada visita a tumbaobaila.com costaría plata aunque nadie
pensara escribir.

**Reabrir la burbuja es gratis.** El endpoint de historial no llama al modelo:
devuelve lo que ya se dijo y la persona ve dónde quedó, en vez de una pantalla
en blanco que la obliga a repetir su queja.

**Si OpenAI se cae, la conversación no se pierde.** El turno se guarda igual y
Cheo responde algo humano. Perder lo que la persona escribió es el único fallo
que de verdad duele.

**Se clasifica cuando la charla se enfría (20 min), no en vivo.** En mitad de
la conversación todavía no se sabe de qué iba, y clasificar cada turno costaría
una llamada por mensaje en vez de una por conversación.

**Si una semana no hubo conversaciones, no se le pide al modelo que analice una
lista vacía.** Llega un correo corto diciendo que no hubo. Pedirle conclusiones
a cero datos es la forma más rápida de llenar el reporte de cosas que nadie dijo.

**El reporte usa `gpt-4o`; todo lo demás usa `gpt-4o-mini`.** Es una llamada por
semana y es la que de verdad hay que leer.

**Cheo declara que es una IA en su primer mensaje**, y la página lo repite abajo.
No se pide nombre ni teléfono de entrada: solo después de conversar, y opcional.

**Tope de 120 mensajes por conversación.** Lo aplica Postgres, no el front. Es
contra bucles y bots, no contra gente que hable mucho.

**Cheo manda varios mensajitos cortos, no párrafos.** Aparecen uno por uno con
la pausa que tomaría escribirlos. Ver un bloque de texto aparecer de golpe es lo
que más delata a un bot; el promedio quedó en ~110 caracteres por mensaje.

**La transcripción se muestra antes de guardarla.** La nota de voz va a un
endpoint aparte que devuelve el texto, se pinta en el chat, y solo entonces se
manda. Si Whisper entendió mal, la persona lo ve y lo corrige. Meterlo todo en
un solo paso habría escondido ese error.

**Whisper alucina con el silencio.** Con audio sin voz no devuelve vacío:
devuelve frases de subtítulos de YouTube que se aprendió de memoria. Hay un
filtro para eso, porque si no Cheo le respondería a algo que nadie dijo y eso
terminaría en el reporte del lunes.

**Las fotos NO se guardan.** Se miran, se saca una frase de lo que hay, y se
sueltan. Lo que queda en la base es la frase. Misma decisión que con los
comprobantes de pago. Si algún día se quieren guardar, hay que abrir un bucket
en Supabase y decidir cuánto tiempo se conservan — es una decisión de
privacidad, no técnica.

**A Cheo se le prohibieron las groserías explícitamente.** Pedirle "colombiano
natural" lo llevó a soltar un *qué chimba* en pruebas. Le escribe a clientes,
no a amigos.

---

## Costo aproximado

Con `gpt-4o-mini` a los precios actuales, una conversación de 6 turnos cuesta
del orden de centavos de dólar. El reporte semanal con `gpt-4o` es una sola
llamada. Con volumen de escuela de baile, esto es dólares al mes, no cientos.

Lo que sí conviene vigilar: si la burbuja se vuelve muy popular, el tope real
lo pone el número de conversaciones abiertas, no los mensajes.

---

## Qué se probó

- Chat completo contra el endpoint real, ida y vuelta, con persistencia verificada en Supabase.
- Burbuja manejada con un navegador real (Playwright): abrir, conversar, dejar
  contacto, cerrar con Escape, recargar y retomar el historial, móvil 390px,
  modo oscuro, y la página propia. 18 comprobaciones, sin errores de JS.
- Clasificación de 5 conversaciones sembradas: el reclamo salió urgencia 5, y
  detectó bien elogio, duda y sugerencia.
- Reporte semanal completo: consolidó, guardó en `cheo_reportes` y **envió el
  correo de verdad**.
- Caminos de degradación: modelo caído, semana sin conversaciones, sesión
  inexistente y sin conexión.

Los datos de prueba se borraron después. Las tablas quedaron en cero para que
el primer reporte real salga limpio.

---

## Ideas para después (no están hechas)

- Panel de admin para leer las conversaciones sin entrar a Supabase.
- Que Cheo consulte horarios y cupos reales (ya existen los webhooks
  `/tumbao/clases`) para responder dudas concretas en vez de remitir a WhatsApp.
- Avisar por WhatsApp cuando entre algo de urgencia 5, sin esperar al lunes.
- Que el bot de WhatsApp pase el `sesion_id` en el link, para que la
  conversación de WhatsApp y la de Cheo sean la misma.

---

## Probarlo sin tocar tumbaobaila.com

Hay una URL de vista previa servida por el propio n8n
([`Tumbao · Cheo (vista previa)`](https://barragan.app.n8n.cloud/workflow/yp8ANcYd2ioJ542k)):

- Página propia: `https://barragan.app.n8n.cloud/webhook/tumbao/cheo/probar`
- Burbuja sobre una página: `https://barragan.app.n8n.cloud/webhook/tumbao/cheo/probar?burbuja=1`

Habla con el Cheo real y guarda en las tablas reales, así que lo que escribas
ahí va a salir en el reporte del lunes. Para pruebas está bien; si no quieres
que aparezca, borra la conversación de `cheo_conversaciones`.

El HTML lo arma n8n y el `cheo.js` se trae de jsDelivr apuntando a un commit
fijo de este repo. **Ojo: la vista previa queda congelada en ese commit.** Si
cambias `cheo.js`, hay que actualizar el SHA de la constante `CDN` en ese
workflow para verlo reflejado.

Cuando ya subas los archivos al sitio real, ese workflow se puede desactivar:
la página real no lo usa.
