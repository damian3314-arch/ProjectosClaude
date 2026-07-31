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
| `Tumbao · Panel de admin` | **activo** — 10 webhooks |
| `Tumbao · Ingesta de pagos` | **activo** — lee las alertas del banco |
| `Tumbao · Importar afiliados y recalcular cupos` | **activo** — 9:30 pm y 8:00 am |
| `Tumbao · Leer comprobante` | **activo** — ⚠️ le falta la credencial de OpenAI |

Corriendo y probados contra los servicios reales. La última importación
trajo los 65 afiliados activos (19 a las 7am, 27 a las 6pm, 19 a las 7pm)
y ajustó los cupos de 28 clases.

### La lectura del comprobante

`Tumbao · Leer comprobante` recibe la captura que sube el cliente y
devuelve **hora, referencia, quién pagó y el valor** para autocompletar
los campos. Le falta una cosa para que funcione:

> **Crea una credencial de tipo OpenAI en n8n y ponla en el nodo
> `OpenAI: leer el comprobante`.** Sin ella el workflow responde igual,
> con todo en null, y la página le pide los datos a mano a la persona —
> no se cae, pero tampoco autocompleta nada. Comprobado.

Tres cosas que conviene tener claras:

- **La imagen sale del celular.** Antes se leía el QR dentro del
  navegador y no salía nada; se cambió porque el QR **nunca trae la
  hora**, que es justo el dato con el que se casa el pago. La página lo
  dice tal cual: *"se usa solo para leer esos datos y no se guarda"*.
- **Y no se guarda, de verdad.** En Settings de ese workflow, guardar
  ejecuciones está en **Do not save** a propósito. Si alguien lo
  enciende, n8n empieza a guardar el cuerpo del webhook —o sea, la
  imagen— en el historial, y esa frase de la página deja de ser cierta.
- **Ante la duda, null.** El prompt insiste en no adivinar y el nodo que
  normaliza vuelve a validar todo. Una hora inventada cruza el pago con
  el equivocado; un null solo hace que la persona la escriba.

Cuesta unos centavos por comprobante. Si algún día molesta, el nodo se
puede cambiar por otro proveedor sin tocar la página: el contrato es
`{ ok, hora, referencia, pagador, valor }`.

`Tumbao · Explorar archivo de planes` fue temporal, para ver el formato del
reporte de Drive. Se puede borrar.

---

## Qué hace el panel

**Pestaña Tablero.** Es donde cae quien entra. Un día a la vez, con cinco
cifras arriba (cupos libres, cuánta gente entra, reservas, por validar y lo
cobrado) y una tarjeta por clase con el desglose: aforo, gente con plan, lo
que queda a la venta y lo reservado. La barra separa los dos grupos que
llenan la sala — los que tienen plan y los que compraron suelta — sobre el
aforo.

En la tarjeta de cada clase, si hay planes que se acaban ese día, sale un
aviso punteado:

> ⌛ **2** con plan vencen este día

Una mensualidad que termina hoy sigue contando hoy: su puesto está
descontado del aforo. Correcto — pero esa persona puede no venir, y si no
viene tampoco renueva, y se guardó un puesto que nadie usó. Con ese número
puedes **arriesgarte a vender hasta esa cantidad de sueltas de más**,
sabiendo exactamente cuánto arriesgas.

**No se suma al cupo a propósito.** Es una apuesta, no un cupo: si los dos
aparecen —y la gente suele renovar el último día— y encima vendiste dos
sueltas, la sala queda apretada. La decisión la tomas tú con el número
delante.

**El sábado, además, sale el reparto:**

> **11** de 15 afiliados · **9** de 15 sueltas

El aforo del sábado va partido en dos cupos independientes. Aquí sí se
muestra, porque es lo único que explica el número de libres de arriba. El
cliente no lo ve — ver más abajo.

Solo lee: desde aquí no se cambia nada. Para eso están las otras dos
pestañas.

> Necesita `supabase/aplicar/PEGAR_TABLERO.sql` aplicado. Sin eso, esta
> pestaña sale en rojo y las otras dos siguen funcionando igual.

