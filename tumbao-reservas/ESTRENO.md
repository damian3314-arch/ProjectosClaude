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

### 2f. ~~Duplicados del banco~~ ✅ aplicado el 12 de agosto

`pagos_unicos` era `(banco, valor, fecha_pago, referencia)` y
`referencia` es la llave Bre-B de la cuenta de Tumbao: **la misma en los
150 pagos**. Con la fecha a precisión de minuto, dos personas pagando lo
mismo en el mismo minuto entraban como un solo depósito y el segundo se
perdía en silencio. Ahora se dedupea por el id del correo de Gmail.
Verificado: los 150 pagos siguen ahí, el índice viejo se fue.

### 2e. ~~Pegar `aplicar/PEGAR_12_AGOSTO.sql`~~ ✅ aplicado el 12 de agosto

Verificado contra la base: las cinco columnas nuevas están, los dos
índices son los parciales por líder, solo queda una `conciliar_reserva`,
y ya está en uso — un grupo de dos confirmado con su depósito, tres
marcadas "no vino" y una reprogramada.

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

### 2g. ~~Quince minutos de gracia~~ ✅ aplicado el 12 de agosto, 10 pm

Verificado contra la base: `minutos_de_gracia()` devuelve 15, las tres
funciones traen el intervalo, y `clases_para('suelta')` responde con las
7 clases de siempre. El endpoint público —el que de verdad usa la
página— contestó 200 con el listado completo después del cambio.

**Y no se movió una sola reserva.** Antes y después: 97 reservas (10 a
futuro), 51 clases, 66 cupos tomados, 156 pagos. Los mismos números.

La comprobación que de verdad importa: el `md5` de `tomar_cupo`,
`tomar_cupos`, `clases_para` y `minutos_de_gracia` en producción es
**idéntico** al de una base local levantada desde 0001..0037, que es
donde corren las 18 pruebas de humo. No es que "debería ser el mismo
código": es byte por byte el mismo código que pasó las pruebas. Las tres
funciones crecieron exactamente 45 caracteres cada una —lo que mide
` - make_interval(mins => minutos_de_gracia())`— así que no se coló nada
más.

**El problema.** Alguien mira la página a las 7:00 en punto para la clase
de las 7:00 y la clase no está. La página no dice "ya empezó": la clase
sencillamente no aparece, y lo que la persona entiende es que no hay
cupo. Se va. Esa misma persona, en la vida real, llega a las 7:10 y
entra sin que nadie le diga nada. La página estaba siendo más estricta
que la puerta.

**Lo que cambia.** Una clase se sigue pudiendo reservar hasta 15 minutos
después de su hora. Nada más se mueve: ni el aforo, ni el cobro, ni las
membresías. Solo cuándo deja de ofrecerse.

**Son tres sitios, no dos.** `tomar_cupo` y `tomar_cupos` deciden si el
cupo se puede tomar; `clases_para` decide si la clase se **ofrece**. Ese
tercero es el que la persona ve — sin él la clase desaparece del listado
a las 7:00:01 aunque el sistema la aceptara, y no hay nada donde hacer
clic. (Ojo: `04-api-reservas.sdk.js` todavía muestra un GET a PostgREST
con `fecha_hora=gt.$now`; el workflow vivo hace rato llama
`clases_para(p_tipo)`. El archivo está viejo, la base manda.)

**El número vive en `ajustes`,** no en el código. El día que quieran 20,
o 10, o cero para el sábado:

```sql
update ajustes set valor = '20' where clave = 'minutos_de_gracia';
```

Si esa fila se borra o alguien escribe "quince", se cae a **cero** —el
comportamiento de siempre—, no a un valor grande. Ser estricto de más se
arregla por WhatsApp; ser permisivo de más mete gente a una clase que ya
va por la mitad.

**Por qué se parchea el texto en vez de reescribir las funciones.**
`tomar_cupo` son 6 KB y es lo más delicado que hay: aforo, sábado
partido, membresías, códigos. Copiarla entera para cambiar una línea es
la mejor forma de meter una errata en algo que hoy funciona. La
migración lee el texto que de verdad está en la base
(`pg_get_functiondef`), cambia solo esa condición y la vuelve a crear.
Si la condición no aparece **exactamente una vez**, revienta en vez de
aplicar algo a medias.

