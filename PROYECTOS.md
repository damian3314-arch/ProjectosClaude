# PROYECTOS.md — Panel de control (actualizado 2026-11-09)

Fuente única: qué proyectos hay, dónde vive cada chat, cómo pedir cosas y qué sigue.
Los datos de estado salen de los chats reales; lo que es suposición va marcado como **[SUPUESTO]**.

---

## 1. Cómo leer un chat (sistema de nombres)

Cada chat en claude.ai/code empieza con un código entre corchetes:

| Código | Proyecto | Qué es |
|---|---|---|
| `[LOG]` | Loggro | Empleo tiempo completo, asesor de venta nueva |
| `[JTS]` | Joyería Tanya Santiago | Rol CTO / asistente administrativo (dashboards, n8n, Sheets) |
| `[CORO]` | Corónate (dentro de Joyería) | Proyecto de 2 meses de Joyería Tanya Santiago → web como centro de operación |
| `[TUM]` | Tumbaobaila.com | Apoyo / laboratorio |
| `[DAMI]` | holadami.com | Asistente real + prospección (Alter) para Loggro y proyectos aparte |
| `[SETTE]` | Sette | Piloto de 8 semanas: inventario, compras, orden de la casa |
| `[SIS]` | Sistema | Configuración de Claude, skills, permisos, plugins |
| `[BEAT]` | Beat (legado) | Gimnasio/AdminGym. No está en tu lista actual → ver pregunta 4 |
| `[PERS]` | Personal | Cosas no laborales |
| `[?]` | Sin clasificar | Necesito que me digas de qué proyecto son |

Además cada chat tiene etiqueta `proy:<nombre>` para filtrar. Los 6 chats de deploy viejos de Dami llevan `estado:archivar-candidato`.
**No archivé ni borré nada.** Solo renombré y etiqueté (reversible).

---

## 2. Estado por proyecto

| Proyecto | Chat canónico (donde seguir) | Dónde quedó | Siguiente paso concreto |
|---|---|---|---|
| **Loggro** | `[LOG] Número de teléfono y tareas Loggro` + `[LOG] Mercado y competencia + Guía del asesor` | Plan de agente listo; esperando respuestas P1 (3 tareas concretas de Loggro) y P3 (dónde viven los datos: API, Excel o Sheets). Existen artifacts "Loggro vs. el Mercado", "Playbook Restobar", "Tarjeta del Asesor" | Responder P1 y P3 en ese chat |
| **Joyería** | `[JTS] Dashboard gerencial de ventas` | Tablero construido sobre la hoja existente con 4 supuestos sin confirmar (metas, facturado, años anteriores) | Confirmar los 4 supuestos con Tanya |
| **Corónate** | `[CORO] Coronate × Joyería` | Artifacts: Propuesta Corónate, Plan Corónate, Corónate para Tania, Sábados de Realeza (v10). Chat enorme: contexto ~624k tokens | **Abrir chat nuevo para la web** (ver §4) |
| **Tumbao** | `[TUM] tumbaobaila.com web + Supabase` | **Bloqueado desde el 7-nov**: espera aprobación de un `Execute SQL` en Supabase. Artifact "Plan Tumbao Cierre 2026" | Revisar ese SQL y aprobar o negar (es 🔴 según CLAUDE.md §2) |
| **HolaDami** | `[DAMI] Kapso + Alter (ventas WhatsApp)` | Alter: 197 envíos, 0 citas aceptadas. Kapso con US$0,12 de crédito y 2007/2000 mensajes → **no puede enviar más sin recarga**. Meta Ads pausada esperando decisión de SIM para WhatsApp Business | Decidir: recargar Kapso o pausar (ver pregunta 2) |
| **Sette** | `[SETTE] Revisión operativa + propuesta CTO fraccional` | Artifacts "Plan Piloto Sette" y "Propuesta Sette Dolce Vita". Se discutió precio: $2M/mes con tope de horas es defendible | Definir alcance y tope de horas por escrito antes de empezar la semana 1 |

Nota: en los chats el proyecto aparece como "Sete". Lo trato como Sette.

---

## 3. Cómo pedir cosas (plantilla universal)

Pega esto al abrir cualquier chat nuevo:

```
Proyecto: [CÓDIGO]. Lee PROYECTOS.md, sección de este proyecto.
Objetivo de esta sesión: <una sola frase>
Entregable: <archivo / workflow / mensaje / decisión>
Límite: <tiempo o alcance, ej. "solo lectura", "sin enviar nada a clientes">
Al terminar: actualiza la fila de Estado en PROYECTOS.md (3 líneas máx.).
```

Regla: **un chat = un resultado**. Si cambia el objetivo, chat nuevo con el mismo código.
Los títulos nuevos: `[CÓDIGO] verbo + objeto` (ej. `[CORO] Construir landing v1`).

