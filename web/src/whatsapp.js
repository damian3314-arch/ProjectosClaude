/**
 * Agente de WhatsApp de HolaDami.
 *
 * Kapso entrega cada mensaje que llega al número (POST /api/whatsapp). El agente hace el mismo formulario que la página:
 * cuenta el problema → 3 preguntas con botones → lead. Guarda en la misma tabla `leads`, con la misma prioridad y el mismo
 * aviso a Damián; los de prioridad C solo quedan guardados.
 *
 * Reglas que no se negocian:
 *  - La firma del webhook se verifica antes de tocar nada.
 *  - Damián (OWNER_WHATSAPP / OWNER_BSUID) nunca entra al formulario: si él escribe, el agente calla.
 *  - Cuando el lead termina (estado "done"), el agente calla: la conversación sigue a mano, desde Kapso o desde la app.
 *  - Lo que escribe la persona es DATO: nunca se ejecuta ni se reenvía a otra persona.
 */

import { handleLoggroInbound, agentOn } from './loggro.js';
import { agentTurn, pauseForHuman } from './agent.js';

const STALE_HOURS = 24;          // un formulario a medias se reinicia si pasaron más de 24 h
const REOPEN_DAYS = 7;           // quien ya terminó puede volver a entrar como lead nuevo después de 7 días
const MAX_MSGS_PER_DAY = 60;     // tope por persona (cuida el costo de IA)
const MAX_NEW_PER_HOUR = 150;    // conversaciones nuevas por hora en total antes de dejar de gastar IA

const QUESTIONS = {
  q_budget: {
    field: 'budget', next: 'q_timing', text: '1 de 3: ¿cuánto tienes pensado invertir, más o menos?',
    options: [['b1', 'Hasta $1,5 M'], ['b2', '$1,5 M – $5 M'], ['b3', 'Más de $5 M']],
  },
  q_timing: {
    field: 'timing', next: 'q_decider', text: '2 de 3: ¿cuándo lo necesitas?',
    options: [['now', 'Ya, es urgente'], ['month', 'Este mes'], ['later', 'Solo averiguando']],
  },
  q_decider: {
    field: 'decider', next: null, text: '3 de 3: ¿esa decisión la tomas tú o con alguien más?',
    options: [['solo', 'La tomo yo'], ['with', 'Con socio o familia'], ['other', 'La toma otra persona']],
  },
};

// El saludo no anuncia que es IA: la conversación fluye como un DM normal. Si la persona pregunta, se le dice la verdad (BOT_REPLY).
const GREETING = 'Hola 👋 Soy Damián Barragán. Cuéntame en una frase qué te está quitando tiempo en tu negocio.';
const BOT_REPLY = 'Soy Alter, el asistente de IA de Damián, y lo estoy apoyando para que todo sea más rápido. Él revisa personalmente cada caso.';
// Mensaje predeterminado de los anuncios (enlace wa.me): no es un problema, es el saludo. Además sirve para saber que llegó desde un anuncio
const PREFILL_RE = /^\s*hola\s+dami[aá]n[,.!]?\s+vi\s+tu\s+(anuncio|video|v[ií]deo|carrusel)/i;
const ASKS_BOT_RE = /\b(eres|hablo con|hablando con|esto es|es esto)\b[^.?!]{0,20}\b(bot|robot|chatbot|ia|inteligencia artificial|humano|persona|real|m[aá]quina)\b/i;
// Mensajes con los que alguien llega por HolaDami (anuncio, página o la presentación de Alter): el mensaje del anuncio y variantes
const FROM_HOLADAMI_RE = /vi\s+tu\s+(anuncio|video|v[ií]deo|carrusel|publicaci[oó]n|post)|holadami|\balter\b|qu[eé]\s+me\s+quita\s+tiempo|diagn[oó]stico\s+(gratis|sin\s+costo)/i;
const STOP_RE = /^\s*(stop|baja|cancelar|no me escriban|no me escribas|no quiero)\s*[.!]*\s*$/i;
const GREETING_RE = /^\s*(hola|holi|buenas|buenos d[ií]as|buenas tardes|buenas noches|hey|hi|hello|buen d[ií]a|informaci[oó]n|info)\b[\s,.!¡?¿a-záéíóúñ]{0,25}$/i;

