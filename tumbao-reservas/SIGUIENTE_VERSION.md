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
- **Lista de asistencia** para el profesor: quién viene a la clase de hoy.
  La función `admin_reservas_de_clase` ya existe y está publicada; solo
  falta pintarla en el panel.
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
| 5 | Nombres de clase, profesores, lista de asistencia | primera semana de uso |
| 6 | Importar cierre de caja | cuando me pases un archivo de ejemplo |
| 7 | Dashboard | después de 2 semanas de uso real |
| 8 | Login y cancelación | cuando cancelar empiece a doler |

El 4 está arriba en la lista a propósito, aunque no se necesite todavía:
es lo único de esta lista que **no se puede recuperar después**.