Probada contra el estado exacto de producción (0001..0036) e idempotente:
pegarla dos veces avisa "ya tenía la gracia puesta" y no toca nada.

### 2h. Pegar `aplicar/PEGAR_CAJA_DEL_DIA.sql` ⬅ pendiente de tu visto bueno

**El problema, medido.** El 11 de agosto la tirilla dijo "Reservas de la
página: **$45.000**". Ese día entraron **$135.000**: nueve personas
pagaron reservas. La caja contó tres.

Las otras seis pagaron el 11 una clase del 12 y del 15, y su plata se
fue a contar esos días. La caja sumaba las reservas por la fecha de la
**clase**, no por cuándo entró la plata.

Con el banco midiendo un día y la caja otro, el cierre no se puede
cuadrar contra nada. Por eso al entrar al panel no se entendía.

**Lo que cambia.** Una reserva entra en la caja del día en que entró su
plata: la fecha del depósito si el banco lo confirmó, o cuándo se
confirmó si fue a mano. Es la misma fecha con la que ya se cuenta
`banco.recibido_cop`, así que las dos mitades del panel hablan por fin
del mismo día.

**Lo que NO cambia.** Ni un movimiento de caja. La plata que se recibe
en la entrada sigue entrando por `caja_movimientos` y contándose el día
en que se registra. La migración no escribe en `caja_cierres`: los
cierres ya firmados se quedan como se firmaron.

**No había doble conteo, aunque lo parecía.** Los movimientos
`clase_suelta` por transferencia cuadraban sospechosamente bien con las
reservas del día. Se revisó pago por pago del 10 al 14 de agosto:
**ningún pago está pegado a la vez a una reserva y a un movimiento de
caja**. Son clases sueltas que se registran a mano —plata distinta— y se
siguen sumando igual.

**Se añade** `reservas_dictadas_cop`: lo que valen las clases dictadas
ese día, que era el número viejo. Sigue estando, en su propia línea y
diciendo que no suma, porque responde a otra pregunta.

Comprobado contra el estado exacto de producción: los cuatro trozos que
parchea aparecen **exactamente una vez** en `caja_del_dia`.

### 2i. La pantalla de Caja, al entrar ⬅ va con la anterior

Al abrir Caja durante el turno se veía **una sola cifra**: "abrió con".
Eso es a propósito para el efectivo —enseñar "en el cajón" todo el día
le da al cajero la respuesta antes de contar, y un arqueo contra una
cifra ya sabida no comprueba nada— pero se estaba aplicando a todo.

Las reservas y las transferencias **nunca pasaron por el cajón**, así
que verlas no adelanta ninguna respuesta. Ahora salen desde el
principio; lo del cajón (el esperado, lo que entró en efectivo, lo que
salió) sigue escondido hasta el arqueo. `prueba-caja` lo vigila: si
alguna vez se cuela "en el cajón" durante el turno, falla.

### 2j. Pegar `aplicar/PEGAR_REPARTO_DEPOSITOS.sql` ⬅ pendiente

**El caso, del 15 de agosto.** Entró una consignación de **$30.000** que
pagaba dos clases de $15.000. No había forma de registrarla:

- el buscador de depósitos filtra por el valor tecleado, así que
  escribiendo `15000` el de $30.000 ni siquiera aparecía;
- y aunque apareciera, `caja_registrar` exigía que el movimiento valiera
  **exactamente** lo mismo que el depósito.

Se quedó en "sin identificar" y ahí iba a quedarse. La única salida era
registrar una línea de $30.000 que en la tirilla no dice de qué fue.

**Lo que cambia.** Un depósito se gasta de a pedazos (`usado_cop`) y
sigue en la lista hasta que se acaba. En el buscador, además del que
cuadra exacto salen hasta tres que **alcanzan** aunque valgan más — y al
escogerlo, la pantalla dice cuánto se va a usar y cuánto queda.

**El cruce automático no se toca.** Apenas la caja le muerde un pedazo a
un depósito, queda marcado como no disponible para el cruce de reservas.
Si no, una reserva de $30.000 se lo llevaría entero y la misma plata
quedaría contada dos veces. El reparto es siempre a mano, decidido por
alguien que está mirando: adivinar repartos de plata automáticamente es
la clase de ayuda que nadie pidió.

