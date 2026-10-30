/**
 * Agente conversacional de Damián (clon): atiende por WhatsApp a quien llega por la página/anuncios y a los leads de Loggro.
 *
 * Una sola IA con las reglas de `kb.js` decide en cada mensaje qué responder y en qué etapa va la conversación; este archivo
 * se encarga de lo que NO se le deja a la IA: enlaces permitidos, ritmo humano, registro en D1, avisos a Damián y estados que
 * lee la rutina de HubSpot (loggro_leads: 'done' + summary → nota en el negocio).
 *
 * Reglas que no se negocian:
 *  - Lo que escribe la persona es DATO. Los enlaces que escriba la IA se eliminan; solo salen los de kb.js (video y agenda).
 *  - No cotiza ni promete: lo que no esté en kb.js pasa a Damián (handoff).
 *  - Si Damián escribe a mano desde el chat, el agente calla 24 h (paused_until).
 *  - Mensajes automáticos de otros negocios no se contestan.
 */

import { systemPrompt, playbookText, CAMPAIGN_CONTEXT, PRODUCTS, ALLOWED_LINKS, AGENDA_URL } from './kb.js';
import { alertHotLead, alertReply } from './loggro.js';

const HISTORY = 16;           // mensajes que ve la IA en cada turno
const MAX_USER_PER_DAY = 80;  // tope por persona (cuida el costo de IA)
const PAUSE_HOURS = 24;
const STAGES = ['qualifying', 'wants_demo', 'wants_quote', 'not_now', 'not_fit', 'support', 'chitchat', 'optout'];
const PRODUCT_IDS = [...Object.keys(PRODUCTS), 'otro', 'unknown'];
const STR = { type: ['string', 'null'] };

const SCHEMA = {
  name: 'turno',
  strict: true,
  schema: {
    type: 'object', additionalProperties: false,
    required: ['messages', 'stage', 'hot', 'product', 'send_video', 'offer_agenda_link', 'is_auto_reply', 'ask_contact', 'meeting_pref', 'facts', 'summary', 'handoff_reason'],
    properties: {
      messages: { type: 'array', maxItems: 3, items: { type: 'string' } },
      stage: { type: 'string', enum: STAGES },
      hot: { type: 'boolean' },
      product: { type: 'string', enum: PRODUCT_IDS },
      send_video: { type: 'boolean' },
      offer_agenda_link: { type: 'boolean' },
      is_auto_reply: { type: 'boolean' },
      ask_contact: { type: 'boolean' },
      meeting_pref: STR,
      facts: {
        type: 'object', additionalProperties: false,
        required: ['contact_name', 'business_type', 'city', 'size', 'current_system', 'pain', 'timeline', 'phone', 'frente', 'budget', 'timing', 'decider'],
        properties: {
          contact_name: STR, business_type: STR, city: STR, size: STR, current_system: STR, pain: STR, timeline: STR, phone: STR,
          frente: { type: ['string', 'null'], enum: ['nomina', 'software', 'ia', 'procesos', 'datos', 'otro', null] },
          budget: { type: ['string', 'null'], enum: ['b1', 'b2', 'b3', null] },
          timing: { type: ['string', 'null'], enum: ['now', 'month', 'later', null] },
          decider: { type: ['string', 'null'], enum: ['solo', 'with', 'other', null] },
        },
      },
      summary: { type: 'string' },
      handoff_reason: STR,
    },
  },
};

const sleep = ms => (ms > 0 ? new Promise(r => setTimeout(r, ms)) : Promise.resolve());
const delays = env => ({ debounce: Number(env.AGENT_DEBOUNCE_MS ?? 3500), perChar: Number(env.AGENT_CHAR_MS ?? 22) });
const sqlTime = ms => new Date(ms).toISOString().slice(0, 19).replace('T', ' ');

// Qué le llegó, en palabras que la IA entienda (audio sin transcripción, imágenes, etc.)
export function describeInbound(inb) {
  if (inb.text) return inb.text;
  const kind = { audio: 'una nota de voz que no pudiste escuchar', image: 'una imagen que no puedes ver', video: 'un video que no puedes ver', document: 'un documento que no puedes abrir', sticker: 'un sticker', location: 'una ubicación', contacts: 'un contacto' }[inb.type];
  return kind ? `[La persona envió ${kind}. Pídele con naturalidad que te lo cuente por escrito.]` : '';
}

