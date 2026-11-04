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

// ── el mensaje que ya va escrito en el enlace: en PRIMERA persona, como lo escribiría la persona ───────────────────
// Damián (10 oct), viendo el chat de Andrea: «sale "Hola, soy Andrea. Necesito ayuda con: Andrea quiere pagar en efectivo…",
// como si hablara en tercera persona». El motivo lo escribe el modelo (o el código) pensando en recepción («Andrea quiere…»,
// «Necesita ayuda porque no puede…»); aquí se pasa a lo que la persona le diría a recepción («Quiero…», «Necesito ayuda porque
// no puedo…»). Lo que ya viene en primera persona se deja igual, y una frase suelta («cambiar mi clase») va con «Necesito ayuda con:».
const TERCERA_PERSONA = [
  [/\bno\s+puede(?!\p{L})/giu, 'no puedo'], [/\bno\s+pudo(?!\p{L})/giu, 'no pude'], [/\bno\s+logra(?!\p{L})/giu, 'no logro'], [/\bno\s+logró(?!\p{L})/giu, 'no logré'],
  [/\bno\s+tuvo(?!\p{L})/giu, 'no tuve'], [/\bno\s+tiene(?!\p{L})/giu, 'no tengo'], [/\bya\s+pagó(?!\p{L})/giu, 'ya pagué'], [/\bpagó(?!\p{L})/giu, 'pagué'],
  [/\bquiere(?!\p{L})/giu, 'quiero'], [/\bnecesita(?!\p{L})/giu, 'necesito'], [/\bsolicita(?!\p{L})/giu, 'solicito'], [/\bpide(?!\p{L})/giu, 'pido'], [/\bdesea(?!\p{L})/giu, 'deseo'],
  [/\btiene(?!\p{L})/giu, 'tengo'], [/\btuvo(?!\p{L})/giu, 'tuve'], [/\bpuede(?!\p{L})/giu, 'puedo'], [/\bbusca(?!\p{L})/giu, 'busco'], [/\bpregunta(?!\p{L})/giu, 'pregunto'],
  [/\breporta(?!\p{L})/giu, 'reporto'], [/\bintentó(?!\p{L})/giu, 'intenté'], [/\bhizo(?!\p{L})/giu, 'hice'], [/\benvió(?!\p{L})/giu, 'envié'], [/\breservó(?!\p{L})/giu, 'reservé'],
  [/\brealizó(?!\p{L})/giu, 'realicé'], [/\bsu\s+(reserva|pago|clase|comprobante|cuenta|transferencia|cupo|c[oó]digo)(?!\p{L})/giu, 'mi $1'],
];
const V3 = 'no\\s+(?:puede|pudo|logra|logró|tuvo|tiene)|ya\\s+pagó|quiere|necesita|solicita|pide|desea|tiene|tuvo|puede|busca|pregunta|reporta|intentó|hizo|pagó|envió|reservó|realizó';
const VERBO_TERCERA = new RegExp(`^(?:su\\s+\\p{L}|(?:${V3})(?!\\p{L}))`, 'iu');
// «Andrea quiere…», «Ana María necesita…»: un nombre propio (con mayúscula) antes del verbo en tercera persona
const NOMBRE_Y_VERBO = new RegExp(`^(?:\\p{Lu}\\p{L}+\\s+){1,3}(?=(?:${V3})(?!\\p{L}))`, 'u');
const PRIMERA_PERSONA = /^(?:quiero|necesito|solicito|pido|deseo|tengo|puedo|busco|estoy|me\s|mi\s|mis\s|no\s+(?:pude|puedo|logr[eé]|logro|tuve|tengo|me\s)|ya\s+pagu[eé]|pagu[eé]|intent[eé]|hice|envi[eé]|reserv[eé])/i;
const escapar = (t) => t.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const mayuscula = (t) => t.charAt(0).toUpperCase() + t.slice(1);

/** El motivo, dicho por la persona. Sin punto final. */
export function enPrimeraPersona(motivo, nombre) {
  let t = limpio(motivo, 160).replace(/[.\s]+$/, '');
  if (!t) return '';
  const nom = limpio(nombre, 40).split(' ')[0];
  const sujeto = new RegExp(`^(?:${nom ? escapar(nom) + '|' : ''}la\\s+persona|el\\s+cliente|la\\s+clienta|ella|él)\\s+`, 'i');
  if (sujeto.test(t) || NOMBRE_Y_VERBO.test(t) || VERBO_TERCERA.test(t)) {
    t = t.replace(sujeto, '').replace(NOMBRE_Y_VERBO, '');
    for (const [re, por] of TERCERA_PERSONA) t = t.replace(re, por);
    return mayuscula(t);
  }
  if (PRIMERA_PERSONA.test(t)) return mayuscula(t);
  return `Necesito ayuda con: ${t.charAt(0).toLowerCase()}${t.slice(1)}`;
}

/**
 * El enlace que abre el chat de recepción, con el mensaje ya escrito.
 * @param {{nombre?: string, motivo?: string}} [datos]
 */
export function enlaceRecepcion({ nombre, motivo } = {}) {
  const n = limpio(nombre, 40);
  const m = enPrimeraPersona(motivo, nombre);
  if (!n && !m) return ENLACE_RECEPCION;
  const texto = `Hola${n ? ', soy ' + n : ''}. ${m ? m + '.' : 'Necesito ayuda.'}`.replace(/\s+/g, ' ').trim();
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
