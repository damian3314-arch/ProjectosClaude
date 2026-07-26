# Cómo poner esto en línea

**Un solo pegue en Supabase. Nada más.**

---

## El único paso

1. Entra a **supabase.com** y abre tu proyecto.
2. En el menú de la izquierda busca el ícono de **SQL Editor** (dice `SQL`).
3. Dale a **+ New query**.
4. Abre el archivo `supabase/aplicar/PEGAR_EN_SUPABASE.sql`, **selecciona
   todo** (Ctrl+A / Cmd+A), cópialo, y pégalo en ese cuadro.
5. Dale **Run** (o Ctrl+Enter).

Abajo te va a salir una tabla así:

| paso | detalle |
|---|---|
| 1. Horario | 51 clases cargadas (proximas 3 semanas) |
| 2. Cupos | Calculados… |
| **3. TU TOKEN DEL PANEL — copialo ya** | `wef2D6UQ...` |

**Copia ese token de una.** Es la clave para entrar al panel y no se puede
volver a ver — lo que queda guardado en la base es solo un hash.

Eso es todo. El archivo hace las tres cosas juntas: crea lo que falta en la
base, carga el horario de las próximas 3 semanas, y emite el token.

**Se puede correr las veces que quieras.** No duplica clases ni emite tokens
de más. Si algo sale mal a mitad, vuelve a darle Run.

### Si perdiste el token

```sql
select crear_token_admin('Tania');
```

Se emiten los que quieras (uno por persona, así se sabe quién es quién).
Para revocar uno:

```sql
update admin_tokens set activo = false where nombre = 'Kevin';
```

---

## Después: publicar las dos páginas

`web/index.html` (la pública) y `web/admin.html` (el panel) son archivos
sueltos, sin build ni dependencias. Sirve cualquier hosting estático —
Cloudflare Pages, Netlify, GitHub Pages. Subes los dos `.html` y la carpeta
`web/img/`.

La URL de n8n ya está puesta dentro de cada archivo. Si el dominio de n8n
cambia, se cambia ahí y en ningún otro lado.

> El panel lleva `noindex` y el token no viaja en la URL, pero **ponlo en una
> ruta que no sea adivinable** (`/panel-a7f3/` en vez de `/admin.html`). Quien
> tenga el token entra; el token es la única puerta.

---

## Lo que ya está hecho y publicado en n8n

| Workflow | Estado |
|---|---|
| `Tumbao · API de reservas` | **activo** — 4 webhooks, miembro vs. clase suelta |
| `Tumbao · Panel de admin` | **activo** — 6 webhooks |
| `Tumbao · Ingesta de pagos` | **activo** — lee las alertas del banco |
| `Tumbao · Importar afiliados y recalcular cupos` | **activo** — 9:30 pm y 8:00 am |

Los dos últimos van a fallar hasta que hagas el pegue de arriba, porque
llaman funciones que todavía no existen en la base. Es ruido esperado.

`Tumbao · Explorar archivo de planes` fue temporal, para ver el formato del
reporte de Drive. Se puede borrar.

---

## Qué hace el panel

**Pestaña Horario.** Una columna por día. En cada clase:

- El **interruptor** la prende o la apaga. Una clase con gente adentro no se
  apaga — el panel avisa en vez de dejar a alguien colgado.
- La **casilla del cupo** es lo que queda para clase suelta. Vacía = se
  calcula solo (aforo − gente con plan a esa hora). Con un número = ese manda,
  y la automatización nocturna ya no lo pisa. No deja bajarlo por debajo de lo
  que ya se reservó.
- Abajo de cada día, **una hora nueva**: para abrir una clase fuera del molde
  de siempre.

Los cambios se acumulan y se guardan todos juntos con el botón de abajo.

**Pestaña Por validar.** La cola de lo que no concilió solo: o el correo del
banco no llegó en 5 minutos, o llegaron dos pagos iguales. Cada tarjeta trae
los pagos sin dueño de ese valor cerca de esa hora, con un **% de parecido**
del nombre. Le das *Es este* al que corresponda, o *Confirmar igual* si te
consta. Después queda un botón para escribirle por WhatsApp con el mensaje ya
redactado.

---

## Antes de cobrarle a alguien de verdad

- [ ] El workflow de ingesta hoy lee el **correo personal de Damián**, que fue
      lo que se usó para probar. Hay que cambiarle la credencial de Gmail a la
      cuenta de Tumbao y borrar los pagos de prueba de la tabla `pagos`.
- [ ] Los nodos que mandan WhatsApp automáticamente están **desactivados** a
      propósito. Desde el panel sí se manda, pero a mano y uno por uno.
- [ ] Falta definir qué da **MEDIA MENSUALIDAD**: ¿acceso a todas las clases
      de su hora, o a la mitad? Hoy se cuentan como plan completo, y son 15 de
      61 personas.

---

## Probar sin tocar nada real

```bash
node pruebas/espejo-api.mjs          # imita los 10 webhooks
node pruebas/prueba-pagina.mjs       # la página pública, los dos caminos
node pruebas/prueba-admin.mjs        # el panel entero
```

El camino de validación humana (cuando el correo del banco no llega):

```bash
NUNCA_LLEGA=1 MINUTOS_ESPERA=0.15 node pruebas/espejo-api.mjs
node pruebas/prueba-validacion-humana.mjs
```

Las funciones de Postgres, contra una base local:

```bash
psql -d tumbao -f pruebas/humo-supabase.sql
psql -d tumbao -f pruebas/humo-admin.sql
```
