# Cómo poner esto en línea

> **Estado a 28 de julio de 2026: la base ya está lista y probada contra
> los servicios reales.** El SQL está aplicado, hay 50 clases cargadas
> hasta el 15 de agosto, y los 65 afiliados activos están importados desde
> `Afiliados activos 2026-07-27.xlsx`, así que los cupos de clase suelta
> son los reales: el martes quedan 11 a las 7am, 3 a las 6pm y 11 a las
> 7pm; el sábado 30, porque nadie tiene plan de sábado.
>
> **Lo único que falta es encender GitHub Pages** — un ajuste de una sola
> vez. Ver "Publicar las páginas" más abajo.
>
> El paso de abajo ya está hecho; queda documentado por si hay que
> reconstruir la base desde cero.

---

## El primer paso (ya hecho)

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

## Publicar las páginas — un ajuste de una sola vez

Las dos páginas ya están listas en la carpeta `docs/` del repo, que es
justo donde GitHub Pages las busca. Falta encenderlo. Es una vez y nunca
más:

1. Ve a **https://github.com/damian3314-arch/ProjectosClaude/settings/pages**
2. En **Source**, deja **Deploy from a branch**.
3. En **Branch**, elige `claude/tumbao-reservas-n8n-831zit`.
4. En la carpeta de al lado, elige **`/docs`**.
5. **Save**.

En un par de minutos quedan en línea:

| | URL |
|---|---|
| **Reservas** — esta es la que se comparte | https://damian3314-arch.github.io/ProjectosClaude/ |
| **Panel** | https://damian3314-arch.github.io/ProjectosClaude/admin.html |

**Se actualiza solo.** Sirviendo desde la rama, cada vez que se suba un
cambio a `docs/` la página se republica sola. No hay que volver a tocar
nada.

> Se intentó automatizar esto con GitHub Actions para que no tuvieras que
> hacer ni ese clic, pero el token de Actions no tiene permiso para *crear*
> el sitio de Pages (`Resource not accessible by integration`). Servir
> directo desde la rama evita ese permiso por completo, y de paso no
> depende de que Actions funcione.

Se eligió GitHub Pages y no Cloudflare porque el repo ya es público, sale
gratis, y queda en línea hoy en vez de esperar a montar dominio y DNS.

### Sobre la seguridad del panel

El panel queda en una URL pública y **no tiene sentido esconderlo en una
ruta rara**: el repo es público, así que cualquiera puede leer el código y
encontrar la ruta. Eso no es un descuido, es una consecuencia de tener el
repo abierto.

La defensa real es el token: 32 bytes aleatorios, guardado hasheado, y
verificado por Postgres en cada una de las seis funciones. Sin él, todas
responden 401 y no devuelven ni un dato. Es suficiente. Pero conviene
saberlo en vez de creer que hay una ruta secreta.

### Cuando quieras el dominio propio

Cloudflare Pages conectado a este mismo repo, apuntando a
`docs`. Ahí sí tiene sentido `reservas.tumbao.com` o lo que
elijas, y de paso puedes poner el panel en un subdominio aparte con
Cloudflare Access delante si quieres una segunda puerta además del token.

La URL de n8n ya está puesta dentro de cada archivo. Si el dominio de n8n
cambia, se cambia ahí y en ningún otro lado.

---

## Lo que ya está hecho y publicado en n8n

| Workflow | Estado |
|---|---|
| `Tumbao · API de reservas` | **activo** — 4 webhooks, miembro vs. clase suelta |
| `Tumbao · Panel de admin` | **activo** — 6 webhooks |
| `Tumbao · Ingesta de pagos` | **activo** — lee las alertas del banco |
| `Tumbao · Importar afiliados y recalcular cupos` | **activo** — 9:30 pm y 8:00 am |

Los cuatro corriendo y probados contra los servicios reales. La última
importación trajo los 65 afiliados activos (19 a las 7am, 27 a las 6pm,
19 a las 7pm) y ajustó los cupos de 28 clases.

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
- [x] ~~Definir qué da MEDIA MENSUALIDAD~~ — resuelto: cuenta como plan
      completo, puede entrar entre semana igual que la mensualidad. El
      código ya lo hacía así.

---

## Probar sin tocar nada real

```bash
node pruebas/espejo-api.mjs          # imita los 10 webhooks
node pruebas/prueba-pagina.mjs       # la página pública, los dos caminos
node pruebas/prueba-admin.mjs        # el panel entero
```

> **Ojo con lo que el espejo NO prueba.** `espejo-api.mjs` reimplementa el
> contrato de la API en Node; no ejecuta el código que corre dentro de
> n8n. Prueba la página, no el workflow. Por eso pasó desapercibido que
> tres nodos Code estaban en un modo donde `$input.first()` está
> prohibido: la página estaba bien, el workflow no. Los chequeos de texto
> (`modo-code-n8n.mjs`, `sin-delete-sin-where.mjs`) existen para tapar ese
> hueco, pero la prueba definitiva sigue siendo reservar de verdad.
>
> El mismo hueco tumbó el panel una segunda vez: el espejo devolvía la
> fecha de cada día como `2026-07-28`, y Supabase la devolvía como
> `2026-07-28T00:00:00+00:00`. La página se caía con *Invalid time
> value* y el error salía en el login, como si el token estuviera mal.
> Ahora se puede correr la suite del panel contra la forma fea:
>
> ```bash
> FECHA_FEA=1 node pruebas/espejo-api.mjs
> node pruebas/prueba-admin.mjs          # tiene que pasar igual
> ```
>
> Y `humo-admin.sql` comprueba, en tres zonas horarias, que la fecha que
> sale de `admin_semana` es `AAAA-MM-DD` pelado.

El camino de validación humana (cuando el correo del banco no llega):

```bash
NUNCA_LLEGA=1 MINUTOS_ESPERA=0.15 node pruebas/espejo-api.mjs
node pruebas/prueba-validacion-humana.mjs
```

Las funciones de Postgres, contra una base local:

```bash
psql -d tumbao -f pruebas/humo-supabase.sql
psql -d tumbao -f pruebas/humo-admin.sql
psql -d tumbao -f pruebas/humo-historico.sql
```

Y los chequeos que no necesitan nada corriendo:

```bash
node pruebas/parser-afiliados.test.mjs   # lee el xlsx de afiliados
node pruebas/elegir-reporte.test.mjs     # cuál archivo de Drive tomar
node pruebas/parser.test.js              # correos del banco
node pruebas/sin-delete-sin-where.mjs    # trampa de Supabase
node pruebas/modo-code-n8n.mjs           # trampa de n8n
```

---

## La rutina diaria

Solo hay que hacer una cosa cada día, y es guardar el archivo bien
nombrado en la carpeta de reportes:

```
Afiliados activos AAAA-MM-DD.xlsx
```

Por ejemplo `Afiliados activos 2026-07-28.xlsx`. La fecha al final, con
año-mes-día. Nada más: a las 9:30 pm y otra vez a las 8:00 am la
automatización lo busca, lo importa y recalcula los cupos sola.

El cierre de caja sigue guardándose como siempre (`28-07-2026.xlsx`) en la
misma carpeta. No se estorban: la automatización de afiliados exige el
prefijo `Afiliados`, así que nunca va a agarrar un cierre por error.
