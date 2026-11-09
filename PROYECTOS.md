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

**Regla del director:** este chat coordina, decide y delega. El trabajo se ejecuta en el chat del proyecto (por código). Aquí solo se actualiza este archivo.

Cada chat lleva etiqueta `proy:<nombre>`. Los 6 chats de deploy viejos de Dami llevan `estado:archivar-candidato`. No archivé ni borré nada.

---

## 2. Estado real por proyecto (lo hecho vs. lo pendiente)

| Proyecto | Ya hecho | Pendiente / bloqueo | Chat donde seguir |
|---|---|---|---|
| **Sette** | Plan piloto de 8 semanas con 7 hitos (H1–H7), matriz de prioridades, backlog operativo, fases 2–4, propuesta para Lorena con inversión y alcance. **Aprobada** | Fecha de arranque. Lorena debe dar: usuario de Restobar, plantilla de importación, hojas de inventario, comandas de 2 días, recetario de 10 platos. Contratar a la auxiliar (~$800.000/mes, la paga Sette) para la semana 3 | `[SETTE] Revisión operativa…` |
| **Corónate** | Plan, Propuesta, "Sábados de Realeza", deck y landing + panel en local (rama `claude/wizardly-fermi-3wpram`, `coronate/`). **Encargo enviado al chat `[CORO]` el 9-nov** | Costos y retorno, diseño y copy navideño, guion y autorización de imagen para grabar lun 9 y mar 10, línea de tiempo y pendientes. Respuesta del chat al director al terminar | `[CORO] Coronate × Joyería` (permisos en modo "default": pedirá tu aprobación) |
| **Tumbao** | Sistema funcionando: confirmación de reserva, asistente del negocio, asistente de clientes por WhatsApp, SALIR, informes 8 am / 8 pm, cupo sin pago, campañas autorizadas del 6 nov al 28 dic (tope $120.000), rutina diaria autónoma lun–sáb 1:17 pm | **La rutina autónoma está parada desde el 7-nov**: espera tu aprobación de un `Execute SQL` en Supabase (era una consulta SELECT de lectura). Sin ese clic no corre. Además ~10 decisiones tuyas abiertas (ver §2a) | `[TUM] tumbaobaila.com web + Supabase` |
| **Joyería** | Tablero gerencial de ventas conectado a la hoja | 4 supuestos sin confirmar con Tanya: metas, facturado, años anteriores | `[JTS] Dashboard gerencial de ventas` |
| **Loggro** | Guía del asesor, comparativo de mercado, Playbook Restobar. Piloto de agente en WhatsApp (Kapso): ya responde mensajes | Faltan el túnel y el webhook para que responda solo. Y 4 respuestas tuyas: 3 tareas concretas de Loggro, quién lo usa, de dónde salen los datos, qué puede hacer sin preguntarte | `[LOG] Número de teléfono y tareas Loggro` |
| **HolaDami** | Landing, Kapso, Alter (197 envíos, 0 citas). 9-nov: causa de los recordatorios que no salían encontrada (reuniones creadas desde Outlook llegan con resultado vacío y la rutina exigía "SCHEDULED"); prompt de la rutina corregido por el chat. A/B de primer contacto programado en código, **apagado** | Recargar Kapso (US$ 0,12 el 7-nov); aprobación de Meta de 2 plantillas (utilidad y mercadeo); **Damián debe revisar el prompt nuevo de la rutina `Alter Loggro`** (se cambió antes de mostrárselo); quitar conectores sobrantes en la UI; falta analizar el cierre (0 citas aceptadas) y las horas de llegada de leads | `[DAMI] Kapso + Alter` |

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
| Corónate | Fase 2 $1,5M · Fase 3 $2M (condicionada) | Ver nota abajo |
| Sette | $2.000.000/mes | Pago anticipado cada mes; el mes 2 se confirma al entregar H4. El chat lo calculó con ~22 h/mes ≈ $91.000/h |
| Tumbao (web + Beat) | $750.000/mes | Hoy solo monitoreo |
| HolaDami | $0 | Solo gasto |

**Corónate: acuerdo vigente (Damián, 9 nov).**
- **Fase 1 = $1.500.000** de honorarios, incluida la campaña completa (prueba, lanzamiento del 21, sábados y domingos de diciembre, semáforo).
- **Costos de insumos y logística: aparte, a cargo de la joyería** (shampoo por cliente, bebidas, hielo, agendas, bolsas, empaques, decoración, foto/video, personal extra). El chat `[CORO]` construye el apartado de costos y retorno (ROI por peso invertido).
- **Fase siguiente = $2.000.000** (WhatsApp oficial verificado), solo si los resultados son muy buenos.
- Bono 3% (tope $1M) y operación de $300.000/mes desde enero: sin confirmar. **[CONFIRMAR]**
- **Meta de ventas nov + dic: $400 M** (el Plan Corónate tenía $320 M del 29 oct al 31 dic: el chat `[CORO]` debe reconciliarlo con números).

