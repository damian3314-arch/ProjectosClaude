# PROYECTOS.md — Panel de control (revisado 2026-11-09)

Fuente única: qué proyectos hay, dónde vive cada chat, cómo pedir cosas y qué sigue.
Los datos de estado salen de los chats y artifacts reales; lo que es suposición va marcado como **[SUPUESTO]**.

**Qué revisé a fondo:** Plan Piloto y Propuesta de Sette; Plan, Propuesta y "Sábados de Realeza" de Corónate; Plan Tumbao Cierre 2026 y la rutina autónoma de Tumbao; chats de Loggro.
**Qué NO revisé a fondo:** el deck "Corónate para Tania", el tablero de Joyería, el chat de HolaDami (solo sus resúmenes) y los chats de skills/sistema.

---

## 1. Cómo leer un chat (sistema de nombres)

| Código | Proyecto | Qué es |
|---|---|---|
| `[LOG]` | Loggro | Empleo tiempo completo, asesor de venta nueva |
| `[JTS]` | Joyería Tanya Santiago | Asesoría mensual: tablero gerencial, hojas, flujos |
| `[CORO]` | Corónate / Sábados de Realeza (dentro de Joyería) | Campaña de ventas hasta el 31 de dic |
| `[TUM]` | Tumbaobaila.com (incluye Beat) | Sistema de reservas, caja, WhatsApp y campañas de la academia |
| `[DAMI]` | holadami.com | Asistente + prospección (Alter) |
| `[SETTE]` | Sette | Piloto de 8 semanas: compras, inventario, precios |
| `[SIS]` | Sistema | Configuración de Claude, skills, permisos |
| `[PERS]` | Personal | No laboral |
| `[?]` | Sin clasificar | Pendiente de que me digas el proyecto |

Cada chat lleva etiqueta `proy:<nombre>`. Los 6 chats de deploy viejos de Dami llevan `estado:archivar-candidato`. No archivé ni borré nada.

---

## 2. Estado real por proyecto (lo hecho vs. lo pendiente)

| Proyecto | Ya hecho | Pendiente / bloqueo | Chat donde seguir |
|---|---|---|---|
| **Sette** | Plan piloto de 8 semanas con 7 hitos (H1–H7), matriz de prioridades, backlog operativo, fases 2–4, propuesta para Lorena con inversión y alcance. **Aprobada** | Fecha de arranque. Lorena debe dar: usuario de Restobar, plantilla de importación, hojas de inventario, comandas de 2 días, recetario de 10 platos. Contratar a la auxiliar (~$800.000/mes, la paga Sette) para la semana 3 | `[SETTE] Revisión operativa…` |
| **Corónate** | Plan (meta $320 M del 29 oct al 31 dic, calendario día por día, WhatsApp, domingos), Propuesta, página "Sábados de Realeza" (v10), deck para Tania | **Esta semana es el piloto del sábado 14 de nov** (ver §2c). Aprobación de Tania, lista de 150 clientes, hora con las asesoras | `[CORO] Coronate × Joyería` (chat de ~624k tokens: conviene abrir uno nuevo para la fase 2) |
| **Tumbao** | Sistema funcionando: confirmación de reserva, asistente del negocio, asistente de clientes por WhatsApp, SALIR, informes 8 am / 8 pm, cupo sin pago, campañas autorizadas del 6 nov al 28 dic (tope $120.000), rutina diaria autónoma lun–sáb 1:17 pm | **La rutina autónoma está parada desde el 7-nov**: espera tu aprobación de un `Execute SQL` en Supabase (era una consulta SELECT de lectura). Sin ese clic no corre. Además ~10 decisiones tuyas abiertas (ver §2a) | `[TUM] tumbaobaila.com web + Supabase` |
| **Joyería** | Tablero gerencial de ventas conectado a la hoja | 4 supuestos sin confirmar con Tanya: metas, facturado, años anteriores | `[JTS] Dashboard gerencial de ventas` |
| **Loggro** | Guía del asesor, comparativo de mercado, Playbook Restobar. Piloto de agente en WhatsApp (Kapso): ya responde mensajes | Faltan el túnel y el webhook para que responda solo. Y 4 respuestas tuyas: 3 tareas concretas de Loggro, quién lo usa, de dónde salen los datos, qué puede hacer sin preguntarte | `[LOG] Número de teléfono y tareas Loggro` |
| **HolaDami** | Landing, Kapso, Alter (197 envíos, 0 citas), Meta Ads. Chats de deploy: 7 para un mismo despliegue | Kapso con US$0,12 y 2007/2000 mensajes: no envía sin recarga. Decisión de SIM para WhatsApp Business. Tú ya dijiste que lo miras | `[DAMI] Kapso + Alter` |

