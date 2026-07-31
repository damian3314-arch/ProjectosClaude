---
name: beat-memoria-modular
description: Estructura y estrategia de lectura de la memoria modular de Beat en `.claudecode/` (stack técnico, retención, caja, Joe v2, arquitectura de datos). Úsala cuando haya que crear, actualizar, reorganizar o decidir qué sub-archivo de memoria leer para una tarea de Beat, o cuando el usuario pregunte dónde vive la documentación de un módulo. NO la uses para Tumbao ni Joyería — su memoria ya vive en Notion y en los workflows de n8n documentados, y no se duplica en Markdown.
---

# Memoria modular de Beat

## Estructura

```
.claudecode/
├── claude.md                  <- índice central
├── 01_stack_tecnico.md        <- Next.js, Supabase, n8n, WhatsApp Cloud API
├── 02_modulo_retencion.md     <- lógica de retención de alumnos
├── 03_modulo_caja.md          <- conciliación de caja, lógica de cobro
├── 04_joe_v2.md               <- bot de recepción WhatsApp como feature de Beat
└── 05_arquitectura_datos.md   <- esquemas Supabase, contratos de webhooks
```

## Estrategia de lectura

Carga el índice **más** el sub-archivo relevante a la tarea. Nada más.

- Tarea sobre retención → `claude.md` + `02_modulo_retencion.md`
- Tarea sobre cobros o caja → `claude.md` + `03_modulo_caja.md`
- Tarea sobre el bot de WhatsApp → `claude.md` + `04_joe_v2.md`
- Tocar tablas o webhooks → suma `05_arquitectura_datos.md`

No cargues el árbol completo para tareas puntuales.

## Al escribir en estos archivos

- Actualiza el sub-archivo del módulo, no el índice, salvo que cambie la estructura misma.
- Antes de crear un archivo nuevo de memoria o una capa de arquitectura, aplica el guardrail anti-parálisis de `CLAUDE.md`: pregunta si lo que ya existe está en uso real.
- Para Tumbao y Joyería no se crea esta estructura. Si te piden "documentar" esos proyectos, la respuesta es Notion o el propio workflow de n8n, no un `.md` en un repo que no existe.
