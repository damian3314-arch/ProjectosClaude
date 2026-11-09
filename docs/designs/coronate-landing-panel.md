# Corónate: landing y panel de campaña

- **Autor:** Claude (chat `[CORO]`), para Damián Barragán
- **Estado:** Borrador para revisión. Se aprueba sección por sección con Damián. Decisiones tomadas: almacén = Cloudflare Worker + D1; acceso = página pública + clave por persona; landing = dominio propio; licor = landing de clientes igual, versión alterna sin cerveza para redes y pauta; premium = top 50 por compras, ajustado por Tania; sábado 14 = ensayo interno sin clientes.
- **Fecha:** 9 de noviembre de 2026
- **Código revisado:** carpeta `coronate/` en la rama `claude/n8n-pdf-report-delay-1v4yym` (commit `d4476d3`). La rama `claude/wizardly-fermi-3wpram` tiene una copia **anterior** de `coronate/` (sin `asesoras.js`, `landing.css`, `creativo.html` ni `grabacion.html`): no sirve como referencia del estado actual.
- **Artifacts revisados:** landing general, vista premium, panel y guía de grabación publicados en claude.ai.

---

## Overview

Corónate ("Sábados de Realeza · Tu oro, tu corona") es la campaña de Navidad de Joyería Tanya Santiago: del sábado 21 de noviembre al 27 de diciembre, los clientes traen hasta 3 joyas de oro, reciben un shampoo de brillo (gratis para invitados premium, desde $20.000 para el resto) y los atienden con bebida mientras ven la vitrina nueva.

El sistema tiene dos piezas:

1. **Landing** (`index.html`): página para el celular del cliente, en versión general y premium (`?n=Nombre&p=1`). No agenda: manda al WhatsApp de la joyería.
2. **Panel** (`panel.html`): tres pestañas.
   - **Asesoras:** lista de clientes, mensajes por paso con botón de WhatsApp, agenda con cupos, piezas para pegar y respuestas rápidas.
   - **Propietaria:** meta, costos y ROI, semáforo por fecha, línea de tiempo, checklist y base de clientes.
   - **Creativo:** Drive, piezas y textos.

   Lo acompañan dos páginas: `creativo.html` (brief) y `grabacion.html` (guía para Giovanni).

Este documento revisa lo construido contra el requisito de Damián, deja a la vista lo que falla o falta y propone qué tiene que estar listo el lunes 16 para que las asesoras envíen el martes 17.

---

## The Problem

**Lo que se pidió:**
- **Asesoras:** escriben a cada cliente con un clic y con el mensaje correcto (invitación, seguimiento, recordatorio). Ven si el cliente es premium y le mandan la tarjeta personalizada.
- **Propietaria:** ve cada semana si la campaña va en verde o en rojo (semáforo) y si el dinero invertido vuelve (ROI).
- **Creativo:** tiene un solo lugar con brief, fechas y piezas.
- **Fase 1:** honorarios de $1,5 M, con costos aparte. La fase siguiente (WhatsApp oficial, $2 M) solo va si los resultados son muy buenos.

**Lo que hoy impide cumplirlo, con evidencia:**

1. **El semáforo no funciona con más de una persona.** Todo el estado vive en el `localStorage` del navegador:
   - `asesoras.js`: 7 escrituras, con las claves `seg`, `base`, `tpl2`, `paso` y `asesora`.
   - `panel.js`: 8 escrituras, con las claves `ventaDia`, `costos2`, `check`, `piezas` y `drive`.

   Si dos asesoras trabajan en dos celulares, cada una ve su propio avance y pueden escribirle dos veces al mismo cliente. La propietaria, desde su celular, ve el semáforo en cero. La mitigación actual (la guía pide "trabajen todas desde el mismo computador") depende de disciplina, no del sistema. **Riesgo 1: confirmado.**