### 2a. Decisiones que solo tú puedes desbloquear

| Proyecto | Decisión | Urgencia |
|---|---|---|
| Corónate | Aprobar con Tania la invitación y el shampoo de regalo; pasar la base de clientes; 1 hora con las asesoras | **Hoy (lun 9)** |
| Tumbao | Aprobar o negar el `Execute SQL` pendiente (SELECT de lectura) | Hoy: la rutina diaria no corre sin eso |
| Sette | Decir la fecha de arranque y pedirle a Lorena los accesos | Esta semana |
| Tumbao | Pre-venta de diciembre, evento de diciembre, beneficio de referidos, clips semanales de clase, ventas de recepción al día | Antes del 20 nov |
| Joyería | Confirmar los 4 supuestos del tablero | Esta semana |
| Loggro | Responder las 4 preguntas del agente, o decidir que no es prioridad | Opcional |
| Dami | Recargar Kapso o pausar | Cuando lo mires |

---

## 2b. Ingresos por proyecto (COP)

| Proyecto | Ingreso | Notas |
|---|---|---|
| Loggro | $2.200.000/mes + comisión | 8 h diarias ≈ 176 h/mes. Comisión: $1,2M, $0,4M, y octubre esperado $0,5–0,8M (promedio ≈ $0,75M) |
| Joyería (asesoría) | $2.200.000/mes | Martes 4 h y sábado ~6 h hoy (10 h/sem) |
| Corónate | Ver nota abajo | **Dos versiones que no coinciden** |
| Sette | $2.000.000/mes | Pago anticipado cada mes; el mes 2 se confirma al entregar H4. El chat lo calculó con ~22 h/mes ≈ $91.000/h |
| Tumbao (web + Beat) | $750.000/mes | Hoy solo monitoreo |
| HolaDami | $0 | Solo gasto |

**Corónate: precios en conflicto.** Lo que tú dices: $1,5M por una primera fase (2 meses) y $2M por la fase 2. Lo que dicen los documentos:
- Propuesta de octubre: $3,5M fijos en tres entregas ($1,5M + $1,0M + $1,0M) + bono 3% con tope de $1M.
- "Sábados de Realeza" v10 (7 nov): **Fase 1 sin costo** (piloto del 14 nov), Fase 2 = $2.000.000, Fase 3 = $1.500.000, bono 3% con tope de $1M.

Los $2M y $1,5M aparecen, pero en orden inverso y con la Fase 1 en $0. **Confirma cuál está acordado con Tania.** Hasta entonces uso tu cifra ($1,5M por 2 meses) como mínimo seguro.

Ingreso base de proyectos: ≈ $5,7M/mes (Joyería 2,2 + Sette 2,0 + Corónate 0,75 + Tumbao 0,75) + Loggro $2,2M + comisión → **≈ $8,3M a $9,1M/mes**. Joyería + Corónate concentran el 37% del ingreso base.

---

## 2c. Cronograma real (9 nov → 27 dic, con fechas que ya existen)

### Lo que ya tiene fecha

| Fecha | Qué | De dónde sale |
|---|---|---|
| Lun 9 nov | Tania aprueba la invitación; se eligen 150 clientes; se arma el calendario de citas | Sábados de Realeza |
| Mar 10 – Mié 11 | Las asesoras envían 75 invitaciones por día, a mano, desde la línea actual | idem |
| Jue 12 | Segunda tanda (50 más si quedan cupos) | idem |
| Vie 13 | Confirmación de cada cita + historias. Es quincena | idem |
| **Sáb 14 nov** | **Piloto "Sábado de Realeza"**, jornada continua con cita. Meta: $10 M de venta (un sábado normal vende $7,3 M) | idem |
| Lun 16 nov | **Festivo** | Plan Corónate |
| **Mar 17 nov** | **Informe del piloto y decisión de fases 2 y 3** | Sábados de Realeza |
| Vie 27 nov | Black Friday | Plan Corónate |
| 21, 28 nov; 5, 12, 19, 26 dic | Sábados de Realeza (fase 2) | idem |
| Dom 29 nov; 6, 13, 20, 27 dic | Domingos abiertos con cita | idem |
| Mar 8 dic | Festivo | idem |
| 22–24 dic | En 2025 la joyería vendió ≈ $92 M en estos 3 días | Plan Corónate |
| Vie 25 dic | Festivo, cerrado | idem |

### Semana del piloto (9–17 nov)