**Se borra el índice `caja_mov_pago_unico`,** que decía literal "un
depósito no puede pagar dos cosas". Lo que lo reemplaza es más fuerte:
el índice limitaba la *cantidad* de líneas y no miraba la plata —nada
impedía enlazar un depósito de $15.000 a un movimiento de $500.000—;
ahora el límite es sobre el **dinero** y se aplica con el depósito
bloqueado, así que dos cajeros a la vez tampoco pueden pasarse.

**El panel aguanta las dos situaciones**, así que da igual el orden: si
el servidor todavía no reparte, la pantalla se comporta como antes.

### 2k. ~~La importación de afiliados se rendía con el primer archivo~~ ✅ el 15 de agosto

El 14 de agosto se subieron dos exportaciones de **un solo horario** —
`Afiliados activos 2026-08-14 (6pm).xls` y `(7pm).xls`. Traen 18 filas y
otras columnas (`Afiliado Titular` en vez de `Afiliado`). Le ganaron por
fecha al reporte completo, la lectura falló, y como el flujo se rendía
con el primer candidato, **la importación quedó dos corridas seguidas
sin correr**: los cupos se calcularon todo el fin de semana con datos de
la mañana del 14.

Falló en seguro —no tocó la tabla de membresías— pero nadie se enteró.

Ahora los candidatos se ordenan (el completo antes que el de un solo
horario) y se prueban **hasta tres**. Solo si todos fallan se detiene, y
el error dice cuáles se intentaron.

Verificado corriéndolo: escogió `Afiliados activos 2026-08-15.xlsx`,
importó **56 afiliados, 0 descartados** — 20 a las 7 am, 18 a las 6 pm y
18 a las 7 pm.

### 2l. Pegar `aplicar/PEGAR_ABRIR_LA_SEMANA.sql` ⬅ pendiente, y corre hoy

**Lo que pasaba.** La semana del 17 al 23 de agosto estaba **vacía** un
sábado por la mañana. El lunes nadie habría podido reservar. `generar_horario()`
existía desde el primer día pero **no la llamaba nadie** — el mismo hueco
que tuvo `liberar_cupos_expirados()` en su momento.

Y aunque alguien la llamara, aplica siempre el mismo molde. Lo dice el
comentario de la 0011: *"si una semana hay festivo, no hay por dónde"*.
El **lunes 17 de agosto es la Asunción**: abrirlo habría dejado a gente
pagando por una clase que no se dicta.

**Lo que trae:**

- una tabla `festivos` que `generar_horario` respeta;
- los festivos de Colombia **calculados**, no escritos a mano: Pascua por
  el algoritmo de Gauss y la Ley Emiliani corriendo al lunes los que
  toca. Una lista a mano sirve un año y después miente en silencio, y la
  forma de enterarse es que la academia abrió un festivo;
- `abrir_semana()`, que hace toda la cuenta del lunes entrante dentro de
  Postgres. Si esa aritmética viviera en n8n, correrla a mano un martes
  abriría la semana equivocada.

**Los domingos ya quedaban afuera solos** — el molde solo tiene lunes a
viernes y sábado. No hizo falta tocar nada.

**La tabla también sirve para lo que ninguna ley sabe:** "ese jueves
cerramos por el evento" se mete con `origen = 'manual'` y `sembrar_festivos`
nunca lo pisa.

**Comprobado** en `humo-semana`: la Pascua de cuatro años distintos, los
18 festivos de 2026, que Reyes se corre al lunes 12 y el 1 de mayo no se
mueve, que la semana del 17 abre 14 clases y no 17, y que no queda una
sola clase en domingo ni en festivo.

**El workflow `Tumbao · Abrir la semana`** ya está creado en n8n: sábados
a las 7 am, hora de Bogotá, con reintentos y avisando por el workflow de
fallos si la semana no queda abierta. Falta **activarlo** y correrlo una
vez a mano para la semana del 17, que ya va tarde.

### 3. ~~Revocar los tokens de prueba~~ ✅ hecho el 12 de agosto

Desactivados los dos `prueba caja claude` (los que se compartieron por
chat) y `tu nombre`, que nunca se usó. Siguen activos `damian` y
`Tania`, y se creó **`Recepción`** para que en el cierre quede quién
registró cada movimiento en vez de que todo salga a nombre de Tania.