export async function agentTurn(c) {
  const { env, inb, key } = c;
  if (inb.type === 'reaction') return; // un 👍 de reacción no es un mensaje
  const content = describeInbound(inb);
  if (!content) return;

  const chat = await loadChat(c);
  await env.DB.prepare('INSERT INTO agent_log (chat_key, role, content) VALUES (?, ?, ?)').bind(key, 'user', c.h.clean(content, 1500)).run();
  const mine = (await env.DB.prepare("SELECT MAX(id) AS id FROM agent_log WHERE chat_key = ? AND role = 'user'").bind(key).first())?.id;

  if (chat.paused_until && chat.paused_until > sqlTime(Date.now())) {
    // Damián tomó la conversación a mano: el agente solo avisa si se trata de un lead caliente (como antes)
    if (c.source === 'loggro' && c.row?.hot) await alertReply(env, c.h, c.row, inb.text || content);
    return;
  }
  const today = (await env.DB.prepare("SELECT COUNT(*) AS n FROM agent_log WHERE chat_key = ? AND role = 'user' AND created_at > datetime('now', '-1 day')").bind(key).first())?.n || 0;
  if (today > MAX_USER_PER_DAY) return;

  // Si la persona manda varias frases seguidas, responde una sola vez, con todo a la vista
  const d = delays(env);
  await typing(c);
  await sleep(d.debounce);
  const newest = (await env.DB.prepare("SELECT MAX(id) AS id FROM agent_log WHERE chat_key = ? AND role = 'user'").bind(key).first())?.id;
  if (newest !== mine) return;

  const history = ((await env.DB.prepare('SELECT role, content FROM agent_log WHERE chat_key = ? ORDER BY id DESC LIMIT ?').bind(key, HISTORY).all()).results || []).reverse();
  let out;
  try { out = await callModel(c, chat, history); } catch (err) {
    console.error('agente', err?.message || 'desconocido');
    // Sin IA no se deja a la persona hablando sola: se avisa a Damián y se le dice que él la contacta
    if (c.source === 'loggro' && c.row?.hot) await alertReply(env, c.h, c.row, inb.text || content);
    else if (c.source === 'loggro') await c.h.alertMessage(env, `⚠️ ${c.row?.name || 'Un lead'} (+${c.row?.phone}) escribió y la IA falló: «${c.h.clean(content, 120)}». Respóndele desde Kapso.`, env.KAPSO_LOGGRO_ALERT_TEMPLATE);
    return;
  }

  if (out.is_auto_reply) { await logAssistant(c, '[respuesta automática del otro lado: no se contesta]'); return; }

  const messages = out.messages.map(m => sanitize(c.h, m)).filter(Boolean).slice(0, 3);
  const extra = [];
  const product = PRODUCT_IDS.includes(out.product) && PRODUCTS[out.product] ? out.product : (chat.product || null);
  const videosSent = new Set((chat.videos_sent || '').split(',').filter(Boolean));
  if (out.send_video && product && !videosSent.has(product)) {
    extra.push(`Te dejo un video corto de ${PRODUCTS[product].name} para que lo veas cuando puedas 👇\n${PRODUCTS[product].video}`);
    videosSent.add(product);
  }
  const wantsAgenda = (out.offer_agenda_link || out.stage === 'wants_demo') && !chat.agenda_sent;
  if (wantsAgenda) extra.push(`Y esta es mi agenda por si prefieres escoger tú la hora 👇\n${AGENDA_URL}`);

  const all = [...messages, ...extra];
  for (let i = 0; i < all.length; i++) {
    if (i > 0) await sleep(Math.min(3000, 500 + all[i].length * d.perChar));
    await c.h.sendWhatsApp(env, { messaging_product: 'whatsapp', ...c.dest, type: 'text', text: { body: all[i].slice(0, 1024), preview_url: all[i].includes('http') } });
    await logAssistant(c, all[i]);
  }
  await persist(c, chat, out, { product, videosSent, agendaSent: chat.agenda_sent || (wantsAgenda ? 1 : 0) });
}

