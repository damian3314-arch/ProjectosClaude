/**
 * Los horarios por WhatsApp: una LISTA para elegir, no un párrafo.
 *
 * Damián (10 oct), mirando el primer chat real del asistente: «el bot está loco, le dijo a un cliente que hoy es martes (hoy es
 * sábado, estamos en Colombia). Y se ve muy feo: hay que encontrar una mejor manera de decirle los horarios para que la persona
 * escoja».
 *
 * Qué se arregló y por qué así:
 *   · el modelo NO sabía qué día era hoy: solo recibía «martes 13 de octubre» y adivinó. Ahora el código le da la fecha de hoy en
 *     Bogotá y marca cada horario con su fecha (AAAA-MM-DD) y con «hoy» / «mañana»;
 *   · el modelo ya no escribe la lista de horarios: pide `mostrar_horarios` y el código manda la lista nativa de WhatsApp
 *     (se abre con un botón): primero el DÍA (con las horas de cada día a la vista) y después la HORA. Un toque cada vez, sin
 *     escribir, y los textos de los días y las horas salen de la base, no de la imaginación del modelo.
 *
 * Límites de WhatsApp para una lista: botón de hasta 20 caracteres, título de fila hasta 24, descripción hasta 72, hasta 10 filas.
 * Aquí todo son funciones puras (fáciles de probar); el envío está en index.js (`enviarListaWA`).
 */
import { miles } from './ventas.js';

const DIAS = ['domingo', 'lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado'];
const MESES = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];
const UN_DIA = 24 * 60 * 60 * 1000;

export const BOTON_DIAS = 'Ver días';
export const BOTON_HORAS = 'Ver horas';
export const TITULO_DIAS = 'Elige el día';
export const TITULO_HORAS = 'Elige la hora';

const cap = (t) => String(t || '').charAt(0).toUpperCase() + String(t || '').slice(1);

/** «2026-10-10» → «sábado 10 de octubre». */
export function textoDeFecha(iso) {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(iso || ''));
  if (!m) return null;
  const dt = new Date(Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3]), 12));
  // Una fecha que no existe (31 de febrero) no es una fecha: Date la corre al mes siguiente.
  if (!Number.isFinite(dt.getTime()) || dt.getUTCDate() !== Number(m[3]) || dt.getUTCMonth() !== Number(m[2]) - 1) return null;
  return `${DIAS[dt.getUTCDay()]} ${Number(m[3])} de ${MESES[Number(m[2]) - 1]}`;
}

/** Hoy en Bogotá: la fecha, el día, el texto y la hora («9:51 am»). Esto es lo que el modelo NO podía adivinar. */
export function hoyBogota(ahoraMs = Date.now()) {
  const d = new Date(ahoraMs);
  const fecha = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Bogota' }).format(d);
  const hh = Number(new Intl.DateTimeFormat('en-GB', { timeZone: 'America/Bogota', hour: '2-digit', hour12: false }).format(d)) % 24;
  const mm = new Intl.DateTimeFormat('en-GB', { timeZone: 'America/Bogota', minute: '2-digit' }).format(d).padStart(2, '0');
  const h12 = hh % 12 === 0 ? 12 : hh % 12;
  const texto = textoDeFecha(fecha);
  return { fecha, dia: texto.split(' ')[0], texto, hora: `${h12}:${mm} ${hh < 12 ? 'am' : 'pm'}` };
}

/** «martes 13 de octubre» → «2026-10-13» (el año sale de hoy: la lista de la base es de los próximos 8 días). */
export function fechaDeTexto(texto, ahoraMs = Date.now()) {
  const m = /(\d{1,2})\s+de\s+([a-záéíóú]+)/i.exec(String(texto || ''));
  if (!m) return null;
  const mes = MESES.indexOf(m[2].toLowerCase());
  const dia = Number(m[1]);
  if (mes < 0 || dia < 1 || dia > 31) return null;
  const hoy = hoyBogota(ahoraMs).fecha;
  let anio = Number(hoy.slice(0, 4));
  const pad = (n) => String(n).padStart(2, '0');
  let iso = `${anio}-${pad(mes + 1)}-${pad(dia)}`;
  // Si ya pasó hace mucho (ej. diciembre → enero), es del año que viene.
  if (Date.parse(`${iso}T12:00:00Z`) < Date.parse(`${hoy}T12:00:00Z`) - 60 * UN_DIA) { anio += 1; iso = `${anio}-${pad(mes + 1)}-${pad(dia)}`; }
  const vuelta = textoDeFecha(iso);
  return vuelta && vuelta.includes(` ${dia} de ${MESES[mes]}`) ? iso : null;
}

