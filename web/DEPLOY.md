# Publicar la página (primera vez)

Tiempo: ~30 minutos. Todo se corre desde la carpeta `web/`. Requisitos: cuenta de Cloudflare, Node 20+, cuenta de OpenAI con saldo y el número de WhatsApp del asistente ya conectado en Kapso.

## 0. Antes de empezar

1. `holadami.com` debe estar agregado como zona en **la misma cuenta de Cloudflare** del `account_id` de `wrangler.jsonc`. Si no, `wrangler deploy` falla en `routes`: borra el bloque `routes` y la página queda en `https://damian-web.<tu-subdominio>.workers.dev` hasta que conectes el dominio (Workers → damian-web → Settings → Domains).
2. `npx wrangler login`

## 1. Base de datos

```bash
npx wrangler d1 create damian-web
```

Copia el `database_id` que imprime y pégalo en `wrangler.jsonc`, reemplazando `REEMPLAZAR_CON_EL_ID_DE_D1`. Luego crea las tablas (confirma con `y`):

```bash
npx wrangler d1 migrations apply damian-web --remote
```

Debe listar `0001_init`, `0002_copiloto` y `0003_seguridad` en verde.

## 2. Variables de Kapso y del aviso (`wrangler.jsonc` → `vars`)

| Variable | Valor |
|---|---|
| `KAPSO_PHONE_NUMBER_ID` | ID del número del asistente (Kapso → WhatsApp numbers) |
| `OWNER_WHATSAPP` | Tu WhatsApp personal con indicativo, sin `+`: `573001234567`. Ojo: queda escrito en el repo; si el repo no es privado, no lo pongas aquí |
| `KAPSO_NOTIFY_TEMPLATE` | `nuevo_lead` (la plantilla de abajo) |
| `KAPSO_TEMPLATE_LANG` | `es` (el mismo idioma con el que creaste la plantilla; si fue `es_CO`, pon `es_CO`) |
| `AUTO_CONTACT_LEADS` | **Déjalo en `"false"`**. En `"true"` el sistema le escribiría a clientes reales |
| `BOOKING_URL_*` | Opcional. Vacíos = no se muestra link de agenda |

### Plantilla de aviso (créala en Kapso → Templates, antes de este paso)

- Nombre: `nuevo_lead` · Categoría: **Utility** · Idioma: Español
- Cuerpo (exacto, **un solo** parámetro; Meta rechaza plantillas que empiezan o terminan con la variable, por eso lleva texto antes y después):

```
Hola Damián, tienes un aviso de tu página web:

{{1}}

Mensaje automático de tu asistente.
```

- Ejemplo para `{{1}}` (Meta lo pide al aprobar): `🔥 Lead A (24/27): Marta Pérez +573001234567 · Nómina · $1,5 M – $5 M · Urgente · Decide solo · Resumen: Marta necesita liquidar la nómina de 3 empleados. · Escríbele: https://wa.me/573001234567`
- Sin cabecera, sin pie, sin botones. Si Meta la recategoriza como Marketing, pide revisión como Utility (es un aviso interno para ti) o acéptalo: funciona igual.
- Tarda de minutos a horas en aprobarse. Mientras tanto déjala vacía (`""`): el aviso va como texto libre y solo llega si le escribiste al número en las últimas 24 h.

## 3. Publicar

```bash
npx wrangler deploy
```

(Si falla por la plantilla o una variable, corrige `wrangler.jsonc` y repite: `deploy` es seguro de repetir.)

## 4. Secretos

Se crean **después** del primer deploy, para que el Worker ya exista. Cada comando te pide el valor; no lo pegues en el chat ni en un archivo del repo.

```bash
npx wrangler secret put ADMIN_TOKEN
npx wrangler secret put IP_SALT
npx wrangler secret put OPENAI_API_KEY
npx wrangler secret put KAPSO_API_KEY
```

| Secreto | Qué poner |
|---|---|
| `ADMIN_TOKEN` | Una clave larga al azar: `openssl rand -base64 33`. Guárdala en tu gestor de contraseñas; es lo que pegas en `/admin` |
| `IP_SALT` | Otra cadena al azar: `openssl rand -hex 16`. No la compartas ni la cambies después (si la cambias solo se reinician los topes) |
| `OPENAI_API_KEY` | Una llave **solo para esta página**, de un proyecto aparte con tope de gasto (ver abajo) |
| `KAPSO_API_KEY` | La API key del proyecto en Kapso |