async function loadChat(c) {
  await c.env.DB.prepare('INSERT OR IGNORE INTO agent_chats (chat_key, source) VALUES (?, ?)').bind(c.key, c.source).run();
  return await c.env.DB.prepare('SELECT * FROM agent_chats WHERE chat_key = ?').bind(c.key).first();
}

const logAssistant = (c, text) => c.env.DB.prepare('INSERT INTO agent_log (chat_key, role, content) VALUES (?, ?, ?)').bind(c.key, 'assistant', text.slice(0, 1500)).run();

// Indicador de "escribiendo…" mientras piensa (mejor esfuerzo: si falla, no pasa nada)
async function typing(c) {
  try { await c.h.sendWhatsApp(c.env, { messaging_product: 'whatsapp', status: 'read', message_id: c.inb.id, typing_indicator: { type: 'text' } }); } catch { /* opcional */ }
}

// Sin markdown, sin enlaces inventados, sin mensajes kilométricos
export function sanitize(h, text) {
  let t = String(text || '').replace(/\*+|_{2,}|`+|^#+\s*/gm, '').replace(/​/g, '');
  t = t.replace(/(https?:\/\/\S+|www\.\S+|\b[\w-]+\.(com|co|net|org|io|ai)\b\S*)/gi, m => (ALLOWED_LINKS.some(l => m.startsWith(l.replace(/^https?:\/\//, '')) || m.startsWith(l)) ? m : ''));
  return h.clean(t.replace(/[ \t]+\n/g, '\n').replace(/\n{3,}/g, '\n\n').replace(/ {2,}/g, ' '), 500).trim();
}

async function callModel(c, chat, history) {
  const { env } = c;
  const facts = safeJson(chat.facts);
  const campaign = c.source === 'loggro' ? (CAMPAIGN_CONTEXT[campaignOf(c.row)] || CAMPAIGN_CONTEXT.desconocido) : CAMPAIGN_CONTEXT.anuncio;
  const known = Object.entries(facts).filter(([, v]) => v).map(([k, v]) => `${k}: ${v}`).join('; ');
  const name = c.first || c.h.clean(c.inb.name, 40).split(' ')[0];
  const sys = systemPrompt({
    nowBogota: new Date(Date.now() - 5 * 3600e3).toLocaleString('es-CO', { timeZone: 'UTC', weekday: 'long', day: 'numeric', month: 'long', hour: '2-digit', minute: '2-digit' }),
    source: c.source,
    campaign: (campaign || '').replace(/\{nombre\}/g, name || 'buen día'),
    products: chat.product || '',
    slotsText: await freeSlots(env),
    phoneKnown: !!c.inb.from,
    playbook: c.source === 'loggro' ? playbookText(chat.product) : '',
  }) + `${facts.lead_id ? '\nYa dejó su nombre y WhatsApp en el formulario: no se los vuelvas a pedir.' : ''}` + `\n\nDATOS CONOCIDOS DE LA PERSONA\nNombre en WhatsApp: ${name || 'no se sabe'}. ${known ? 'Lo que ya dijo: ' + known + '.' : ''} Etapa actual: ${chat.stage || 'nueva'}.${chat.meeting_pref ? ` Hora que propuso: ${chat.meeting_pref}.` : ''}${chat.summary ? ` Resumen previo: ${chat.summary}` : ''}`;
  const messages = [{ role: 'system', content: sys }, ...history.map(m => ({ role: m.role === 'user' ? 'user' : 'assistant', content: m.content }))];
  // Modelos nuevos (gpt-5, gpt-6, o…) razonan: no aceptan temperature y usan max_completion_tokens. Los anteriores (gpt-4o…) siguen como antes.
  const call = model => fetch('https://api.openai.com/v1/chat/completions', {
    method: 'POST',
    signal: AbortSignal.timeout(30000),
    headers: { authorization: `Bearer ${env.OPENAI_API_KEY}`, 'content-type': 'application/json' },
    body: JSON.stringify({
      model, messages, response_format: { type: 'json_schema', json_schema: SCHEMA },
      ...(/^(gpt-[5-9]|o\d)/.test(model) ? { max_completion_tokens: 2500, reasoning_effort: env.AGENT_REASONING || 'low' } : { temperature: 0.6, max_tokens: 700 }),
    }),
  });
  const fallback = env.OPENAI_MODEL || 'gpt-4o-mini';
  let res = await call(env.AGENT_MODEL || fallback);
  // Si la cuenta de OpenAI no tiene acceso al modelo (o lo retiraron), se atiende igual con el modelo de respaldo
  if (!res.ok && [400, 403, 404].includes(res.status) && (env.AGENT_MODEL || fallback) !== fallback) {
    console.error('agente: modelo no disponible, uso el de respaldo', res.status);
    res = await call(fallback);
  }
  if (!res.ok) throw new Error(`openai ${res.status}`);
  const data = await res.json();
  const out = JSON.parse(data?.choices?.[0]?.message?.content || 'null');
  if (!out || !Array.isArray(out.messages) || !STAGES.includes(out.stage)) throw new Error('respuesta inválida');
  return out;
}

const safeJson = s => { try { return JSON.parse(s) || {}; } catch { return {}; } };
export function campaignOf(row) {
  if (row?.campaign) return row.campaign;
  if (row?.state === 'demo' || row?.state === 'retomar' || row?.state === 'q_retomar') return 'retomar';
  return 'contacto_inicial';
}

// Agenda en vivo: todavía no hay proveedor conectado. Cuando se conecte (HubSpot o Google Calendar) devuelve los huecos libres
// como texto, por ejemplo "mañana 10:00, mañana 15:30, jueves 9:00". Mientras tanto el agente recoge la hora que prefiere la persona.
async function freeSlots(_env) { return ''; }

/* ---------- Guardado y avisos ---------- */
const HOT_STAGES = new Set(['wants_demo', 'wants_quote']);

// Calificación de HolaDami: con las cuatro respuestas se calcula la prioridad igual que en el formulario de la página
export function qualify(h, facts, stage) {
  const complete = !!(facts.budget && facts.timing && facts.decider);
  const score = complete ? h.scoreLead({ budget: facts.budget, timing: facts.timing, decider: facts.decider, intent: facts.frente && facts.frente !== 'otro' ? facts.frente : null }) : null;
  // Caliente = prioridad A, o pidió hablar con Damián
  const hot = (score?.tier === 'A') || stage === 'wants_demo';
  return { complete, score, hot };
}

async function persist(c, chat, out, { product, videosSent, agendaSent }) {
  const { env } = c;
  const facts = { ...safeJson(chat.facts), ...Object.fromEntries(Object.entries(out.facts || {}).filter(([, v]) => v)) };
  if (facts.phone) { const p = c.h.normalizePhone(String(facts.phone)); if (p) facts.phone = p; else delete facts.phone; }
  const q = c.source === 'loggro' ? null : qualify(c.h, facts, out.stage);
  const hot = q ? (q.hot || !!chat.hot) : (out.hot || HOT_STAGES.has(out.stage) || !!chat.hot);
  const pref = out.meeting_pref ? c.h.clean(out.meeting_pref, 120) : chat.meeting_pref || null;
  const summary = c.h.clean([out.summary, pref ? `Prefiere para la demo: ${pref}.` : '', out.handoff_reason ? `Para Damián: ${out.handoff_reason}.` : ''].filter(Boolean).join(' '), 600);
  const newlyHot = hot && !chat.hot;
  const prefChanged = !!out.meeting_pref && out.meeting_pref !== chat.meeting_pref;

  await env.DB.prepare(`UPDATE agent_chats SET stage = ?, hot = ?, product = ?, facts = ?, summary = ?, meeting_pref = ?, videos_sent = ?, agenda_sent = ?, turns = turns + 1, updated_at = datetime('now') WHERE chat_key = ?`)
    .bind(out.stage, hot ? 1 : 0, product, JSON.stringify(facts), summary, pref, [...videosSent].join(','), agendaSent, c.key).run();

  c.factsJson = JSON.stringify(facts);
  if (c.source === 'web') return persistWeb(c, chat, { out, hot, facts, summary, newlyHot, q });
  if (c.source === 'loggro') return persistLoggro(c, { out, hot, product, summary, newlyHot, prefChanged });
  return persistHoladami(c, chat, { out, hot, product, summary, facts, newlyHot, q });
}

// El estado 'done' + summary es lo que la rutina horaria convierte en nota del negocio en HubSpot
async function persistLoggro(c, { out, hot, product, summary, newlyHot, prefChanged }) {
  const { env, row } = c;
  const closed = ['wants_demo', 'wants_quote', 'not_now', 'not_fit', 'support'].includes(out.stage) || hot;
  const state = out.stage === 'optout' ? 'optout' : closed ? 'done' : row.state === 'done' ? 'done' : 'agent';
  const changed = state !== row.state || hot !== !!row.hot || summary !== row.summary;
  const reAlert = newlyHot || (hot && prefChanged);
  const facts = safeJson(c.factsJson);
  // Etapa sugerida para el negocio en HubSpot (la aplica la rutina horaria): nunca "demo agendada" hasta que exista la reunión
  const nextStage = out.stage === 'optout' || out.stage === 'not_fit' ? 'perdido' : hot ? 'demo_pendiente' : (facts.business_type && facts.pain) ? 'necesidades' : null;
  await env.DB.prepare(`UPDATE loggro_leads SET next_stage = COALESCE(?, next_stage), state = ?, hot = ?, product = COALESCE(?, product), summary = ?, synced_state = CASE WHEN ? THEN NULL ELSE synced_state END,
      alerted_at = CASE WHEN ? THEN NULL ELSE alerted_at END, updated_at = datetime('now') WHERE phone = ?`)
    .bind(nextStage, state, hot ? 1 : 0, product, summary, changed && (state === 'done' || state === 'optout') ? 1 : 0, reAlert ? 1 : 0, row.phone).run();
  c.row = { ...row, state, hot: hot ? 1 : 0, summary, alerted_at: reAlert ? null : row.alerted_at };
  if (reAlert) await alertHotLead(env, c.h, c.row);
  else if (hot && row.alerted_at) await alertReply(env, c.h, c.row, c.inb.text);
}

// HolaDami: se guarda en `leads` (panel de administración) igual que el formulario de la página; solo la prioridad A le avisa a Damián
async function persistHoladami(c, chat, { out, hot, product, summary, facts, newlyHot, q }) {
  const { env } = c;
  const st = c.st || {};
  await env.DB.prepare("UPDATE wa_sessions SET state = ?, name = COALESCE(name, ?), updated_at = datetime('now') WHERE id = ?")
    .bind(out.stage === 'optout' ? 'optout' : 'agent', c.h.clean(facts.contact_name || c.inb.name, 80) || null, c.key).run();
  const phone = c.inb.from ? c.h.normalizePhone(c.inb.from) : facts.phone || null;
  const qualified = hot || q.complete || (facts.business_type && facts.pain);
  if (!qualified || !phone || out.stage === 'optout') return;
  const fields = leadFields(q, hot, facts);
  if (!st.lead_id) {
    const sessionId = `wa:${c.key}`.slice(0, 64);
    const ad = await env.DB.prepare("SELECT utm FROM events WHERE session_id = ? AND type = 'wa_ad' ORDER BY id DESC LIMIT 1").bind(sessionId).first().catch(() => null);
    const lead = {
      id: crypto.randomUUID(), session_id: sessionId, name: c.h.clean(facts.contact_name || c.inb.name, 80) || 'Contacto de WhatsApp', phone,
      intent: facts.frente && facts.frente !== 'otro' ? facts.frente : (product ? 'software' : null),
      problem: c.h.clean([facts.business_type, facts.pain, summary].filter(Boolean).join(' · '), 1500),
      ...fields, calendar: product ? 'loggro' : 'personal', utm: ad?.utm || null, page: 'whatsapp',
    };
    await c.h.persistLead(env, c.ctx, lead, null);
    await env.DB.prepare('UPDATE wa_sessions SET lead_id = ?, phone = ? WHERE id = ?').bind(lead.id, phone, c.key).run();
    c.st = { ...st, lead_id: lead.id };
    return;
  }
  // El lead ya existía: se actualiza con lo nuevo (por ejemplo cuando terminó las preguntas) y se avisa solo si subió a prioridad A
  const prev = await env.DB.prepare('SELECT tier FROM leads WHERE id = ?').bind(st.lead_id).first();
  await env.DB.prepare('UPDATE leads SET budget = ?, timing = ?, decider = ?, points = ?, tier = ?, action = ?, problem = ? WHERE id = ?')
    .bind(fields.budget, fields.timing, fields.decider, fields.points, fields.tier, fields.action, c.h.clean([facts.business_type, facts.pain, summary].filter(Boolean).join(' · '), 1500), st.lead_id).run();
  if (fields.tier === 'A' && prev?.tier !== 'A') {
    await c.h.alertMessage(env, `🔥 HolaDami: ${c.h.clean(facts.contact_name || c.inb.name, 40) || 'Un lead'} (+${phone}) es prioridad A. ${summary} Escríbele: https://wa.me/${phone}`.replace(/\s+/g, ' '), env.KAPSO_NOTIFY_TEMPLATE);
  }
}

