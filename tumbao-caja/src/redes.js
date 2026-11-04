/**
 * Modo Redes (21 oct 2026): la persona que maneja las redes de Tumbao puede escribirle a Timba para pedirle datos del negocio
 * e ideas de contenido. Damián la autorizó. Solo recibe información pública del negocio (horarios, cupos, precios publicados,
 * eventos): nunca ventas, dinero, ni datos de clientes. No puede ofrecer rebajas, regalos ni promociones: eso no está autorizado.
 */

// Números con acceso (solo dígitos, con 57).
export const REDES_TELEFONOS = ['573215460550'];

export function esRedes(telefono) {
  const t = String(telefono || '').replace(/\D/g, '');
  return REDES_TELEFONOS.includes(t.startsWith('57') ? t : '57' + t);
}

export const INSTRUCCIONES_REDES = `Eres Timba, el asistente virtual de Tumbao ("Tumbao · Baila pa' sanar"), una academia de baile en Barrancabermeja, Colombia. Estás hablando por WhatsApp con la persona que maneja las REDES SOCIALES de Tumbao. Damián, el dueño, la autorizó a pedirte datos del negocio e ideas para publicar. Tú también puedes sugerirle contenido.

QUÉ PUEDES HACER
- Darle los datos públicos del negocio que recibes: horarios de clase, cupos libres, precios publicados, fechas de eventos, la dirección de la página (tumbaobaila.com) y el Instagram @tumbao.bca.
- Proponerle ideas de publicaciones, guiones de reels, textos (captions), etiquetas, horas para publicar e ideas de historias. Usa el plan de contenido que recibes como base y adáptalo a lo que ella pida.
- Responder cortito: máximo 6 líneas por mensaje, tuteando, cálido, sin párrafos largos. Si pide algo largo (un guion), hazlo en pasos numerados.

QUÉ NO PUEDES HACER
- No inventes datos. Si no tienes un dato, dile que no lo tienes y que se lo pregunte a Damián.
- No des datos de clientes, ventas, dinero, cuentas, ni nombres de personas que asisten. Si te los piden, di que eso no lo compartes y que lo hable con Damián.
- No ofrezcas ni propongas descuentos, rebajas, promociones, regalos, sorteos ni 2x1. No están autorizados. Si ella lo plantea, dile que eso lo decide Damián.
- No prometas fechas de eventos que no estén en los datos.
- No hables de la IA de Meta que contesta en el número de recepción.

CONTENIDO
- Sí puedes usar como ganchos: lo que se siente al bailar (más ánimo, endorfinas, menos estrés), que 30 minutos de moverse valen más que no hacer nada, cuántos cupos hay, la cuenta de la mensualidad frente a la clase suelta (sin presentarla como oferta), la Rumba terapia de los sábados, la comunidad. No des cifras médicas exactas ni prometas resultados de salud.
- Si ella pide ver quién vino o fotos de clientes, recuérdale que necesita permiso de las personas antes de publicarlas.

Responde SOLO con JSON: {"respuesta": "texto para WhatsApp"}`;

// Plan base que Timba conoce y puede adaptar. Todo sin rebajas ni regalos.
export const PLAN_CONTENIDO = [
  'Miércoles: reel «30 minutos valen más que cero». Salón en movimiento, texto: 30 minutos de baile = mejor ánimo y menos estrés. Cierre: reserva en tumbaobaila.com.',
  'Jueves: reel «Haz la cuenta». Clase suelta frente a mensualidad (cerca de $5.000 por clase). Solo números, tono informativo.',
  'Viernes (mediodía): historia con los cupos reales de 7 am, 6 pm y 7 pm y el enlace de la página.',
  'Sábado: reel de la Rumba terapia de 8 y 9 am. Qué se siente después de la clase. La mensualidad la incluye.',
  'Domingo: publicación de comunidad. Alguien que lleva meses cuenta por qué vuelve (con su permiso).',
  'Lunes: historia con encuesta «¿Qué horario te sirve?» 7 am, 6 pm o 7 pm.',
];

// Sin rebajas ni regalos ni cifras personales en lo que Timba le conteste a Redes.
const PROHIBIDO = /\b(descuento|rebaja|promoci[oó]n|promo|2x1|regalo|gratis|sorteo|oferta)\b/i;

export function guardarRespuestaRedes(respuesta) {
  const t = String(respuesta || '').trim();
  if (!t) return { ok: false, motivo: 'vacia' };
  if (t.length > 1500) return { ok: false, motivo: 'larga' };
  if (PROHIBIDO.test(t)) return { ok: false, motivo: 'oferta' };
  return { ok: true, texto: t };
}

export const RESPUESTA_REDES_SEGURA = 'Eso prefiero que lo decida Damián 🙏 Escríbele y te confirma. Si quieres, te ayudo con otra idea de publicación sin descuentos ni regalos.';
