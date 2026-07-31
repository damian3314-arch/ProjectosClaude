# Siguiente versión

Qué sigue después de que la página esté publicada y usándose.

Está separado a propósito en **lo que se puede hacer hoy** y **lo que
necesita datos que todavía no entran al sistema**. La diferencia importa:
la mitad de los indicadores que se suelen pedir ya son calculables con lo
que hay, y la otra mitad no lo será hasta que se importe el cierre de caja.

---

## Antes que nada: una advertencia de orden

Nada de este documento debería construirse antes de que **alguien reserve
de verdad por la página**. Un dashboard sobre una tabla de reservas vacía
no dice nada, y las decisiones de diseño que se tomen sin datos reales casi
siempre salen mal.

El orden sano es: publicar → que se use una o dos semanas → mirar qué
preguntas aparecen solas → construir el dashboard que las responda.

Lo de abajo es para tenerlo listo cuando llegue ese momento, no para
empezarlo ya.

---

## 1. Página de dashboard

### 1.0 Lo que ya está hecho (julio 2026)

La pestaña **Tablero** del panel ya responde el día de hoy, clase por
clase: cupos libres, gente con plan, reservas, cuánta gente entra a la
sala y lo cobrado. Se puede mover día a día.

Lo que **no** hace, y es todo lo de abajo: comparar. Un solo día no dice
si el 7pm está vendiendo peor que hace un mes. Para eso hacen falta
semanas de datos reales, que es justo lo que todavía no hay.

### 1.1 Lo que ya se puede calcular hoy

Todo esto sale de `reservas`, `clases`, `pagos` y `membresias`, sin
importar nada nuevo.

#### Ocupación

- **Ocupación por clase**: cuántos de los cupos ofrecidos se vendieron.
- **Ocupación por hora del día**: ¿el 7am llena y el 7pm no?
- **Ocupación por día de la semana**: ¿el sábado vale la pena?
- **Cupos que se quedaron sin vender**, en número y en plata. Este es el
  indicador de "dinero que se dejó sobre la mesa" y probablemente el más
  accionable de todos: si el 7pm ofrece 14 cupos y vende 2 todas las
  semanas, o sobra profesor o falta promoción.

#### Ventas de clase suelta

- Cuántas clases sueltas se vendieron por semana y por mes.
- Ingreso por clase suelta (número de reservas confirmadas × $15.000).
- Qué horario vende más sueltas.

#### Quién no llegó — nuevo, desde que existe la lista de la puerta

La tabla `asistencias` empieza a registrar quién entró de verdad a cada
clase. Cruzada con `reservas` y con `membresias` abre dos preguntas que
antes no se podían ni formular:

- **Cuántos reservan y no llegan.** Si es alto, un cupo vendido no es un
  cupo ocupado, y la sala se ve más llena de lo que está.
- **Miembros que dejaron de venir.** Alguien con mensualidad activa que
  lleva dos semanas sin aparecer es alguien que probablemente no renueve.
  Esto es retención pura, y es la señal más temprana que va a haber.

Los dos necesitan que la puerta se marque con constancia. Si no se marca,
el dato no existe — conviene decidirlo antes de contar con él.

#### Salud del proceso de pago

Esto mide si el sistema está funcionando, no el negocio:

- **% de pagos que concilian solos** vs. los que tocó validar a mano. Si
  este número baja, algo se rompió en la ingesta del correo.
- **Cuánto tarda** en promedio un pago en confirmarse.
- Cuántas reservas se quedaron en `pendiente_pago` y expiraron — gente que
  empezó a reservar y no terminó.

#### Membresías — el más valioso

- **Membresías que vencen en los próximos 7 días**, con nombre y celular.

  Este es el que yo pondría de primero en la pantalla. Hoy esa información
  está en un Excel que se descarga y nadie mira; el sistema ya la tiene
  cargada y fechada. Una lista de "estas 6 personas vencen esta semana"
  es una acción concreta que se puede hacer el mismo día, y es retención
  pura.

- Activos por horario, y cómo evoluciona semana a semana.
- **Cuántos se fueron**: quién estaba activo el mes pasado y ya no.
  Requiere guardar el histórico — ver 1.3.

### 1.2 Lo que necesita el reporte de caja