| Día | Horas | Qué |
|---|---|---|
| Lun 9 | 2 h | Corónate: texto con Tania, lista de 150, calendario de citas |
| Mar 10 | 4 h | Joyería + apoyo a las asesoras con las invitaciones |
| Mié 11 | 2 h | Corónate: agenda de quienes respondieron QUIERO |
| Jue 12 | 2 h | Sette: pedir accesos a Lorena y fijar fecha de arranque |
| Vie 13 | 2 h | Corónate: confirmaciones (1 h) + Tumbao (0,5 h) + revisión semanal (0,5 h) |
| Sáb 14 | 6 h | Corónate: día del piloto, registro de visitas y ventas |
| Dom 15 | 0 | Descanso |
| Lun 16 (festivo) | 4–5 h | **[SUPUESTO]** Sette: día de acompañamiento en compras y cierre (H1) si Loggro está cerrado |
| Mar 17 | 4 h + 2 h | Joyería + informe del piloto para Tania (decisión de fases 2 y 3) |

### Semana tipo desde el 18 de nov (≈ 18 h/semana fuera de Loggro)

| Día | Horas | Proyecto |
|---|---|---|
| Lun | 2 h | Sette |
| Mar | 4 h | Joyería (incluye lo de Corónate que se haga en tienda) |
| Mié | 2 h | Corónate (WhatsApp, plantillas, agenda, tablero) |
| Jue | 2 h | Sette |
| Vie | 2 h | Sette revisión con Lorena 1 h + Tumbao 0,5 h + revisión semanal 0,5 h |
| Sáb | 5–6 h | **Corónate / Sábado de Realeza** (reemplaza el sábado de Joyería) |
| Dom | 0 | Descanso, salvo domingos abiertos (ver pregunta 4) |

### Sette: 8 semanas **[SUPUESTO: arranque lunes 16 nov]**

| Sem | Fechas | Hito del plan |
|---|---|---|
| 1 | 16–22 nov | H1 mapa del proceso aprobado (día de compras y cierre) |
| 2 | 23–29 nov | H2 plantilla de compras probada |
| 3 | 30 nov–6 dic | H3 primera carga completa en Restobar; entra la auxiliar |
| 4 | 7–13 dic | H4 reporte semanal de compras + recetas de 10 platos. **Aquí se confirma el mes 2** |
| 5 | 14–20 dic | Operación asistida |
| 6 | 21–27 dic | H5 primer cruce de inventario. **Semana crítica (Navidad)** |
| 7 | 28 dic–3 ene | H6 costo y precio de los 10 platos |
| 8 | 4–10 ene | H7 piloto cerrado + propuesta de fase 2 |

### Semanas de choque
- **23–29 nov:** Black Friday + Sábado de Realeza (28) + domingo abierto (29) + H2 de Sette.
- **14–20 dic:** primas (prima se paga hasta el 20) + sábado y domingo de Realeza + H4/H5 de Sette.
- **21–27 dic:** Navidad en la joyería + H5 de Sette + sábado 26 + domingo 27. Si hay que sacrificar algo, se mueve H5 a la semana 7, no se toca Joyería.

### Reglas
1. Sábado: máximo 6 h. Domingo libre salvo los cinco domingos abiertos que tú decidas atender.
2. Si un proyecto necesita más horas, otro cede esas horas. No se agregan horas.
3. Viernes (30 min): ¿hubo entregable por proyecto? Si no, se mueve o se recorta alcance.
4. Nada nuevo para Dami ni para el agente de Loggro hasta después del 17 de nov.

---

## 3. Cómo pedir cosas (plantilla universal)

```
Proyecto: [CÓDIGO]. Lee PROYECTOS.md, sección de este proyecto.
Objetivo de esta sesión: <una sola frase>
Entregable: <archivo / workflow / mensaje / decisión>
Límite: <tiempo o alcance, ej. "solo lectura", "sin enviar nada a clientes">
Al terminar: actualiza la fila de Estado en PROYECTOS.md (3 líneas máx.).
```

Regla: **un chat = un resultado**. Títulos nuevos: `[CÓDIGO] verbo + objeto`.

| Código | Primer mensaje |
|---|---|
| `[LOG]` | "Prepárame la llamada con [cliente/sector]. Usa el Playbook Restobar y dime las 3 objeciones más probables." |
| `[JTS]` | "Revisa el tablero con los 4 supuestos pendientes y dime qué pregunto a Tanya." |
| `[CORO]` | "Estado del piloto del 14 de nov: invitaciones enviadas, respuestas QUIERO, citas agendadas. Arma el informe del 17 contra las metas del plan." |
| `[TUM]` | "Solo lectura: dime qué hace el SQL pendiente y qué decisiones mías están abiertas." |
| `[DAMI]` | "Informe de Alter de la semana: envíos, respuestas, citas, costo por cita." |
| `[SETTE]` | "Checklist de la semana N del piloto: qué debe entregar Lorena, qué entrego yo, qué hito cierra el domingo." |
| `[SIS]` | "Audita qué plugins/skills uso de verdad en los últimos 30 días." |