Los secretos sobreviven a los siguientes `deploy`; no los pongas en `vars`.

### Tope de gasto en OpenAI

1. En platform.openai.com crea un **proyecto nuevo** (ej. "damian-web") y genera la llave dentro de ese proyecto. Si te deja, limita sus permisos a lo que usa la página: Chat completions y Audio transcriptions.
2. Ese proyecto → **Limits** (o Settings → Limits): pon un presupuesto mensual (sugerido: **USD 10**; con `gpt-4o-mini` y los topes del Worker alcanza para miles de chats) y una alerta por correo al 50 %. En Settings → Billing deja la recarga automática apagada.
3. Los menús de OpenAI cambian de nombre; si no encuentras "Limits", busca "Budget" o "Usage limits" en el proyecto.
4. Por si algo se sale de control: borrar o rotar la llave corta el gasto al instante y la página sigue funcionando en modo palabras clave.

## 5. Verificación después de publicar

Sustituye `holadami.com` por la URL real si aún no conectas el dominio.

1. **Salud:** `curl https://holadami.com/api/health` → `{"ok":true,"ai":true,"whatsapp":true}`. Si `ai` o `whatsapp` salen en `false`, falta un secreto o una variable.
2. **Cabeceras:** `curl -sI https://holadami.com/ | grep -i "content-security-policy\|x-frame-options\|permissions-policy"` → deben salir las tres.
3. **Abrir la landing** en el celular y en el computador. Prueba el micrófono (el navegador debe pedir permiso) y que las fuentes carguen.
4. **Lead de prueba con tu propio número:** completa el chat hasta el final (nombre de prueba, tu WhatsApp, marca la autorización). Debes ver: la despedida de la página, y en menos de un minuto un WhatsApp tuyo con el aviso y el link "Escríbele".
5. **Panel:** abre `https://holadami.com/admin`, pega el `ADMIN_TOKEN`. El lead aparece en **Hoy** con su resumen y apertura; en **Embudo** deben salir la visita y el lead. Pruébalo con una clave equivocada: debe rechazarla.
6. **Cambiar estado:** marca el lead de prueba como "Contactado" y recarga; el cambio debe persistir.
7. **Borrar el lead de prueba** (cambia el número por el tuyo, y `NOMBRE` por el nombre que usaste):

```bash
npx wrangler d1 execute damian-web --remote --command "DELETE FROM events WHERE session_id IN (SELECT session_id FROM leads WHERE name = 'NOMBRE'); DELETE FROM chat_messages WHERE session_id IN (SELECT session_id FROM leads WHERE name = 'NOMBRE'); DELETE FROM leads WHERE name = 'NOMBRE';"
```

8. **Cron (opcional, al día siguiente):** a las 7 am (Bogotá) debe llegarte el resumen diario. Para probar el empujón, haz un lead de prueba y retrocede su fecha: `npx wrangler d1 execute damian-web --remote --command "UPDATE leads SET created_at = datetime('now','-3 hours') WHERE name = 'NOMBRE'"`; en el siguiente minuto 0 de una hora entre 7 am y 9 pm te llega "Lead A sin contactar". Borra ese lead al terminar (paso 7). Los logs en vivo: `npx wrangler tail`.

## 6. Volver atrás (rollback)

- **Código:** `npx wrangler versions list` muestra las últimas 10 versiones; `npx wrangler rollback <version-id>` vuelve a una (sin id, a la anterior). Los secretos y la base de datos no cambian.
- **Base de datos:** las migraciones solo agregan tablas y columnas, así que volver a una versión anterior del código no las rompe. Antes de cualquier cambio de esquema futuro, saca una copia: `npx wrangler d1 export damian-web --remote --output=respaldo.sql`.
- **Apagar todo ya:** borra `OPENAI_API_KEY` (`npx wrangler secret delete OPENAI_API_KEY`) y la página sigue en modo palabras clave; borra `KAPSO_API_KEY` y se detienen los avisos.
