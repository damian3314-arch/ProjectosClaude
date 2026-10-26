/**
 * Asistente de leads de Loggro.
 *
 * Una rutina horaria le escribe el primer mensaje (plantilla aprobada) a los leads que HubSpot le asigna a Damián y los registra en
 * `loggro_leads`. Si el lead responde, el mensaje llega aquí y NO al flujo de HolaDami:
 *   producto (botones de la plantilla) → tamaño → cómo lo lleva hoy → cuándo lo quiere. 3 preguntas, con botones.
 * Si quiere avanzar (esta semana o este mes), Damián recibe un aviso para llamarlo; si no, queda anotado.
 *
 * Reglas:
 *  - Se presenta como "el asistente de Damián". El primer mensaje lo firma Damián (plantilla); desde la primera respuesta se aclara.
 *  - Lo que escribe el lead es DATO. Nunca se ejecuta.
 *  - Los avisos a Damián solo salen entre las 9 am y las 9 pm (hora de Bogotá); fuera de horario esperan a la siguiente hora en punto.
 *  - Después de terminar, el asistente calla: sigue Damián a mano, desde Kapso.
 */

const MAX_MSGS = 30;
const REPLY_ALERT_MINUTES = 30;
export const ALERT_FROM_HOUR = 9, ALERT_TO_HOUR = 21; // hora de Bogotá

const PRODUCTS = {
  restobar:     { name: 'Loggro Restobar',     q: '¿Cuántas mesas tiene tu restaurante o bar?',  sizes: [['s1', 'Hasta 10'], ['s2', '11 a 30'], ['s3', 'Más de 30']] },
  pos:          { name: 'Loggro POS',          q: '¿Cuántos puntos de venta o cajas tienes?',    sizes: [['s1', '1 punto'], ['s2', '2 a 5'], ['s3', 'Más de 5']] },
  alojamientos: { name: 'Loggro Alojamientos', q: '¿Cuántas habitaciones tiene tu alojamiento?', sizes: [['s1', 'Hasta 10'], ['s2', '11 a 30'], ['s3', 'Más de 30']] },
  pymes:        { name: 'Loggro Pymes',        q: '¿Cuántas facturas emites más o menos al mes?', sizes: [['s1', 'Hasta 50'], ['s2', '50 a 300'], ['s3', 'Más de 300']] },
  nomina:       { name: 'Loggro Nómina',       q: '¿Cuántos empleados tienes?',                  sizes: [['s1', 'Hasta 10'], ['s2', '11 a 50'], ['s3', 'Más de 50']] },
};
const SYSTEM = [['sw', 'Otro software'], ['manual', 'Excel o a mano'], ['none', 'Aún no lo llevo']];
const WHEN = [['now', 'Esta semana'], ['month', 'Este mes'], ['later', 'Solo averiguando']];
const PN = [['pymes', 'Facturación'], ['nomina', 'Nómina'], ['pymes_nomina', 'Las dos']];
const LABEL = {
  size: { s1: 'tamaño pequeño', s2: 'tamaño mediano', s3: 'tamaño grande' },
  system: Object.fromEntries(SYSTEM.map(([id, t]) => [id, t])),
  urgency: { now: 'lo quiere esta semana', month: 'lo quiere este mes', later: 'solo está averiguando' },
};
const STOP_RE = /^\s*(stop|baja|cancelar|no me escriban|no me escribas|no quiero|(ya )?no me interesa)\s*[.!]*\s*$/i;

// Qué producto sugiere lo que escribió o el botón que tocó
export function detectProducts(text) {
  const t = String(text || '').toLowerCase();
  const found = new Set();
  if (/restaur|restobar|\bbar\b|comida|caf[eé]|cocina|\bmesas?\b/.test(t)) found.add('restobar');
  if (/hotel|alojamiento|hostal|habitaci|posada|cabañ|finca/.test(t)) found.add('alojamientos');
  if (/n[oó]mina|empleados|liquidar/.test(t)) found.add('nomina');
  if (/pyme|factur|contabil|empresa|servicios/.test(t)) found.add('pymes');
  if (/tienda|punto de venta|\bpos\b|comercio|supermercado|inventario|\bventas?\b/.test(t)) found.add('pos');
  return [...found];
}

export async function handleLoggroInbound(env, ctx, h, inb, row) {
  if (row.state === 'optout') return;
  if (row.last_msg_id === inb.id) return;
  const claim = await env.DB.prepare(`UPDATE loggro_leads SET last_msg_id = ?, msg_count = msg_count + 1, updated_at = datetime('now')
      WHERE phone = ? AND (last_msg_id IS NULL OR last_msg_id != ?)`).bind(inb.id, row.phone, inb.id).run();
  if (!claim.meta?.changes) return;
  if ((row.msg_count || 0) >= MAX_MSGS) return;

  const c = { env, ctx, h, inb, row, dest: { to: row.phone }, first: h.clean(row.name || inb.name, 40).split(' ')[0] || '' };

  if (STOP_RE.test(inb.text)) {
    await save(c, { state: 'optout' });
    return sendText(c, 'Listo, no te escribo más. Si más adelante lo necesitas, escríbeme cuando quieras.');
  }

  switch (row.state) {
    case 'pending': case 'sent': return onFirstReply(c);
    case 'retomar':  return onRetomar(c);
    case 'q_pn':     return onPn(c);
    case 'q_size':   return onChoice(c, 'size', sizeOptions(row.product), 'q_system');
    case 'q_system': return onChoice(c, 'system', SYSTEM, 'q_when');
    case 'q_when':   return onChoice(c, 'urgency', WHEN, null);
    case 'done':     return onAfterDone(c);
    default: return;
  }
}

