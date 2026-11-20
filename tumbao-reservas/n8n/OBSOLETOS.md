# Workflows del primer diseño (no usar)

`obsoleto-01-disponibilidad.json` y `obsoleto-02-reservar.json` son de la
primera versión, cuando el modelo de datos era el de Beat en Notion
(`sesiones_clase`, `clientes`, `crear_reserva`).

El Supabase que quedó montado usa el esquema del blueprint: `clases`,
`reservas`, `pagos`, con `tomar_cupo()`. **No son compatibles** — estos
workflows fallarían contra esa base.

Los reemplaza `04-api-reservas.sdk.js`, ya creado en n8n como
"Tumbao · API de reservas".

Se conservan solo como referencia de la lógica de agrupación por día y
del honeypot, que sí se reusaron.