2. **No hay base de clientes con celular.** La lista que existe tiene 198 nombres con compras de 2026, sin teléfonos. En Drive, la carpeta "04_Clientes y Asesoría" está vacía y el PDF "Reporte ventas anuales Detallado clientes" no se pudo leer. Sin este archivo no sale ninguna invitación el 17.
3. **La landing no le llega a ningún cliente.** Los mensajes solo incluyen el enlace si `config.baseUrl` tiene valor, y hoy está vacío. Publicarla en un dominio es una acción roja (CLAUDE.md §2) que no se ha autorizado. El artifact de claude.ai es público por link, pero puede perder los parámetros `?n=&p=1`, así que la versión premium no se vería.
4. **El panel publicado es un artifact privado de claude.ai.** Para abrirlo, cada asesora necesita cuenta en claude.ai y que Damián se lo comparta. Nadie ha probado que las asesoras puedan entrar.
5. **`apps-script/Code.gs` no está probado y ya no se usa.** La landing dejó de agendar por formulario y todo va por WhatsApp; `config.agenda.endpoint` está vacío. Es código muerto que el README todavía describe como camino para recibir citas. **Riesgo 2: confirmado, y además está desconectado.**

---

## Goals

1. El martes 17, cada asesora abre el panel, ve sus clientes con nombre, celular y marca premium o general, y envía la invitación con un clic desde el WhatsApp Business de la joyería.
2. Ningún cliente recibe el mismo mensaje dos veces por error de coordinación entre asesoras.
3. La propietaria ve cada lunes, en su celular, el semáforo por fecha: invitaciones, respuestas, citas, llegadas, compras y venta del día contra la meta.
4. La propietaria ve el costo total de la campaña y el retorno por peso, con cifras que ella misma ajusta.
5. Giovanni y el creativo tienen un link con todo lo que necesitan, sin que Damián esté al lado.
6. Ningún teléfono ni nombre de cliente queda en el repositorio público.

## Non-Goals

- WhatsApp oficial (API, plantillas aprobadas por Meta, envíos automáticos). Es la fase siguiente de $2 M y solo va si la Fase 1 da resultados muy buenos.
- Agendamiento en línea por el cliente. Se decidió que agende la asesora por WhatsApp.
- Calendario de Google sincronizado en vivo.
- Conexión automática a Drive. El creativo pega el link de la carpeta.
- Integración con el libro de ventas o la caja. La venta del día se escribe a mano en el semáforo.
- Medir aperturas o clics de los mensajes.

---

## Open Questions

Las preguntas con más de una respuesta defendible se le hacen a Damián **una a la vez**, empezando por la 1.

1. ~~¿Dónde se guarda el estado compartido?~~ **Decidido por Damián (9 nov): Cloudflare Worker + D1** (opción B). Crear la cuenta, la base y desplegar el Worker son acciones rojas: requieren su autorización explícita antes de ejecutarse.
2. ~~¿Cómo entran las asesoras al panel?~~ **Decidido por Damián (9 nov): página pública + clave.** El panel se publica en Cloudflare Pages o GitHub Pages. El HTML queda a la vista, pero los datos solo salen del Worker con la clave de cada asesora (y una de propietaria). Publicar es una acción roja: necesita autorización antes del deploy. Ningún archivo con teléfonos va en la página publicada: la base se sube al Worker, no a `clientes.js`.
3. ~~¿Cómo se publica la landing?~~ **Decidido por Damián (9 nov): dominio propio**, apuntando al mismo sitio de Cloudflare/GitHub Pages. Comprar el dominio y configurar el DNS son acciones rojas: necesitan autorización y el nombre exacto. Debe estar en línea antes del lunes 16 para revisar los enlaces personalizados. Cuando exista, `config.baseUrl` lleva esa dirección y los mensajes incluyen el enlace solos.
4. ~~¿Qué clientes son premium?~~ **Decidido por Damián (9 nov): propongo los 50 con más compras en 2026 y Tania quita o agrega** antes del lunes 16. El archivo para su revisión se genera fuera del repo, porque tiene nombres reales.
5. ~~¿El día de prueba del sábado 14 se mantiene?~~ **Decidido por Damián (9 nov): ensayo interno sin clientes.** El equipo ensaya con familiares o empleados el orden del día, los tiempos por turno, el shampoo, las bebidas y la caída de la tela. El 14 sale de la agenda de clientes y del semáforo.
6. **Quien paga el servicio y no cabe el 21:** ¿se le ofrece martes o miércoles, otra máquina o el sábado siguiente?
7. **Precio del servicio pago:** desde $20.000 (lo que dice la landing) o $25.000 (lo que usa el modelo de costos).
8. **Precio por joya adicional después de las 3.** Las respuestas rápidas dicen [CONFIRMAR].
9. **Snacks:** sí o no.
10. **Domingo de noviembre:** ¿se abre el 29 con cita?
11. **Domingos de diciembre:** ¿quién atiende? Normalmente 1 asesora, y una sola persona no puede atender 3 puestos por bloque.
12. **Margen real sobre la venta de joyas.** El ROI usa 45% sin confirmar.
13. **Datos para las autorizaciones de imagen:** razón social y NIT del titular, plazo de uso en años y canal de contacto.
14. ~~Horario y agenda~~ **Decidido por Damián (9 nov): se abre a las 9:30 a. m. y se cierra a las 7:30 p. m.; turnos de 9:30 a. m. a 6:30 p. m., 3 personas por turno.** Falta la dirección y el horario de los domingos.