Ingreso base de proyectos: ≈ $5,7M/mes (Joyería 2,2 + Sette 2,0 + Corónate 0,75 + Tumbao 0,75) + Loggro $2,2M + comisión → **≈ $8,3M a $9,1M/mes**. Joyería + Corónate concentran el 37% del ingreso base.

---

## 2c. Cronograma real (9 nov → 27 dic, con fechas que ya existen)

### Lo que ya tiene fecha

| Fecha | Qué | De dónde sale |
|---|---|---|
| Lun 9 nov | Landing + panel + copy listos en local; Tania aprueba la invitación; se elige la base selecta | Reajuste del 9-nov |
| Mar 10 – Mié 11 | Las asesoras envían 75 invitaciones por día, a mano, desde la línea actual | idem |
| Jue 12 | Segunda tanda (50 más si quedan cupos) | idem |
| Vie 13 | Confirmación de cada cita + historias. Es quincena | idem |
| **Sáb 14 nov** | **Día de prueba** con base selecta (sin redes ni mensajes masivos). Meta: $8 M | Reajuste del 9-nov |
| Lun 16 nov | **Festivo** | Plan Corónate |
| **Mar 17 nov** | Informe de la prueba y ajustes de texto, tarjeta y cupos | Reajuste del 9-nov |
| 16–20 nov | Expectativa en redes (vitrina tapada) e invitaciones a la base completa **[SUPUESTO]** | Reajuste del 9-nov |
| **Sáb 21 nov** | **Lanzamiento oficial**: revelación de la vitrina, decoración de Navidad, música, cerveza y bebidas sin alcohol | Reajuste del 9-nov |
| Vie 27 nov | Black Friday | Plan Corónate |
| 28 nov; 5, 12, 19, 26 dic | Sábados de Realeza (con el 21 son 6) | idem |
| Dom 6, 13, 20, 27 dic | Domingos de diciembre. Normalmente atiende 1 asesora (puede haber 2). Damián va 2–3 h en la tarde. Domingo de noviembre por decidir | Damián, 9-nov |
| Mar 8 dic | Festivo | idem |
| 22–24 dic | En 2025 la joyería vendió ≈ $92 M en estos 3 días | Plan Corónate |
| Vie 25 dic | Festivo, cerrado | idem |

### Tu horario real (semana del 9 al 15 nov)

| Día | Gimnasio (bloqueado 6–9) | Loggro | Chat Loggro | Libre para proyectos |
|---|---|---|---|---|
| Lun 9 | 6:00–8:00 (calendario) | 9–19 | — | Noche 19:30–21:00 |
| Mar 10 | 6:00–8:00 | 9–19 | — | Noche 19:30–21:30 |
| Mié 11 | 6:00–8:00 | **11–19** | — | **Mañana 9:00–11:00 en la joyería (todos los miércoles)** + noche 19:30–21:00 |
| Jue 12 | 6:00–8:00 | 9–19 | 17–19 | Noche 19:30–20:15 (liviana) |
| Vie 13 | 6:00–8:00 | 9–18 | 17–18 | Noche 18:30–20:00 |
| Sáb 14 | 6:00–8:00 | Descanso | — | Todo el día; bloque Joyería 14–18 |
| Dom 15 | — | Descanso | — | Visita a la joyería 14:30–17:00; revisión semanal 20:00 |

Estas son ≈ 17 h de proyectos en la semana, con Loggro y gimnasio intactos.

### Bloques creados en tu Google Calendar (9–15 nov)

| Día y hora | Bloque |
|---|---|
| Lun 9, 19:30–21:00 | `[CORO]` Revisión con el chat Corónate: costos, diseño, grabación |
| Mar 10, 19:30–21:30 | `[JTS]` Joyería y Tumbao (**movido** de 2–6 p. m. porque choca con Loggro) |
| Mié 11, 9:00–11:00 (y todos los miércoles hasta el 30 dic) | `[JTS]` Joyería antes de Loggro |
| Mié 11, 19:30–21:00 | `[CORO]` Costos reales con Tania para el ROI |
| Jue 12, 19:30–20:15 | `[CORO]` Aprobar piezas e invitaciones |
| Vie 13, 18:30–20:00 | `[TUM][DIR]` Tumbao, decisiones abiertas y revisión semanal |
| Dom 15, 14:30–17:00 | `[JTS]` Visita a la joyería |
| Dom 15, 20:00–20:45 | `[DIR]` Revisión semanal y plan de la semana del 16 |
| **Lun 16 (festivo), 9:30–13:30** | `[CORO]` Ultimar detalles: todo listo para enviar el martes 17 |
| Lun 16 (festivo), 19:00–21:30 | `[SETTE]` solo si Lorena confirma auxiliar; si no, libre |
| Mar 17, 19:30–21:00 | `[CORO]` Día 1 de invitaciones: revisar envíos y respuestas (movido desde 2–6 p. m.) |
| Sáb 21 | `[CORO]` LANZAMIENTO (evento de día completo) |

