# WhatsApp de Alter: API de Meta directo (sin Kapso)

Número de Alter: **+57 333 402 1068**, registrado en el Business Manager de Tumbao Barrancabermeja. Alter conversa con quien escribe desde
holadami.com (o por el botón de WhatsApp de la página) y te avisa a **+57 301 537 3964** cuando hay un lead que atender.

```
Cliente ──► WhatsApp ──► Meta ──► POST https://holadami.com/api/whatsapp (Worker, firma X-Hub-Signature-256)
                                      └─► Alter (IA) ──► POST graph.facebook.com/v24.0/{WA_PHONE_NUMBER_ID}/messages ──► Cliente
Lead caliente ──► Worker ──► aviso a tu número (+57 301 537 3964)
```

## Lo que necesito de Meta (4 datos)

| Dato | Dónde sale | Dónde va |
|---|---|---|
| **WA_PHONE_NUMBER_ID** (un número largo; no es el teléfono) | developers.facebook.com → tu app → WhatsApp → *Configuración de la API* → selecciona el +57 333 402 1068 | `wrangler.jsonc` (no es secreto: pásamelo en el chat) |
| **WA_TOKEN** (token permanente) | Ver paso 2 | Secreto de Cloudflare |
| **WA_APP_SECRET** | Tu app → *Configuración de la app* → *Básica* → *Clave secreta de la app* → Mostrar | Secreto de Cloudflare |
| **WA_VERIFY_TOKEN** | Lo inventas tú (una frase larga al azar, sin espacios) | Secreto de Cloudflare y el webhook de Meta |

Los secretos no se pegan en el chat ni en el repo.

## Pasos

1. **App de Meta.** developers.facebook.com → *Crear app* → tipo **Empresa** → vincúlala al portafolio *Tumbao Barrancabermeja* → agrega el producto **WhatsApp**.
   En *WhatsApp → Configuración de la API* debe aparecer el +57 333 402 1068 (estado Conectado). Ahí copias el **Phone number ID**.
2. **Token permanente.** business.facebook.com/settings → *Usuarios* → *Usuarios del sistema* → *Agregar* (nombre `alter`, rol Admin) →
   *Agregar activos*: la app (control total) y la cuenta de WhatsApp de Alter (control total) → *Generar token*: elige la app, caducidad **Nunca**,
   permisos `whatsapp_business_messaging` y `whatsapp_business_management`. Ese es el `WA_TOKEN`.
3. **Secretos en Cloudflare.** Workers → `projectosclaude` → *Settings* → *Variables and secrets* → agrega como **Secret**: `WA_TOKEN`, `WA_APP_SECRET`, `WA_VERIFY_TOKEN`.
   Y actualiza el secreto `LOGGRO_ALERT_WHATSAPP` a `573015373964` (a ese número llegan los avisos).
4. **Publicar** el código (push a `landing-personal`) con `WA_PHONE_NUMBER_ID` ya puesto.
5. **Webhook.** Tu app → *WhatsApp → Configuración* → *Webhook* → URL `https://holadami.com/api/whatsapp` + el `WA_VERIFY_TOKEN` → *Verificar y guardar*
   → en *Campos del webhook* suscríbete a **messages**. Verifica también que la cuenta de WhatsApp de Alter esté suscrita a la app (Meta lo hace al agregar el número;
   si no llegan mensajes, es lo primero que se revisa: `POST /{waba-id}/subscribed_apps`).
6. **Plantillas** (WhatsApp Manager → *Plantillas de mensajes*, categoría **Utility**, idioma Español). Solo las usa Alter para avisarte cuando tu ventana de 24 h está cerrada:
   - `aviso_lead`: `Aviso de tu asistente Alter: {{1}}` + línea en blanco + `Responde a este mensaje o revisa el panel para ver el detalle.` (ejemplo de `{{1}}`: `Lead nuevo de HolaDami: Marta, tienda, quiere demo`).
   - `alerta_nueva_solicitud`: `Notificación del sistema: se registró una nueva solicitud que requiere tu atención. Resumen: {{1}}. Puedes revisar el detalle en el panel de administración.` (ejemplo: `Marta, tienda de ropa, pidió una demo`).
7. **Prueba.** Desde el +57 301 537 3964 escríbele "hola" al +57 333 402 1068: eso abre tu ventana de 24 h (los avisos llegan como texto). Luego, desde otro celular, escribe
   "Hola, vi tu página holadami.com…" y mira que Alter conteste. `curl https://holadami.com/api/health` debe mostrar `"whatsapp":true`.
8. **Botón en la página.** Cuando todo funcione, pon `ALTER_WHATSAPP` = `573334021068` en `wrangler.jsonc` y publica: aparece "Prefiero escribir por WhatsApp" y el número en las dudas.

## Cosas que cambian frente a Kapso

- No hay bandeja: las conversaciones las lleva Alter y los avisos te llegan al celular con el link `wa.me` del lead. Tú le escribes al lead desde tu número.
- Una línea de Cloud API no se usa desde la app de WhatsApp en un celular. Por eso Alter no se calla solo cuando tú escribes a un lead: si quieres que Alter pare con alguien, dilo en el aviso o márcalo en `/admin`.
- Las notas de voz que llegan por WhatsApp se transcriben con OpenAI (máx. 4 MB).
- Si cambias de número: nuevo `WA_PHONE_NUMBER_ID` y `WA_SENDER_NUMBER`, y el mismo webhook.
