# Arquitectura de Tumbao

Este documento contrasta la arquitectura propuesta con lo que **hoy existe
de verdad**, para que no haya que adivinar dónde vive cada dato.

Fecha: julio 2026.

---

## 1. La regla de la fuente de verdad, con la precisión que le faltaba

La propuesta dice "Supabase = fuente de verdad". Es correcto, pero dicho así
choca de frente con la sección 5 del mismo documento, que dice que AdminGym
sigue siendo la fuente oficial de miembros y caja. Las dos cosas no pueden
ser ciertas al mismo tiempo sobre el mismo dato.

La regla que sí funciona, y que es la que el código ya aplica:

> **Supabase es la fuente de verdad de lo que el sistema nuevo crea.**
> Los datos de AdminGym viven en Supabase como **réplica**: se reemplazan
> enteros en cada importación y nunca se editan a mano.

En la práctica:

| Dato | Fuente de verdad | En Supabase |
|---|---|---|
| Reservas | **Supabase** | tabla `reservas` — se crea aquí, no existe en otro lado |
| Clases y horarios | **Supabase** | tabla `clases` — se arman desde el panel |
| Cupos | **Supabase** | `clases.cupo_total`, calculado |
| Pagos conciliados | **Supabase** | tabla `pagos` — origen: correo del banco |
| Tokens de admin | **Supabase** | tabla `admin_tokens` |
| **Afiliados y planes** | **AdminGym** | tabla `membresias` — *réplica*, se borra y recarga cada noche (65 activos hoy) |
| **Caja y ventas** | **AdminGym** | todavía no se importa |

Por qué importa la distinción: si alguien edita `membresias` a mano, el
cambio se pierde esa misma noche. Esa tabla es un espejo, no un registro.
En cambio `reservas` no existe en ningún otro sistema, así que Supabase es
el único sitio donde esa información es real.

---

## 2. Qué hace cada herramienta hoy

| Herramienta | Papel | Estado real |
|---|---|---|
| **Supabase** | Base del sistema. Toda la lógica de negocio vive en funciones de Postgres, no en n8n | ✅ funcionando |
| **n8n** | Pegamento. Mueve y transforma, no decide ni guarda lógica | ✅ 4 workflows activos |
| **Google Drive** | Solo depósito de los Excel de AdminGym | ✅ se lee, no se escribe |
| ↳ carpeta de reportes | `1aqP6ZmNCUEBpLe9Nkfbf8aKEZdmMnJYp` — ahí van cierres y afiliados | ✅ |
| **Google Sheets** | Solo auditoría: copia de los pagos que entran, para revisar a mano | ✅ rama paralela, no bloquea nada |
| **GitHub** | Código, migraciones, pruebas y esta documentación | ✅ |
| **GitHub Pages** | Publica las dos páginas desde `docs/`, se actualiza en cada push | ⚠️ falta encenderlo en Settings |
| **Cloudflare** | Dominio propio | ⏳ más adelante |

Detalle que vale la pena tener claro sobre n8n: **no toma ninguna decisión
de negocio.** Quién tiene cupo, a quién se le abona un pago, si un token
vale — todo eso lo resuelve Postgres con bloqueo de fila. n8n solo enruta
HTTP. Eso es a propósito: si mañana se cambia n8n por otra cosa, la lógica
no se va con él.

---

## 3. Los 8 objetivos, uno por uno

| Objetivo | Estado |
|---|---|
| Reserva de clases | ✅ página pública, miembro y clase suelta |
| Control de cupos | ✅ automático desde membresías + ajuste manual |
| Gestión de horarios | ✅ panel, semana por semana |
| Automatizaciones | ✅ ingesta de pagos + importación nocturna |
| Administración de usuarios | ⚠️ **parcial** — ver abajo |
| Control de acceso en la puerta | ✅ lista por clase, con asistencia |
| Dashboard administrativo | ⚠️ **parcial** — hay tablero del día; falta la serie histórica |
| Reportes | ❌ no hay |
| Escalabilidad | ✅ el esquema aguanta; falta caja |

---

## 4. Los tres huecos reales

### 4.1 No hay login de usuarios

