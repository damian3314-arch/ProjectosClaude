# Tumbao — Página de reservas

Reserva self-service de clases de salsa y bachata. El alumno entra desde el link
de Instagram, elige horario, deja nombre y celular, y se lleva un código para
mostrar en recepción. Paga al llegar.

**Estado: construido y probado de punta a punta contra Postgres real y Chromium.
Falta conectarlo a tu n8n y a tu Supabase — eso no lo pude hacer yo (ver
[Qué necesito de ti](#qué-necesito-de-ti)).**

---

## Cómo funciona

```
Navegador (web/index.html, estático)
   │  GET  /webhook/tumbao/disponibilidad   → horarios con cupos
   │  POST /webhook/tumbao/reservar         → crea la reserva
   ▼
n8n (2 workflows)
   ▼
Supabase / Postgres
   crear_reserva()  ← toda la lógica de cupo vive aquí
```

La página **no tiene claves de Supabase**. Solo habla con n8n; n8n es el único
que toca la base. Si alguien abre el código fuente de la página no encuentra
nada aprovechable.

El control de cupo está en la función de Postgres, no en el workflow, a
propósito: si el "¿hay cupo?" y el "inserta la reserva" fueran dos pasos
separados en n8n, dos personas tocando el último cupo al mismo tiempo entrarían
las dos. Esto está probado (ver abajo).

---

## Ponerlo en línea

### 1. Base de datos (Supabase → SQL Editor)

Ejecuta en orden:

| Archivo | Qué hace |
|---|---|
| `db/001_schema.sql` | Tablas, enums, índices |
| `db/002_logica_reservas.sql` | Vista de disponibilidad, `crear_reserva()`, `cancelar_reserva()`, RLS |
| `db/003_seed_demo.sql` | Academia Tumbao + horario **de ejemplo** para 28 días |

Los tres son re-ejecutables sin romper nada ni borrar reservas.

Comprobación rápida:

```sql
SELECT clase, start_at, cupo_total, cupos_disponibles
  FROM v_disponibilidad ORDER BY start_at LIMIT 10;
```

> ⚠️ El horario de `003` está inventado (Lun/Mié salsa 7pm, Mar/Jue bachata,
> Sáb rueda 10am, instructores "Kevin" y "Laura"). Reemplázalo por el real antes
> de publicar el link.

### 2. Credencial de Postgres en n8n

n8n → **Credentials → New → Postgres**. Los datos salen de Supabase en
*Project Settings → Database → Connection info*. Usa el **connection pooler**
(puerto 6543) si tu n8n es cloud. Nómbrala `Supabase Tumbao`.

### 3. Importar los workflows

n8n → **Workflows → Import from File**:

- `n8n/01-tumbao-disponibilidad.json`
- `n8n/02-tumbao-reservar.json`

En cada nodo de Postgres, selecciona la credencial `Supabase Tumbao` (vienen con
`"id": "REEMPLAZAR"`, hay que elegirla a mano una vez). Después **activa** los
dos workflows y copia la **Production URL** del webhook.

### 4. Publicar la página

Edita el bloque `CONFIG` al inicio de `web/index.html`:

```js
const CONFIG = {
  N8N_BASE: 'https://tu-n8n.com/webhook',   // ← lo único obligatorio
  SLUG:     'tumbao',
  DIAS:     14,
  WHATSAPP: '573017833550',
  INSTAGRAM:'tumbao.bca',
  PRECIO_SUELTA:'$15.000'
};
```

Es un archivo suelto sin build. Arrástralo a **Cloudflare Pages** (o Vercel,
o Netlify) y ya. Ese link va en la bio de Instagram.

---

## Qué está probado

Levanté un Postgres 16 real y un servidor que **ejecuta el código JS extraído de
los propios workflows** (no una reimplementación), y conduje la página con
Chromium.

Reproducible: `node pruebas/espejo-n8n.mjs` y `node pruebas/prueba-pagina.mjs`.

**Base de datos — 18 casos:**

- Reserva feliz, con código de 6 caracteres
- Reservar dos veces devuelve el **mismo** código (idempotente)
- `+57 300 123 4567`, `300 123 4567` y `3001234567` son la misma persona — no duplica cliente
- Sin autorización de datos → rechaza
- Celular de menos de 10 dígitos → rechaza
- Sesión inexistente, cancelada o ya empezada → rechaza
- Clase llena → `sin_cupo`
- **Condición de carrera:** dos transacciones simultáneas peleando el último
  cupo → una entra, la otra recibe `sin_cupo`, queda exactamente 1 reserva.
  Sin sobreventa.
- Cancelar con celular equivocado → no deja
- Cancelar libera el cupo; cancelar dos veces no rompe
- Volver a reservar tras cancelar reactiva la reserva con el código original
- Las tres migraciones son re-ejecutables

**Página — 18 casos:** carga de días, cambio de día, clases agotadas
deshabilitadas, validación de los tres campos obligatorios, flujo completo hasta
el código, doble envío, honeypot anti-bot, `409` de clase llena bien mostrado,
cero errores de JavaScript.

Dos bugs salieron de correr esto y quedaron corregidos: re-ejecutar el seed
duplicaba sesiones que ya tenían alumnos inscritos (arreglado con un índice
único), y la hora salía como `7:00 p. m.` y desbordaba la tarjeta en móvil.

---

## Qué necesito de ti

Esto es lo que me bloquea. Lo demás ya está.

1. **Enciende el conector de n8n en este chat.** Está instalado en tu cuenta
   pero apagado para esta conversación (`enabledInChat: false`), así que no pude
   crear los workflows directamente. Se activa en los ajustes de conectores del
   chat. Con eso encendido, los subo yo.

2. **Conecta Supabase.** No está instalado en tu cuenta — solo n8n, Notion,
   Gmail, Calendar, Canva y Drive. Se agrega desde claude.ai. Si ya tienes un
   proyecto de Supabase para Beat, dime y uso ese.

3. **El horario real de Tumbao:** qué clases, qué días, a qué hora, con qué
   instructor y cuántos cupos por clase. Con eso reemplazo `003_seed_demo.sql`
   por el horario de verdad.

4. **La URL de tu n8n** (cloud o self-host).

5. **Decisión de negocio que asumí:** que se **aparta el cupo y se paga al
   llegar**, sin cobro en línea. Es lo más rápido de shippear y encaja con que
   hoy el 83% paga por transferencia. Si prefieres cobrar antes con QR Bre-B,
   dímelo — cambia el flujo.

6. **Autorización explícita para activar el WhatsApp de confirmación.** El nodo
   está construido pero **desactivado** en el workflow: manda mensajes a
   clientes reales, y eso es rojo en el framework. No lo enciendo sin que me lo
   digas, y antes hay que probarlo contra un número tuyo.

7. **Link a tu política de tratamiento de datos.** La página ya pide la
   autorización de habeas data (Ley 1581) y no guarda a nadie sin ella, pero el
   texto debería enlazar a tu política publicada.

---

## Límites conscientes

Cosas que **no** están y que no son descuidos:

- **Sin cobro en línea.** Ver punto 5 arriba.
- **Sin login.** El alumno se identifica por celular. Para cancelar necesita su
  código + su celular. Suficiente para una academia; no es un banco.
- **Sin rate limiting.** Hay un honeypot que corta bots simples, pero un ataque
  dirigido podría llenar clases con reservas falsas. Si pasa, la solución es
  Cloudflare Turnstile en el formulario — media hora de trabajo, pero no vale la
  pena antes de tener tráfico real.
- **Sin recordatorio antes de clase.** Es un workflow aparte (cron), fácil de
  añadir cuando el WhatsApp esté autorizado.
- **Sin panel para la recepcionista.** Hoy vería las reservas en Supabase.
  El check-in contra el código es lo siguiente natural, y ya encaja con el
  modelo de datos de Beat.
- **`asistencias`, `pagos`, `membresías` y `caja` no están.** Este proyecto es
  solo la reserva. El schema usa los mismos nombres del modelo de datos de Beat
  en Notion, así que esas tablas se agregan encima sin migrar nada de esto.
