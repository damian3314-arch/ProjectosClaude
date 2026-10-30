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

import { agentTurn } from './agent.js';

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
  if ((row.msg_count || 0) >= (agentOn(env) ? 200 : MAX_MSGS)) return;

  const c = { env, ctx, h, inb, row, dest: { to: row.phone }, first: h.clean(row.name || inb.name, 40).split(' ')[0] || '' };

  if (STOP_RE.test(inb.text)) {
    await save(c, { state: 'optout' });
    return sendText(c, 'Listo, no te escribo más. Si más adelante lo necesitas, escríbeme cuando quieras.');
  }

  // Agente conversacional: atiende cualquier etapa como un chat de persona. Si está apagado, siguen los botones de abajo.
  if (agentOn(env)) return agentTurn({ ...c, key: row.phone, source: 'loggro' });

  switch (row.state) {
    case 'pending': case 'sent': return onFirstReply(c);
    case 'retomar': case 'q_retomar': return onRetomar(c);
    case 'q_rescate': return onFirstReply(c);
    case 'demo':     return onDemo(c);
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

// Recordatorio de demo: mientras no haya plantilla de recordatorio aprobada, se le escribe con contacto_inicial y el texto con el
// link (guardado en summary) sale apenas responda, ya dentro de la ventana de 24 h. Luego queda como caliente: lo que escriba
// después le llega a Damián.
async function onDemo(c) {
  const msg = String(c.row.summary || '').trim();
  if (!msg) return;
  await save(c, { state: 'done', hot: 1, summary: 'Recordatorio de demo: se le envió la confirmación con el link.' });
  await sendText(c, msg);
  return c.h.alertMessage(c.env, `📅 ${c.row.name || 'Tu cliente'} (+${c.row.phone}) respondió y ya le envié el link de la demo. Escribió: «${h2(c.h, c.inb.text, 120)}».`, c.env.KAPSO_LOGGRO_ALERT_TEMPLATE);
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

export const agentOn = env => env.AGENT_V2 === 'on' && !!env.OPENAI_API_KEY;

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

/* ---------- Campaña de rescate: envío por lotes desde el cron ----------
 * Los leads viejos de Damián quedan en cola en loggro_leads con estado q_retomar (tibios) o q_rescate (sin contacto / perdidos).
 * Cada hora en punto, de 9 am a 7 pm (Bogotá), se envían hasta 30, con tope de 150 al día (el número nuevo de WhatsApp
 * puede escribirle a 250 personas por día y la rutina de leads nuevos necesita su parte). Primero los tibios.
 * Si Meta aún no aprueba la plantilla o hay un límite, se detiene y reintenta en la siguiente hora. Se apaga con RESCATE_ENVIOS != 'on'.
 */
export const RESCUE = { from: 9, to: 19, perRun: 30, perDay: 150 };
const STOP_CODES = new Set([132001, 132000, 131048, 130429, 131056, 368]); // plantilla no aprobada, límites o bloqueo temporal: parar
const BAD_NUMBER_CODES = new Set([131026, 131049, 131021]); // sin WhatsApp, Meta decidió no entregar, o es el mismo número

export async function rescueSend(env) {
  if (env.RESCATE_ENVIOS !== 'on' || !env.KAPSO_API_KEY || !env.KAPSO_PHONE_NUMBER_ID) return { sent: 0, reason: 'off' };
  const bogota = new Date(Date.now() - 5 * 3600e3);
  const hour = bogota.getUTCHours();
  if (hour < RESCUE.from || hour >= RESCUE.to) return { sent: 0, reason: 'hora' };
  const dayStart = `${bogota.toISOString().slice(0, 10)} 05:00:00`;
  const done = await env.DB.prepare("SELECT COUNT(*) AS n FROM events WHERE type = 'rescate_sent' AND created_at >= ?").bind(dayStart).first();
  const budget = Math.min(RESCUE.perRun, RESCUE.perDay - (done?.n || 0));
  if (budget <= 0) return { sent: 0, reason: 'tope' };
  const rows = (await env.DB.prepare(`SELECT phone, name, state FROM loggro_leads WHERE state IN ('q_retomar', 'q_rescate')
      ORDER BY CASE state WHEN 'q_retomar' THEN 0 ELSE 1 END, rowid LIMIT ?`).bind(budget).all()).results || [];
  let sent = 0;
  for (const r of rows) {
    const retomar = r.state === 'q_retomar';
    const res = await sendTemplate(env, r.phone, retomar ? 'loggro_retomar' : 'loggro_rescate', r.name || 'buen día');
    if (res.ok) {
      await env.DB.prepare("UPDATE loggro_leads SET state = ?, campaign = ?, wamid = ?, sent_at = datetime('now'), updated_at = datetime('now') WHERE phone = ? AND state = ?")
        .bind(retomar ? 'retomar' : 'sent', retomar ? 'retomar' : 'rescate', res.wamid || null, r.phone, r.state).run();
      await env.DB.prepare("INSERT INTO events (session_id, type) VALUES ('rescate', 'rescate_sent')").run();
      sent++;
    } else if (BAD_NUMBER_CODES.has(res.code)) {
      await env.DB.prepare("UPDATE loggro_leads SET state = 'failed', summary = ?, updated_at = datetime('now') WHERE phone = ?").bind(`Rescate: no se pudo entregar (${res.code}).`, r.phone).run();
    } else {
      return { sent, reason: STOP_CODES.has(res.code) ? `meta ${res.code}` : `error ${res.code || res.status}` };
    }
  }
  return { sent, reason: 'ok' };
}

async function sendTemplate(env, phone, name, param) {
  const params = (Array.isArray(param) ? param : [param]).map(x => ({ type: 'text', text: String(x).replace(/\s*\n\s*/g, ' ').slice(0, 200) }));
  try {
    const res = await fetch(`https://api.kapso.ai/meta/whatsapp/v24.0/${encodeURIComponent(env.KAPSO_PHONE_NUMBER_ID)}/messages`, {
      method: 'POST',
      headers: { 'X-API-Key': env.KAPSO_API_KEY, 'content-type': 'application/json' },
      body: JSON.stringify({ messaging_product: 'whatsapp', to: phone, type: 'template', template: { name, language: { code: 'es' }, components: params.length ? [{ type: 'body', parameters: params }] : [] } }),
      signal: AbortSignal.timeout(10000),
    });
    const body = await res.json().catch(() => ({}));
    if (!res.ok) console.error('Rescate', res.status, body?.error?.code, String(body?.error?.message || '').replace(/\d{5,}/g, '#').slice(0, 200));
    return { ok: res.ok, status: res.status, code: Number(body?.error?.code) || 0, wamid: body?.messages?.[0]?.id };
  } catch (err) { console.error('Rescate', err?.name || 'error'); return { ok: false, status: 0, code: 0 }; }
}

// Lo usa el agente conversacional: aviso de lead caliente (con el horario de siempre) y aviso cuando un lead caliente vuelve a escribir
export const alertHotLead = (env, h, row) => maybeAlert({ env, h, row });
export async function alertReply(env, h, row, text) {
  if (!text) return;
  const c = { env, h, row };
  return onAfterDone({ ...c, inb: { text } });
}

/* ---------- Bandeja de salida: el servidor envía lo que la rutina de HubSpot dejó en `outbox` ----------
 * Cada hora en punto, de 9 am a 7 pm (Bogotá), sale lo que ya toca (send_after vencido, estado 'queued'), con tope diario (OUTBOX_PER_DAY, 5 por
 * defecto mientras el número nuevo "se calienta") y sin escribirle a quien pidió la baja ni a quien ya recibió un mensaje en los últimos 7 días.
 * Al salir, el lead queda registrado en loggro_leads (estado 'sent') y, si responde, lo atiende Alter. Se apaga con OUTBOX_ENVIOS = 'off'.
 */
// Permite cambiar la plantilla que se usa sin tocar la rutina: OUTBOX_ALIAS = {"loggro_primer_contacto":"loggro_solicitud_info"}
function templateAlias(env, name) { try { return JSON.parse(env.OUTBOX_ALIAS || '{}')[name] || name; } catch { return name; } }
export const OUTBOX = { from: 9, to: 19, perDay: 5 };

export async function outboxSend(env) {
  if (env.OUTBOX_ENVIOS === 'off' || !env.KAPSO_API_KEY || !env.KAPSO_PHONE_NUMBER_ID) return { sent: 0, reason: 'off' };
  const bogota = new Date(Date.now() - 5 * 3600e3);
  const hour = bogota.getUTCHours();
  if (hour < OUTBOX.from || hour >= OUTBOX.to) return { sent: 0, reason: 'hora' };
  const dayStart = `${bogota.toISOString().slice(0, 10)} 05:00:00`;
  const done = await env.DB.prepare("SELECT COUNT(*) AS n FROM outbox WHERE status = 'sent' AND kind != 'recordatorio' AND sent_at >= ?").bind(dayStart).first();
  const cap = Number(env.OUTBOX_PER_DAY) > 0 ? Number(env.OUTBOX_PER_DAY) : OUTBOX.perDay;
  let budget = cap - (done?.n || 0);
  const rows = (await env.DB.prepare(`SELECT * FROM outbox WHERE status = 'queued' AND send_after <= datetime('now') ORDER BY CASE kind WHEN 'recordatorio' THEN 0 ELSE 1 END, send_after, id LIMIT 20`).all()).results || [];
  let sent = 0;
  for (const r of rows) {
    const reminder = r.kind === 'recordatorio';
    const mark = (status, error) => env.DB.prepare("UPDATE outbox SET status = ?, error = ? WHERE id = ?").bind(status, error || null, r.id).run();
    if (r.expires_at && r.expires_at < sqlTime(Date.now())) { await mark('skipped', 'vencido'); continue; }
    const lead = await env.DB.prepare('SELECT state, sent_at FROM loggro_leads WHERE phone = ?').bind(r.phone).first();
    if (lead?.state === 'optout') { await mark('skipped', 'pidió la baja'); continue; }
    if (!reminder && lead?.sent_at && lead.sent_at > sqlTime(Date.now() - 7 * 86400e3)) { await mark('skipped', 'ya recibió un mensaje en los últimos 7 días'); continue; }
    if (!reminder && budget <= 0) continue; // tope diario alcanzado: queda para mañana
    let params = []; try { params = JSON.parse(r.params || '[]'); } catch { /* sin parámetros */ }
    const res = await sendTemplate(env, r.phone, templateAlias(env, r.template), params);
    if (res.ok) {
      await env.DB.prepare("UPDATE outbox SET status = 'sent', sent_at = ?, wamid = ? WHERE id = ?").bind(sqlTime(Date.now()), res.wamid || null, r.id).run();
      if (!reminder) {
        // Queda registrado para que Alter atienda la respuesta; el recordatorio no cambia el estado de una conversación en curso
        await env.DB.prepare("INSERT OR IGNORE INTO loggro_leads (phone, deal_id, contact_id, name, state) VALUES (?, ?, ?, ?, 'sent')").bind(r.phone, r.deal_id || null, r.contact_id || null, r.name || null).run();
        await env.DB.prepare("UPDATE loggro_leads SET state = CASE WHEN state IN ('optout', 'done', 'agent') THEN state ELSE 'sent' END, campaign = ?, wamid = ?, sent_at = datetime('now'), deal_id = COALESCE(?, deal_id), contact_id = COALESCE(?, contact_id), updated_at = datetime('now') WHERE phone = ?")
          .bind(r.kind, res.wamid || null, r.deal_id || null, r.contact_id || null, r.phone).run();
        await env.DB.prepare("INSERT INTO events (session_id, type) VALUES ('outbox', 'outbox_sent')").run().catch(() => {});
        budget--;
      }
      sent++;
    } else if (BAD_NUMBER_CODES.has(res.code)) {
      await mark('failed', `no se pudo entregar (${res.code})`);
    } else {
      // Plantilla sin aprobar, límite de Meta o error: se detiene y se reintenta en la siguiente hora
      return { sent, reason: STOP_CODES.has(res.code) ? `meta ${res.code}` : `error ${res.code || res.status}` };
    }
  }
  return { sent, reason: 'ok' };
}
const sqlTime = ms => new Date(ms).toISOString().slice(0, 19).replace('T', ' ');
