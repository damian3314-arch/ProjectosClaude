# claude.md — Framework Operativo (Beat / Tumbao / Joyería Tanya Santiago)

Índice central. Si vas a tocar un módulo específico, lee también el sub-archivo correspondiente (sección 4). No leas todo el árbol para tareas puntuales.

**Importante de entrada:** este framework rige principalmente el repo de **Beat** (código real: Next.js, Supabase, n8n, WhatsApp Cloud API). Para Tumbao y Joyería, el trabajo casi nunca es "escribir código" — es construir/mantener workflows de n8n, hojas de Google Sheets y archivos `.skill`. Ahí aplican solo las secciones 2, 3 y 5. No fuerces hacks de frontend (sección 1) sobre automatizaciones contables.

---

## 1. Ingeniería visual basada en referencias (solo Beat)

Cuando se provea una imagen/mockup de referencia:

1. Analiza layout, paleta, tipografía, micro-interacciones.
2. Genera código con el stack real de Beat (Next.js + Tailwind + Supabase).
3. Añade interacción solo si suma a UX, no por adorno.

**Ejemplo:** captura de un dashboard SaaS → componente de retención de alumnos o conciliación de caja para Beat.

No aplica a Tumbao/Joyería: ahí no hay frontend que construir, hay flujos.

---

## 2. Autonomía — tabla explícita (aplica a los 3 proyectos)

Nada de "tareas estándar" ambiguo. Lista cerrada:

| Categoría | Ejemplos | Acción |
|---|---|---|
| **Verde — ejecutar sin preguntar** | linting, tipados, subcarpetas, responsive, refactor de UI sin tocar lógica de negocio, documentación interna | Ejecutar y reportar al final |
| **Amarillo — ejecutar y avisar de inmediato** | cambios en queries de lectura, nuevos endpoints sin side-effects, ajustes de copy | Ejecutar, notificar en el mismo mensaje qué se cambió |
| **Rojo — detenerse y pedir autorización explícita** | cualquier migración de esquema en Supabase, `DELETE`/`DROP`, scripts que tocan nómina/PILA/caja reales, envío de mensajes a clientes reales (WhatsApp, email), deploy a producción, cualquier cosa que mueva dinero o data de un cliente real | Nunca ejecutar sin confirmación tuya, sin excepción |

Regla de oro: lotes largos (ej. refactor de 5 páginas) se procesan completos y se entregan con reporte consolidado — pero solo si están en verde/amarillo. Si algo del lote cae en rojo, se detiene ahí y pregunta.

---

## 3. APIs externas y Skills — no duplicar lo que ya existe

Ya tienes una librería de 6 skills (`entrevistador-procesos`, `humanizador`, `presentaciones-visuales`, `verificador-datos`, `superpowers`, `optimizador-prompts`). Antes de escribir lógica de integración nueva:

1. Revisa si ya existe un `.skill` que cubra el caso.
2. Si no existe y la lógica se va a reusar más de una vez, propone un nuevo `.skill` — no lo crees sin decírmelo primero.
3. Para Joyería/Tumbao, las integraciones externas (Dataico, WhatsApp Cloud API, tasas de cambio) ya corren por n8n, no por código de Beat. No reimplementes en Beat algo que ya vive en un workflow de n8n.

---

## 4. Memoria modular — estructura real (solo Beat)

```
.claudecode/
├── claude.md                  <- este archivo, índice central
├── 01_stack_tecnico.md        <- Next.js, Supabase, n8n, WhatsApp Cloud API
├── 02_modulo_retencion.md     <- lógica de retención de alumnos (Beat)
├── 03_modulo_caja.md          <- conciliación de caja, lógica de cobro
├── 04_joe_v2.md                <- bot de recepción WhatsApp como feature de Beat
└── 05_arquitectura_datos.md   <- esquemas Supabase, contratos de webhooks
```

Estrategia de lectura: si la tarea es sobre el módulo de retención, lee `claude.md` + `02_modulo_retencion.md`. No cargues `04_joe_v2.md` si no es relevante.

Para Tumbao y Joyería no se crea esta estructura — su "memoria" ya es Notion + los workflows de n8n documentados. No dupliques eso en Markdown dentro de un repo que no existe para esos proyectos.

---

## 5. Bucle de autocorrección (los 3 proyectos)

Antes de entregar:

1. Revisa lógica y output simulando uso real.
2. Corre pruebas que existan (`npm run build`, linters, tests; para n8n: ejecución de prueba del workflow con datos dummy antes de tocar datos reales).
3. Corrige automáticamente lo que caiga en verde/amarillo de la tabla de la sección 2. Lo rojo se reporta, no se corrige solo.
4. Entrega con log breve: qué se corrigió, qué quedó pendiente de tu autorización.

---

## 6. Guardrail anti-parálisis (reemplaza el mantra decorativo)

Tu patrón documentado es construir infraestructura y documentación antes de que alguien use lo que ya existe. Esta sección lo vuelve una regla operativa, no una frase bonita:

> **Antes de crear un módulo, ADR, o capa nueva de arquitectura para Beat, Claude Code debe preguntar primero: "¿la versión actual ya la está usando Tania?"**
> Si la respuesta es no, la prioridad es shippear lo mínimo usable, no seguir planificando.

Esto aplica en frío: si pides documentar o diseñar algo nuevo sin que lo anterior esté en uso real, Claude Code te lo señala antes de ejecutar.

---

## 7. Checklist de arranque (sin teatro de "confirma asimilación")

Al cargar este archivo en una sesión nueva, Claude Code simplemente:

1. Lee este índice + el sub-archivo relevante a la tarea pedida.
2. Verifica estado actual del repo (qué existe, qué no).
3. Empieza a ejecutar lo que esté en verde/amarillo. No pide confirmación de haber "entendido el framework" — eso no aporta nada, solo ejecuta.