/** A cada horario le agrega su fecha (AAAA-MM-DD) y si es «hoy» o «mañana». */
export function conFechas(horarios, ahoraMs = Date.now()) {
  const hoy = hoyBogota(ahoraMs).fecha;
  const manana = hoyBogota(ahoraMs + UN_DIA).fecha;
  return (Array.isArray(horarios) ? horarios : []).map((h) => {
    const fecha = fechaDeTexto(h && h.fecha_texto, ahoraMs);
    return { ...h, fecha, cuando: fecha === hoy ? 'hoy' : fecha === manana ? 'mañana' : '' };
  });
}

/** Los horarios agrupados por día, en el orden en que vienen (cronológico). */
export function diasDe(horarios) {
  const por = new Map();
  for (const h of (Array.isArray(horarios) ? horarios : [])) {
    if (!h || !h.fecha) continue;
    if (!por.has(h.fecha)) por.set(h.fecha, { fecha: h.fecha, fecha_texto: h.fecha_texto, cuando: h.cuando || '', clases: [] });
    por.get(h.fecha).clases.push(h);
  }
  return [...por.values()];
}

// ── la lista de DÍAS ───────────────────────────────────────────────────────────────────────────────────────────
/** El título de la fila de un día (máx. 24): «Hoy · sábado 10», «Mañana · domingo 11», «Martes 13 de octubre». */
export function etiquetaDia(d) {
  const [dia, num, , mes] = String(d.fecha_texto || '').split(' ');
  const pre = d.cuando === 'hoy' ? 'Hoy · ' : d.cuando === 'mañana' ? 'Mañana · ' : '';
  let t = pre ? `${pre}${dia} ${num}` : cap(d.fecha_texto);
  if (t.length > 24) t = `${pre}${pre ? dia : cap(dia)} ${num} ${String(mes || '').slice(0, 3)}`;
  return t.slice(0, 24);
}

/** Las filas de la lista de días: cada una trae las horas de ese día a la vista. */
export function filasDeDias(dias) {
  return dias.slice(0, 10).map((d) => ({
    id: `asist:d:${d.fecha}`,
    title: etiquetaDia(d),
    description: d.clases.map((h) => h.hora_texto).join(' · ').slice(0, 72),
  }));
}

export function cuerpoDeDias(lead) {
  const l = String(lead || '').trim();
  return l && l.length <= 300 ? `${l}\n\nToca *${BOTON_DIAS}* y elige el que te sirva 👇` : `¿Para qué día quieres tu clase? Toca *${BOTON_DIAS}* y elige 👇`;
}

// ── la lista de HORAS de un día ────────────────────────────────────────────────────────────────────────────────
// «Clase 7:00 am» no dice nada que la hora no diga; «Rumba básica» sí.
const nombreEspecial = (h) => (h && h.clase && !/^clase\b/i.test(String(h.clase)) ? String(h.clase) : '');

export function filasDeHoras(dia) {
  return dia.clases.slice(0, 10).map((h) => {
    const esp = nombreEspecial(h);
    const cupos = Number(h.libres) === 1 ? 'Queda 1 cupo' : `Quedan ${Number(h.libres)} cupos`;
    return {
      id: `asist:c:${h.clase_id}`,
      title: (esp ? `${h.hora_texto} · ${esp}` : String(h.hora_texto)).slice(0, 24),
      description: `${cupos} · $${miles(Number(h.precio_cop) || 0)}`.slice(0, 72),
    };
  });
}