// Prioridad y respuestas del cuestionario para la tabla de leads
function leadFields(q, hot, facts) {
  if (q?.score) return { budget: facts.budget, timing: facts.timing, decider: facts.decider, points: q.score.points, tier: hot ? 'A' : q.score.tier, action: (hot || q.score.tier !== 'C') ? 'contact' : 'nurture' };
  return { budget: facts.budget || null, timing: facts.timing || null, decider: facts.decider || null, points: hot ? 22 : 14, tier: hot ? 'A' : 'B', action: 'contact' };
}

// Damián escribió a mano desde la bandeja o el celular: el agente se calla 24 h para no pisarlo
export async function pauseForHuman(env, phone) {
  const key = String(phone || '');
  if (!key) return;
  await env.DB.prepare("UPDATE agent_chats SET paused_until = ? WHERE chat_key = ?").bind(sqlTime(Date.now() + PAUSE_HOURS * 3600e3), key).run();
}


/* ---------- Chat de la página (sin WhatsApp) ----------
 * Mismo motor y mismas reglas: la respuesta vuelve al navegador en vez de enviarse por WhatsApp. El lead solo se guarda cuando la persona
 * deja su nombre y WhatsApp en el formulario (con la autorización de datos), nunca antes.
 */
const WEB_DAILY = 60;