**La lista de la puerta.** Toca cualquier tarjeta de clase en el Tablero y se
abre quién entra a esa clase. Es la respuesta a *"llega alguien y dice yo
reservé, ¿dónde miro?"*.

Trae **dos grupos**, y esto es lo importante:

| | reserva | por qué está en la lista |
|---|---|---|
| **Reservaron** | sí | compraron clase suelta |
| **Con plan de esta hora** | no | su puesto ya salió del aforo, solo llegan |

Con solo las reservas estarías mirando 3 nombres de las 30 personas que van a
entrar. El sábado el segundo grupo va vacío: ahí nadie tiene plan y todos
reservan.

Arriba, un contador de *N de M entraron* y un buscador por nombre, código o
celular. Cada persona tiene un botón grande de **Marcar / ✓ Entró**, que se
puede quitar si fue un error. Marcar dos veces no cuenta dos personas — en la
puerta se dan clics repetidos y con prisa.

Cada persona a la que se le acaba el plan ese día sale marcada con
**⌛ vence hoy**. Está enfrente tuyo: es el mejor momento que vas a tener
para renovarla, sin llamar a nadie.

Las reservas que aún no concilian **también salen**, con un aviso de *sin
confirmar* al lado: alguien puede plantarse en la puerta con el pago hecho
hace dos minutos. Las rechazadas no salen.

> Necesita `supabase/aplicar/PEGAR_PUERTA.sql`. La asistencia se guarda en una
> tabla aparte a propósito: `membresias` se borra entera cada noche, y lo que
> ya pasó por la puerta no puede irse con ella.

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
banco no llegó en 3 minutos, o llegaron dos pagos iguales. Cada tarjeta trae
los pagos sin dueño de ese valor cerca de esa hora, con un **% de parecido**
del nombre. Le das *Es este* al que corresponda, o *Confirmar igual* si te
consta. Después queda un botón para escribirle por WhatsApp con el mensaje ya
redactado.

La cola viene **agrupada por horario**, para que se vea de un golpe quién
viene a las 6 y quién a las 7, y arriba hay un **buscador** por nombre,
código o celular. Ignora tildes y mayúsculas: en el mostrador nadie escribe
"Velásquez" con el acento puesto. Si son puros números, busca por celular.
El contador de la pestaña no se mueve al filtrar — es cuánto trabajo queda,
no cuánto se está viendo.

**Deshacer.** Confirmar y rechazar están uno al lado del otro, y la duda llega
medio segundo después del clic. La tarjeta ya resuelta trae un botón
**↩ Deshacer** con el plazo que queda; la reserva vuelve a la cola tal como
estaba, con sus pagos candidatos y sus dos botones.

Tres candados, a propósito:

- Solo lo que resolvió una persona desde el panel. Lo que concilió solo el
  sistema no se toca desde ahí.
- Solo dentro de los **15 minutos** siguientes. Pasado eso ya no es un
  resbalón, y a la persona probablemente ya se le avisó por WhatsApp.
- Una sola vez.

Lo único que puede no poder hacer: si deshaces un **rechazo** y mientras
tanto alguien compró ese cupo, se niega y te lo dice. Antes de sobrevender,
prefiere quedarse quieto — la salida es subir el cupo a mano en Horario.

> Necesita `supabase/aplicar/PEGAR_DESHACER.sql` aplicado. Sin eso el botón
> sencillamente no aparece y el resto sigue igual.

---

### El sábado: 15 y 15, sin que se note

El aforo del sábado está partido: **15 puestos para afiliados y 15 para
clase suelta**, independientes. Cuando se llenan los 15 de plan no entra
ningún afiliado más aunque queden sueltas libres, y al revés.

**El cliente no se entera, y no porque se le esconda.** La página ya sabe
quién está mirando: lo primero que pregunta es *"¿vienes con mensualidad o
por clase suelta?"*. Así que a cada quien se le contesta el número de **su**
lado. Los del otro lado ni siquiera salen del servidor, así que no hay nada
que encontrar mirando la respuesta — la prueba lo comprueba clave por clave.

Cuando un lado se llena, el mensaje es el de siempre —*"Esa clase se
llenó"*— justo para no delatar el reparto.

**Entre semana no cambia nada**: ahí el afiliado ni siquiera reserva, su
puesto ya está descontado del aforo.

