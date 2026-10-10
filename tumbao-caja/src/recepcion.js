/**
 * Cómo manda el bot a la gente a recepción.
 *
 * Damián (10 oct): «que el bot le diga "tranquilo, te escribimos de otro número": descártalo. Ese bot debe ayudar en lo que
 * más pueda y, si algo sale mal, decir "por favor escríbenos al de recepción" y darle un enlace tipo wa.me para que de una
 * le abra la conversación con ese número».
 *
 * Por qué importa: este número (el del bot) no es el de recepción. Prometerle a alguien «te escribimos hoy» lo deja
 * esperando a que otra persona, desde otro número, se acuerde. Un enlace wa.me convierte «hay que hablar con una persona»
 * en un toque: se abre el chat de recepción, y con el mensaje ya escrito (quién es y qué necesita) para que recepción no
 * tenga que preguntar nada.
 *
 * El enlace lo arma SIEMPRE el código, nunca el modelo: así no se inventa un número ni un texto raro.
 */

export const NUMERO_RECEPCION = '573017833550';
export const NUMERO_RECEPCION_BONITO = '301 783 3550';
export const ENLACE_RECEPCION = `https://wa.me/${NUMERO_RECEPCION}`;

// Lo que viene de la conversación (nombre, motivo) se limpia antes de ir en un enlace: sin enlaces, sin números largos
// (un celular o una cuenta no deben viajar en una URL) y sin saltos de línea.
function limpio(texto, max) {
  return String(texto == null ? '' : texto)
    .replace(/https?:\/\/\S+|www\.\S+/gi, ' ')
    .replace(/\d{6,}/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, max)
    .trim();
}

/**
 * El enlace que abre el chat de recepción, con el mensaje ya escrito.
 * @param {{nombre?: string, motivo?: string}} [datos]
 */
export function enlaceRecepcion({ nombre, motivo } = {}) {
  const n = limpio(nombre, 40);
  const m = limpio(motivo, 90).replace(/[.\s]+$/, '');
  if (!n && !m) return ENLACE_RECEPCION;
  const texto = `Hola, ${n ? 'soy ' + n + '. ' : ''}${m ? 'Necesito ayuda con: ' + m + '.' : 'Necesito ayuda.'}`.replace(/\s+/g, ' ').trim();
  return `${ENLACE_RECEPCION}?text=${encodeURIComponent(texto)}`;
}

/** La frase de cierre cuando el bot no puede resolver algo: pide escribir a recepción y da el enlace. */
export function lineaRecepcion(datos) {
  return `Escríbenos a recepción y te ayudan de una 👉 ${enlaceRecepcion(datos)}`;
}

/** ¿El texto ya trae el enlace a recepción? (para no ponerlo dos veces) */
export function llevaEnlaceRecepcion(texto) {
  return /wa\.me\/573017833550/i.test(String(texto || ''));
}

/** Agrega la línea de recepción al final de un mensaje, una sola vez. */
export function conRecepcion(texto, datos) {
  const t = String(texto || '').trim();
  return llevaEnlaceRecepcion(t) ? t : `${t}${t ? '\n\n' : ''}${lineaRecepcion(datos)}`;
}

/**
 * Las frases que prometen que ALGUIEN va a escribir o llamar («te escribimos», «el equipo te escribe», «desde otro
 * número»). El bot no puede prometer eso: este número no es el de recepción y nadie queda pendiente de escribirle. Si el
 * modelo las escribe igual, la baranda corta el mensaje y va el texto seguro con el enlace a recepción.
 * No toca «escríbenos» ni «te escribo» (quien escribe es la persona, o el propio bot ahora).
 */
export const PROMETE_ESCRIBIR =
  /(?<![\p{L}\p{N}])(?:te\s+(?:escrib(?:imos|iremos|en|e|ir[aá]|ir[aá]n)|contact(?:amos|aremos|an|ar[aá]|ar[aá]n)|llam(?:amos|aremos|an|ar[aá]|ar[aá]n))|nos\s+comunicamos|nos\s+ponemos\s+en\s+contacto|(?:desde|por)\s+otro\s+n[uú]mero)(?![\p{L}\p{N}])/iu;
