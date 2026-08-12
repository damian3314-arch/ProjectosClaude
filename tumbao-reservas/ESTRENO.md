# Salir a producción — lista de verificación

Escrito el 8 de agosto de 2026, antes del estreno con clientes reales en
`tumbaobaila.com`.

---

## 🔴 Lo que hay que hacer ANTES de abrirle a la gente

### 1. ~~Subir el reporte de afiliados~~ ✅ resuelto el 8 de agosto

`Afiliados activos 2026-08-08.xlsx` importado: **63 afiliados, 0
descartados, 15 clases recalculadas, 0 clases apretadas**.

El reparto que quedó vivo:

| Clase | Con plan |
|---|---|
| 7:00 am | 21 |
| 6:00 pm | 24 |
| 7:00 pm | 18 |

Y comprobado contra la página pública: el lunes 10 salen 12 libres a las
7 am, 6 a las 6 pm y 14 a las 7 pm. Los números cambian de un día a otro
porque las membresías vencen en fechas distintas y se descuentan solas.

**Lo que había pasado:** los reportes se guardan en una carpeta por mes
y el workflow apuntaba a la de julio. Ya no depende de la carpeta —
busca el archivo por nombre en todo el Drive, así que el 1 de septiembre
no se vuelve a romper.

**Sigue siendo el único paso manual del que dependen los cupos.** Cada
día hay que exportar de AdminGym y guardar en Drive con la fecha en el
nombre:

    Afiliados activos AAAA-MM-DD.xlsx

Vale que diga "afiliados" o "miembros", en cualquier carpeta, pero la
fecha va en ese orden: los cierres de caja usan `DD-MM-AAAA` y el
sistema los distingue por ahí. Si el archivo no trae fecha en el nombre,
se ignora y el error lo dice — ya pasó con `Afiliados activos.xls` y
`Afiliados 2.xls`, que siguen ahí sin usarse.

No se usa la fecha de subida de Drive a propósito: lo que importa es de
qué día son los datos, no cuándo se guardó. Un reporte de julio subido
hoy sigue teniendo datos de julio. Si pasan más de 7 días sin subir
nada, el import se frena en vez de vender cupos que no existen.

### 2. ~~Pegar el SQL~~ ✅ aplicado

Verificado contra la base el 11 de agosto: el corte de producción está en
`2026-08-08`, la cola de "Por validar" está en cero, `admin_pendientes`
filtra por el corte y `caja_del_dia` trae el control del banco **y** el
arreglo del doble conteo.

> El archivo `PEGAR_LISTO_PRODUCCION.sql` **se borró**. Reemplazaba
> `caja_del_dia` entera, y después de aplicarlo otra sesión arregló un
> doble conteo de plata dentro de esa misma función. Volver a pegarlo lo
> habría deshecho en silencio. Ver `aplicar/LEEME-ANTES-DE-PEGAR.md`.

### 2b. ~~El panel gastaba n8n por clic~~ ✅ resuelto el 11 de agosto

Medido: **483 ejecuciones del workflow del panel en 24 horas**, contra un
plan de 2.500 al mes. Cinco días de vida. Y al agotarse no caía solo el
panel: la página pública reserva por n8n también, así que un cajero
repasando el tablero podía dejar sin reservar a los clientes.

Las nueve rutas del panel se movieron al Worker `tumbao-caja`, que ya
tenía el secreto y el CORS configurados — por eso no hubo nada que
configurar. Ahí caben 100.000 peticiones diarias y no cuestan nada.

El workflow `Tumbao · Panel de admin` se deja **activo a propósito**: un
webhook en reposo no gasta nada, y si a alguien le quedó la página vieja
abierta en el celular, sus clics siguen funcionando en vez de dar 404.
Se puede apagar cuando lleve un día sin recibir llamadas.

### 2c. ~~Pegar `aplicar/PEGAR_ESTA_NOCHE.sql`~~ ✅ aplicado el 11 de agosto

0031 (abrir/cerrar la caja de verdad) y 0032 (cruzar los pagos también
desde el lado de la reserva). Verificado: `admin_pendientes` ya devuelve
`pagos_libres`.