Nada de esto se puede hoy, porque el cierre de caja de AdminGym no entra
al sistema:

- Ingresos totales del día / mes.
- Efectivo vs. banco.
- Egresos y cuadre de caja.
- Ticket promedio.
- Comparar mes contra mes.
- Peso de las clases sueltas dentro del ingreso total.

Ese último es interesante: hoy sabemos cuánto entra por clase suelta, pero
no contra qué compararlo.

### 1.3 Un cambio de esquema que hay que hacer temprano

`membresias` se **borra y se recarga entera** en cada importación. Eso está
bien para saber quién está activo hoy, pero significa que **no hay
histórico**: no se puede responder "¿cuántos activos teníamos en junio?"
ni "¿quién se fue?".

Si eso importa —y para retención importa mucho— hay que empezar a guardar
una foto diaria **antes** de necesitarla, porque el pasado no se puede
reconstruir. Es una tabla `membresias_historico` con la fecha de la foto,
y una línea más en el workflow que ya existe.

Es barato hacerlo ahora y imposible hacerlo después.

---

## 2. Importar el cierre de caja

El mismo camino que ya funciona para afiliados:

```
AdminGym → Excel → Drive → n8n → Supabase
```

El workflow de afiliados sirve de molde: buscar el archivo en Drive,
elegir el más reciente, leer el xlsx, parsear, guardar. Lo que cambia es
el parser y la tabla destino.

Reglas que deben ser las mismas:

- Tabla `caja_diaria`, réplica de AdminGym, **una fila por fecha**.
- Se reemplaza por fecha, no se acumula ciegamente: si se reimporta el
  mismo día, se pisa.
- Un archivo vacío **no borra nada** — la misma guarda que tiene
  `importar_membresias`.
- Nada se edita a mano.

**Lo que necesito de ti para esto:** un ejemplo del archivo de cierre de
caja en Drive, igual que hiciste con el de afiliados. Sin verlo no puedo
escribir el parser, y adivinar el formato es exactamente lo que hizo que
el parser de afiliados fallara la primera vez.

---

## 3. Login de usuarios

Hoy una reserva es **nombre + celular**, sin cuenta. Eso permitió arrancar
rápido y funciona, pero tiene tres consecuencias:

1. Nadie ve su historial de reservas.
2. Nadie puede cancelar solo; toca escribir por WhatsApp.
3. Quien sepa el celular de un miembro puede reservar el sábado en su
   nombre.

La tercera es la que puede doler. Hoy el daño máximo es quitar un cupo —
no mueve plata — pero conviene que sea una decisión y no un descuido.

Cuando se quiera cerrar: Supabase trae autenticación por OTP (código al
WhatsApp o al correo). La tabla `reservas` ya guarda el celular, así que
las cuentas nuevas se pueden amarrar al historial que ya exista sin perder
nada.

**Cancelar** es la funcionalidad que más se va a pedir apenas la página se
use, y es la que hace que el login valga la pena. Si alguien cancela con
tiempo, ese cupo se puede revender.

---

## 4. Cosas pequeñas que valen la pena

Ninguna es un proyecto; son de horas.

- **Nombres de clase y profesor de verdad.** Hoy todas se llaman "Clase
  7:00 am" y el profesor es "Por asignar". El panel ya deja cambiar el
  profesor; falta ponerlos.
- **Recordatorio el día antes** por WhatsApp a quien reservó. Reduce el
  que no llega. Es un workflow de n8n de una hora, pero mandar mensajes
  a clientes reales necesita tu visto bueno explícito.
- ~~**Lista de asistencia**~~ — hecha. Toca una tarjeta de clase en el
  Tablero y sale quién entra, en dos grupos (los que reservaron y los que
  tienen plan de esa hora), con un botón para marcar que entró.
- **Aviso cuando la importación nocturna falle.** Hoy si falla, se sabe
  entrando a n8n. Debería llegar un mensaje.

---

## 5. Orden que yo seguiría