---

## Critical User Journeys

### CUJ 1 · La asesora envía una invitación

- **Given** la base de clientes está cargada y la asesora escribió su nombre en el panel,
- **When** elige el paso "Invitación", toca "Imagen" en un cliente premium y luego el botón verde,
- **Then** se abre WhatsApp con el chat del cliente y el mensaje premium ya escrito con su nombre y el de ella; pega la tarjeta con el nombre del cliente y envía. El cliente pasa a "Invitación enviada" y sale de la lista de ese paso.

**Hoy:** funciona en un solo navegador (probado con Playwright y datos de ejemplo).

**Falla cuando:**
- Otra asesora, en otro dispositivo, ve al mismo cliente todavía "Por invitar".
- No hay base cargada.
- El navegador no deja copiar imágenes. En ese caso se descarga el archivo y hay que adjuntarlo.

### CUJ 2 · El cliente agenda

- **Given** el cliente recibió la invitación,
- **When** responde por WhatsApp con un día,
- **Then** la asesora toca "Agendar", elige día y hora entre los cupos libres (3 por bloque de 30 min, de 9:30 a. m. a 6:30 p. m.: 57 cupos por día), guarda y envía la confirmación desde el mismo diálogo. El día anterior, el paso "Recordatorio" le muestra ese cliente primero.

**Hoy:** funciona en un solo navegador.

**Falla cuando:**
- Dos asesoras agendan la misma hora en dispositivos distintos: el cupo se sobrevende.
- El cliente agenda por su cuenta escribiendo al WhatsApp sin que nadie lo registre en el panel.

### CUJ 3 · La propietaria ve el semáforo y el ROI

- **Given** las asesoras marcan respuestas, citas, llegadas y compras, y alguien escribe la venta de caja del día,
- **When** Tania abre la pestaña Propietaria el lunes,
- **Then** ve por cada fecha citas, llegadas y compras contra la meta, la venta del día con su color, el costo total de la campaña y cuánto vuelve por cada peso.

**Hoy:**
- **ROI y meta:** funcionan con las cifras de ejemplo.
- **Semáforo:** solo cuenta lo que se marcó en *ese* navegador. **No cumple el Goal 3.**

### CUJ 4 · El creativo sube material

- **Given** Giovanni grabó el lunes 9 y el martes 10,
- **When** abre la guía de grabación por el link,
- **Then** sabe qué piezas hacen falta, qué tomas grabar, qué no decir, cómo firmar las autorizaciones y dónde subir el material (Drive, una carpeta por día, antes de las 9 p. m.).

**Hoy:** la guía está publicada.

**Falla cuando:**
- Giovanni no tiene acceso al artifact privado: Damián debe compartirlo.
- No hay link de la carpeta de Drive: no está en `config.drive.carpeta`.
- Faltan razón social y NIT para las autorizaciones.

---

## Technical Plan

Hoy todo es un sitio estático sin servidor:

```
            config.js (fechas, precios, metas, costos, textos)
                 │
      ┌──────────┴───────────┐
      ▼                      ▼
  index.html            panel.html ── creativo.html, grabacion.html
  landing.js            asesoras.js + panel.js
      │                      │
      │  botón "Agenda"      │  botón por cliente
      └──────► WhatsApp de la joyería ◄──────┘
                             │
                     localStorage del navegador   ◄── aquí está el problema
                     (seg, base, ventaDia, costos2…)
```

Plan propuesto. La caja "ALMACÉN COMPARTIDO" depende de la Open Question 1:

```
  clientes.csv (privado) ──► ALMACÉN COMPARTIDO ◄── panel (cada asesora, la propietaria)
                               │  clientes, estado por cliente, citas, venta del día
                               ▼
                         semáforo y ROI en la pestaña Propietaria
```

**Decisiones mecánicas que tomo yo:**
- **Clave de cada cliente:** el celular normalizado (57 + 10 dígitos).
- **Escrituras:** cada cambio de estado se guarda con fecha, hora y nombre de la asesora (historial), no solo el estado final.
- **Sin conexión:** si el almacén no responde, el panel sigue funcionando en local, avisa con una franja roja y reintenta.
- **Datos de clientes:** nunca entran al repo. `coronate/assets/clientes.js` y `*.csv` ya están en `.gitignore`.
- **Enlaces de WhatsApp:** van por `api.whatsapp.com/send`, porque `wa.me` daña los emojis (probado).

---

## Alternatives Considered

Estas son las opciones para el almacén compartido (Open Question 1). Se presentan sin recomendación: decide Damián.

### A. Hoja de Google + Apps Script como API

- **Cómo funciona:** una hoja con tres pestañas (clientes, eventos, venta del día). Un Apps Script publicado como Web App recibe y entrega JSON. El panel lee al abrir y cada 60 s, y escribe en cada clic.
- **Pros:**
  - Tania ve los datos en una hoja que ya entiende.
  - No cuesta.
  - Ya existe un `Code.gs` como punto de partida, aunque sin probar.
- **Contras:**
  - La URL de la Web App es la única "clave": quien la tenga lee los teléfonos.
  - Apps Script tiene cuotas diarias y tarda de 1 a 3 s por llamada.
  - Hay que desplegarlo desde la cuenta de Google de la joyería, que es una acción con permisos de Damián o Tania.
- **Falla cuando:** se filtra la URL, se pasan las cuotas (poco probable con 200 clientes) o alguien edita la hoja a mano y rompe las columnas.

### B. Cloudflare Worker + base D1

- **Cómo funciona:** un Worker con 4 rutas (leer clientes, registrar evento, leer resumen, guardar venta del día) y una base D1. El panel manda una clave por asesora.
- **Pros:**
  - Responde rápido.
  - Permite una clave por persona y revocarla.
  - El HTML puede ser público sin exponer datos.
- **Contras:**
  - Es infraestructura nueva para una campaña de 6 semanas, contra el guardrail de CLAUDE.md §6.
  - Requiere una cuenta de Cloudflare y un deploy, que son acciones rojas.
  - Los datos no se ven en una hoja si nadie construye la vista.
- **Falla cuando:** nadie mantiene el Worker después de diciembre, o las claves se comparten por WhatsApp.

### C. Sin almacén: un solo computador + consolidación por CSV

- **Cómo funciona:** todas las asesoras trabajan en el computador del WhatsApp Business de la joyería; el estado vive en ese navegador. Cada noche alguien toca "Descargar copia" y se la envía a Tania, o Tania mira el panel en ese mismo computador.
- **Pros:**
  - Ya está construido.
  - No hay datos en la nube fuera del navegador.
  - Cero riesgo de deploy.
- **Contras:**
  - Depende de que nadie use otro dispositivo.
  - El semáforo solo se ve en ese computador o con la copia del día anterior.
  - Si se borran los datos del navegador, se pierde el avance; mitigarlo exige descargar la copia a diario.
- **Falla cuando:** una asesora responde desde su celular, el computador se daña o alguien limpia el historial.

**Decisión (Damián, 9 nov): B.**
- *A rechazada por Damián:* eligió B.
- *C rechazada por Damián:* eligió B. Mientras el Worker no esté desplegado, C es el modo de respaldo: el panel sigue guardando en local.

### Otras decisiones ya tomadas y descartadas