export async function handleWhatsAppWebhook(request, env, ctx, h) {
  // Sin el secreto de firma no se procesa nada: cualquiera podría escribirle al agente haciéndose pasar por Kapso
  if (!env.KAPSO_WEBHOOK_SECRET) return new Response('Webhook no configurado', { status: 503 });
  const raw = await h.readText(request, 512 * 1024);
  if (raw == null) return new Response('Muy grande', { status: 413 });
  // El secreto se pega a mano en dos paneles: un espacio o salto de línea de más no debe tumbar el agente
  const signature = (request.headers.get('x-webhook-signature') || '').trim().replace(/^sha256=/i, '');
  if (!(await validSignature(String(env.KAPSO_WEBHOOK_SECRET).trim(), raw, signature))) {
    console.error('webhook: firma inválida', signature ? `(llegó una firma de ${signature.length} caracteres)` : '(no llegó firma)');
    return new Response('Firma inválida', { status: 401 });
  }
  const event = request.headers.get('x-webhook-event');
  if (event !== 'whatsapp.message.received' && event !== 'whatsapp.message.sent') return new Response('OK');

  let body;
  try { body = JSON.parse(raw); } catch { return new Response('OK'); }
  if (event === 'whatsapp.message.sent') {
    // Si Damián escribe a mano (desde la bandeja o el celular), el agente calla 24 h en esa conversación
    ctx.waitUntil(onSent(env, body).catch(err => console.error('sent', err?.message || 'desconocido')));
    return new Response('OK');
  }
  const items = body?.batch === true && Array.isArray(body.data) ? body.data : [body];
  // Se responde de una vez (Kapso espera 200 en menos de 10 s); el agente trabaja en segundo plano
  ctx.waitUntil((async () => {
    for (const payload of items) {
      try { await handleInbound(env, ctx, h, payload); } catch (err) { console.error('agente', err?.message || 'desconocido'); }
    }
  })());
  return new Response('OK');
}

async function onSent(env, body) {
  for (const p of body?.batch === true && Array.isArray(body.data) ? body.data : [body]) {
    const m = p?.message;
    const origin = String(m?.kapso?.origin || '');
    if (!m || !origin || origin === 'cloud_api') continue; // lo que envía el propio agente o las plantillas no cuenta
    const to = String(m.to || p.conversation?.phone_number || p.conversation?.contact_phone || '').replace(/\D/g, '');
    if (!to) continue;
    // Si Damián le escribe a mano el primer mensaje a un lead que estaba en la bandeja, cuenta como enviado y NO se pausa a Alter:
    // así Alter atiende la respuesta de ese lead. En cualquier otro chat, lo que Damián escribe a mano pausa a Alter 24 h.
    const q = await env.DB.prepare("SELECT id, deal_id, contact_id, name FROM outbox WHERE phone = ? AND status = 'queued' AND kind != 'recordatorio' ORDER BY id LIMIT 1").bind(to).first().catch(() => null);
    if (q) {
      await env.DB.prepare("UPDATE outbox SET status = 'sent', template = 'manual', sent_at = ?, wamid = ?, error = 'enviado a mano desde la app' WHERE id = ?").bind(sqlTime(Date.now()), String(m.id || ''), q.id).run();
      await env.DB.prepare("INSERT OR IGNORE INTO loggro_leads (phone, deal_id, contact_id, name, state) VALUES (?, ?, ?, ?, 'sent')").bind(to, q.deal_id || null, q.contact_id || null, q.name || null).run();
      await env.DB.prepare("UPDATE loggro_leads SET state = CASE WHEN state IN ('optout', 'done', 'agent') THEN state ELSE 'sent' END, campaign = 'primer_contacto', sent_at = datetime('now'), deal_id = COALESCE(?, deal_id), contact_id = COALESCE(?, contact_id), updated_at = datetime('now') WHERE phone = ?").bind(q.deal_id || null, q.contact_id || null, to).run();
      continue;
    }
    await pauseForHuman(env, to);
  }
}