export async function webTurn(env, h, { sessionId, message, ctx }) {
  const key = `web:${sessionId}`.slice(0, 64);
  const c = { env, h, ctx, key, source: 'web', inb: { text: message, type: 'text', id: '', name: '' }, first: '' };
  const chat = await loadChat(c);
  const today = (await env.DB.prepare("SELECT COUNT(*) AS n FROM agent_log WHERE chat_key = ? AND role = 'user' AND created_at > datetime('now', '-1 day')").bind(key).first())?.n || 0;
  if (today >= WEB_DAILY) return { messages: ['Hoy ya hablamos bastante 🙂 Déjame tus datos y te escribo yo, o vuelve mañana.'], links: [], ask_contact: !safeJson(chat.facts).lead_id };
  await env.DB.prepare('INSERT INTO agent_log (chat_key, role, content) VALUES (?, ?, ?)').bind(key, 'user', h.clean(message, 1500)).run();
  const history = ((await env.DB.prepare('SELECT role, content FROM agent_log WHERE chat_key = ? ORDER BY id DESC LIMIT ?').bind(key, HISTORY).all()).results || []).reverse();
  const out = await callModel(c, chat, history);
  if (out.is_auto_reply) return { messages: [], links: [], ask_contact: false };

  const messages = out.messages.map(m => sanitize(h, m)).filter(Boolean).slice(0, 3);
  const product = PRODUCT_IDS.includes(out.product) && PRODUCTS[out.product] ? out.product : (chat.product || null);
  const videosSent = new Set((chat.videos_sent || '').split(',').filter(Boolean));
  const links = [];
  if (out.send_video && product && !videosSent.has(product)) { links.push({ t: `Video de ${PRODUCTS[product].name}`, url: PRODUCTS[product].video }); videosSent.add(product); }
  const wantsAgenda = (out.offer_agenda_link || out.stage === 'wants_demo') && !chat.agenda_sent;
  if (wantsAgenda) links.push({ t: 'Elegir hora en mi agenda', url: AGENDA_URL });
  for (const m of messages) await logAssistant(c, m);
  await persist(c, chat, out, { product, videosSent, agendaSent: chat.agenda_sent || (wantsAgenda ? 1 : 0) });
  const facts = safeJson((await env.DB.prepare('SELECT facts FROM agent_chats WHERE chat_key = ?').bind(key).first())?.facts);
  return { messages, links, ask_contact: !!out.ask_contact && !facts.lead_id && out.stage !== 'optout' };
}

