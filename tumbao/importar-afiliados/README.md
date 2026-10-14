# Tumbao · Importar afiliados y recalcular cupos (Cloudflare Worker)

Reemplaza el workflow de n8n del mismo nombre. Mismo flujo, mismas reglas:

```
Cron (9:30 pm y 8:00 am Bogota)
 → Drive: carpeta del año → carpeta del mes (+ mes anterior)
 → elegir candidatos por fecha en el nombre (AAAA-MM-DD, máx. 7 días, máx. 3 intentos)
 → por cada candidato: bajar → leer xlsx → buscar cabecera → parsear
     · si no se puede leer, prueba el siguiente
 → Supabase RPC importar_membresias(p_filas) → recalcula cupos
 → resumen en el log
```

Si algo falla, el Worker lanza error: la invocación queda en rojo en Cloudflare
(Workers → tumbao-importar-afiliados → Logs / Observability). No toca Supabase
si ningún archivo se pudo leer.

## Diferencias frente a n8n

| n8n | Worker |
|---|---|
| OAuth2 de tu cuenta Google | Cuenta de servicio: la carpeta se comparte con su correo (lector) |
| `errorWorkflow` JDko0xmWXYOxoYgX | Invocación fallida en Cloudflare. Alertas por correo: ver abajo |
| Hoja `Sheet1` | `Sheet1` si existe; si no, la primera hoja |
| Si la RPC devolvía `ok:false`, solo quedaba en el resumen | Se marca la corrida como fallida |
| Un fallo de descarga detenía el flujo | Se prueba el siguiente candidato |
| Resumen por WhatsApp: pendiente (es Rojo) | Igual: solo log |

## Puesta en marcha

1. **Cuenta de servicio** (Google Cloud Console): proyecto → habilitar *Google Drive API* →
   IAM → Cuentas de servicio → crear → Claves → JSON.
2. En Drive, compartir la carpeta **Miembros Activos** con el `client_email` del JSON, rol *Lector*.
3. Instalar y entrar a Cloudflare:
   ```bash
   cd tumbao/importar-afiliados
   npm install
   npx wrangler login
   ```
4. Secretos:
   ```bash
   npx wrangler secret put GOOGLE_SERVICE_ACCOUNT   # pegar el JSON completo
   npx wrangler secret put SUPABASE_SERVICE_KEY     # la misma key que usa la credencial "Supabase Tumbao" en n8n
   npx wrangler secret put RUN_TOKEN                # cualquier string largo, solo para la prueba en seco
   ```
5. Desplegar: `npx wrangler deploy`
6. **Prueba en seco** (lee Drive y parsea, NO escribe en Supabase):
   ```bash
   curl -H "Authorization: Bearer $RUN_TOKEN" "https://tumbao-importar-afiliados.<tu-subdominio>.workers.dev/run?dry=1"
   ```
   Debe devolver el archivo elegido, la carpeta y el conteo por horario. Compáralo con la última ejecución de n8n.
7. **Corrida en paralelo**: deja n8n y el Worker activos un ciclo completo (noche + mañana). Importar dos veces el mismo
   reporte no hace daño. Verifica que `clases_actualizadas` coincida.
8. Desactivar el workflow en n8n.

## Horarios

Cloudflare usa UTC. Bogotá es UTC-5 todo el año: `30 2 * * *` = 9:30 pm y `0 13 * * *` = 8:00 am.

## Alertas de fallo

Cloudflare Dashboard → Notifications → Add → alerta de Workers → correo.
Alternativa: Observability → filtrar por `outcome = exception`.

## Desarrollo

```bash
npm test                # 16 pruebas, datos dummy, Drive y Supabase simulados
npm run build:check     # empaqueta sin desplegar
npm run dev             # wrangler dev; para disparar el cron local: curl "http://localhost:8787/__scheduled"
```
`wrangler dev` con secretos reales y `/__scheduled` SÍ escribe en Supabase. Para probar sin escribir, usa `/run?dry=1`.

## Nota de seguridad

`xlsx@0.18.5` (la versión de npm) tiene avisos conocidos de ReDoS/prototype pollution con archivos maliciosos.
Aquí el archivo sale de tu propia carpeta de Drive, así que el riesgo es bajo, pero no abras el Worker a archivos de terceros.