// Entrega, ya con la ventana abierta, los avisos que quedaron esperando (guardados con su teléfono o con su BSUID)
async function flushAlerts(env, h, keys) {
  const marks = keys.map(() => '?').join(',');
  const rows = (await env.DB.prepare(`SELECT id, dest, text FROM alert_queue WHERE dest IN (${marks}) AND sent_at IS NULL ORDER BY id LIMIT 15`).bind(...keys.map(String)).all().catch(() => ({ results: [] }))).results || [];
  for (const r of rows) {
    const dest = /^\d+$/.test(r.dest) ? { to: r.dest } : { recipient: r.dest };
    if (await h.sendWhatsApp(env, { messaging_product: 'whatsapp', ...dest, type: 'text', text: { body: r.text.slice(0, 1024), preview_url: false } })) {
      await env.DB.prepare("UPDATE alert_queue SET sent_at = datetime('now') WHERE id = ?").bind(r.id).run();
    } else break;
  }
}

async function validSignature(secret, raw, signature) {
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey('raw', enc.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const mac = new Uint8Array(await crypto.subtle.sign('HMAC', key, enc.encode(raw)));
  const hex = [...mac].map(b => b.toString(16).padStart(2, '0')).join('');
  if (hex.length !== signature.length) return false;
  let diff = 0;
  for (let i = 0; i < hex.length; i++) diff |= hex.charCodeAt(i) ^ signature.charCodeAt(i);
  return diff === 0;
}

// Normaliza lo que manda Kapso (v2) a lo único que el agente necesita.
function parseInbound(p) {
  const m = p?.message;
  if (!m || !m.id) return null;
  if (m.kapso?.direction === 'outbound') return null;
  if (m.kapso?.origin === 'history_sync') return null; // historial importado al conectar la coexistencia: nunca se contesta
  let text = '', buttonId = '';
  if (m.type === 'text') text = m.text?.body || '';
  else if (m.type === 'interactive') {
    const r = m.interactive?.button_reply || m.interactive?.list_reply;
    buttonId = r?.id || '';
    text = r?.title || '';
  } else if (m.type === 'button') {
    buttonId = m.button?.payload || '';
    text = m.button?.text || '';
  } else if (m.type === 'audio') {
    const t = m.kapso?.transcript;
    text = typeof t === 'string' ? t : t?.text || '';
  }
  // Si llegó desde un anuncio de Meta (Click to WhatsApp), viene el dato del anuncio: se guarda para medir qué trae cada peso
  const ref = m.referral || m.kapso?.referral;
  let ad = '';
  if (!ref && PREFILL_RE.test(text)) ad = JSON.stringify({ utm_source: 'meta_ads', utm_medium: 'whatsapp', utm_campaign: 'wa_link', utm_content: 'mensaje_anuncio' });
  if (ref && typeof ref === 'object') {
    const u = { utm_source: 'meta_ads', utm_medium: 'whatsapp', utm_campaign: String(ref.source_id || '').slice(0, 100), utm_content: String(ref.headline || '').slice(0, 100) };
    ad = JSON.stringify(Object.fromEntries(Object.entries(u).filter(([, v]) => v)));
  }
  return {
    id: String(m.id), type: m.type, text: String(text).trim(), buttonId: String(buttonId),
    from: String(m.from || '').replace(/\D/g, ''),
    userId: m.from_user_id ? String(m.from_user_id) : '',
    name: String(p.conversation?.contact_name || ''),
    phoneNumberId: String(p.phone_number_id || ''),
    ad,
  };
}

async function handleInbound(env, ctx, h, payload) {
  const inb = parseInbound(payload);
  if (!inb) return;
  if (env.KAPSO_PHONE_NUMBER_ID && inb.phoneNumberId && inb.phoneNumberId !== String(env.KAPSO_PHONE_NUMBER_ID)) return;
  const key = inb.from || inb.userId;
  if (!key) return;

  // Damián no entra al formulario: si él escribe (por ejemplo su "hola" diario para abrir la ventana), el agente calla
  const ownerPhone = String(env.OWNER_WHATSAPP || '').replace(/\D/g, '');
  const workPhone = String(env.LOGGRO_ALERT_WHATSAPP || '').replace(/\D/g, '');
  if ((ownerPhone && inb.from === ownerPhone) || (workPhone && inb.from === workPhone) || (env.OWNER_BSUID && inb.userId === String(env.OWNER_BSUID).trim())) {
    // Damián escribió (por ejemplo tocó "Ver avisos"): se le entregan los avisos que estaban esperando y el agente calla
    return flushAlerts(env, h, [inb.from, inb.userId].filter(Boolean));
  }

  // Si es un lead de Loggro al que Damián le escribió el primer mensaje, lo atiende el flujo de Loggro, nunca el de HolaDami
  if (inb.from) {
    const lg = await env.DB.prepare('SELECT * FROM loggro_leads WHERE phone = ?').bind(inb.from).first().catch(() => null);
    if (lg) return handleLoggroInbound(env, ctx, h, inb, lg);
  }

  // El número está en coexistencia: también recibe los chats personales y de negocio de Damián (clientes, proveedores, bots de Tumbao).
  // El agente solo atiende a quien llega por HolaDami (anuncio o mensaje de la página) o ya está en conversación con él. Al resto no responde ni lo guarda.
  if (env.AGENT_ALLOWLIST !== 'off') {
    // "Ya en conversación" = habló con el agente en los últimos 3 días (un contacto viejo que reaparece con un "hola" no cuenta)
    const known = await env.DB.prepare("SELECT 1 FROM wa_sessions WHERE id = ? AND state != 'new' AND updated_at > datetime('now', '-3 days')").bind(key).first();
    if (!known && !(inb.ad || FROM_HOLADAMI_RE.test(inb.text))) return;
  }

  await env.DB.prepare('INSERT OR IGNORE INTO wa_sessions (id) VALUES (?)').bind(key).run();
  const s = await env.DB.prepare('SELECT * FROM wa_sessions WHERE id = ?').bind(key).first();
  if (!s || s.last_msg_id === inb.id) return;
  const today = new Date().toISOString().slice(0, 10);
  const claim = await env.DB.prepare(`UPDATE wa_sessions SET last_msg_id = ?, msg_count = CASE WHEN day = ? THEN msg_count + 1 ELSE 1 END, day = ?, updated_at = datetime('now')
      WHERE id = ? AND (last_msg_id IS NULL OR last_msg_id != ?)`).bind(inb.id, today, today, key, inb.id).run();
  if (!claim.meta?.changes) return; // el mismo mensaje llegó dos veces
  if (inb.ad) await env.DB.prepare('INSERT INTO events (session_id, type, utm) VALUES (?, ?, ?)').bind(`wa:${key}`.slice(0, 64), 'wa_ad', inb.ad).run().catch(err => console.error('wa_ad', err?.message));

  const ageH = (Date.now() - Date.parse(String(s.updated_at).replace(' ', 'T') + 'Z')) / 3600e3;
  let st = { ...s };
  if (s.state === 'optout') return;
  const agent = agentOn(env);
  if (!agent && ((s.state !== 'done' && ageH > STALE_HOURS) || (s.state === 'done' && ageH > REOPEN_DAYS * 24))) {
    st = { ...s, state: 'new', problem: null, intent: null, budget: null, timing: null, decider: null, lead_id: null, phone: null };
  }
  if (st.state === 'done' && !agent) return; // la conversación sigue a mano
  if ((s.msg_count || 0) >= MAX_MSGS_PER_DAY) return;

  const ctxw = { env, ctx, h, inb, key, st, dest: inb.from ? { to: inb.from } : { recipient: inb.userId } };

  if (STOP_RE.test(inb.text)) {
    await save(ctxw, { state: 'optout' });
    return sendText(ctxw, 'Listo, no te escribo más. Si cambias de idea, escríbeme cuando quieras.');
  }

  // Agente conversacional: conversa como Damián y deja el lead guardado. Si está apagado, sigue el formulario de abajo.
  if (agent) return agentTurn({ ...ctxw, source: 'holadami' });

  // Si pregunta si es un bot o una persona, se le dice la verdad y se retoma el paso donde iba
  if (inb.text.length <= 80 && ASKS_BOT_RE.test(inb.text)) {
    if (QUESTIONS[st.state]) {
      await sendText(ctxw, BOT_REPLY);
      return sendButtons(ctxw, QUESTIONS[st.state].text, QUESTIONS[st.state].options);
    }
    if (st.state === 'need_phone') return sendText(ctxw, `${BOT_REPLY} ¿A qué número de WhatsApp te escribo? Con el indicativo, por ejemplo 573001234567.`);
    await save(ctxw, { state: 'need_problem' });
    return sendText(ctxw, `${BOT_REPLY} Cuéntame en una frase qué te está quitando tiempo en tu negocio.`);
  }

  switch (st.state) {
    case 'new': {
      if (!PREFILL_RE.test(inb.text) && looksLikeProblem(inb.text)) return onProblem(ctxw, inb.text);
      await save(ctxw, { state: 'need_problem' });
      return sendText(ctxw, GREETING);
    }
    case 'need_problem': {
      if (!inb.text) return sendText(ctxw, 'Por aquí no alcanzo a abrir eso. ¿Me cuentas en una frase qué te está quitando tiempo?');
      if (GREETING_RE.test(inb.text) || PREFILL_RE.test(inb.text)) return sendText(ctxw, 'Cuéntame en una frase qué te está quitando tiempo en tu negocio, y sigo con unas preguntas rápidas.');
      return onProblem(ctxw, inb.text);
    }
    case 'q_budget': case 'q_timing': case 'q_decider':
      return onAnswer(ctxw, st.state);
    case 'need_phone':
      return onPhone(ctxw);
    default:
      return;
  }
}

const FROM_AD_RE = /vi tu anuncio|quiero contarte qu[eé] me quita tiempo/i;

function looksLikeProblem(text) {
  if (!text || GREETING_RE.test(text)) return false;
  return text.split(/\s+/).length >= 4;
}

async function onProblem(c, text) {
  const problem = c.h.clean(text, 3000);
  let t = { intent: null, reply: 'Gracias por contarme.' };
  const fresh = await c.env.DB.prepare("SELECT COUNT(*) AS n FROM wa_sessions WHERE created_at > datetime('now', '-1 hour')").first();
  if (c.env.OPENAI_API_KEY && (fresh?.n || 0) <= MAX_NEW_PER_HOUR) {
    try { t = await c.h.triage(c.env, problem); } catch (err) { console.error('triage wa', err?.message || 'desconocido'); }
  }
  // Preguntó quién es Damián o de qué se trata: se le explica y se queda esperando su problema (sin calificarlo todavía)
  if (t.kind === 'sobre') {
    await save(c, { state: 'need_problem' });
    return sendText(c, t.reply);
  }
  // Si lo que escribió no parece un problema de negocio (saludo, charla, otro idioma), se le aclara una vez antes de calificarlo
  const prior = c.st.state === 'need_problem' ? c.st.problem || '' : '';
  if (!t.intent && !prior) {
    await save(c, { state: 'need_problem', problem });
    // Llega del anuncio con el mensaje listo ("vi tu anuncio, quiero contarte…"): pregunta abierta y cálida, sin lista de temas
    if (c.inb.ad || FROM_AD_RE.test(text)) return sendText(c, '¡Claro! Cuéntame, ¿qué tipo de negocio tienes y qué es lo que más te está costando?');
    return sendText(c, 'Cuéntame un poco más 🙂 ¿Qué se te complica en tu negocio: la nómina, el inventario o la facturación, las ventas, el WhatsApp o el desorden en los procesos?');
  }
  await save(c, { state: 'q_budget', problem: prior ? `${prior}\n${problem}`.slice(0, 3000) : problem, intent: t.intent, name: c.h.clean(c.inb.name, 80) || null });
  const q = QUESTIONS.q_budget;
  return sendButtons(c, `${t.reply}\n\nTe hago 3 preguntas rápidas, no toma ni un minuto. ${q.text}\n\nAl responder autorizas que guarde tus datos para atenderte. Política: holadami.com/#privacidad`, q.options);
}

async function onAnswer(c, state) {
  const q = QUESTIONS[state];
  const typed = c.inb.text.toLowerCase();
  const idx = ['1', '2', '3'].indexOf(typed);
  const choice = q.options.find(([id, title]) => id === c.inb.buttonId || title.toLowerCase() === typed) || (idx >= 0 ? q.options[idx] : null);
  if (!choice) return sendButtons(c, `Toca una de las opciones 👇\n\n${q.text}`, q.options);

  await save(c, { [q.field]: choice[0], state: q.next || 'need_phone' });
  if (q.next) {
    const n = QUESTIONS[q.next];
    return sendButtons(c, n.text, n.options);
  }
  c.st = { ...c.st, [q.field]: choice[0] };
  return finish(c);
}

async function onPhone(c) {
  const phone = c.h.normalizePhone(c.inb.text);
  if (!phone) return sendText(c, 'Escríbelo con el indicativo y sin espacios, por ejemplo 573001234567.');
  c.st = { ...c.st, phone };
  await save(c, { phone });
  return finish(c);
}

// Último paso: se guarda el lead con la misma prioridad que la página y se avisa a Damián si hay que gestionarlo.
async function finish(c) {
  const st = c.st;
  const phone = c.inb.from ? c.h.normalizePhone(c.inb.from) : st.phone;
  if (!phone) {
    await save(c, { state: 'need_phone' });
    return sendText(c, 'Última cosa: ¿a qué número de WhatsApp te escribo? Escríbelo con el indicativo, por ejemplo 573001234567.');
  }
  const name = c.h.clean(st.name || c.inb.name, 80) || 'Contacto de WhatsApp';
  const score = c.h.scoreLead({ budget: st.budget, timing: st.timing, decider: st.decider, intent: st.intent });
  const sessionId = `wa:${c.key}`.slice(0, 64);
  const ad = await c.env.DB.prepare("SELECT utm FROM events WHERE session_id = ? AND type = 'wa_ad' ORDER BY id DESC LIMIT 1").bind(sessionId).first().catch(() => null);
  const lead = {
    id: crypto.randomUUID(), session_id: sessionId, name, phone,
    intent: st.intent || null, problem: st.problem || '', budget: st.budget, timing: st.timing, decider: st.decider,
    ...score, utm: ad?.utm || null, page: 'whatsapp',
  };
  await c.h.persistLead(c.env, c.ctx, lead, null);
  await save(c, { state: 'done', lead_id: lead.id, phone });
  const first = c.h.clean(name, 40).split(' ')[0];
  return sendText(c, score.tier === 'A'
    ? `Listo, ${first}. Ya tengo tu caso: te contacto personalmente hoy.`
    : score.tier === 'B'
      ? `Gracias, ${first}. Ya tengo tu caso. Lo reviso y, si veo cómo ayudarte, te escribo.`
      : `Gracias, ${first}. Quedó registrado. Si más adelante quieres retomarlo, escríbeme por aquí.`);
}

async function save(c, fields) {
  const cols = Object.keys(fields);
  await c.env.DB.prepare(`UPDATE wa_sessions SET ${cols.map(k => `${k} = ?`).join(', ')}, updated_at = datetime('now') WHERE id = ?`)
    .bind(...cols.map(k => fields[k] ?? null), c.key).run();
  c.st = { ...c.st, ...fields };
}

function sendText(c, body) {
  return c.h.sendWhatsApp(c.env, { messaging_product: 'whatsapp', ...c.dest, type: 'text', text: { body: body.slice(0, 1024), preview_url: false } });
}

function sendButtons(c, body, options) {
  return c.h.sendWhatsApp(c.env, {
    messaging_product: 'whatsapp', ...c.dest, type: 'interactive',
    interactive: {
      type: 'button', body: { text: body.slice(0, 1024) },
      action: { buttons: options.map(([id, title]) => ({ type: 'reply', reply: { id, title: title.slice(0, 20) } })) },
    },
  });
}

/* ---------- Seguimiento si la persona deja de responder ----------
 * Mientras la ventana de 24 h está abierta, si alguien deja la conversación a medias se le escribe una vez a los 15 minutos
 * y otra 30 minutos después, en tono de Damián. 30 minutos más tarde el chat se cierra en la bandeja de Kapso y no se le insiste
 * más (si vuelve a escribir, el chat se reabre y el bot sigue donde iba).
 * Solo de 7 am a 9 pm (hora de Bogotá). Lo corre el cron cada 5 minutos.
 */
const NUDGE_FIRST_MIN = 15, NUDGE_SECOND_MIN = 30, NUDGE_MAX_HOURS = 3; // conversaciones de hace más de 3 h no se retoman (sonaría raro)
const NUDGE_LAST = 'No te quiero llenar de mensajes 😅 Si ahora no es buen momento, tranqui: cuando quieras me escribes por aquí y seguimos donde quedamos.';
const NUDGE_AGENT = '¿Sigues por ahí? 🙂 Sin afán: cuando puedas me cuentas y seguimos.';
const NUDGE_FIRST = {
  need_problem: '¿Sigues por ahí? 🙂 Cuéntame con tus palabras qué es lo que más tiempo te está quitando y te digo si te puedo ayudar.',
  q_budget: '¿Sigues por ahí? Te dejé una pregunta arriba 👆 Con tocar una opción basta y seguimos.',
  q_timing: '¿Sigues por ahí? Te dejé una pregunta arriba 👆 Con tocar una opción basta y seguimos.',
  q_decider: '¿Sigues por ahí? Te dejé una pregunta arriba 👆 Con tocar una opción basta y seguimos.',
  need_phone: '¿Me compartes el número de WhatsApp donde te escribo? Con eso termino 🙂',
  loggro: '¿Sigues por ahí? Te falta poquito: toca una opción de arriba 👆 y te digo qué solución te sirve.',
};

export async function nudgeIdle(env, h) {
  if (!env.KAPSO_API_KEY || !env.KAPSO_PHONE_NUMBER_ID) return { sent: 0 };
  const hour = new Date(Date.now() - 5 * 3600e3).getUTCHours();
  if (hour < 7 || hour >= 21) return { sent: 0 };
  const since = sqlTime(Date.now() - NUDGE_MAX_HOURS * 3600e3), firstBefore = sqlTime(Date.now() - NUDGE_FIRST_MIN * 60e3);
  const ho = (await env.DB.prepare(`SELECT id AS dest, state, updated_at FROM wa_sessions
      WHERE state IN ('need_problem', 'q_budget', 'q_timing', 'q_decider', 'need_phone') AND updated_at > ? AND updated_at <= ? LIMIT 50`).bind(since, firstBefore).all()).results || [];
  const lg = (await env.DB.prepare(`SELECT phone AS dest, 'loggro' AS state, updated_at FROM loggro_leads
      WHERE (state IN ('q_pn', 'q_size', 'q_system', 'q_when') OR (state = 'sent' AND msg_count > 0)) AND updated_at > ? AND updated_at <= ? LIMIT 50`).bind(since, firstBefore).all()).results || [];
  // Conversaciones del agente: la última palabra fue del agente y la persona no ha contestado
  const ag = (await env.DB.prepare(`SELECT a.chat_key AS dest, a.source AS source, 'agente' AS state, l.created_at AS updated_at FROM agent_chats a
      JOIN agent_log l ON l.id = (SELECT MAX(id) FROM agent_log WHERE chat_key = a.chat_key)
      WHERE l.role = 'assistant' AND a.stage = 'qualifying' AND a.hot = 0 AND a.paused_until IS NULL AND l.created_at > ? AND l.created_at <= ? LIMIT 50`).bind(since, firstBefore).all().catch(() => ({ results: [] }))).results || [];
  let sent = 0;
  for (const r of [...ho.map(x => ({ ...x, sid: `nudge:wa:${x.dest}` })), ...(agentOn(env) ? [] : lg).map(x => ({ ...x, sid: `nudge:lg:${x.dest}` })), ...ag.map(x => ({ ...x, sid: `nudge:ag:${x.dest}` }))]) {
    const prev = await env.DB.prepare("SELECT COUNT(*) AS n, MAX(created_at) AS last FROM events WHERE session_id = ? AND type = 'nudge' AND created_at >= ?").bind(r.sid.slice(0, 64), r.updated_at).first();
    const n = prev?.n || 0;
    if (n >= 2) {
      // 30 minutos después del último recordatorio sin respuesta: se cierra el chat en la bandeja de Kapso (una sola vez)
      if (prev.last > sqlTime(Date.now() - NUDGE_SECOND_MIN * 60e3) || !/^\d+$/.test(r.dest)) continue;
      const closed = await env.DB.prepare("SELECT 1 FROM events WHERE session_id = ? AND type = 'chat_closed' AND created_at >= ?").bind(r.sid.slice(0, 64), r.updated_at).first();
      if (closed) continue;
      if (await closeKapsoChat(env, r.dest)) {
        await env.DB.prepare("INSERT INTO events (session_id, type) VALUES (?, 'chat_closed')").bind(r.sid.slice(0, 64)).run();
        // Lead de Loggro que dejó de responder: queda anotado en HubSpot (la rutina lee 'done') sin marcarlo como caliente
        if (r.source === 'loggro') await env.DB.prepare(`UPDATE loggro_leads SET state = 'done', hot = 0, summary = 'Dejó de responder tras el seguimiento. ' || COALESCE(summary, ''), synced_state = NULL, updated_at = datetime('now') WHERE phone = ? AND state = 'agent'`).bind(r.dest).run();
      }
      continue;
    }
    if (n === 1 && prev.last > sqlTime(Date.now() - NUDGE_SECOND_MIN * 60e3)) continue;
    const body = n === 0 ? (r.state === 'agente' ? NUDGE_AGENT : NUDGE_FIRST[r.state]) : NUDGE_LAST;
    if (!body) continue;
    const dest = /^\d+$/.test(r.dest) ? { to: r.dest } : { recipient: r.dest };
    if (await h.sendWhatsApp(env, { messaging_product: 'whatsapp', ...dest, type: 'text', text: { body, preview_url: false } })) {
      await env.DB.prepare("INSERT INTO events (session_id, type) VALUES (?, 'nudge')").bind(r.sid.slice(0, 64)).run();
      sent++;
    }
  }
  return { sent };
}
// Busca el chat activo de ese número en Kapso y lo marca como terminado (queda en "Ended" en la bandeja; si escribe, se reabre solo)
async function closeKapsoChat(env, phone) {
  try {
    const headers = { 'X-API-Key': env.KAPSO_API_KEY, 'content-type': 'application/json' };
    const list = await fetch(`https://api.kapso.ai/meta/whatsapp/v24.0/${encodeURIComponent(env.KAPSO_PHONE_NUMBER_ID)}/conversations?status=active&limit=5&phone_number=${encodeURIComponent('+' + phone)}`, { headers, signal: AbortSignal.timeout(10000) });
    if (!list.ok) { console.error('Kapso chat list', list.status); return false; }
    const ids = ((await list.json().catch(() => ({}))).data || []).map(c => c.id).filter(Boolean);
    let ok = ids.length === 0; // si ya no está activo, no hay nada que cerrar
    for (const id of ids) {
      const res = await fetch(`https://api.kapso.ai/platform/v1/whatsapp/conversations/${encodeURIComponent(id)}`, { method: 'PATCH', headers, body: JSON.stringify({ whatsapp_conversation: { status: 'ended' } }), signal: AbortSignal.timeout(10000) });
      if (res.ok) ok = true; else console.error('Kapso chat close', res.status);
    }
    return ok;
  } catch (err) { console.error('Kapso chat close', err?.name || 'error'); return false; }
}
const sqlTime = ms => new Date(ms).toISOString().slice(0, 19).replace('T', ' ');