export function cuerpoDeHoras(dia) {
  const cuando = dia.cuando ? ` (${dia.cuando})` : '';
  return `*${cap(dia.fecha_texto)}*${cuando} 🗓️\n¿A qué hora? Toca *${BOTON_HORAS}* y elige 👇`;
}

/** Dijo un día que no tiene clases con cupo (o ya pasó): se le dice sin enredos y se le muestran los días que sí. */
export function textoSinClasesEseDia(fechaPedida, ahoraMs = Date.now()) {
  const hoy = hoyBogota(ahoraMs).fecha;
  if (fechaPedida && fechaPedida === hoy) return 'Hoy ya no quedan clases con cupo 🙈 Estos son los próximos días 👇';
  const t = fechaPedida && textoDeFecha(fechaPedida);
  return t ? `El ${t} no hay clases con cupo 🙈 Estos son los días que sí tienen 👇` : 'Ese día no hay clases con cupo 🙈 Estos son los días que sí tienen 👇';
}

/** Tocó una hora: se le confirma lo elegido y se le pide solo lo que falta, el nombre. */
export function textoPideNombre(h) {
  const esp = nombreEspecial(h);
  return `¡Perfecto! Elegiste el ${h.fecha_texto} a las ${h.hora_texto}${esp ? ` (${esp})` : ''} 🙌\n\n¿A nombre de quién la reservo? Escríbeme tu nombre y apellido.`;
}

/** Si WhatsApp no deja mandar la lista: los próximos días en texto, una línea por día, para que escriba cuál. */
export function textoDiasPlano(dias) {
  const lineas = dias.slice(0, 4).map((d) => `• ${cap(String(d.fecha_texto).split(' ').slice(0, 2).join(' '))}: ${d.clases.map((h) => h.hora_texto).join(' · ')}`);
  return `Estos son los próximos horarios con cupo:\n${lineas.join('\n')}\n\nDime qué día y a qué hora la quieres 🙂`;
}

// ── lo que llega cuando la persona toca una fila ───────────────────────────────────────────────────────────────
/** El toque llega guardado como «[lista:asist:d:2026-10-13] Martes 13 de octubre» (un texto escrito a mano no cuenta: tipo «interactive»). */
export function leerLista(texto, tipo) {
  if (tipo !== 'interactive') return null;
  const m = /^\[lista:asist:(d|c):(\d{4}-\d{2}-\d{2}|[0-9a-f-]{36})\]/i.exec(String(texto || ''));
  if (!m) return null;
  return m[1].toLowerCase() === 'd' ? { tipo: 'dia', fecha: m[2] } : { tipo: 'clase', clase_id: m[2].toLowerCase() };
}

/** Lo que se anota como mensaje de la persona cuando elige una hora (el modelo lo lee en el historial). */
export const textoEleccion = (h) => `(eligió la clase del ${h.fecha_texto} a las ${h.hora_texto})`;

/** La clase que la persona eligió en la lista justo antes de este mensaje (para que el modelo solo le pida el nombre). */
export function eleccionPrevia(historial, horarios) {
  const h = Array.isArray(historial) ? historial : [];
  for (let i = h.length - 1; i >= 0; i--) {
    if (h[i].direccion !== 'entrante') continue;
    const m = /^\(eligió la clase del (.+) a las (.+)\)$/.exec(String(h[i].texto || ''));
    if (!m) return null; // lo último que escribió no fue elegir: ya no cuenta
    const x = (Array.isArray(horarios) ? horarios : []).find((c) => c.fecha_texto === m[1] && c.hora_texto === m[2]);
    return x ? { n: x.n, clase: x.clase, fecha_texto: x.fecha_texto, hora_texto: x.hora_texto } : null;
  }
  return null;
}

/** ¿El texto del modelo trae una lista de horarios (3 o más horas)? Eso lo muestra la lista, no un párrafo. */
export function traeListaDeHoras(texto) {
  return (String(texto || '').match(/\b\d{1,2}:\d{2}\s*[ap]\.?\s?m\b/gi) || []).length >= 3;
}
