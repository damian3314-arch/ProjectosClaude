# Página de Damián Barragán

Página tipo chat + backend en Cloudflare. Todo vive en Cloudflare: la página, la lógica (Worker) y la base de datos (D1).

```
Visitante ──► Página (public/) ──► Worker (src/worker.js)
                                     ├─ OpenAI: entiende el problema y transcribe notas de voz
                                     ├─ D1: guarda leads y conversación
                                     └─ Kapso: te avisa por WhatsApp cuando llega un lead
```

## Qué hace cada ruta

| Ruta | Para qué |
|---|---|
| `GET /api/health` | Dice si la IA y WhatsApp están configurados |
| `POST /api/chat` | La IA lee el problema, lo clasifica (nómina, software, IA, procesos, datos) y responde |
| `POST /api/transcribe` | Convierte la nota de voz en texto |
| `POST /api/lead` | Guarda el lead, calcula prioridad A/B/C, elige calendario y te avisa por WhatsApp |
| `GET /api/leads` | Tu lista de leads (requiere `ADMIN_TOKEN`) |
| `POST /api/agent` | El agente conversa con el lead y **agenda** la reunión (herramientas: horarios, reservar, avisarte) |
| `GET /api/resume` | Retoma la conversación desde el link `holadami.com/?r=<lead>` de un seguimiento |
| cron cada 30 min | Seguimiento a leads A/B, confirmación y recordatorios (solo con `AUTO_CONTACT_LEADS="true"`) |

**Prioridad:** inversión ×3 + urgencia ×3 + quién decide ×2 + tema que sí resuelvo (3). Máximo 27.
A ≥ 20 → contacto hoy · B ≥ 13 → contacto en 24 h · C → nutrir con contenido.

**Calendario:** si el tema es *software* → `BOOKING_URL_LOGGRO` (HubSpot de Loggro). Todo lo demás → `BOOKING_URL_PERSONAL` (tu Google Calendar).

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
npx wrangler secret put N8N_SECRET            # la misma clave que valida tus webhooks de n8n

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

## El agente que agenda (n8n)

Tras las 3 preguntas, los leads A y B siguen hablando con el agente en lenguaje natural ("el jueves después de las 7"), por texto o voz. El agente propone horarios y **reserva la cita**; no manda links. Si hace falta una persona (excepción de horario, cambio de cita, pregunta que no sabe), te avisa por WhatsApp.

**Las reglas de horario viven en `src/agent.js`** (el modelo no puede reservar fuera de ellas), en hora de Bogotá, llamadas de 30 min, 15 min de colchón, mínimo 3 h de anticipación, 14 días hacia adelante:

| Tema | Calendario | Horarios |
|---|---|---|
| IA, procesos, datos, nómina | Google (`personal`) | L-V 6:30 pm–9:00 pm · sábado 8 am–12 m |
| Software (Loggro) | Outlook (`loggro`) | L-V 9 am–6 pm |

Cambiar un horario = editar `WINDOWS` en `src/agent.js`.

### Los 2 webhooks de n8n

Ambos reciben el header `x-api-key` (= secreto `N8N_SECRET`; rechaza si no coincide). `N8N_BASE_URL` es la base, ej. `https://tu-n8n.app.n8n.cloud/webhook`.

**`POST {N8N_BASE_URL}/availability`** — qué está ocupado
```json
// entra
{ "calendar": "personal" | "loggro", "from": "2026-10-26T00:00:00Z", "to": "2026-11-10T00:00:00Z" }
// responde
{ "busy": [ { "start": "2026-10-27T23:30:00Z", "end": "2026-10-28T00:30:00Z" } ] }
```
`personal` → Google Calendar (free/busy). `loggro` → Outlook (getSchedule / eventos).

**`POST {N8N_BASE_URL}/book`** — crea el evento
```json
// entra
{ "calendar": "personal", "start": "2026-10-29T00:00:00Z", "end": "2026-10-29T00:30:00Z",
  "title": "Llamada con Marta · IA y automatización", "description": "…", "attendeeName": "Marta", "phone": "573001234567", "leadId": "…" }
// responde
{ "eventId": "abc123" }
```

### Mensajes proactivos (apagados por defecto)

Escriben a clientes reales. Se activan con `AUTO_CONTACT_LEADS = "true"` **después** de probar con tu número y de tener las plantillas aprobadas en Meta:

| Variable | Cuándo se envía | Parámetros |
|---|---|---|
| `KAPSO_FOLLOWUP_TEMPLATE` | Lead A/B sin cita: a las 3 h y a las 24 h (máx. 2, solo 8 am–8 pm) | `{{1}}` nombre · `{{2}}` tema · `{{3}}` link para retomar |
| `KAPSO_CONFIRM_TEMPLATE` | Al agendar | `{{1}}` nombre · `{{2}}` cuándo |
| `KAPSO_REMIND_TEMPLATE` | 24 h y 1 h antes de la cita | `{{1}}` nombre · `{{2}}` cuándo |

Límite actual: si el lead responde **dentro de WhatsApp**, nadie lo procesa todavía (lo ves en el inbox de Kapso). El agente conversa en la página, a la que el lead vuelve con el link del seguimiento. Responder dentro de WhatsApp es la siguiente fase.

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