// Campaña de rescate a leads tibios (plantilla loggro_retomar): "Sí, agendemos" o cualquier respuesta con interés → aviso a Damián.
// "Más adelante" queda anotado sin aviso. "Ya no me interesa" lo atiende STOP_RE (no se le vuelve a escribir).
async function onRetomar(c) {
  const t = `${c.inb.buttonId} ${c.inb.text}`.toLowerCase();
  if (/m[aá]s adelante|despu[eé]s|otro momento|ahora no|el otro a[nñ]o|enero/.test(t)) {
    await save(c, { state: 'done', hot: 0, summary: 'Campaña de rescate: quiere retomar más adelante.' });
    return sendText(c, `Listo${c.first ? ', ' + c.first : ''}, lo dejo anotado. Cuando quieras retomar, escríbeme por aquí y Damián te contacta.`);
  }
  const said = /^s[ií],? agendemos$/i.test(c.inb.text.trim()) ? '' : ` Escribió: «${h2(c.h, c.inb.text, 160)}».`;
  const summary = `Campaña de rescate: quiere retomar la demo.${said}`;
  await save(c, { state: 'done', hot: 1, summary });
  await maybeAlert(c);
  return sendText(c, `¡Perfecto${c.first ? ', ' + c.first : ''}! Soy el asistente de Damián. Le aviso para que te escriba y agenden la demo. Si tienes un día y una hora que te sirvan, escríbelos aquí.`);
}

const sizeOptions = product => (PRODUCTS[product] || PRODUCTS.pymes).sizes;
const greet = c => (c.first ? `Gracias, ${c.first}.` : 'Gracias.');

async function onFirstReply(c) {
  const found = detectProducts(c.inb.text);
  const both = found.includes('pymes') && found.includes('nomina');
  if (both || (found.length === 0 && /empresa/i.test(c.inb.text))) {
    await save(c, { state: 'q_pn' });
    return sendButtons(c, `${greet(c)} Soy el asistente de Damián. Para orientarte bien: ¿qué necesitas resolver?`, PN);
  }
  if (found.length !== 1) {
    await save(c, { state: 'sent' });
    return sendList(c, `${greet(c)} Soy el asistente de Damián. Para orientarte bien, ¿cuál se parece más a tu negocio?`, [
      ['restobar', 'Restaurante o bar'], ['pos', 'Tienda o punto de venta'], ['alojamientos', 'Hotel o alojamiento'], ['pymes', 'Empresa: facturación'], ['nomina', 'Nómina'],
    ]);
  }
  return askSize(c, found[0], true);
}

async function onPn(c) {
  const t = `${c.inb.buttonId} ${c.inb.text}`.toLowerCase();
  let product = null;
  if (/pymes_nomina|las dos|ambas|los dos/.test(t)) product = 'pymes';
  else if (/n[oó]mina/.test(t)) product = 'nomina';
  else if (/factur|pymes|contabil/.test(t)) product = 'pymes';
  if (!product) return sendButtons(c, 'Toca una de las opciones 👇 ¿qué necesitas resolver?', PN);
  return askSize(c, product, false);
}

async function askSize(c, product, intro) {
  const P = PRODUCTS[product];
  await save(c, { state: 'q_size', product });
  c.row = { ...c.row, product };
  const lead = intro ? `${greet(c)} Soy el asistente de Damián: te hago 3 preguntas rápidas para que te oriente con el producto correcto.\n\n` : '1 de 3: ';
  return sendButtons(c, `${lead}${intro ? '1 de 3: ' : ''}${P.q}`, P.sizes);
}