Si mañana quieres 20 y 10, es un número guardado, no una fórmula:

```sql
update clases set cupo_miembros = 20, cupo_sueltas = 10
 where extract(dow from fecha_hora at time zone 'America/Bogota') = 6
   and fecha_hora > now();
```

(y cambia el `/ 2` de `generar_horario` para los sábados que se creen
después)

---

## Antes de cobrarle a alguien de verdad

- [x] ~~Cambiar la ingesta al correo de Tumbao~~ — hecho. Verificado el 29 de
      julio de 2026 leyendo la cabecera `Delivered-To` de un correo que el
      workflow acababa de procesar: **`bailatumbao@gmail.com`**. La credencial
      que lo hace es `Gmail OAuth2 API`.
- [ ] Borrar los **pagos de prueba** de la tabla `pagos`. Hay al menos dos de
      $1.000 a nombre de Damián, del 26 y del 29 de julio, los dos con
      `sin_reserva_que_casar`. Están en `supabase/aplicar/LIMPIAR_PRUEBAS.sql`,
      que primero muestra y solo borra si descomentas la parte 2.
- [ ] **Renombrar las credenciales de Gmail.** En este n8n conviven dos y los
      nombres no dicen nada: `Gmail OAuth2 API` es la de Tumbao y
      `Gmail account` es la de **Joyería** (`joyeriataller5@gmail.com`). Si
      alguien elige la equivocada en el nodo del trigger, la ingesta se queda
      leyendo un buzón donde nunca va a llegar una alerta del banco: no falla,
      no avisa, simplemente deja de conciliar. Ponerles el correo en el nombre
      cuesta un minuto y cierra el agujero.
- [ ] Los nodos que mandan WhatsApp automáticamente están **desactivados** a
      propósito. Desde el panel sí se manda, pero a mano y uno por uno.
- [x] ~~Definir qué da MEDIA MENSUALIDAD~~ — resuelto: cuenta como plan
      completo, puede entrar entre semana igual que la mensualidad. El
      código ya lo hacía así.

---

## Probar sin tocar nada real

```bash
node pruebas/espejo-api.mjs          # imita todos los webhooks
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
psql -d tumbao -f pruebas/humo-aviso-pago.sql
psql -d tumbao -f pruebas/humo-aforo.sql
psql -d tumbao -f pruebas/humo-tablero.sql
psql -d tumbao -f pruebas/humo-deshacer.sql
psql -d tumbao -f pruebas/humo-puerta.sql
psql -d tumbao -f pruebas/humo-vencen.sql
psql -d tumbao -f pruebas/humo-sabado-partido.sql
```

Y las dos carreras, que son las únicas que prueban lo que solo se rompe
con varias personas dándole al botón a la vez:

```bash
node pruebas/carrera-cupos.mjs     # 12 personas por 4 cupos
node pruebas/carrera-sabado.mjs    # 20 y 20 contra el reparto 15/15
```

La lectura del comprobante se prueba en sus tres caminos, y el que más
importa es el segundo:

```bash
node pruebas/espejo-api.mjs                     # lee bien
LECTURA_VACIA=1 node pruebas/espejo-api.mjs     # no saca nada
LECTURA_OTRO=1  node pruebas/espejo-api.mjs     # pagó otra persona
# y la misma variable al correr prueba-comprobante.mjs
```

`LECTURA_VACIA` es el camino que va a pasar seguido —bancos raros,
capturas recortadas, o simplemente que falte la credencial— y ahí la
persona tiene que poder escribir los datos y seguir como si nada.

Las suites de navegador se pueden correr varias veces seguidas contra el
mismo espejo: `prueba-admin.mjs` lo devuelve al estado inicial antes de
empezar (`GET /_prueba/reiniciar`). Sin eso, la segunda corrida arrancaba
sobre los restos de la primera y fallaba por cosas que no tenían nada que
ver con el código.

El de deshacer es el que hay que mirar si se toca la cola de validación:
comprueba que restaura el estado exacto, que el cupo vuelve, que el pago se
suelta, y —lo que de verdad importa— que **no sobrevende** cuando el cupo ya
se vendió mientras se dudaba.

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