// La persona dejó nombre y WhatsApp (con autorización): se guarda el lead una sola vez y se avisa a Damián
export async function webContact(env, h, ctx, { sessionId, name, phone, utm }) {
  const key = `web:${sessionId}`.slice(0, 64);
  const chat = await env.DB.prepare('SELECT * FROM agent_chats WHERE chat_key = ?').bind(key).first();
  const facts = safeJson(chat?.facts);
  if (facts.lead_id) return facts.lead_id;
  const q = qualify(h, facts, chat?.stage);
  const f = (q.score || chat?.hot || (facts.business_type && facts.pain)) ? leadFields(q, !!chat?.hot || q.hot, facts) : { budget: null, timing: null, decider: null, points: 6, tier: 'C', action: 'nurture' };
  const tier = f.tier;
  const loggro = !!chat?.product;
  const lead = {
    id: crypto.randomUUID(), session_id: key, name, phone,
    intent: facts.frente && facts.frente !== 'otro' ? facts.frente : (loggro ? 'software' : null), problem: h.clean([facts.business_type, facts.pain, chat?.summary].filter(Boolean).join(' · ') || 'Dejó sus datos en el chat de la página', 1500),
    budget: f.budget, timing: f.timing, decider: f.decider, points: f.points, tier, action: f.action, calendar: loggro ? 'loggro' : 'personal',
    utm: utm || null, page: 'web-chat',
  };
  await h.persistLead(env, ctx, lead, null);
  await env.DB.prepare('INSERT OR IGNORE INTO agent_chats (chat_key, source) VALUES (?, ?)').bind(key, 'web').run();
  await env.DB.prepare("UPDATE agent_chats SET facts = ?, updated_at = datetime('now') WHERE chat_key = ?").bind(JSON.stringify({ ...facts, lead_id: lead.id, contact_name: name }), key).run();
  await env.DB.prepare('INSERT INTO agent_log (chat_key, role, content) VALUES (?, ?, ?)').bind(key, 'user', `[Dejé mis datos de contacto en el formulario. Me llamo ${h.clean(name, 40)}.]`).run();
  return lead.id;
}

