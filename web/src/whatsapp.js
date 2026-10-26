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

import { handleLoggroInbound } from './loggro.js';

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
const BOT_REPLY = 'Soy el asistente de IA de Damián y lo estoy apoyando para que todo sea más rápido. Él revisa personalmente cada caso.';
const ASKS_BOT_RE = /\b(eres|hablo con|hablando con|esto es|es esto)\b[^.?!]{0,20}\b(bot|robot|chatbot|ia|inteligencia artificial|humano|persona|real|m[aá]quina)\b/i;
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
  if (request.headers.get('x-webhook-event') !== 'whatsapp.message.received') return new Response('OK');

  let body;
  try { body = JSON.parse(raw); } catch { return new Response('OK'); }
  const items = body?.batch === true && Array.isArray(body.data) ? body.data : [body];
  // Se responde de una vez (Kapso espera 200 en menos de 10 s); el agente trabaja en segundo plano
  ctx.waitUntil((async () => {
    for (const payload of items) {
      try { await handleInbound(env, ctx, h, payload); } catch (err) { console.error('agente', err?.message || 'desconocido'); }
    }
  })());
  return new Response('OK');
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
  if ((ownerPhone && inb.from === ownerPhone) || (env.OWNER_BSUID && inb.userId === String(env.OWNER_BSUID).trim())) return;

  // Si es un lead de Loggro al que Damián le escribió el primer mensaje, lo atiende el flujo de Loggro, nunca el de HolaDami
  if (inb.from) {
    const lg = await env.DB.prepare('SELECT * FROM loggro_leads WHERE phone = ?').bind(inb.from).first().catch(() => null);
    if (lg) return handleLoggroInbound(env, ctx, h, inb, lg);
  }

  await env.DB.prepare('INSERT OR IGNORE INTO wa_sessions (id) VALUES (?)').bind(key).run();
  const s = await env.DB.prepare('SELECT * FROM wa_sessions WHERE id = ?').bind(key).first();
  if (!s || s.last_msg_id === inb.id) return;
  const today = new Date().toISOString().slice(0, 10);
  const claim = await env.DB.prepare(`UPDATE wa_sessions SET last_msg_id = ?, msg_count = CASE WHEN day = ? THEN msg_count + 1 ELSE 1 END, day = ?
      WHERE id = ? AND (last_msg_id IS NULL OR last_msg_id != ?)`).bind(inb.id, today, today, key, inb.id).run();
  if (!claim.meta?.changes) return; // el mismo mensaje llegó dos veces
  if (inb.ad) await env.DB.prepare('INSERT INTO events (session_id, type, utm) VALUES (?, ?, ?)').bind(`wa:${key}`.slice(0, 64), 'wa_ad', inb.ad).run().catch(err => console.error('wa_ad', err?.message));

  const ageH = (Date.now() - Date.parse(String(s.updated_at).replace(' ', 'T') + 'Z')) / 3600e3;
  let st = { ...s };
  if (s.state === 'optout') return;
  if ((s.state !== 'done' && ageH > STALE_HOURS) || (s.state === 'done' && ageH > REOPEN_DAYS * 24)) {
    st = { ...s, state: 'new', problem: null, intent: null, budget: null, timing: null, decider: null, lead_id: null, phone: null };
  }
  if (st.state === 'done') return; // la conversación sigue a mano
  if ((s.msg_count || 0) >= MAX_MSGS_PER_DAY) return;

  const ctxw = { env, ctx, h, inb, key, st, dest: inb.from ? { to: inb.from } : { recipient: inb.userId } };

  if (STOP_RE.test(inb.text)) {
    await save(ctxw, { state: 'optout' });
    return sendText(ctxw, 'Listo, no te escribo más. Si cambias de idea, escríbeme cuando quieras.');
  }

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
      if (looksLikeProblem(inb.text)) return onProblem(ctxw, inb.text);
      await save(ctxw, { state: 'need_problem' });
      return sendText(ctxw, GREETING);
    }
    case 'need_problem': {
      if (!inb.text) return sendText(ctxw, 'Por aquí no alcanzo a abrir eso. ¿Me cuentas en una frase qué te está quitando tiempo?');
      if (GREETING_RE.test(inb.text)) return sendText(ctxw, 'Cuéntame en una frase qué te está quitando tiempo en tu negocio, y sigo con unas preguntas rápidas.');
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
    return sendText(c, 'Cuéntame un poco más 🙂 ¿Qué se te complica en tu negocio: la nómina, el inventario o la facturación, las ventas, el WhatsApp o el desorden en los procesos?');
  }
  await save(c, { state: 'q_budget', problem: prior ? `${prior}\n${problem}`.slice(0, 3000) : problem, intent: t.intent, name: c.h.clean(c.inb.name, 80) || null });
  const q = QUESTIONS.q_budget;
  return sendButtons(c, `${t.reply}\n\nTe hago 3 preguntas rápidas, no toma ni un minuto. ${q.text}`, q.options);
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