El token de Recepción se entregó por chat. Si eso incomoda, se cambia en
dos líneas:

```sql
update admin_tokens set activo = false where nombre = 'Recepción';
select crear_token_admin('Recepción');
```

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

# Base de datos: 21 pruebas de humo sobre Postgres (`humo-*.sql`, todas).
# Abajo van las que más cosas han cazado; se corren todas de una con
#   for f in humo-*.sql; do psql -d <base> -f $f; done
psql -d <base> -f humo-corte.sql        # el corte no esconde cupos vivos
psql -d <base> -f humo-banco.sql        # conciliación depósito por depósito
psql -d <base> -f humo-aforo.sql        # no se vende dos veces el mismo puesto
psql -d <base> -f humo-cruce.sql        # el cruce en las dos direcciones (37)
psql -d <base> -f humo-grupo.sql        # varios cupos con un solo pago (39)
psql -d <base> -f humo-disfrutar.sql    # pagó y no vino, y reprogramar
psql -d <base> -f humo-duplicados.sql   # dos pagos iguales en el mismo minuto
psql -d <base> -f humo-gracia.sql       # se reserva hasta 15 min después de empezar
psql -d <base> -f humo-caja-del-dia.sql  # la caja del día es la plata del día
psql -d <base> -f humo-reparto.sql       # un depósito paga varias cosas
psql -d <base> -f humo-semana.sql        # la semana se abre sola, sin festivos ni domingos

# Panel: navegador de verdad, haciendo clic
node espejo-api.mjs &       # el panel necesita el espejo en otra terminal
node prueba-admin.mjs       # tablero, puerta, horario, cola, "Es este"
node prueba-caja.mjs        # 53 comprobaciones
node prueba-apuntar.mjs     # 14
node prueba-varios.mjs      # el contador y los N nombres, en la página pública
node prueba-burbuja.mjs     # la burbuja de opiniones, sin estorbar al formulario

# Sin navegador
node ../../tumbao-opina/pruebas/limpiar-transcripcion.test.mjs
node elegir-reporte.test.mjs      # qué archivo de afiliados se importa
node sin-delete-sin-where.mjs     # ningún DELETE/UPDATE sin WHERE
```

**Las 21 de base de datos y las 9 de node/navegador están en verde**
(corridas el 15 de agosto, con la 0037, 0038 y 0039 aplicadas en
producción y la 0040 puesta encima).

Cinco pruebas fallaban **según el día en que se corrieran**, y ninguna
por el código:

- `prueba-admin` se caía los viernes (saltaba al día siguiente a ciegas y
  eso daba sábado, que tiene otro horario y nadie con plan de esa hora) y
  los sábados (la navegación por días no se sale de la semana en curso, y
  un sábado ya solo queda el domingo).
- `humo-aforo`, `humo-puerta`, `humo-sabado-partido` y `humo-supabase`
  escogían "el próximo sábado" por fecha, así que un sábado agarraban la
  clase de las 8 am que ya había pasado.

Todas escogen ahora un día completo por delante, y fallan solo cuando algo
esté de verdad roto. `humo-admin` y `humo-tablero` llevaban días
rojas y no era del código: las dos escogían "la próxima clase" y a media
tarde eso caía en HOY — abrir una clase a las 5 pm de hoy falla con "esa
hora ya paso", y las 19 personas del plan de las 7 am de hoy ya no
sumaban. Ahora escogen un día completo por delante y fallan solo cuando
algo esté de verdad roto.

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

1. **Miembro con plan en otro horario.** Hoy `tomar_cupo` lo bloquea a
   propósito (`OTRO_HORARIO`, `PLAN_YA_CUBRE`). Antes de tocarlo hay que
   decidir la regla: ¿cuántas veces al mes? ¿solo si hay cupo libre?
2. **Default branch a `main`** en Settings del repo. Hoy es
   `claude/aprende-esto-khjryq`, que solo tiene el CLAUDE.md, y ya tumbó
   una vez el despliegue de Cloudflare Pages.
3. **Las tablas `cheo_*` de Supabase nunca existieron.** El bot de
   opiniones se rehizo en Cloudflare Workers con D1. No hay nada que
   borrar; queda anotado para que nadie las busque.
4. **El cierre de AdminGym se sube a mano** y nadie avisa si un día no
   se sube. Los de julio dejaron de subirse el día 30.