### 2e. Pegar `aplicar/PEGAR_12_AGOSTO.sql` ⬅ pendiente

Trae las tres cosas del 12 de agosto, en orden: el arreglo del choque de
nombres (2d, que quedó sin pegar), varios cupos con un solo pago, y
"pagó y no vino". Probado contra el estado exacto de producción
(0001..0032 + el archivo), idempotente, y **sin tocar ni una reserva de
las que ya existen**: todo lo nuevo son columnas que nacen vacías, y una
reserva de una sola persona se comporta igual que hasta ahora.

Reemplaza a `PEGAR_UN_SOLO_CRUCE.sql`, que va incluido dentro.

**Varios cupos.** En la página, al elegir clase suelta hay un contador.
Subirlo pide un nombre por persona —un solo celular y correo— y el total
a pagar sale del contador. El banco busca ese total. Las seis son seis
filas distintas (cada una entra por la puerta por separado) pero un solo
grupo, con un solo pago.

- El contador se frena en los cupos que quedan en esa clase: el error se
  evita en vez de explicarse.
- O entran todos o no entra ninguno. Medio grupo sería lo peor: cupos
  ocupados que nadie va a usar y un cobro que no cuadra con nada.
- Tope de 8. No es una regla de negocio, es un freno: sin él un cero de
  más en el contador se lleva la clase entera.
- En "Por validar" un grupo es UNA tarjeta, con los nombres de los demás
  y el precio del grupo.

**Reserva de a uno: intacta.** Sigue yendo por el webhook de n8n de
siempre. Solo el camino de varios pasa por el Worker. Por ahí entra casi
todo, funciona, y este cambio no tiene por qué poder romperlo.

**Pagó y no vino.** En la lista de la puerta, junto a quien está
confirmado, un botón "No vino". No suelta el cupo ni mueve la plata —esa
clase está cobrada y la caja de hoy cuadra con ella— sino que abre un
crédito de 3 días, contados desde la clase que se perdió. Sale en la
pestaña nueva "Por disfrutar", ordenada por lo que vence primero, con un
desplegable para moverla a otra clase sin volver a cobrar. Reprogramar no
sobrevende: si la clase nueva está llena, rebota.

Al vencer se cae de la lista pero **no se borra nada**: si alguien
reclama en una semana, se puede mirar qué pasó.

### 2d. ~~Pegar `aplicar/PEGAR_UN_SOLO_CRUCE.sql`~~ ⬅ incluido en 2e

Arregla un error del archivo anterior. **La 0032 creó una función
llamada `conciliar_reserva` sin ver que ya existía otra con ese nombre**
desde la 0004 — la que llama la barra de progreso de la página en cada
consulta de estado. No rompió nada (Postgres las distingue por el tipo
del argumento), pero PostgREST resuelve las sobrecargas por los nombres
de los parámetros que recibe, y basta uno de más para caer en la que no
era. Ya nos costó un 502 una vez. La nueva pasa a llamarse
`cruzar_reserva` y la sobrecarga se borra.

De paso, las dos comparten la misma búsqueda. **La vieja tenía su propia
copia con un bug real**: cuando encontraba varios depósitos parecidos al
nombre se llevaba uno cualquiera (`for update skip locked`, sin orden),
o sea que podía amarrarle a alguien la plata de otra persona.

Y la ventana se intenta dos veces: primero ±30 min alrededor de la hora
declarada, y si no hay nada, desde 15 min antes de reservar hasta 3 horas
después. Recoge a quien escribe mal la hora sin aflojar la regla de no
adivinar ante el empate.

**Nota sobre lo que dije el 11 de agosto:** afirmé que "solo una de cinco
consignaciones se cruzó sola". Es falso. Mirando `resuelta_por` en las
nueve reservas del día, **seis se cruzaron solas** y solo dos las resolvió
una persona — las dos sin depósito que las respaldara (una reserva
duplicada y un pago que entró por otro canal). El cruce inverso ya
existía en `conciliar_reserva(codigo)`; lo que pasa es que solo corre
mientras el cliente tiene la página abierta. La 0032 lo hace también del
lado del servidor, que es seguro adicional, no el arreglo de una avería.

