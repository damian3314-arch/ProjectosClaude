# Página de Damián Barragán

Página tipo chat + backend en Cloudflare. Todo vive en Cloudflare: la página, la lógica (Worker) y la base de datos (D1).

```
Visitante ──► Página (public/) ──► Worker (src/worker.js)
                                     ├─ OpenAI: entiende el problema y transcribe notas de voz
                                     ├─ D1: guarda leads y conversación
                                     └─ Kapso: te avisa por WhatsApp (lead nuevo, sin contactar, resumen diario)
```

## Qué hace cada ruta

| Ruta | Para qué |
|---|---|
| `GET /api/health` | Dice si la IA y WhatsApp están configurados |
| `POST /api/chat` | La IA lee el problema, lo clasifica (nómina, software, IA, procesos, datos) y responde |
| `POST /api/transcribe` | Convierte la nota de voz en texto |
| `POST /api/lead` | Guarda el lead, calcula prioridad A/B/C, prepara el brief y te avisa por WhatsApp |
| `POST /api/event` | Embudo: `{sessionId, type, intent?, utm?}`. Siempre responde 204; lo inválido se ignora. Límite ~120 por IP cada 10 min |
| `GET /api/leads` | Tus leads con su brief y estado (requiere `ADMIN_TOKEN`) |
| `PATCH /api/leads/:id` | Cambia el estado (`nuevo`, `contactado`, `agendado`, `cliente`, `descartado`) y/o la nota (máx. 1000) |
| `GET /api/stats?days=30` | Embudo por sesiones únicas, prioridades, temas, fuentes, leads por día, estados y horas promedio al primer contacto (1 a 90 días) |
| cron cada hora | Empujón a ti por leads sin contactar y resumen diario de las 7 am. Solo te escribe a ti |

Los endpoints de admin usan `Authorization: Bearer <ADMIN_TOKEN>`.

**Prioridad:** inversión ×3 + urgencia ×3 + quién decide ×2 + tema que sí resuelvo (3). Máximo 27.
A ≥ 20 → contacto hoy · B ≥ 13 → contacto en 24 h · C → nutrir con contenido.

**Agenda:** la haces tú a mano. `BOOKING_URL_LOGGRO` (software) y `BOOKING_URL_PERSONAL` (lo demás) son opcionales: si los llenas, `/api/lead` devuelve el link; vacíos, no pasa nada.

Si el backend no responde, la página sigue funcionando sola (clasifica por palabras clave y muestra "modo demo").

## Publicar (una sola vez, ~20 minutos)

Desde la carpeta `web/`:

```bash
npx wrangler login
npx wrangler d1 create damian-web            # copia el database_id en wrangler.jsonc
npx wrangler d1 migrations apply damian-web --remote

npx wrangler secret put OPENAI_API_KEY
npx wrangler secret put KAPSO_API_KEY
npx wrangler secret put ADMIN_TOKEN           # una clave larga que inventes tú
npx wrangler secret put IP_SALT               # otra cadena aleatoria

npx wrangler deploy
```

Luego, en `wrangler.jsonc` → `vars`, completa:

| Variable | Valor |
|---|---|
| `KAPSO_PHONE_NUMBER_ID` | ID del número del asistente en Kapso (Dashboard → WhatsApp numbers) |
| `OWNER_WHATSAPP` | Tu WhatsApp personal, ej. `573001234567` (aquí te llegan los avisos) |
| `KAPSO_NOTIFY_TEMPLATE` | Nombre de la plantilla de aviso (ver abajo). Vacío = texto libre |
| `BOOKING_URL_PERSONAL` | Link de tu página de citas de Google Calendar |
| `BOOKING_URL_LOGGRO` | Link de tu agenda de HubSpot para Loggro |

Y vuelve a correr `npx wrangler deploy`. Para tu dominio: Cloudflare → Workers → damian-web → Settings → Domains.

### Plantilla de aviso en WhatsApp

WhatsApp solo deja escribir texto libre si tú le escribiste al número en las últimas 24 horas. Para que los avisos lleguen siempre, crea en Kapso una plantilla **Utility**, por ejemplo `nuevo_lead`, con el cuerpo:

```
Nuevo lead en tu página: {{1}}
```

y pon `KAPSO_NOTIFY_TEMPLATE = "nuevo_lead"`.

### Contacto automático a clientes (apagado)

`AUTO_CONTACT_LEADS = "false"`. Si lo pones en `"true"` y defines `KAPSO_LEAD_TEMPLATE` (plantilla aprobada con `{{1}}` = nombre y `{{2}}` = tema), el asistente les escribe solo a los leads A y B. Es un mensaje a clientes reales: actívalo después de probar con tu propio número.

## Copiloto de leads

El sistema te ayuda a convertir; no agenda ni le escribe a los leads por su cuenta.

**Brief del lead** (`src/brief.js`). Al guardar un lead, OpenAI prepara: resumen, qué necesita de verdad, la **apertura** (primer WhatsApp tuyo, máx. 350 caracteres, termina en pregunta), 3 preguntas de descubrimiento, alertas ("decide otra persona", "presupuesto bajo…") y el frente sugerido. Se guarda en `leads.brief`. El texto del lead va delimitado y se trata como dato, no como instrucción. Si la IA falla o tarda más de 10 s, se usa un brief de plantilla: nunca falta. Te llega por WhatsApp con prioridad, nombre, teléfono, resumen, la apertura y un link `wa.me` que abre el chat con la apertura ya escrita.

**Embudo.** La página manda a `POST /api/event` una etapa por sesión: `visit`, `start`, `intent`, `q_budget`, `q_timing`, `q_decider`, `contact_form`; el servidor registra `lead` solo. `GET /api/stats` las cuenta como sesiones únicas, con los días en hora de Bogotá.

**Empujón.** Cada hora, entre 7 am y 9 pm (Bogotá), el cron te avisa una sola vez por lead: lead A en `nuevo` hace más de 2 h, lead B hace más de 24 h. A las 7 am te llega el resumen del día anterior y los pendientes. Todo va a `OWNER_WHATSAPP`, nunca a un lead. Si marcas el lead como `contactado`, deja de avisar. Si Kapso falla, reintenta a la hora siguiente.

| Variable | Para qué |
|---|---|
| `OPENAI_API_KEY`, `OPENAI_MODEL` | El brief (sin llave, usa la plantilla) |
| `KAPSO_API_KEY`, `KAPSO_PHONE_NUMBER_ID`, `OWNER_WHATSAPP` | Los avisos a ti |
| `KAPSO_NOTIFY_TEMPLATE` | Plantilla Utility con **un** parámetro `{{1}}` (todo el aviso en una línea, hasta ~900 caracteres). Vacío = texto libre, que solo llega dentro de las 24 h desde que le escribiste al número. Para que el empujón y el resumen de las 7 am lleguen siempre, usa plantilla |
| `ADMIN_TOKEN` | Leads, cambios de estado y métricas |
| `AUTO_CONTACT_LEADS` | Sigue apagado (`"false"`). Es el único camino que escribiría a un lead |

## Probar en tu computador

```bash
cd web
printf 'ADMIN_TOKEN=prueba\nIP_SALT=sal\n' > .dev.vars   # agrega OPENAI_API_KEY=... para probar la IA
npx wrangler d1 migrations apply damian-web --local
npx wrangler dev
```

Abre http://localhost:8787. Para ver los leads:

```bash
curl -H "Authorization: Bearer prueba" http://localhost:8787/api/leads
```

## Fase 2: el asistente de WhatsApp (pendiente)

Lo que falta para que el asistente trabaje 24/7:

1. **Webhook de Kapso → Worker** (`POST /api/whatsapp`): recibe los mensajes que llegan al número del asistente.
2. **Cerebro con herramientas** (OpenAI con *function calling*): consultar leads en D1, proponer horarios y agendar.
3. **Google Calendar** de tu empresa (OAuth de damian3314@gmail.com): ver espacios libres y crear la reunión de Meet.
4. **Regla de calendario**: si el cliente habla de Loggro, el asistente le manda tu link de HubSpot. Si no, agenda en tu Google Calendar.
5. **Resumen diario** a tu WhatsApp: a quién contactar hoy.