Hoy una reserva se hace con **nombre + celular**, sin cuenta. El miembro se
identifica porque su celular aparece en `membresias`.

Eso funciona y es lo que permitió arrancar rápido, pero significa que:

- nadie puede ver su historial de reservas;
- nadie puede cancelar una reserva por su cuenta;
- cualquiera que sepa el celular de un miembro puede reservar en su nombre
  el sábado.

Lo último es el que puede doler. Hoy el riesgo es bajo (solo quita un cupo,
no mueve plata), pero conviene decidirlo a conciencia y no por descuido.

Cuando se quiera cerrar: Supabase trae autenticación por OTP a WhatsApp o
correo, y la tabla `reservas` ya tiene el celular para amarrar cuentas
existentes sin perder historial.

### 4.2 No se importa el cierre de caja

El flujo del documento contempla los **dos** reportes de AdminGym. Hoy solo
se importa el de afiliados activos. El cierre de caja —efectivo, banco,
ingresos, egresos, cuadre— no entra a Supabase.

Es lo que falta para que haya indicadores de verdad, y es el paso que
convierte esto de "sistema de reservas" a "sistema con dashboard".

Cuando se haga, va en una tabla aparte (`caja_diaria`), con la misma regla:
réplica de AdminGym, se reemplaza por fecha, no se edita a mano.

### 4.3 Falta encender GitHub Pages

`docs/index.html` y `docs/admin.html` están listos y en la carpeta que
GitHub Pages sirve. Falta un ajuste de una sola vez en Settings → Pages
(rama + carpeta `/docs`). Está explicado paso a paso en
COMO_PONERLO_EN_LINEA.md.

Se intentó automatizar con GitHub Actions, pero el token de Actions no
tiene permiso para crear el sitio de Pages. Servir desde la rama evita ese
permiso y encima republica solo en cada push.

---

## 4bis. Cómo se nombran los archivos de Drive

En la carpeta de reportes conviven **dos cosas distintas**, y la
automatización tiene que poder separarlas:

| Qué | Cómo se llama | Ejemplo |
|---|---|---|
| Cierre de caja diario | solo la fecha | `25-07-2026.xlsx` |
| Reporte de afiliados | prefijo + fecha ISO | `Afiliados activos 2026-07-27.xlsx` |

**El prefijo no es decorativo.** Sin él, "el archivo más reciente" de esa
carpeta sería un cierre de caja, y se intentaría leer como si fuera el
listado de gente con plan.

**La fecha va en el nombre porque no hay otra forma de saberla.** La
operación de búsqueda de Drive que usa n8n devuelve id y nombre, y no la
fecha de modificación. El nombre es la única señal fiable.

### Por qué importa que el archivo esté fresco

Las membresías traen inicio y fin, así que las vencidas se descuentan
solas — hasta ahí el archivo viejo se degrada bien. El problema es al
revés: **quien se afilió después del archivo no aparece**. El sistema cree
que hay menos gente con plan de la que hay, y ofrece más clases sueltas de
las que caben en la sala.

No es teórico. Al pasar del archivo viejo (61 afiliados) al nuevo (65), el
martes a las 7pm bajó de 14 cupos a 11. Tres puestos que no existían.

Por eso el selector mide el atraso: hasta 2 días pasa callado, de 3 a 7
importa pero avisa, y de 8 en adelante **se niega y deja la ejecución en
rojo** en vez de calcular cupos con datos viejos.

### Si algún día no se guarda el archivo

No pasa nada grave: los cupos se quedan como estaban en la última
importación buena. Lo que no puede pasar es que nadie se entere, y hoy esa
es la pieza que falta — el aviso llega al log de n8n, no a un WhatsApp.
Está anotado en SIGUIENTE_VERSION.md.

---

## 4ter. Cómo se calculan los cupos

**Los 30 son por clase, no por día.** Cada hora es una sala llena
distinta: el lunes hay 30 puestos a las 7am, otros 30 a las 6pm y otros
30 a las 7pm.

```
cupos que se pueden vender = 30 − gente con plan activo a esa hora ese día
```