### 3. Revocar los tokens de prueba

Se compartieron dos por chat para depurar:

- `aenqLp4JAoaBPIMcCzysoC0CA2opFHP9_UNEDVBHS1U`
- `_YYeMg1F0AzlsDYo10_WieZoblpfRSu2Ti_isOhAses`

```sql
update admin_tokens set activo = false
 where nombre in ('...');   -- mira primero: select id, nombre, activo from admin_tokens;
```

Y crear el de la recepcionista con su nombre, para que en el cierre se
sepa quién registró cada movimiento.

---

## 🟡 Conviene, pero no bloquea

- **Dos secretos del bot de opiniones**, los dos en Cloudflare →
  Workers → `tumbao-opina` → Settings → Variables → Add secret:

  | Secreto | Para qué | Sin él |
  |---|---|---|
  | `TOKEN_REPORTE` | leer lo que dice la gente en `/leer` | La página no abre y dice dónde ponerlo. **Lo que la gente cuenta se guarda igual**, solo que no hay dónde verlo. La llave la eliges tú; el enlace queda `opina.tumbaobaila.com/leer?token=LOQUEPUSISTE` |
  | `OPENAI_API_KEY` | que el bot converse de verdad y resuma | Sigue funcionando con las tres preguntas fijas y guarda todo, pero sin resumen, sin clasificar y sin detectar lo urgente. Sale marcado `(ensayo sin llave)` |

  Cuesta ~$0,004 por conversación con `gpt-4o-mini`. Una campaña de 40
  personas, menos de un dólar.

- **En la base del bot hay 9 conversaciones de prueba** (4 del 3 de
  agosto y 5 del 12, de comprobar que esto funciona). No estorban —las
  de un solo turno ni salen— pero si quieres las borro.

- **El token de Cloudflare** `cfat_VLRH…` sigue vivo con permisos de
  Pages y Workers. Si no se va a usar más, revocarlo.
- **Las dos credenciales de Gmail en n8n** se llaman parecido y una es de
  Joyería. Renombrarlas evita que alguien las cruce.
- **Datos de prueba en `pagos` y `caja_movimientos`** (los dos de $1.000,
  las notas "PRUEBA CLAUDE"). Con el corte ya no se ven, así que borrarlos
  es opcional. Si se quiere, está en `aplicar/LIMPIAR_PRUEBAS.sql` — pero
  léelo antes: borra de verdad.

---

## Cómo se comprueba que sigue en pie

Las pruebas no son decorativas: cada una existe porque algo se rompió.

```bash
cd tumbao-reservas/pruebas

# Base de datos: 12 pruebas de humo sobre Postgres
psql -d <base> -f humo-corte.sql        # el corte no esconde cupos vivos
psql -d <base> -f humo-banco.sql        # conciliación depósito por depósito
psql -d <base> -f humo-aforo.sql        # no se vende dos veces el mismo puesto
psql -d <base> -f humo-cruce.sql        # el cruce en las dos direcciones (37)
psql -d <base> -f humo-grupo.sql        # varios cupos con un solo pago (39)
psql -d <base> -f humo-disfrutar.sql    # pagó y no vino, y reprogramar

# Panel: navegador de verdad, haciendo clic
node espejo-api.mjs &       # el panel necesita el espejo en otra terminal
node prueba-admin.mjs       # tablero, puerta, horario, cola, "Es este"
node prueba-caja.mjs        # 53 comprobaciones
node prueba-apuntar.mjs     # 14
node prueba-varios.mjs      # el contador y los N nombres, en la página pública

# Sin navegador
node ../../tumbao-opina/pruebas/limpiar-transcripcion.test.mjs
node elegir-reporte.test.mjs      # qué archivo de afiliados se importa
node sin-delete-sin-where.mjs     # ningún DELETE/UPDATE sin WHERE
```

