---
name: beat-referencia-visual
description: Convierte una imagen, captura, mockup o referencia visual en código real de Beat (Next.js + Tailwind + Supabase). Úsala cuando el usuario adjunte o enlace una imagen de UI, un dashboard, un diseño de Figma o una captura de otra app y pida "hazlo así", "replica esto", "quiero una pantalla como esta" o "usa esto de referencia". Solo aplica al repo de Beat, donde hay frontend real. NO la uses para Tumbao ni Joyería Tanya Santiago — ahí no hay frontend que construir, hay workflows de n8n y hojas de cálculo.
---

# Ingeniería visual basada en referencias (solo Beat)

## Cuándo aplica

Hay una imagen/mockup/captura de referencia **y** el destino es el frontend de Beat.

Si el proyecto es Tumbao o Joyería, para: no fuerces hacks de frontend sobre automatizaciones contables. Lo que ahí se necesita es un workflow, no un componente.

## Proceso

1. **Analiza la referencia antes de escribir nada:** layout y jerarquía, paleta, tipografía, espaciado, micro-interacciones. Di en voz alta qué estás leyendo de la imagen para que el usuario pueda corregirte temprano.
2. **Genera código con el stack real de Beat:** Next.js + Tailwind + Supabase. Nada de librerías nuevas de UI ni dependencias extra sin avisar.
3. **Interacción solo si suma a UX**, no por adorno. Animaciones, transiciones y estados hover se justifican o no se ponen.
4. **Traduce la referencia al dominio de Beat.** Una captura genérica de dashboard SaaS no se copia literal: se convierte en algo que Beat necesita — retención de alumnos, conciliación de caja, cobros.

## Límites

- Un cambio visual que toque lógica de negocio deja de ser verde en la tabla de autonomía. Revisa `CLAUDE.md` antes de ejecutar.
- No inventes datos de ejemplo que parezcan reales (nombres de alumnos, montos de caja). Usa placeholders obvios.
