# Página de Damián Barragán

Página tipo chat + backend en Cloudflare. Todo vive en Cloudflare: la página, la lógica (Worker) y la base de datos (D1).

```
Visitante ──► Página (public/) ──► Worker (src/worker.js)
                                     ├─ OpenAI: entiende el problema, transcribe notas de voz y prepara el brief
                                     ├─ D1: guarda leads, conversación y embudo
                                     └─ Kapso: te avisa por WhatsApp (lead nuevo, sin contactar, resumen diario)
```

Para publicar por primera vez: **`DEPLOY.md`**.

## Qué hace cada ruta

| Ruta | Para qué |
|---|---|
| `GET /api/health` | Dice si la IA y WhatsApp están configurados |
| `POST /api/chat` | La IA lee el problema, lo clasifica (nómina, software, IA, procesos, datos) y responde |
| `POST /api/transcribe` | Convierte la nota de voz en texto (máx. 4 MB) |
| `POST /api/lead` | Guarda el lead (exige la autorización de datos), calcula prioridad A/B/C, prepara el brief y te avisa por WhatsApp |
| `POST /api/event` | Embudo: `{sessionId, type, intent?, utm?}`. Siempre responde 204; lo inválido se ignora |
| `GET /api/leads` | Tus leads con su brief y estado (requiere `ADMIN_TOKEN`) |
| `PATCH /api/leads/:id` | Cambia el estado (`nuevo`, `contactado`, `agendado`, `cliente`, `descartado`) y/o la nota (máx. 1000) |
| `GET /api/stats?days=30` | Embudo por sesiones únicas, prioridades, temas, fuentes (visitas y leads), leads por día, estados y horas promedio al primer contacto (1 a 90 días) |
| `/admin` | Tu panel (Hoy, Todos, Embudo). Pide el `ADMIN_TOKEN`. No se indexa |
| cron cada hora | Empujón a ti por leads sin contactar y resumen diario de las 7 am. Solo te escribe a ti |

Los endpoints de admin usan `Authorization: Bearer <ADMIN_TOKEN>`.

**Prioridad:** inversión ×3 + urgencia ×3 + quién decide ×2 + tema que sí resuelvo (3). Máximo 27.
A ≥ 20 → contacto hoy · B ≥ 13 → contacto en 24 h · C → nutrir con contenido.

**Agenda:** la haces tú a mano. `BOOKING_URL_LOGGRO` (software) y `BOOKING_URL_PERSONAL` (lo demás) son opcionales: si los llenas, `/api/lead` devuelve el link y la página muestra "Prefiero elegir hora"; vacíos, no pasa nada.

Si el backend no responde, la página sigue funcionando sola (clasifica por palabras clave y muestra "modo demo").

## Copiloto de leads

El sistema te ayuda a convertir; no agenda ni le escribe a los leads por su cuenta.

**Brief del lead** (`src/brief.js`). Al guardar un lead, OpenAI prepara: resumen, qué necesita de verdad, la **apertura** (primer WhatsApp tuyo, máx. 350 caracteres, termina en pregunta), 3 preguntas de descubrimiento, alertas ("decide otra persona", "presupuesto bajo…") y el frente sugerido. Se guarda en `leads.brief`. El texto del lead va delimitado y se trata como dato, no como instrucción; si el modelo devuelve un campo con enlace, dominio o teléfono, ese campo se reemplaza por la plantilla. Si la IA falla o tarda más de 10 s, se usa un brief de plantilla: nunca falta. Te llega por WhatsApp con prioridad, nombre, teléfono, resumen, la apertura y un link `wa.me` que abre el chat con la apertura ya escrita.

**Embudo.** La página manda a `POST /api/event` una etapa por sesión: `visit`, `start`, `intent`, `q_budget`, `q_timing`, `q_decider`, `contact_form`; el servidor registra `lead` solo. De dónde llega cada visita se guarda como `utm_*` y, si no hay, el **dominio** de referencia (solo `google.com`, nunca la URL completa). `GET /api/stats` las cuenta como sesiones únicas, con los días en hora de Bogotá.

