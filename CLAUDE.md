# claude.md — Framework Operativo (Beat / Tumbao / Joyería Tanya Santiago)

Este archivo contiene **solo lo que aplica siempre**, en cualquier tarea y en cualquiera de los tres proyectos. Lo condicional vive en skills (ver sección 5) y se carga solo cuando la tarea lo pide.

**Contexto de entrada:** este framework rige principalmente el repo de **Beat** (código real: Next.js, Supabase, n8n, WhatsApp Cloud API). Para Tumbao y Joyería el trabajo casi nunca es escribir código — es construir/mantener workflows de n8n, hojas de Google Sheets y archivos `.skill`. No fuerces soluciones de frontend sobre automatizaciones contables.

---

## 1. Autonomía — tabla explícita (los 3 proyectos)

Nada de "tareas estándar" ambiguo. Lista cerrada:

| Categoría | Ejemplos | Acción |
|---|---|---|
| **Verde — ejecutar sin preguntar** | linting, tipados, subcarpetas, responsive, refactor de UI sin tocar lógica de negocio, documentación interna | Ejecutar y reportar al final |
| **Amarillo — ejecutar y avisar de inmediato** | cambios en queries de lectura, nuevos endpoints sin side-effects, ajustes de copy | Ejecutar, notificar en el mismo mensaje qué se cambió |
| **Rojo — detenerse y pedir autorización explícita** | cualquier migración de esquema en Supabase, `DELETE`/`DROP`, scripts que tocan nómina/PILA/caja reales, envío de mensajes a clientes reales (WhatsApp, email), deploy a producción, publicar un workflow de n8n, cualquier cosa que mueva dinero o data de un cliente real | Nunca ejecutar sin confirmación tuya, sin excepción |

Regla de oro: lotes largos (ej. refactor de 5 páginas) se procesan completos y se entregan con reporte consolidado — pero solo si están en verde/amarillo. Si algo del lote cae en rojo, se detiene ahí y pregunta.

---

## 2. Bucle de autocorrección (los 3 proyectos)

Antes de entregar:

1. Revisa lógica y output simulando uso real.
2. Corre las pruebas que existan (`npm run build`, linters, tests; para n8n: ejecución de prueba con datos dummy antes de tocar datos reales).
3. Corrige automáticamente lo que caiga en verde/amarillo. Lo rojo se reporta, no se corrige solo.
4. Entrega con log breve: qué se corrigió, qué quedó pendiente de tu autorización.

---

## 3. Guardrail anti-parálisis

Tu patrón documentado es construir infraestructura y documentación antes de que alguien use lo que ya existe. Esto es una regla operativa, no una frase bonita:

> **Antes de crear un módulo, ADR o capa nueva de arquitectura, pregunta primero: "¿la versión actual ya la está usando Tania?"**
> Si la respuesta es no, la prioridad es shippear lo mínimo usable, no seguir planificando.

Aplica en frío: si pides documentar o diseñar algo nuevo sin que lo anterior esté en uso real, se te señala antes de ejecutar.

---

## 4. No duplicar lo que ya existe

Antes de escribir lógica nueva de integración o proceso:

1. Revisa si ya hay un `.skill` que cubra el caso.
2. Si no existe y la lógica se va a reusar más de una vez, **propón** una skill nueva — no la crees sin decírmelo primero.

---

## 5. Skills — qué existe y cuándo se usa

Skills de este repo (`.claude/skills/`):

| Skill | Cuándo se activa |
|---|---|
| `beat-referencia-visual` | Hay una imagen/mockup/captura de referencia y hay que convertirla en UI de Beat. Solo Beat. |
| `beat-memoria-modular` | Hay que leer, crear o reorganizar la memoria de Beat en `.claudecode/`, o decidir qué sub-archivo cargar. Solo Beat. |
| `n8n-integraciones-externas` | La tarea toca Dataico, WhatsApp Cloud API, tasas de cambio o Sheets en Tumbao/Joyería — cosas que ya viven en n8n y no se reimplementan en Beat. |

Librería general ya disponible: `entrevistador-procesos`, `humanizador`, `presentaciones-visuales`, `verificador-datos`, `superpowers`, `optimizador-prompts`.

---

## 6. Checklist de arranque

Al cargar este archivo en una sesión nueva:

1. Lee este archivo + la skill relevante a la tarea pedida (si aplica alguna).
2. Verifica el estado actual del repo (qué existe, qué no).
3. Empieza a ejecutar lo que esté en verde/amarillo. No pidas confirmación de haber "entendido el framework" — eso no aporta nada.