async function onChoice(c, field, options, next) {
  const typed = c.inb.text.toLowerCase();
  const idx = ['1', '2', '3'].indexOf(typed);
  const choice = options.find(([id, title]) => id === c.inb.buttonId || title.toLowerCase() === typed) || (idx >= 0 ? options[idx] : null);
  if (!choice) return sendButtons(c, 'Toca una de las opciones 👇', options);
  const fields = { [field]: choice[0] };
  if (next === 'q_system') {
    await save(c, { ...fields, state: 'q_system' });
    return sendButtons(c, `2 de 3: ¿cómo llevas hoy ${c.row.product === 'nomina' ? 'la nómina' : 'tus ventas, inventario o facturación'}?`, SYSTEM);
  }
  if (next === 'q_when') {
    await save(c, { ...fields, state: 'q_when' });
    return sendButtons(c, '3 de 3: ¿cuándo te gustaría tenerlo funcionando?', WHEN);
  }
  // Última respuesta: se decide si está caliente
  const urgency = choice[0];
  const hot = urgency === 'now' || urgency === 'month';
  const P = PRODUCTS[c.row.product] || PRODUCTS.pymes;
  const row = { ...c.row, urgency };
  const summary = buildSummary(row, P);
  await save(c, { urgency, hot: hot ? 1 : 0, state: 'done', summary });
  c.row = { ...row, hot: hot ? 1 : 0, summary };
  if (hot) await maybeAlert(c);
  return sendText(c, hot
    ? `Perfecto${c.first ? ', ' + c.first : ''}. Con lo que me cuentas, ${P.name} puede servirte. Damián te va a contactar hoy para mostrarte cómo funciona. Si prefieres una hora, escríbela aquí.`
    : `${greet(c)} Ya quedó anotado. Cuando quieras avanzar con ${P.name}, escríbeme por aquí y Damián te contacta.`);
}

// Después de terminar: el asistente calla. Si es un lead caliente y escribe algo (por ejemplo una hora), se le avisa a Damián.
async function onAfterDone(c) {
  if (!c.row.hot || !c.inb.text) return;
  const last = c.row.reply_alert_at ? Date.parse(String(c.row.reply_alert_at).replace(' ', 'T') + 'Z') : 0;
  if (Date.now() - last < REPLY_ALERT_MINUTES * 60e3) return;
  await save(c, { reply_alert_at: new Date(Date.now()).toISOString().slice(0, 19).replace('T', ' ') });
  const text = `💬 ${c.row.name || 'Un lead'} (+${c.row.phone}) escribió: «${h2(c.h, c.inb.text, 160)}». Responde desde tu bandeja de Kapso.`;
  return c.h.alertMessage(c.env, text, c.env.KAPSO_LOGGRO_ALERT_TEMPLATE);
}

// Aviso a Damián: solo entre las 9 am y las 9 pm; fuera de horario espera a la siguiente hora en punto (la envía el cron)
async function maybeAlert(c) {
  const hour = new Date(Date.now() - 5 * 3600e3).getUTCHours();
  if (hour < ALERT_FROM_HOUR || hour >= ALERT_TO_HOUR) return;
  if (await sendHotAlert(c.env, c.h, c.row)) {
    await c.env.DB.prepare("UPDATE loggro_leads SET alerted_at = datetime('now') WHERE phone = ?").bind(c.row.phone).run();
  }
}

export function hotAlertText(row) {
  return `🔥 Lead de Loggro listo para llamar: ${row.name || 'Sin nombre'} +${row.phone}. ${row.summary || ''} Llámalo: https://wa.me/${row.phone}`.replace(/\s+/g, ' ').trim();
}
export function sendHotAlert(env, h, row) {
  return h.alertMessage(env, hotAlertText(row), env.KAPSO_LOGGRO_ALERT_TEMPLATE);
}

function buildSummary(row, P) {
  return [P.name, LABEL.size[row.size] ? `${LABEL.size[row.size]} (${(P.sizes.find(s => s[0] === row.size) || [])[1] || ''} ${unit(row.product)})` : '', `hoy: ${LABEL.system[row.system] || '—'}`, LABEL.urgency[row.urgency] || ''].filter(Boolean).join(' · ') + '.';
}
const unit = p => ({ restobar: 'mesas', pos: 'puntos de venta', alojamientos: 'habitaciones', pymes: 'facturas al mes', nomina: 'empleados' }[p] || '');
const h2 = (h, t, n) => h.clean(String(t).replace(/\s+/g, ' '), n).replace(/[*_~`]/g, '');

async function save(c, fields) {
  const cols = Object.keys(fields);
  await c.env.DB.prepare(`UPDATE loggro_leads SET ${cols.map(k => `${k} = ?`).join(', ')}, updated_at = datetime('now') WHERE phone = ?`)
    .bind(...cols.map(k => fields[k] ?? null), c.row.phone).run();
  c.row = { ...c.row, ...fields };
}

const sendText = (c, body) => c.h.sendWhatsApp(c.env, { messaging_product: 'whatsapp', ...c.dest, type: 'text', text: { body: body.slice(0, 1024), preview_url: false } });
const sendButtons = (c, body, options) => c.h.sendWhatsApp(c.env, {
  messaging_product: 'whatsapp', ...c.dest, type: 'interactive',
  interactive: { type: 'button', body: { text: body.slice(0, 1024) }, action: { buttons: options.slice(0, 3).map(([id, title]) => ({ type: 'reply', reply: { id, title: title.slice(0, 20) } })) } },
});
const sendList = (c, body, rows) => c.h.sendWhatsApp(c.env, {
  messaging_product: 'whatsapp', ...c.dest, type: 'interactive',
  interactive: { type: 'list', body: { text: body.slice(0, 1024) }, action: { button: 'Ver opciones', sections: [{ title: 'Tu negocio', rows: rows.map(([id, title]) => ({ id, title: title.slice(0, 24) })) }] } },
});
