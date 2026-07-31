---
name: n8n-integraciones-externas
description: Reglas de frontera para integraciones externas de Tumbao y Joyería Tanya Santiago — Dataico, WhatsApp Cloud API, tasas de cambio, Google Sheets — que ya corren en workflows de n8n y no deben reimplementarse en código de Beat. Úsala cuando la tarea toque facturación electrónica, envío de mensajes, tipos de cambio, sincronización de hojas de cálculo, o cuando el usuario pida "conectar con X", "automatizar Y" o "crear/arreglar un workflow" en cualquiera de esos dos proyectos.
---

# Integraciones externas — dónde vive cada cosa

## Regla de frontera

Las integraciones externas de Tumbao y Joyería (Dataico, WhatsApp Cloud API, tasas de cambio, Google Sheets) **ya viven en n8n**. No las reimplementes en código de Beat, ni escribas un cliente HTTP nuevo para algo que ya tiene un workflow.

Antes de construir cualquier lógica de integración:

1. Busca el workflow existente en n8n (`search_workflows`, `get_workflow_details`).
2. Si existe, se modifica ahí. Si no existe, se crea ahí — no en Beat.
3. Beat solo consume el resultado (webhook, tabla en Supabase, hoja), no habla directo con el proveedor.

## Antes de escribir lógica nueva

Revisa si ya hay un `.skill` que cubra el caso. Si no lo hay y la lógica se va a reusar más de una vez, **propón** una skill nueva — no la crees sin avisar primero.

## Probar antes de tocar datos reales

Ejecución de prueba del workflow con datos dummy **siempre** antes de correrlo contra datos reales. Usa `test_workflow` / `prepare_test_pin_data`, no `execute_workflow` sobre producción.

Recordatorio de la tabla de autonomía (`CLAUDE.md`): facturar en Dataico, mandar WhatsApp a clientes reales, tocar nómina/PILA/caja o publicar un workflow a producción es **rojo**. Se para y se pide autorización explícita, sin excepción.

## Documentación

La memoria de estos proyectos es Notion + el propio workflow documentado. No dupliques eso en Markdown dentro de un repo.