| # | Qué | Cuándo |
|---|---|---|
| 1 | Publicar las páginas en Cloudflare | ya |
| 2 | Prueba completa con una reserva real | ya |
| 3 | Borrar pagos de prueba, renombrar credenciales de Gmail | antes de cobrar |
| 4 | Foto diaria de membresías (`membresias_historico`) | **antes de que haga falta** |
| 5 | Nombres de clase y profesores | primera semana de uso |
| 6 | Importar cierre de caja | cuando me pases un archivo de ejemplo |
| 7 | Dashboard | después de 2 semanas de uso real |
| 8 | Login y cancelación | cuando cancelar empiece a doler |

El 4 está arriba en la lista a propósito, aunque no se necesite todavía:
es lo único de esta lista que **no se puede recuperar después**.

---

## 6. n8n v3 — qué hay que hacer y cuándo

**Sale en octubre de 2026.** No corre prisa, y sobre todo: no se toca el
día que hay clientes estrenando la página.

### Lo más grande no nos toca

El cambio más pesado de v3 es que **el self-hosted va a exigir Docker**:
las instalaciones por `npm` / `npx n8n` dejan de estar soportadas. Tumbao
corre en **n8n Cloud** (`barragan.app.n8n.cloud`), así que ese cambio pasa
de largo. Es el que más trabajo le va a dar a otra gente y a nosotros
ninguno.

### Lo que sí hay que revisar

| Cambio | Estado en Tumbao |
|---|---|
| Se eliminan los nodos **Function**, **Function Item** e **Item Lists** | ✅ no se usan |
| Se elimina el helper `$getPairedItem` | ✅ no se usa |
| Cambia el comportamiento viejo de **Execute Workflow** | ✅ no se usa |
| Se retira el **Chat hub** | ✅ no se usa |
| Se quita **importar workflow desde URL** en el editor | ✅ no se usa |
| Rotación de llaves activada por defecto | ⚠️ revisar credenciales |
| Defaults de seguridad más estrictos | ⚠️ revisar tras actualizar |

Verificado nodo por nodo en cuatro de los seis workflows de Tumbao —
*API de reservas*, *Leer comprobante*, *Ingesta de pagos* y *Avisos de
fallo*. Todos usan `code` v2, `httpRequest` v4.2, `if` v2.2, `filter`
v2.3, `set` v3.4, `webhook` v2, `gmail` 2.2, `googleSheets` 4.7 y
`gmailTrigger` 1.4. Ninguno de esos desaparece en v3.

Faltan por revisar a mano *Panel de admin* e *Importar afiliados*. El
riesgo es bajo —los seis se construyeron la misma semana con el mismo
SDK, que ni siquiera puede emitir los nodos legacy— pero bajo no es cero.

### La comprobación que manda

n8n trae un **Migration Report** que escanea la instancia entera: todos
los workflows y también la configuración de instancia, que desde fuera no
se ve. Eso es más confiable que cualquier auditoría a mano, incluida esta.
Hay que correrlo cuando esté disponible para v3.

### Orden sugerido

1. Correr el Migration Report cuando n8n lo habilite para v3.
2. Arreglar lo que reporte, con la página en horario de poco uso.
3. Actualizar. En Cloud lo hace n8n, pero conviene tener revisado antes.
4. Después de actualizar: probar los cinco endpoints de la página y los
   seis del panel. Están listados en `DIA_DE_ESTRENO.md` §6 con el
   resultado que debe dar cada uno.

