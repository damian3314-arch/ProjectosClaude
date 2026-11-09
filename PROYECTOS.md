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
| `[TUM]` | Tumbaobaila.com (incluye Beat) | Apoyo / laboratorio. Beat (retención de alumnos, caja, AdminGym) es el sistema de Tumbao |
| `[DAMI]` | holadami.com | Asistente real + prospección (Alter) para Loggro y proyectos aparte |
| `[SETTE]` | Sette | Piloto de 8 semanas: inventario, compras, orden de la casa |
| `[SIS]` | Sistema | Configuración de Claude, skills, permisos, plugins |
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
| **Sette** | `[SETTE] Revisión operativa + propuesta CTO fraccional` | Artifacts "Plan Piloto Sette" y "Propuesta Sette Dolce Vita". Se discutió precio: $2M/mes con tope de horas es defendible | Honorarios aprobados: $2M/mes. Falta fijar por escrito alcance, tope de horas y fecha de pago antes de la semana 1 |

Nota: en los chats el proyecto aparece como "Sete". Lo trato como Sette.

---

## 2b. Ingresos por proyecto (COP, durante los próximos 2 meses)

| Proyecto | Ingreso | Notas |
|---|---|---|
| Loggro | $2.200.000/mes de salario + comisión | 8 h diarias ≈ 176 h/mes ≈ $12.500/h solo con el salario. Comisión sin dato |
| Joyería (asesoría mensual) | $2.200.000/mes | Recurrente |
| Corónate (dentro de Joyería) | $1.500.000 por 2 meses ≈ $750.000/mes | **[SUPUESTO]** $1,5M es el total, no por mes |
| Sette | $2.000.000/mes | Piloto 8 semanas, sin tope de horas definido |
| Tumbao (web + Beat) | $750.000/mes | |
| HolaDami | $0 | Solo gasto (Kapso, Meta Ads, Cloudflare, tokens) |
| **Total extra a Loggro** | **≈ $5.700.000/mes** | Joyería concentra $2,95M (52%) |
| **Total base (sin comisión)** | **≈ $7.900.000/mes** | Loggro es 28%; los proyectos son 72% |

Lectura rápida:
- La mayor ambición (Corónate = "centro neurálgico") es de lo que menos pagan por hora. Joyería es 52% de tus ingresos extra, así que Corónate importa por la relación con Joyería más que por sus $750.000.
- Loggro te ocupa 8 h al día pero es solo 28% del ingreso base. Los proyectos pagan más del doble y compiten por las horas que quedan fuera de Loggro. La comisión de Loggro es la única variable que puede cambiar ese 28%: cuánto sube con el tiempo que le dedicas es un dato que aún falta.

### Ingreso real con la comisión de Loggro

| Mes | Comisión Loggro |
|---|---|
| Hace 2 meses | $1.200.000 |
| Mes pasado | $400.000 |
| Octubre (esperado) | $500.000 – $800.000 |
| Promedio de los 3 | ≈ $750.000 (varía de $0,4M a $1,2M) |

Ingreso total esperado: **≈ $8,3M (mes malo) a $9,1M (mes bueno)**, con base fija de $7,9M. La comisión es la única parte que no controlas; los proyectos son lo estable.

---

## 2c. Cronograma realista (9-nov-2026 → 3-ene-2027)

**Supuestos que debes confirmar:** Sette y Corónate arrancan esta semana; el martes de Joyería es en la noche (no en horario Loggro); domingo libre; Dami congelado hasta que decidas.

### Semana tipo (18 h/semana fuera de Loggro)

| Día | Bloque | Proyecto |
|---|---|---|
| Lun | 2 h | Sette |
| Mar | 4 h | Joyería (fijo) |
| Mié | 2 h | Corónate |
| Jue | 2 h | Sette |
| Vie | 2 h | Corónate 1 h + Tumbao monitoreo 0,5 h + revisión semanal 0,5 h |
| Sáb | 6 h | Joyería 2 h (baja de 6 a 2) + Sette 2 h + Corónate 2 h |
| Dom | 0 | Descanso |

| Proyecto | Horas/sem hoy → plan | Ingreso | Valor/hora aprox. |
|---|---|---|---|
| Joyería | 10 → **6** | $2,2M/mes | $51.000 → **$85.000** |
| Sette | ? → 6 | $2,0M/mes | ≈ $77.000 |
| Corónate | ? → 5 | $1,5M fase 1 (≈ 43 h) | ≈ $35.000 (el más bajo) |
| Tumbao | ? → 0,5 | $0,75M/mes | monitoreo, muy alto |
| Dami | ? → 0 | $0 | congelado |

Corónate fase 2 ($2M) no tiene fecha ni alcance todavía.

### Hitos por semana

| Sem | Fechas | Sette | Corónate | Joyería / Tumbao / Dami |
|---|---|---|---|---|
| 1 | 9–15 nov | Alcance por escrito (entregables, tope de horas, fecha de pago) | Alcance fase 1 en 1 página: qué hace la web el día 1 y quién la usa | Joyería: cerrar 4 supuestos del tablero. Tumbao: resolver el SQL pendiente. Dami: decidir recarga o pausa |
| 2 | 16–22 nov (lun 16 festivo*) | Levantamiento: inventario actual y proceso de compras | Estructura y contenido de la web | — |
| 3 | 23–29 nov (Black Friday 27) | Datos base listos: maestro de productos, proveedores | Primera versión visible para Tanya | Joyería: probable pico de trabajo; protege el martes |
| 4 | 30 nov–6 dic | Reglas de reposición y mínimos definidos | Ajustes con feedback de Tanya | — |
| 5 | 7–13 dic (mar 8 festivo*) | Piloto de compras operando | Web v1 en línea | Joyería: temporada de diciembre |
| 6 | 14–20 dic | Revisión del piloto con datos reales | Entrega fase 1 y cobro. Decisión de fase 2 ($2M) | — |
| 7 | 21–27 dic (vie 25 festivo*) | Buffer / corrección | Buffer | Carga alta Joyería |
| 8 | 28 dic–3 ene | Informe de resultados + propuesta de continuidad | Cierre | Revisión de todo el panel |

\*Festivos de Colombia: verifica las fechas, no las he cotejado con calendario oficial.

### Reglas del cronograma
1. Sábado: máximo 6 h en total; Joyería no pasa de 2 h.
2. Si un proyecto necesita más horas, otro cede esas horas. No se agregan horas.
3. Viernes (30 min): ¿hubo entregable por proyecto esta semana? Si no, se mueve de semana o se recorta alcance.
4. Si en semana 3 o 5 Joyería se desborda (temporada), Corónate cede horas y se negocia el hito, no el sábado de descanso.

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
| Principal | Corónate, Sette | Tienen fecha límite (2 meses / 8 semanas). Sette ya está pagado ($2M/mes) |
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
4. ~~Beat / AdminGym~~ Resuelto: Beat es de Tumbao. Pendiente: el chat `[TUM] Beat: app Windows huella dactilar` espera que pruebes apagar AdminGym y me digas la marca/modelo del lector.
5. ~~¿Sette cobra?~~ Resuelto: aprobaron **$2.000.000 COP/mes** de honorarios. Pendiente por escrito: tope de horas por mes, fecha de pago y qué pasa si el piloto se extiende más de 8 semanas.
