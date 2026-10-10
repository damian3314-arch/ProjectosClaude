/**
 * Los horarios por WhatsApp, como los diría una persona de recepción.
 *
 * Damián (10 oct), mirando el primer chat real del asistente: «el bot le dijo a un cliente que hoy es martes (hoy es sábado, estamos
 * en Colombia)» y «los horarios se ven muy feo».
 * Y después de probar la primera solución (listas de WhatsApp con botones «Ver días» / «Ver horas»): «ahora todo se volvió una
 * toquedera; recuerda que es como hablar con un humano y ese montón de botones rompe eso. Es decirle al cliente el listado de
 * horarios fijos que manejamos y que diga "quiero el martes a las 7 pm". El objetivo es lograr la reserva y que se sienta humano».
 *
 * Por eso:
 *   · el código le da al modelo la fecha de HOY en Bogotá y marca cada horario con su fecha (AAAA-MM-DD) y «hoy»/«mañana»: antes
 *     el modelo adivinaba qué día era;
 *   · cuando la persona quiere ver los horarios, el CÓDIGO arma un bloque corto con el horario fijo agrupado por días iguales
 *     («Martes y jueves: 7:00 am, 5:00 pm y 7:00 pm»), con las horas que salen de la base, y después le pide lo único que falta:
 *     «dime qué día y a qué hora te sirve y a nombre de quién la reservo». Un solo mensaje, sin botones; ella contesta escribiendo.
 * Los únicos botones que quedan son los de la autorización de datos (Sí, autorizo / No autorizo), que Damián pidió.
 */

const DIAS = ['domingo', 'lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado'];
const ORDEN_SEMANA = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
const MESES = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];
const UN_DIA = 24 * 60 * 60 * 1000;

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

// ── el horario fijo, en un bloque corto y con aire ─────────────────────────────────────────────────────────────
// «Clase 7:00 am» no dice nada que la hora no diga; «Rumba básica» sí.
const nombreEspecial = (h) => (h && h.clase && !/^clase\b/i.test(String(h.clase)) ? String(h.clase) : '');
const unir = (a) => (a.length <= 1 ? a.join('') : `${a.slice(0, -1).join(', ')} y ${a[a.length - 1]}`);

const RELOJ_EN_PUNTO = ['🕛', '🕐', '🕑', '🕒', '🕓', '🕔', '🕕', '🕖', '🕗', '🕘', '🕙', '🕚'];
const RELOJ_Y_MEDIA = ['🕧', '🕜', '🕝', '🕞', '🕟', '🕠', '🕡', '🕢', '🕣', '🕤', '🕥', '🕦'];
/** El relojito de una hora («5:00 pm» → 🕔; «7:30 am» → 🕢). Cualquier minuto se redondea a la hora o a la media. */
export function relojDe(horaTexto) {
  const m = /^(\d{1,2}):(\d{2})/.exec(String(horaTexto || '').trim());
  if (!m) return '🕐';
  const hh = Number(m[1]) % 12;
  return Number(m[2]) >= 15 && Number(m[2]) < 45 ? RELOJ_Y_MEDIA[hh] : RELOJ_EN_PUNTO[(hh + (Number(m[2]) >= 45 ? 1 : 0)) % 12];
}

/** Una línea por hora: «🕔 5:00 pm · _Rumba básica_». */
const lineaDeHora = (h) => `${relojDe(h.hora_texto)} ${h.hora_texto}${nombreEspecial(h) ? ` · _${nombreEspecial(h)}_` : ''}`;

/**
 * El horario fijo, para WhatsApp: el día en negrita y cada hora en su línea, con una línea en blanco entre un grupo y otro
 * (los días que tienen las mismas horas van juntos):
 *   *Martes y jueves*
 *   🕖 7:00 am
 *   🕔 5:00 pm · _Rumba básica_
 *   🕕 6:00 pm
 *
 *   *Sábado*
 *   🕗 8:00 am
 * Sale de las clases con cupo de los próximos días; de cada día de la semana se toma la fecha que tiene MÁS horas (hoy, a media
 * mañana, solo conserva las de la tarde: no es «el horario del sábado»).
 */
export function horarioSemanal(horarios) {
  const por = new Map();
  for (const d of diasDe(horarios)) {
    const dia = String(d.fecha_texto || '').split(' ')[0];
    const previo = por.get(dia);
    if (!previo || d.clases.length > previo.length) por.set(dia, d.clases);
  }
  const grupos = new Map(); // firma de horas → días
  for (const dia of ORDEN_SEMANA) {
    if (!por.has(dia)) continue;
    const firma = por.get(dia).map((h) => `${h.hora_texto}|${nombreEspecial(h)}`).join(';');
    if (!grupos.has(firma)) grupos.set(firma, { dias: [], clases: por.get(dia) });
    grupos.get(firma).dias.push(dia);
  }
  return [...grupos.values()].map((g) => `*${cap(unir(g.dias))}*\n${g.clases.map(lineaDeHora).join('\n')}`).join('\n\n');
}

/** Lo que se pide al final: un solo mensaje, y ella contesta escribiendo (como con una persona). */
export const CIERRE_HORARIOS = '✍️ Cuéntame *qué día y hora* te sirve y *a nombre de quién* la reservo, y te la dejo lista por aquí 🙌\n\nSi prefieres, reserva tú en https://tumbaobaila.com';

/** El mensaje de los horarios: una frase de arranque (del modelo, si pasó la baranda), el bloque y lo que falta. */
export function textoHorarios(horarios, lead) {
  const bloque = horarioSemanal(horarios);
  if (!bloque) return null;
  let l = String(lead || '').trim();
  if (traeListaDeHoras(l)) l = ''; // el bloque YA trae las horas; una lista escrita por el modelo sobra
  return `${l || 'Estos son nuestros horarios 💃'}\n\n${bloque}\n\n${CIERRE_HORARIOS}`;
}

/**
 * ¿El texto del modelo trae una lista larga de horarios (varios días seguidos)? Eso lo muestra el bloque, no un párrafo apretado.
 * Contestar un día concreto («el martes hay a las 7:00 am, 5:00 pm, 6:00 pm y 7:00 pm») son 4 horas y es natural: no cuenta.
 */
export function traeListaDeHoras(texto, minimo = 7) {
  return (String(texto || '').match(/\b\d{1,2}:\d{2}\s*[ap]\.?\s?m\b/gi) || []).length >= minimo;
}