**Empujón.** Cada hora, entre 7 am y 9 pm (Bogotá), el cron te avisa una sola vez por lead: lead A en `nuevo` hace más de 2 h, lead B hace más de 24 h (solo leads de la última semana). A las 7 am te llega el resumen del día anterior y los pendientes. Todo va a `OWNER_WHATSAPP`, nunca a un lead. Si marcas el lead como `contactado`, deja de avisar. Si Kapso falla, reintenta a la hora siguiente.

| Variable | Para qué |
|---|---|
| `OPENAI_API_KEY` (secreto), `OPENAI_MODEL`, `OPENAI_TRANSCRIBE_MODEL` | El chat, el brief y las notas de voz (sin llave, la página usa palabras clave y el brief usa la plantilla) |
| `KAPSO_API_KEY` (secreto), `KAPSO_PHONE_NUMBER_ID`, `OWNER_WHATSAPP` | Los avisos a ti |
| `KAPSO_NOTIFY_TEMPLATE`, `KAPSO_TEMPLATE_LANG` | Plantilla Utility con **un** parámetro `{{1}}` (todo el aviso en una línea, hasta ~900 caracteres). Vacío = texto libre, que solo llega dentro de las 24 h desde que le escribiste al número. Para que el empujón y el resumen de las 7 am lleguen siempre, usa plantilla |
| `ADMIN_TOKEN` (secreto) | Leads, cambios de estado y métricas |
| `IP_SALT` (secreto) | Sal para guardar las IP como huella, no como número |
| `AUTO_CONTACT_LEADS`, `KAPSO_LEAD_TEMPLATE` | Siguen apagados (`"false"`). Es el único camino que escribiría a un lead: no lo prendas |
| `BOOKING_URL_LOGGRO`, `BOOKING_URL_PERSONAL` | Opcionales (ver Agenda) |

## Seguridad y límites

- **Cabeceras** (en el Worker, para la página y la API): CSP (solo scripts y estilos propios, Google Fonts, `connect-src 'self'`), `X-Content-Type-Options`, `X-Frame-Options`/`frame-ancestors`, `Referrer-Policy`, `Permissions-Policy` con `microphone=(self)` y HSTS. `/admin` y `/api` además salen con `no-store` y `noindex`. Por eso `wrangler.jsonc` tiene `run_worker_first: true`.
- **Mismo origen:** los POST públicos rechazan otro `Origin` y `Sec-Fetch-Site: cross-site` (403). Sin `Origin` (curl) pasan: ahí protegen los topes.
- **Topes (cuidan el gasto de OpenAI y tu WhatsApp):** chat 30 por IP cada 10 min y 400 por hora en total · audio 8 por IP cada 10 min y 150 por día en total, máx. 4 MB · leads 5 por IP por hora; si entran más de 10 leads en una hora se guardan igual pero sin IA ni aviso individual · eventos 120 por IP cada 10 min. Las constantes están arriba de `src/worker.js`.
- **Panel:** 10 claves equivocadas desde la misma IP en 15 min bloquean esa IP 15 min (429).
- **Datos:** las IP se guardan como huella con sal. Los logs no llevan teléfonos ni textos. Los textos de terceros se escapan en el panel y en la página; lo que va a tu WhatsApp pasa sin enlaces ni formato.
- **Qué NO cubre:** la CSP permite scripts inline (la página los usa), así que la defensa contra XSS es el escapado, no la CSP.

## Probar en tu computador

```bash
cd web
printf 'ADMIN_TOKEN=prueba\nIP_SALT=sal\n' > .dev.vars   # agrega OPENAI_API_KEY=... para probar la IA
npx wrangler d1 migrations apply damian-web --local
npx wrangler dev
```

Abre http://localhost:8787 (la página) y http://localhost:8787/admin (el panel; la clave es la de `.dev.vars`). `/admin?demo=1` muestra el panel con datos de ejemplo, sin backend. Para ver los leads por consola:

```bash
curl -H "Authorization: Bearer prueba" http://localhost:8787/api/leads
```