### Primer mensaje sugerido por proyecto

| Código | Primer mensaje |
|---|---|
| `[LOG]` | "Prepárame la llamada con [cliente/sector]. Usa el Playbook Restobar y dime las 3 objeciones más probables." |
| `[JTS]` | "Revisa el workflow n8n de [X] con datos dummy. No toques datos reales." |
| `[CORO]` | "Sesión de construcción de la web de Corónate. Meta de hoy: [sección]. Muéstrame el resultado en el navegador antes de seguir." |
| `[TUM]` | "Solo lectura: dime qué hace el SQL pendiente y qué cambia en las tablas." |
| `[DAMI]` | "Dame el informe de Alter de la semana: envíos, respuestas, citas, costo por cita." |
| `[SETTE]` | "Arma el checklist de la semana N del piloto: inventario, compras, responsables, entregable del viernes." |
| `[SIS]` | "Audita qué plugins/skills uso de verdad en los últimos 30 días." |

---

## 4. Estrategia sugerida (hipótesis, rétala)

1. **Corónate = web central.** Antes de construirla, define qué hace la web el día 1 (¿registrar pedidos? ¿mostrar avance? ¿cobrar?). Guardrail de CLAUDE.md §6: si no hay un usuario real que la use la primera semana, es infraestructura prematura.
2. **Chats gigantes → cortar y empezar limpio.** `[TUM]` (443k de contexto) y `[CORO]` (624k) están muy cargados. Antes de cerrarlos, pídeles un resumen de 10 líneas; el chat nuevo arranca desde ese resumen.
3. **Dami: medir antes de recargar.** 0 citas en 197 envíos es una señal, no un fallo técnico. Revisa mensaje y lista de destinatarios antes de poner más dinero.
4. **Límite de trabajo en curso [SUPUESTO]:** 1 proyecto principal + 2 secundarios por semana. Siete frentes con empleo de tiempo completo no caben.

### Propuesta de prioridad (la ajustas tú)

| Nivel | Proyectos | Razón |
|---|---|---|
| Principal | Corónate, Sette | Tienen fecha límite (2 meses / 8 semanas) |
| Sostener | Loggro | Es tu ingreso fijo; se alimenta con rutina, no con proyectos |
| Mínimo viable | Joyería, Dami | Joyería: solo cerrar los 4 supuestos. Dami: decidir recarga o pausa |
| Mantenimiento | Tumbao | Desbloquear el SQL y dejarlo estable |

---

## 5. Entornos y repo

| Entorno | Tipo | Estado |
|---|---|---|
| `Default` | Nube de Claude | **Todos los chats de nube corren aquí** |
| `MacBook-Air-de-Damian:Claude` / `:ClaudeBot` / `:matriz-viralidad` | Puente a tu Mac | Activos, pero ningún chat los usa hoy. No sé qué contiene cada carpeta **[SUPUESTO: matriz-viralidad y ClaudeBot son proyectos locales tuyos]** |

- Repo: solo `damian3314-arch/ProjectosClaude`. Cada chat crea su propia rama `claude/...` (ya hay ~30). La rama `landing-personal` es de HolaDami.
- Riesgo: todos los proyectos comparten el mismo entorno Default. Las claves (Cloudflare, Kapso, OpenAI) quedan mezcladas. Recomendación: un entorno por proyecto cuando tengas claves de clientes (Sette, Joyería). No lo creé: requiere tu aprobación.
- `CLAUDE.md` solo describe Beat, Tumbao y Joyería. **No menciona Loggro, Dami, Sette ni Corónate.** Está desactualizado frente a tu realidad actual.

---

## 6. Ritmo de gestión

| Cuándo | Qué | Tiempo |
|---|---|---|
| Lunes | Abrir este archivo, elegir principal + 2 secundarios, actualizar Estado | 15 min |
| Diario | Entrar solo a chats con el código de proyecto del día | — |
| Viernes | Cerrar: ¿hubo entregable por proyecto? Si no, ¿por qué? | 15 min |

---

## 7. Preguntas que necesito que respondas

1. ~~¿Corónate es de Joyería?~~ Resuelto: sí, es de Joyería.
2. Dami: ¿recargas Kapso hoy, o pausas hasta revisar el mensaje que da 0 citas? (pendiente: lo miras tú)
3. Los 5 chats `[?]` (Worker Cloudflare que reemplaza n8n, Chocamama, video de propuesta de optimización, certificado, Forjabot): ¿de qué proyecto son, o se archivan?
4. Beat / AdminGym: ¿sigue vivo o lo damos por cerrado?
5. ¿Sette cobra? ¿El piloto de 8 semanas tiene pago definido?