### Cosas del calendario que debes revisar
1. **Gimnasio:** bloqueado de 6 a 9 a. m. (incluye traslado). Decisión de Damián: se deja así. Mis bloques no pueden empezar antes de las 9.
2. **Bloque de Joyería de los martes (2–6 p. m.):** choca con Loggro. Solo moví el del 10 nov. El del 17 sigue igual.
3. **PILA de Tania:** el recordatorio está el 10 nov, pero tu nota dice "día hábil 10". Con el festivo del 2 y del 16 de nov, mi cuenta da el **martes 17 de nov**. Verifícalo en la tabla de Aportes en Línea antes de pagar. Mora = intereses + 1 día de salario por día de retraso.
4. **Tumbao:** tienes un recordatorio el sáb 14 a las 9:00 para planear diciembre (clausura, show de fin de año, clase especial de Feria de Cali del 25 al 30). No estaba en mi plan; hay que tenerlo.
5. **Festivos confirmados:** lun 16 nov, mar 8 dic, vie 25 dic.

### Semana tipo desde el 18 de nov
Mismo molde: lunes a viernes solo noches de 1,5 a 2 h y los miércoles 8:45–10:45; sábados de Corónate; domingo de visita a la joyería. Máximo 3 noches con proyectos por semana; el resto es descanso.

### Sette: 8 semanas **(en espera: Lorena está entrevistando a la auxiliar y avisará)**

| Sem | Fechas | Hito del plan |
|---|---|---|
| 1 | **Por definir** (arranca cuando Lorena tenga auxiliar) | H1 mapa del proceso aprobado. Acompañar un día de compras y cierre |
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

1. **Corónate: la landing es el centro, pero pruébala el 14 antes de crecerla.** Ya está construida en local (`coronate/`). Guardrail de CLAUDE.md §6: el día de prueba con base pequeña es lo que valida si las asesoras la usan de verdad. Si el 14 no la usan, se simplifica antes del 21.
2. **Tumbao ya está construido; el cuello de botella es que tú apruebes cosas.** La rutina autónoma lleva dos días parada por un clic. Ese es tu cuello de botella más barato de arreglar.
3. **Sábados.** Corónate ocupa todos los sábados hasta el 26 de dic. El "sábado de Joyería" y el "sábado de Corónate" son el mismo tiempo: define con Tania si cuentan como parte de las 6 h de tu asesoría.
4. **Chats gigantes.** `[TUM]` (443k) y `[CORO]` (624k) están muy cargados. Antes de la fase 2, pide un resumen de 10 líneas y abre un chat nuevo desde ahí.
5. **Dami y el agente de Loggro:** congelados hasta después del 17 de nov. Ninguno tiene ingreso.

| Nivel | Proyectos | Razón |
|---|---|---|
| Principal (esta semana) | Corónate (prueba 14 nov, lanzamiento 21 nov) | Dos fechas duras |
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

**Corónate (decisiones de Damián/Tania):**
1. El 21: quien PAGA el servicio y no cabe ese día, ¿se agenda martes/miércoles o se habilita otra máquina? ¿Precio del servicio pago?
2. Snacks: ¿sí o no?
3. Domingo de noviembre: ¿cuál se habilita? ¿Dos asesoras algún domingo?
4. Prueba del 14: ¿se hace? ¿con qué grupo?
5. Margen real de la joyería (para el ROI). Y valor de insumos (shampoo, bebidas, etc.).
6. ¿Bono 3% y $300.000 mensuales siguen o no?

**Otros proyectos:**
7. **Sette:** fecha de arranque, accesos de Lorena, ¿presencial o remoto?
8. ~~Lunes 16 (festivo)~~ Resuelto: se dedica a Sette (H1: compras y cierre).
9. **Tumbao:** aprobar el `Execute SQL` (SELECT) pendiente; decisiones abiertas del plan.
10. **Dami:** recargar Kapso o pausar.
11. Los 5 chats `[?]`: ¿de qué proyecto son?

Resueltas: la grabación del 9 y 10 la hace Giovanni (Damián le envía el brief por link, sin estar presente); invitaciones salen el martes 17; Corónate es de Joyería; Beat es de Tumbao; Sette paga $2M/mes; Corónate Fase 1 = $1,5M con costos aparte; invitaciones del 16 al 20; domingos los atienden las asesoras.