Entre semana, quien tiene mensualidad no reserva: su puesto ya está
descontado del aforo. Lo que queda sale a clase suelta.

El sábado nadie tiene plan de sábado, así que salen los 30 completos —
y **ahí sí el miembro también reserva**, del mismo pozo que las sueltas.

Hoy en producción, con 65 afiliados repartidos 19/27/19:

| | con plan | libres |
|---|---|---|
| 7:00 am | 19 | 11 |
| 6:00 pm | 27 | 3 |
| 7:00 pm | 19 | 11 |
| Sábado 8 y 9 am | 0 | 30 |

### La página tiene la última palabra

Si dice 3, se venden 3. Eso descansa en un `select ... for update` dentro
de `tomar_cupo`: las sesiones hacen fila sobre la fila de la clase, así
que dos personas no pueden llevarse el último cupo aunque den al botón en
el mismo segundo.

No es una promesa de papel: `pruebas/carrera-cupos.mjs` abre doce
conexiones de verdad contra una clase de cuatro cupos y las lanza juntas.
Entran cuatro, rebotan ocho, cero códigos repetidos.

### El número que faltaba: cuánta gente entra

`cupos libres` responde "¿puedo vender otra?". No responde "¿cuánta
gente va a haber en la sala?", que es lo que se necesita al abrir la
puerta. Entre semana entran dos grupos distintos:

```
en sala = gente con plan (no reserva, solo llega) + reservas vivas
```

El sábado el primer sumando es cero, así que en sala son las reservas.
La pestaña **Tablero** del panel lo muestra clase por clase, con una
barra que separa los dos grupos sobre el aforo. Es solo lectura y sale
de columnas que ya se mantienen solas: si un número se ve raro, el
problema está en la importación de la noche, no en el tablero.

### La única forma de pasarse de 30

Si alguien reserva una suelta y **después** entran más afiliados con plan
a esa hora, el ideal bajaría por debajo de lo ya vendido. Ahí el sistema
prefiere quedar apretado antes que cancelarle a alguien que ya pagó, y lo
**reporta** en `clases_sobrevendidas_por_reservas_previas`. Hoy ese
contador está en 0.

---

## 5. Reglas de negocio, ya todas confirmadas

- **Media mensualidad = plan completo.** Puede entrar entre semana igual
  que la mensualidad, así que ocupa un puesto fijo del aforo. Es cerca de
  una cuarta parte de los afiliados. Confirmado por Damián en julio 2026;
  el código ya lo hacía así, no hubo que cambiar nada.
- **Entre semana, quien tiene plan no reserva.** Su puesto está asegurado,
  solo llega. Reservar es únicamente para el sábado y para clase suelta.
- **El sábado nadie tiene plan**, así que el aforo entero (30) sale a
  clase suelta y los miembros sí tienen que apartar.
- **El monto de la clase suelta no se toca.** Es fijo ($15.000) porque solo
  paga quien no tiene mensualidad. Por eso los pagos se casan por nombre y
  hora, no por un valor único.

Ya no queda ninguna regla adivinada.

---

## 6. El orden en que yo seguiría

1. **Encender GitHub Pages.** Nada de lo construido sirve mientras nadie
   pueda entrar. Es un ajuste de una sola vez.
2. **Probar el flujo completo con una reserva de verdad** — la de los
   $1.000 que hay en el correo.
3. **Borrar los pagos de prueba.** La ingesta ya lee el correo de Tumbao
   (`bailatumbao@gmail.com`, verificado el 29 de julio en la cabecera
   `Delivered-To` de un correo recién procesado). Lo que queda es limpiar
   los $1.000 de prueba de la tabla `pagos`.
4. **Importar el cierre de caja.** Ahí ya se puede hablar de dashboard.
5. **Login de usuarios**, cuando cancelar y ver historial empiecen a hacer
   falta de verdad.

Los primeros tres son de minutos u horas. El resto son proyectos.

> Nota sobre el orden: el 4 y el 5 son tentadores porque son los más
> vistosos, pero construirlos antes de que alguien use la página es
> exactamente el patrón de armar infraestructura para algo que nadie está
> usando todavía.