---

## 4. Estrategia (hipótesis, rétala)

1. **Esta semana no se construye nada nuevo en Corónate: se mide el sábado 14.** La decisión de fases 2 y 3 se toma el 17 con cifras. Una web nueva antes de esa decisión es el patrón de CLAUDE.md §6: infraestructura antes de uso real. La web como "centro neurálgico" puede ser el Plan Corónate que ya existe, con datos reales del piloto.
2. **Tumbao ya está construido; el cuello de botella es que tú apruebes cosas.** La rutina autónoma lleva dos días parada por un clic. Ese es tu cuello de botella más barato de arreglar.
3. **Sábados.** Corónate ocupa todos los sábados hasta el 26 de dic. El "sábado de Joyería" y el "sábado de Corónate" son el mismo tiempo: define con Tania si cuentan como parte de las 6 h de tu asesoría.
4. **Chats gigantes.** `[TUM]` (443k) y `[CORO]` (624k) están muy cargados. Antes de la fase 2, pide un resumen de 10 líneas y abre un chat nuevo desde ahí.
5. **Dami y el agente de Loggro:** congelados hasta después del 17 de nov. Ninguno tiene ingreso.

| Nivel | Proyectos | Razón |
|---|---|---|
| Principal (esta semana) | Corónate (piloto 14 nov) | Fecha dura y decisión de dinero el 17 |
| Principal (de la semana 2) | Sette | Pagado, 8 semanas, accesos de Lorena pendientes |
| Sostener | Loggro, Joyería (martes) | Ingreso fijo y recurrente |
| Mantenimiento | Tumbao | Un clic hoy y 30 min por semana |
| Congelado | Dami, agente de Loggro | Sin ingreso |

---

## 5. Entornos y repo

| Entorno | Tipo | Estado |
|---|---|---|
| `Default` | Nube de Claude | Todos los chats de nube corren aquí |
| `MacBook-Air-de-Damian:Claude` / `:ClaudeBot` / `:matriz-viralidad` | Puente a tu Mac | Activos, ningún chat los usa hoy. No sé qué contienen |

- Repo único: `damian3314-arch/ProjectosClaude`. Cada chat crea su rama `claude/...`. `landing-personal` es de HolaDami.
- Riesgo: todo comparte el entorno Default; las claves de Cloudflare, Kapso, OpenAI y Supabase están mezcladas. Un entorno por proyecto cuando manejes claves de clientes (Sette, Joyería). No lo creé: requiere tu aprobación.
- `CLAUDE.md` describe Beat, Tumbao y Joyería. No menciona Loggro, Dami, Sette ni Corónate.

---

## 6. Ritmo de gestión

| Cuándo | Qué | Tiempo |
|---|---|---|
| Lunes | Abrir este archivo, mirar §2a (decisiones abiertas) y §2c (semana) | 15 min |
| Diario | Entrar solo a chats del proyecto del día | — |
| Viernes | ¿Hubo entregable por proyecto? Actualizar Estado | 30 min |

---

## 7. Preguntas abiertas

1. **Corónate:** ¿cuál es el precio acordado con Tania: Fase 1 = $0 con fases 2 ($2M) y 3 ($1,5M), o Fase 1 = $1,5M y Fase 2 = $2M?
2. **Sette:** ¿qué fecha arranca? ¿Lorena ya te dio los accesos? ¿El acompañamiento es presencial en Barrancabermeja o remoto?
3. **Lunes 16 (festivo):** ¿Loggro cierra? Si sí, ese día sirve para el día de compras y cierre de Sette.
4. **Domingos abiertos de Corónate (29 nov, 6, 13, 20, 27 dic):** ¿los atiendes tú o las asesoras?
5. Los 5 chats `[?]`: Worker Cloudflare que reemplaza n8n, Chocamama, video de propuesta de optimización, certificado, Forjabot. ¿De qué proyecto son?
6. **Dami:** recargar o pausar (tú lo miras).
7. **Tumbao:** el chat de Beat (app de huella, AdminGym) sigue esperando que pruebes apagar AdminGym y des la marca del lector.

Resueltas: Corónate es de Joyería; Beat es de Tumbao; Sette paga $2M/mes.