- **Formulario de agendamiento en la landing con Apps Script.**
  - *Rechazada por Damián:* el cliente debe hablar con una asesora, que lo atiende y lo agenda.
- **Plantillas editables como campos principales del panel.**
  - *Rechazada por Damián:* no convencía. Quedó un selector de paso, y la edición está escondida en "Editar el texto de este paso".
- **Llamadas en frío para invitar.**
  - *Rechazada por Damián.*

---

## Non-Functional Requirements

Solo los riesgos críticos.

### Privacidad de datos de clientes (Riesgo 3)

- **El repo es público.**
  - **Protegido hoy:** la base real va en `assets/clientes.js`, que está en `.gitignore`. El repo solo tiene `clientes.ejemplo.js`, con números inventados (300 000 0001…). Revisé el diff de cada commit buscando celulares reales y no encontré ninguno.
  - **Sin protección:** si el panel se publica en una URL pública junto con `clientes.js`, cualquiera con el link descarga los teléfonos. El panel no tiene contraseña.
- **Con la opción A o B:** los teléfonos viajan a Google o a Cloudflare. Es un tratamiento de datos personales (Ley 1581 de 2012). Hay que confirmar que los clientes de la joyería tienen autorización de contacto, o limitarse a clientes que ya han escrito antes.
- **Regla:** ningún archivo con teléfonos se publica sin decisión explícita de Damián.

### Riesgo de bloqueo del WhatsApp de la joyería (Riesgo 4)

Son de 100 a 200 mensajes manuales desde la línea actual.

**Ya está en el panel:**
- Nombre del cliente en cada mensaje.
- Línea de baja en la invitación ("respóndeme NO").
- Estado "No escribir más", que bloquea el botón.
- Máximo dos mensajes sin respuesta, según la guía.

**Falta definir:**
- **Ritmo:** propuesta mecánica de 25 a 30 por hora y no más de 75 por día por línea, repartidos entre el 17 y el 20.
- **A quién NO escribir:** a quien pidió no recibir mensajes antes, a números que no son celulares, a clientes con reclamo abierto (Tania sabe quiénes son) y a menores de edad.

**Contradicción:** el texto de baja dice "respóndeme NO", pero un cliente puede responder "no" queriendo decir "no puedo el sábado". La asesora decide; no hay automatismo.

### Licor (Riesgo 5)

**Contradicción grave:** la imagen principal de la landing es una botella de cerveza con corona y limón, que se arma en pantalla. Eso es licor como protagonista, no como detalle. Además:
- La frase "una Corona bien fría" se repite en el hero, en el ticker, en la versión premium, en las plantillas de WhatsApp y en las piezas.
- "Corona" es una marca registrada de un tercero. Usarla como gancho de la campaña puede traer reclamos, y esto **no está verificado legalmente**.
- La leyenda de alcohol está solo en el pie de la landing.

Para anuncios pagados en Meta, el licor tiene restricciones de edad y de país que no están configuradas: el panel no hace pauta. 

**Decisión (Damián, 9 nov):**
- La landing que reciben los clientes queda **como está**: botella, frase y leyenda al pie.
- Para redes y pauta se prepara una **versión alterna**: la joya al frente y un "detalle bien helado" que se entienda sin decir "cerveza" ni "Corona".

Esa versión es la única que se usa en anuncios pagados. El riesgo por el uso de la marca sigue sin verificar.

### Rollout (Riesgos 6 y 7)

Ver *Detailed Implementation Plan*.

**Prueba con 2 asesoras el jueves 12** (CLAUDE.md §6: ¿quién usa esto esta semana?):
- 30 minutos en la joyería, con 10 clientes de prueba con números del equipo.
- Cada asesora envía una invitación, agenda un turno y marca una respuesta.
- Se mide si entienden el panel sin ayuda y si el estado se ve igual en los dos dispositivos.
- Sin esa prueba, el martes 17 es el primer uso real.

---

## Detailed Implementation Plan

### Lo que DEBE estar listo el lunes 16 (festivo, revisión de Damián)