Fuente: [v3.0 Breaking changes](https://docs.n8n.io/changelog/v30-breaking-changes)

---

## 7. Consumo de n8n — lo hecho y lo que falta

Medido el 31/07/2026: **362 ejecuciones en 24 horas**, o sea ~10.900 al
mes contra un plan de **2.500**. El reparto real sorprende:

| Origen | Peso | Qué lo dispara |
|---|---|---|
| Panel de admin | **55%** | cada clic; abrir el panel eran 2-3 de golpe |
| API de reservas | 22% | sobre todo la consulta de estado |
| Barrido de cupos | — | el reloj (lo introduje yo, a 5 min = 8.640/mes) |
| Ingesta de pagos | 2% | solo cuando llega correo del banco |

Dato útil: **el Gmail Trigger no gasta cuando no hay correos.** Sondea
cada minuto y solo generó 8 ejecuciones en 24h. Los sondeos en vacío son
gratis; los Schedule Trigger no.

### Hecho

1. **Espera de pago**: de preguntar cada 8s a siete tiempos fijos.
   ~23 llamadas por reserva pasan a ~8.
2. **Panel**: ventana de frescura, 45s el tablero y 10s la cola.
   Mata las ráfagas de siete llamadas en catorce segundos.
3. **Barrido**: de cada 5 minutos a una vez por hora, 6am–10pm.
   8.640/mes → ~480/mes.
4. **Joyería**: la corrida de respaldo de las 8:30pm fallaba todos los
   días. Ya no.

### Falta

**Matar el barrido del todo.** En vez de un reloj, expirar los cupos
vencidos dentro de `tomar_cupo`, que ya bloquea la fila de la clase, y
descontarlos en `clases_para` al leer. Cuesta **cero ejecuciones** y
libera el cupo justo cuando alguien lo necesita, no hasta una hora
después. Ahorro: ~480/mes, y quita un reloj del sistema.

Es migración SQL, así que no se hizo el día del estreno.

**Seguir bajando el panel.** Lo grande ya está, pero abrir el panel
sigue costando dos llamadas y cada confirmación una más. Si hiciera
falta, se pueden juntar tablero y pendientes en un solo webhook.

### Dónde queda la cuenta

Con lo hecho, la proyección es **~3.500/mes** — todavía por encima de
2.500, pero hay que tener en cuenta que el día medido fue de pruebas
intensivas, no de uso normal. Con el punto pendiente y una semana de
datos reales se sabrá si hace falta subir de plan o seguir recortando.

**Regla para lo que venga:** antes de añadir cualquier Schedule Trigger,
calcular qué son al mes. Cada 5 minutos son 8.640. Cada minuto son
43.200. Es la forma más fácil de fundir un plan sin darse cuenta.

---

## 8. Opción A — sacar las lecturas de n8n

Decidida el 31/07. **No se hace antes de tener una semana de datos
reales**, y esa es la parte importante de la decisión: la estimación de
abajo dice qué pesa según mi aritmética, no según el uso.

### El problema de fondo

n8n hace de intermediario para leer cosas que **no son secretas**. Ver
los horarios o preguntar "¿ya me confirmaron?" no necesita ninguna llave
privada, pero hoy cada pregunta cuesta una ejecución.

### Qué se mueve

| Endpoint | Hoy | Con A |
|---|---|---|
| `/tumbao/clases` | n8n → Supabase | la página → Supabase (llave `anon`) |
| `/tumbao/estado` | n8n → Supabase | la página → Supabase (llave `anon`) |
| `/tumbao/reservar` | n8n | **se queda en n8n** — mueve cupos |
| `/tumbao/comprobante` | n8n | **se queda** — toca estado de pago |
| Panel de admin | n8n | **se queda** — token privado |

Lo que se mueve son las dos **lecturas**. Nada que escriba sale de n8n.

### Lo que hay que resolver antes de escribir código

1. **RLS de verdad.** Hoy `anon` no puede ejecutar nada, y eso está bien.
   Hay que abrir exactamente dos caminos y ni uno más:
   - listar clases futuras con su cupo — público, no expone a nadie;
   - consultar UNA reserva por su código — el código es de 6 caracteres,
     así que hay que pensar el límite de intentos. Un `select` por código
     sin freno es una forma de enumerar reservas ajenas.
2. **Qué queda expuesto.** La respuesta de estado no puede traer teléfono
   ni nombre completo: solo el estado y lo mínimo para pintar la
   pantalla.
3. **El reparto del sábado tiene que seguir invisible.** `clases_para`
   ya lo resuelve; hay que asegurarse de que la vista pública no filtre
   `cupo_miembros` ni `cupo_sueltas`.

### Ahorro estimado

Quita ~6 de las ~11 ejecuciones por reserva. Con 30 reservas diarias:
de ~10.600/mes a **~5.600/mes**. Sigue por encima de 2.500, así que A
**no evita subir de plan** — lo que hace es que el siguiente escalón
dure años en vez de meses.

Conviene decirlo claro para no construir con una expectativa falsa.

### Orden

1. Una semana de uso real y volver a medir. Sin eso, optimizar es
   adivinar.
2. Con los datos: ver si lo que pesa es lo que creo. Si resulta que
   pesa más el marcado de asistencia que la consulta de estado, el
   trabajo es otro.
3. Entonces sí, RLS y las dos lecturas.