**Dos están rojas y no es del código.** `humo-admin.sql` y
`humo-tablero.sql` construyen una semana con `admin_guardar_semana` y
después dan por hecho que ciertas horas siguen siendo futuras — una de
ellas crea una clase a las 5 pm. Corriéndolas por la tarde fallan, y
fallan por sitios distintos según la hora a la que se corran. Fallan
igual con y sin los cambios de hoy: se comprobó pegando y sin pegar. Hay
que anclarles la fecha, pero no bloquea nada.

---

## Lo que hay que mirar la primera semana

| Qué | Dónde | Qué significa si se tuerce |
|---|---|---|
| El reporte de afiliados importa | correo de fallos de n8n | Si falla, los cupos mienten |
| Consumo de n8n | panel de n8n | El plan son 2.500/mes. Con el panel fuera debería bajar a ~600-900 |
| "Sin identificar, de hoy" | pestaña Caja | Si no baja a cero, alguien pagó y no se registró |
| "Apuntado sin respaldo" | pestaña Caja | Transferencias que el banco no confirmó |
| Cola de "Por validar" | pestaña Por validar | Tiene que vaciarse cada día |

---

## Límites conocidos

- **Solo lee Bancolombia.** Un pago por Nequi o a otra cuenta no genera
  correo, así que aparece como "sin respaldo". No es un error del
  sistema: es que esa plata entró por un canal que nadie está leyendo.
  El 11 de agosto ya pasó: Nicole Arévalo quedó en la cola con su
  referencia `M10758771` y en Bancolombia no hay ni un depósito de
  $15.000 a esa hora. Por ahí no entró.
- **Dos personas que paguen el MISMO valor en el MISMO minuto se
  registran como un solo depósito.** El índice `pagos_unicos` es
  `(banco, valor, fecha_pago, referencia)`, y `referencia` viene siendo
  la llave Bre-B de la cuenta de Tumbao — la misma en todos los correos.
  La fecha llega con precisión de minuto. A las 6 pm, con varios de
  $15.000 seguidos, es cuestión de tiempo. El arreglo es dedupear por el
  id del correo de Gmail (`hoja_fila`, que ya se guarda), pero eso obliga
  a botar el índice actual: no se hizo hoy para no tocar dos cosas de la
  misma función la misma noche.
- **El parser reconoce cuatro formatos** de aviso de Bancolombia. Si el
  banco cambia el texto, el pago cae en "estructura_no_reconocida" y no
  entra. Conviene cuadrar contra el extracto los primeros días.
- **El cierre de AdminGym se sube a mano.** Nadie avisa si un día no se
  sube. Los cierres de julio dejaron de subirse el día 30; si ahora van a
  la carpeta del mes, bien, pero de eso no avisa nadie todavía.

---

## Lo que queda por hacer (nada bloquea el estreno)

En orden de lo que más se nota en el mostrador:

0. **Los duplicados del banco.** Dos personas que paguen el MISMO valor
   en el MISMO minuto se registran como un solo depósito — el índice
   `pagos_unicos` usa la llave Bre-B como referencia, y es la misma en
   todos los correos. A las 6 pm, con varios de $15.000 seguidos, es
   cuestión de tiempo. Ya se tropezó con esto escribiendo una prueba. El
   arreglo es dedupear por el id del correo de Gmail, que ya se guarda,
   pero obliga a botar el índice actual.

1. **Miembro con plan en otro horario.** Hoy `tomar_cupo` lo bloquea a
   propósito (`OTRO_HORARIO`, `PLAN_YA_CUBRE`). Antes de tocarlo hay que
   decidir la regla: ¿cuántas veces al mes? ¿solo si hay cupo libre?
2. **`por_soltar` en el Tablero.** El dato ya viaja en la respuesta desde
   que se arreglaron los cupos fantasma; falta pintarlo cuando sea > 0.
3. **Default branch a `main`** en Settings del repo. Hoy es
   `claude/aprende-esto-khjryq`, que solo tiene el CLAUDE.md, y ya tumbó
   una vez el despliegue de Cloudflare Pages.
4. **Tablas `cheo_*` en Supabase**, vacías y sin uso. Decidir si se
   borran.