1. Base de clientes con nombre, celular, premium sí/no y asesora (opcional), cargada en el panel.
2. Decisión sobre el almacén (Open Question 1) y sobre el acceso de las asesoras (Open Question 2).
3. Textos de los 5 pasos aprobados por Tania (premium y general).
4. Tarjeta de invitación final del creativo (si no llega, queda la generada por el panel).
5. Dirección, horario y horas de agenda en `config.js`.
6. Prueba del jueves 12 hecha y ajustes aplicados.

### Lo que puede esperar

- Publicación de la landing en dominio, si se decide (Open Question 3). La invitación funciona sin enlace.
- Conexión a Drive, calendario en vivo y la pestaña completa del creativo.
- `Code.gs`: probarlo solo si se elige la opción A. Si no, borrarlo.

### Archivos

**Si se elige C (sin almacén):**

| Archivo | Acción | Por qué |
|---|---|---|
| `coronate/assets/asesoras.js` | Cambia | Botón "Descargar copia del día" visible en la pestaña Asesoras y aviso si la última copia tiene más de 24 h. |
| `coronate/panel.html` | Cambia | Texto de la guía: "solo en este computador". |
| `coronate/apps-script/Code.gs` | Se borra | Código sin uso y sin probar. |
| `coronate/README.md` | Cambia | Quitar la sección de Apps Script; explicar la copia diaria. |

**Si se elige A (Google Sheets):**

| Archivo | Acción | Por qué |
|---|---|---|
| `coronate/apps-script/Code.gs` | Se reescribe | Rutas: `GET clientes`, `GET resumen`, `POST evento`, `POST ventaDia`. Pseudocódigo: `doPost(e) → valida clave → agrega fila {fecha, asesora, celular, paso, estado, cita} → devuelve ok`. `doGet(e) → lee hoja → devuelve JSON`. |
| `coronate/assets/almacen.js` | Se crea | Capa única de lectura y escritura: `guardarEvento(evt)`, `cargar()`, cola local si no hay red. |
| `coronate/assets/asesoras.js` | Cambia | `seg()` y `guardar()` pasan por `almacen.js`. |
| `coronate/assets/panel.js` | Cambia | `regs()` y `ventaDia` leen del almacén. |
| `coronate/assets/config.js` | Cambia | `almacen: { url, clave }`. La clave **no** se sube: va en un archivo ignorado. |
| `.gitignore` | Cambia | Ignorar `coronate/assets/almacen.local.js`. |
| `coronate/README.md` | Cambia | Pasos para desplegar el Apps Script. |

**Si se elige B (Cloudflare):** lo mismo que A, con `worker/` (rutas y esquema D1: `clientes(celular PK, nombre, premium, asesora)`, `eventos(id, fecha, asesora, celular, paso, estado, cita_f, cita_h)`, `venta_dia(fecha PK, valor)`) en lugar de `Code.gs`.

**Cambios que no dependen de la decisión:**

| Archivo | Acción | Por qué |
|---|---|---|
| `coronate/assets/config.js` | Cambia | Dirección, horario, agenda, `drive.carpeta`, precio pago y joya adicional, cuando Tania los dé. |
| `coronate/assets/asesoras.js` | Cambia | Ritmo de envío: contador por hora y aviso al pasar de 30. Lista "no escribir" cargada con la base. |
| `coronate/index.html`, `landing.css`, `landing.js` | Cambia | Variante `?v=redes`: héroe con la joya al frente, "detalle bien helado" sin mencionar cerveza ni marca, para pauta. La versión de clientes no cambia. |
| `coronate/grabacion.html` | Cambia | Razón social, NIT y plazo cuando los dé Tania. |
| `docs/designs/coronate-landing-panel.md` | Se mantiene | Este documento; se actualiza con cada decisión. |

---

## Lo que no pude verificar

- Que las asesoras puedan abrir un artifact privado de claude.ai en su celular.
- Que copiar imagen funcione en el computador de la joyería: probado en Chromium sin interfaz, no en su equipo.
- El uso de la marca "Corona" y el texto legal del licor: sin revisión legal.
- Los textos legales de las autorizaciones de imagen: sin revisión de abogado.
- `Code.gs`: nunca se ejecutó.
- Que los 198 clientes de la lista actual tengan autorización para recibir mensajes de la joyería.
