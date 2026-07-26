# Cómo poner esto en línea

**Falta un solo paso tuyo: pegar un SQL en Supabase.** Todo lo demás ya está
hecho y publicado. Mientras ese SQL no esté, nada funciona — la base todavía
no tiene las funciones que la página y el panel llaman.

---

## 1. Pegar el SQL en Supabase ← esto es lo único pendiente

Supabase → **SQL Editor** → New query → pegar todo el contenido de:

```
supabase/aplicar/0007-0011_todo_junto.sql
```

→ **Run**.

Se puede correr dos veces sin romper nada (está probado desde cero, dos
pasadas seguidas). Qué agrega:

| | |
|---|---|
| 0007 | compara nombres, para saber quién pagó cuando hay dos pagos iguales |
| 0008 | usa esa comparación al conciliar |
| 0009 | cupos sueltos = aforo − gente con plan activo a esa hora |
| 0010 | separa reserva de miembro y de clase suelta, e importa afiliados |
| 0011 | panel de admin: horario a mano, cupos forzados, y el check humano |

Para comprobar que quedó, en el mismo SQL Editor:

```sql
select proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and proname in
   ('importar_membresias','recalcular_cupos','generar_horario',
    'similitud_nombre','admin_semana','admin_confirmar');
```

Tienen que salir las seis.

## 2. Emitir tu token del panel

En el mismo SQL Editor:

```sql
select crear_token_admin('Tania');
```

Devuelve algo como `{"ok": true, "token": "xK3n..."}`. **Ese token se ve una
sola vez** — lo que se guarda en la base es solo un hash. Cópialo y guárdalo
donde guardes las claves. Si se pierde, no se recupera: se emite otro y ya.

Con ese token entras al panel. Cada persona que vaya a usarlo debería tener
el suyo (`crear_token_admin('Kevin')`, etc.), así se sabe quién es quién y se
puede revocar uno solo:

```sql
update admin_tokens set activo = false where nombre = 'Kevin';
```

## 3. Cargar el horario

Sin esto la página no muestra nada, porque la tabla `clases` está vacía. Dos
formas:

**Desde el panel** (recomendado): abres `admin.html`, te paras en la semana
y vas abriendo las horas una por una. Sirve para semanas raras — festivos,
una clase extra, un horario distinto.

**De un golpe, para las próximas dos semanas:**

```sql
select generar_horario(current_date, current_date + 13);
```

Genera lunes a viernes 7:00 am, 6:00 pm y 7:00 pm, y sábado 8:00 am y
9:00 am. Domingo no. Aforo 30 y precio $15.000.

Después, en n8n, dale **Execute** una vez al workflow *Tumbao · Importar
afiliados y recalcular cupos* para que los cupos dejen de ser 30 y pasen a
ser los reales.

## 4. Publicar las dos páginas

`web/index.html` (público) y `web/admin.html` (panel) son archivos sueltos,
sin build ni dependencias. Sirve cualquier hosting estático — Cloudflare
Pages, Netlify, GitHub Pages. Hay que subir los dos `.html` y la carpeta
`web/img/`.

La URL de n8n ya está puesta en el bloque `CONFIG` de cada archivo. Si el
dominio de n8n cambia, se cambia ahí y en ningún otro lado.

> El panel lleva `noindex` y el token no viaja en la URL, pero **ponlo en una
> ruta que no sea adivinable** (`/panel-a7f3/` en vez de `/admin.html`). Quien
> tenga el token entra; el token es la única puerta.

---

## Lo que ya está hecho y publicado

| Workflow n8n | Estado |
|---|---|
| `Tumbao · API de reservas` | **activo** — 4 webhooks, ya con miembro vs. clase suelta |
| `Tumbao · Panel de admin` | **activo** — 6 webhooks |
| `Tumbao · Ingesta de pagos` | **activo** — lee las alertas del banco |
| `Tumbao · Importar afiliados y recalcular cupos` | **activo** — 9:30 pm y 8:00 am |

Ojo: los dos últimos van a fallar hasta que apliques el SQL del paso 1,
porque llaman funciones que todavía no existen. Es ruido esperado, no algo
roto.

`Tumbao · Explorar archivo de planes` fue temporal, para ver el formato del
reporte de Drive. Se puede borrar.

---

## Qué hace el panel

**Pestaña Horario.** Una columna por día de la semana. En cada clase:

- El **interruptor** la prende o la apaga. Una clase con gente adentro no se
  apaga — el panel avisa en vez de dejar a alguien colgado.
- La **casilla del cupo** es lo que queda para clase suelta. Vacía = se
  calcula solo (aforo − gente con plan a esa hora). Con un número = ese manda,
  y `recalcular_cupos` ya no lo pisa. No deja bajarlo por debajo de lo que ya
  se reservó.
- Abajo de cada día, **una hora nueva**: para abrir una clase que no está en
  el molde de siempre.

Los cambios se acumulan y se guardan todos juntos con el botón de abajo.

**Pestaña Por validar.** La cola de lo que no concilió solo: o el correo del
banco no llegó en 5 minutos, o llegaron dos pagos iguales. Cada tarjeta trae
los pagos sin dueño de ese valor cerca de esa hora, con un **% de parecido**
del nombre. Le das *Es este* al que corresponda, o *Confirmar igual* si te
consta. Después queda un botón para escribirle por WhatsApp con el mensaje ya
redactado.

Esto es la parte del flujo que decías desde el principio — "el humano da el
check y le envía un mensaje por WhatsApp" — y hasta ahora no existía: las
reservas caían en `pendiente_validacion` y se quedaban ahí para siempre.

---

## Antes de cobrarle a alguien de verdad

- [ ] El workflow de ingesta hoy lee el **correo personal de Damián**, que fue
      lo que se usó para probar. Hay que cambiarle la credencial de Gmail a la
      cuenta de Tumbao y borrar los pagos de prueba de la tabla `pagos`.
- [ ] Los nodos que mandan WhatsApp automáticamente están **desactivados** a
      propósito. Desde el panel sí se manda, pero a mano y uno por uno.
- [ ] Falta definir qué da **MEDIA MENSUALIDAD**: ¿acceso a todas las clases
      de su hora, o a la mitad? Hoy se cuentan como plan completo, y son 15 de
      61 personas. Si en realidad vienen día por medio, estamos ofreciendo
      menos cupos sueltos de los que se podrían vender.

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

Y las funciones de Postgres, contra una base local:

```bash
psql -d tumbao -f pruebas/humo-supabase.sql
psql -d tumbao -f pruebas/humo-admin.sql
```
