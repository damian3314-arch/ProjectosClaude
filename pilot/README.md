# Piloto Kapso (WhatsApp)

1. `export KAPSO_API_KEY=... KAPSO_WEBHOOK_SECRET=...` (nunca en el repo)
2. `node server.mjs` y exponer con un túnel HTTPS (ej. `cloudflared tunnel --url http://localhost:3000`)
3. Crear webhook en Kapso apuntando a `https://<túnel>/webhooks/kapso`, eventos `whatsapp.message.received`, `whatsapp.message.failed`, payload v2.
4. `AUTO_REPLY=true` activa la respuesta automática (apagada por defecto).
