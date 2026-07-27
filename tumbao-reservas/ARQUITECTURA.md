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
| **Afiliados y planes** | **AdminGym** | tabla `membresias` — *réplica*, se borra y recarga cada noche (61 activos hoy) |
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
| **Google Sheets** | Solo auditoría: copia de los pagos que entran, para revisar a mano | ✅ rama paralela, no bloquea nada |
| **GitHub** | Código, migraciones, pruebas y esta documentación | ✅ |
| **Cloudflare** | Publicar las dos páginas | ❌ **pendiente** |

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
| Dashboard administrativo | ⚠️ **parcial** — hay panel de operación, no de indicadores |
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

### 4.3 Las páginas no están publicadas

`web/index.html` y `web/admin.html` funcionan, pero viven en el repo. Hasta
que no estén en Cloudflare, nadie puede reservar.

---

## 5. Reglas de negocio, ya todas confirmadas

- **Media mensualidad = plan completo.** Puede entrar entre semana igual
  que la mensualidad, así que ocupa un puesto fijo del aforo. Son 15 de 61
  afiliados. Confirmado por Damián en julio 2026; el código ya lo hacía
  así, no hubo que cambiar nada.
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

1. **Publicar las páginas en Cloudflare.** Nada de lo construido sirve
   mientras nadie pueda entrar. Es lo más barato y lo que más cambia.
2. **Probar el flujo completo con una reserva de verdad** — la de los
   $1.000 que hay en el correo.
3. **Cambiar la ingesta al correo de Tumbao** y borrar los pagos de prueba.
   Hoy lee el correo personal de Damián, que fue lo que se usó para probar.
4. **Resolver lo de MEDIA MENSUALIDAD**, que es una pregunta de negocio, no
   de código.
5. **Importar el cierre de caja.** Ahí ya se puede hablar de dashboard.
6. **Login de usuarios**, cuando cancelar y ver historial empiecen a hacer
   falta de verdad.

Los primeros tres son de horas. El resto son proyectos.

> Nota sobre el orden: el punto 5 y el 6 son tentadores porque son los más
> vistosos, pero construirlos antes de que alguien use la página es
> exactamente el patrón de armar infraestructura para algo que nadie está
> usando todavía.