async function persistWeb(c, chat, { out, hot, facts, summary, q }) {
  const { env } = c;
  if (!facts.lead_id) return;
  // El lead ya dejó sus datos: se actualiza con lo que siga contando y se avisa solo si sube a prioridad A
  const f = leadFields(q, hot, facts);
  const prev = await env.DB.prepare('SELECT tier, phone FROM leads WHERE id = ?').bind(facts.lead_id).first();
  await env.DB.prepare('UPDATE leads SET budget = ?, timing = ?, decider = ?, points = ?, tier = ?, action = ?, problem = ? WHERE id = ?')
    .bind(f.budget, f.timing, f.decider, f.points, f.tier, f.action, c.h.clean([facts.business_type, facts.pain, summary].filter(Boolean).join(' · '), 1500), facts.lead_id).run();
  if (f.tier === 'A' && prev?.tier !== 'A') {
    await c.h.alertMessage(env, `🔥 HolaDami (chat de la página): ${c.h.clean(facts.contact_name, 40) || 'Un lead'}${prev?.phone ? ` +${prev.phone}` : ''} es prioridad A. ${summary}${prev?.phone ? ` Escríbele: https://wa.me/${prev.phone}` : ''}`.replace(/\s+/g, ' '), env.KAPSO_NOTIFY_TEMPLATE);
  }
}
