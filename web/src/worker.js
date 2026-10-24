/**
 * Backend de la página de Damián Barragán (Cloudflare Worker).
 *
 *   GET  /api/health      → estado
 *   POST /api/chat        → la IA (OpenAI) entiende el problema y responde
 *   POST /api/transcribe  → nota de voz → texto (OpenAI)
 *   POST /api/lead        → guarda el lead en D1, calcula prioridad, avisa a Damián por WhatsApp (Kapso)
 *   GET  /api/leads       → lista de leads (requiere ADMIN_TOKEN)
 *   POST /api/agent       → el agente conversa con el lead y agenda la reunión (n8n → Google/Outlook)
 *   GET  /api/resume      → retomar la conversación desde el link de un seguimiento (?r=<lead>)
 *   cron (cada 30 min)    → seguimiento a leads A/B, confirmaciones y recordatorios (solo si AUTO_CONTACT_LEADS = "true")
 *
 * Todo lo demás lo sirve la carpeta /public (la página).
 */

import { runAgent, label as whenLabel } from './agent.js';

const INTENTS = ['nomina', 'software', 'ia', 'procesos', 'datos'];
const INTENT_NAMES = { nomina: 'Nómina', software: 'Software', ia: 'IA y automatización', procesos: 'Procesos', datos: 'Datos y campañas' };
const LABELS = {
  budget: { b1: 'Hasta $1,5 M', b2: '$1,5 M – $5 M', b3: 'Más de $5 M' },
  timing: { now: 'Urgente', month: 'Este mes', later: 'Solo averiguando' },
  decider: { solo: 'Decide solo', with: 'Decide con socio/familia', other: 'Decide otra persona' },
};
const SCORES = { b1: 1, b2: 2, b3: 3, now: 3, month: 2, later: 0, solo: 3, with: 2, other: 0 };

const SYSTEM_PROMPT = `Eres el asistente de la página web de Damián Barragán, consultor en Colombia con 15 años en ventas y operación de empresas de servicio (banca, telecomunicaciones, comercio y software).
Damián resuelve problemas puntuales de pequeños negocios en cinco frentes:
- nomina: liquidación de nómina, prestaciones, seguridad social, nómina electrónica (con Loggro Nómina o con su aliada Nomiluz).
- software: POS, inventario, facturación electrónica DIAN y contabilidad con Loggro.
- ia: asistentes de WhatsApp con IA, automatizaciones con n8n, páginas web en Cloudflare.
- procesos: desorden, cuellos de botella, el negocio depende del dueño, la caja no cuadra.
- datos: base de clientes, segmentación y campañas masivas por WhatsApp.
Lee el mensaje del visitante y responde en JSON:
- intent: el frente que mejor encaja, u "otro" si no encaja en ninguno.
- reply: 1 o 2 frases en español de Colombia, cálidas y concretas, en primera persona como Damián. Muestra que entendiste el problema y di cómo lo resolverías en una línea. No inventes precios, plazos ni resultados. No hagas preguntas: el formulario sigue con las preguntas.
Si el mensaje no tiene sentido o es ofensivo, intent "otro" y una respuesta breve y amable.`;

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    if (!url.pathname.startsWith('/api/')) return env.ASSETS.fetch(request);
    try {
      if (url.pathname === '/api/health') return json({ ok: true, ai: !!env.OPENAI_API_KEY, whatsapp: !!(env.KAPSO_API_KEY && env.KAPSO_PHONE_NUMBER_ID), agenda: agentReady(env) });
      if (request.method === 'POST' && url.pathname === '/api/chat') return await chat(request, env);
      if (request.method === 'POST' && url.pathname === '/api/transcribe') return await transcribe(request, env);
      if (request.method === 'POST' && url.pathname === '/api/lead') return await createLead(request, env, ctx);
      if (request.method === 'GET' && url.pathname === '/api/leads') return await listLeads(request, env);
      if (request.method === 'POST' && url.pathname === '/api/agent') return await agent(request, env, ctx);
      if (request.method === 'GET' && url.pathname === '/api/resume') return await resume(request, env);
      return json({ error: 'No encontrado' }, 404);
    } catch (err) {
      console.error(err);
      return json({ error: 'Error interno' }, 500);
    }
  },
  async scheduled(event, env, ctx) {
    ctx.waitUntil(proactive(env).catch(err => console.error('proactive', err)));
  },
};

/* ---------- /api/chat ---------- */
async function chat(request, env) {
  if (!sameOrigin(request)) return json({ error: 'Origen no permitido' }, 403);
  const body = await request.json().catch(() => null);
  const message = clean(body?.message, 1500);
  const sessionId = clean(body?.sessionId, 64);
  if (!message || !sessionId) return json({ error: 'Falta el mensaje' }, 400);

  const ipHash = await hashIp(request, env);
  if (await overLimit(env, ipHash)) return json({ error: 'Demasiados mensajes. Intenta en unos minutos.' }, 429);
  await env.DB.prepare('INSERT INTO chat_messages (session_id, ip_hash, role, content) VALUES (?, ?, ?, ?)')
    .bind(sessionId, ipHash, 'user', message).run();

  if (!env.OPENAI_API_KEY) return json({ error: 'IA no configurada' }, 503);
  const res = await fetch('https://api.openai.com/v1/chat/completions', {
    method: 'POST',
    headers: { authorization: `Bearer ${env.OPENAI_API_KEY}`, 'content-type': 'application/json' },
    body: JSON.stringify({
      model: env.OPENAI_MODEL || 'gpt-4o-mini',
      temperature: 0.4,
      max_tokens: 220,
      messages: [{ role: 'system', content: SYSTEM_PROMPT }, { role: 'user', content: message }],
      response_format: {
        type: 'json_schema',
        json_schema: {
          name: 'triage', strict: true,
          schema: {
            type: 'object', additionalProperties: false, required: ['intent', 'reply'],
            properties: { intent: { type: 'string', enum: [...INTENTS, 'otro'] }, reply: { type: 'string' } },
          },
        },
      },
    }),
  });
  if (!res.ok) { console.error('OpenAI chat', res.status, await res.text()); return json({ error: 'IA no disponible' }, 502); }
  const data = await res.json();
  let out;
  try { out = JSON.parse(data.choices[0].message.content); } catch { return json({ error: 'Respuesta inválida' }, 502); }
  const intent = INTENTS.includes(out.intent) ? out.intent : null;
  const reply = clean(out.reply, 600);
  await env.DB.prepare('INSERT INTO chat_messages (session_id, ip_hash, role, content, intent) VALUES (?, ?, ?, ?, ?)')
    .bind(sessionId, ipHash, 'assistant', reply, intent).run();
  return json({ intent, reply });
}

/* ---------- /api/transcribe ---------- */
async function transcribe(request, env) {
  if (!sameOrigin(request)) return json({ error: 'Origen no permitido' }, 403);
  if (!env.OPENAI_API_KEY) return json({ error: 'IA no configurada' }, 503);
  const form = await request.formData().catch(() => null);
  const audio = form?.get('audio');
  if (!audio || typeof audio === 'string') return json({ error: 'Falta el audio' }, 400);
  if (audio.size > 10 * 1024 * 1024) return json({ error: 'El audio supera 10 MB' }, 413);

  const ipHash = await hashIp(request, env);
  if (await overLimit(env, ipHash)) return json({ error: 'Demasiados mensajes. Intenta en unos minutos.' }, 429);

  const fd = new FormData();
  fd.append('file', audio, audio.name || 'nota.webm');
  fd.append('model', env.OPENAI_TRANSCRIBE_MODEL || 'whisper-1');
  fd.append('language', 'es');
  const res = await fetch('https://api.openai.com/v1/audio/transcriptions', {
    method: 'POST', headers: { authorization: `Bearer ${env.OPENAI_API_KEY}` }, body: fd,
  });
  if (!res.ok) { console.error('OpenAI transcribe', res.status, await res.text()); return json({ error: 'No pude transcribir el audio' }, 502); }
  const { text } = await res.json();
  return json({ text: clean(text, 3000) });
}

/* ---------- /api/lead ---------- */
async function createLead(request, env, ctx) {
  if (!sameOrigin(request)) return json({ error: 'Origen no permitido' }, 403);
  const b = await request.json().catch(() => null);
  if (!b) return json({ error: 'Datos inválidos' }, 400);

  const name = clean(b.name, 80);
  const phone = normalizePhone(b.phone);
  const intent = INTENTS.includes(b.intent) ? b.intent : null;
  const budget = ['b1', 'b2', 'b3'].includes(b.budget) ? b.budget : null;
  const timing = ['now', 'month', 'later'].includes(b.timing) ? b.timing : null;
  const decider = ['solo', 'with', 'other'].includes(b.decider) ? b.decider : null;
  if (!name || !phone || !budget || !timing || !decider) return json({ error: 'Faltan datos' }, 400);
  if (b.consent !== true) return json({ error: 'Falta la autorización de datos' }, 400);

  // La prioridad se calcula aquí, no en el navegador
  const points = SCORES[budget] * 3 + SCORES[timing] * 3 + SCORES[decider] * 2 + (intent ? 3 : 0); // máx. 27
  const tier = points >= 20 ? 'A' : points >= 13 ? 'B' : 'C';
  const action = tier === 'C' ? 'nurture' : 'contact';
  // Software (Loggro) se agenda en el calendario de Loggro; lo demás, en el calendario de la empresa de Damián
  const calendar = intent === 'software' ? 'loggro' : 'personal';
  const bookingUrl = action === 'contact' ? (calendar === 'loggro' ? env.BOOKING_URL_LOGGRO : env.BOOKING_URL_PERSONAL) || null : null;

  const id = crypto.randomUUID();
  const lead = {
    id, session_id: clean(b.sessionId, 64), name, phone, intent, problem: clean(b.problem, 3000),
    budget, timing, decider, points, tier, action, calendar,
    utm: JSON.stringify(b.utm && typeof b.utm === 'object' ? b.utm : {}).slice(0, 1000), page: clean(b.page, 500),
  };
  await env.DB.prepare(`INSERT INTO leads (id, session_id, name, phone, intent, problem, budget, timing, decider, points, tier, action, calendar, consent, utm, page)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?)`)
    .bind(lead.id, lead.session_id, name, phone, intent, lead.problem, budget, timing, decider, points, tier, action, calendar, lead.utm, lead.page).run();

  ctx.waitUntil(notifyOwner(env, lead));
  if (env.AUTO_CONTACT_LEADS === 'true' && action === 'contact') ctx.waitUntil(contactLead(env, lead));

  return json({ id, tier, action, bookingUrl, agent: action === 'contact' && agentReady(env) });
}

/* ---------- /api/leads (solo Damián) ---------- */
async function listLeads(request, env) {
  const token = (request.headers.get('authorization') || '').replace(/^Bearer\s+/i, '');
  if (!env.ADMIN_TOKEN || token !== env.ADMIN_TOKEN) return json({ error: 'No autorizado' }, 401);
  const { results } = await env.DB.prepare('SELECT * FROM leads ORDER BY created_at DESC LIMIT 200').all();
  return json({ leads: results });
}

/* ---------- Agente que agenda ---------- */
function agentReady(env) {
  return !!(env.OPENAI_API_KEY && env.N8N_BASE_URL && env.N8N_SECRET);
}

async function loadLead(env, id) {
  const lead = await env.DB.prepare('SELECT * FROM leads WHERE id = ?').bind(id).first();
  if (lead) lead.intentName = INTENT_NAMES[lead.intent] || null;
  return lead;
}

async function agent(request, env, ctx) {
  if (!sameOrigin(request)) return json({ error: 'Origen no permitido' }, 403);
  if (!agentReady(env)) return json({ error: 'Agenda no configurada' }, 503);
  const b = await request.json().catch(() => null);
  const message = clean(b?.message, 1000);
  const leadId = clean(b?.leadId, 64);
  const sessionId = clean(b?.sessionId, 64);
  if (!message || !leadId) return json({ error: 'Falta el mensaje' }, 400);

  const lead = await loadLead(env, leadId);
  if (!lead || lead.tier === 'C') return json({ error: 'No encontrado' }, 404);
  // Dueño de la conversación: la sesión que creó el lead, o quien llega por el link del seguimiento (UUID imposible de adivinar).
  if (lead.session_id !== sessionId && b.resume !== true) return json({ error: 'No autorizado' }, 403);

  const ipHash = await hashIp(request, env);
  if (await overLimit(env, ipHash)) return json({ error: 'Demasiados mensajes. Intenta en unos minutos.' }, 429);

  const thread = `lead:${lead.id}`;
  const { results } = await env.DB.prepare('SELECT role, content FROM chat_messages WHERE session_id = ? ORDER BY id DESC LIMIT 16').bind(thread).all();
  const history = results.reverse();
  await env.DB.prepare('INSERT INTO chat_messages (session_id, ip_hash, role, content, intent) VALUES (?, ?, ?, ?, ?)')
    .bind(thread, ipHash, 'user', message, 'agent').run();

  const deps = {
    saveBooking: async ({ startMs, endMs, eventId }) => {
      const soon = startMs - Date.now() < 26 * 3600e3 ? 1 : 0; // si la cita es en menos de ~1 día, no hace falta el recordatorio de 24 h
      await env.DB.prepare("UPDATE leads SET meeting_start = ?, meeting_end = ?, meeting_event_id = ?, status = 'agendado', reminded_24 = ? WHERE id = ?")
        .bind(new Date(startMs).toISOString(), new Date(endMs).toISOString(), eventId, soon, lead.id).run();
      ctx.waitUntil(announceBooking(env, lead, startMs));
    },
    notify: async reason => {
      await env.DB.prepare('UPDATE leads SET owner_note = ? WHERE id = ?').bind(reason, lead.id).run();
      ctx.waitUntil(ownerMessage(env, `🙋 Te necesitan: ${lead.name} +${lead.phone} (${INTENT_NAMES[lead.intent] || 'sin tema'})\n${reason}`));
    },
  };

  let out;
  try { out = await runAgent({ env, lead, history, message, deps }); }
  catch (err) { console.error('agent', err); return json({ error: 'Agente no disponible' }, 502); }
  const reply = clean(out.reply, 900) || 'Déjame confirmarlo con Damián y te escribo.';
  await env.DB.prepare('INSERT INTO chat_messages (session_id, ip_hash, role, content, intent) VALUES (?, ?, ?, ?, ?)')
    .bind(thread, ipHash, 'assistant', reply, 'agent').run();
  return json({ reply, booked: out.booked ? { label: out.booked.label } : null });
}

// Retomar desde el link del seguimiento: https://holadami.com/?r=<leadId>
async function resume(request, env) {
  if (!agentReady(env)) return json({ error: 'Agenda no configurada' }, 503);
  const id = clean(new URL(request.url).searchParams.get('lead'), 64);
  const lead = id && await loadLead(env, id);
  if (!lead || lead.tier === 'C') return json({ error: 'No encontrado' }, 404);
  return json({
    leadId: lead.id, firstName: lead.name.split(' ')[0],
    meeting: lead.meeting_start ? whenLabel(Date.parse(lead.meeting_start)) : null,
  });
}

async function announceBooking(env, lead, startMs) {
  const when = whenLabel(startMs);
  await ownerMessage(env, `📅 Cita agendada: ${lead.name} +${lead.phone}\n${when} · ${lead.calendar === 'loggro' ? 'calendario Loggro' : 'calendario personal'}\nTema: ${INTENT_NAMES[lead.intent] || 'Sin clasificar'}`);
  if (env.AUTO_CONTACT_LEADS === 'true' && env.KAPSO_CONFIRM_TEMPLATE) {
    await sendWhatsApp(env, template(lead.phone, env.KAPSO_CONFIRM_TEMPLATE, env.KAPSO_TEMPLATE_LANG, [lead.name.split(' ')[0], when]));
  }
}

async function ownerMessage(env, text) {
  if (!env.KAPSO_API_KEY || !env.KAPSO_PHONE_NUMBER_ID || !env.OWNER_WHATSAPP) return;
  await sendWhatsApp(env, env.KAPSO_NOTIFY_TEMPLATE
    ? template(env.OWNER_WHATSAPP, env.KAPSO_NOTIFY_TEMPLATE, env.KAPSO_TEMPLATE_LANG, [text])
    : { messaging_product: 'whatsapp', to: env.OWNER_WHATSAPP, type: 'text', text: { body: text } });
}

/* ---------- Proactividad (cron cada 30 min) ----------
 * Escribe a clientes reales, así que solo corre con AUTO_CONTACT_LEADS = "true" y plantillas aprobadas en Meta:
 *   KAPSO_FOLLOWUP_TEMPLATE → {{1}} nombre · {{2}} tema · {{3}} link para retomar
 *   KAPSO_REMIND_TEMPLATE   → {{1}} nombre · {{2}} cuándo
 */
async function proactive(env) {
  if (env.AUTO_CONTACT_LEADS !== 'true' || !env.KAPSO_API_KEY || !env.KAPSO_PHONE_NUMBER_ID) return;
  const lang = env.KAPSO_TEMPLATE_LANG;
  const now = Date.now();

  // 1. Recordatorios de cita: 24 h y 1 h antes
  if (env.KAPSO_REMIND_TEMPLATE) {
    const { results } = await env.DB.prepare("SELECT * FROM leads WHERE status = 'agendado' AND meeting_start IS NOT NULL AND (reminded_24 = 0 OR reminded_1 = 0)").all();
    for (const m of results) {
      const ms = Date.parse(m.meeting_start), delta = ms - now;
      if (!Number.isFinite(ms) || delta < 0) continue;
      const col = delta <= 75 * 60e3 ? (m.reminded_1 ? null : 'reminded_1') : delta <= 24 * 3600e3 ? (m.reminded_24 ? null : 'reminded_24') : null;
      if (!col) continue;
      const ok = await sendWhatsApp(env, template(m.phone, env.KAPSO_REMIND_TEMPLATE, lang, [m.name.split(' ')[0], whenLabel(ms)]));
      if (ok) await env.DB.prepare(`UPDATE leads SET ${col} = 1${col === 'reminded_1' ? ', reminded_24 = 1' : ''} WHERE id = ?`).bind(m.id).run();
    }
  }

  // 2. Seguimiento a leads A/B que no agendaron: a las 3 h y a las 24 h, máximo 2, solo de 8 am a 8 pm
  const hourBogota = new Date(now - 5 * 3600e3).getUTCHours();
  if (env.KAPSO_FOLLOWUP_TEMPLATE && agentReady(env) && hourBogota >= 8 && hourBogota < 20) {
    const origin = env.PUBLIC_URL || 'https://holadami.com';
    const { results } = await env.DB.prepare(`SELECT * FROM leads
      WHERE tier IN ('A', 'B') AND status = 'nuevo' AND consent = 1 AND meeting_start IS NULL AND followups < 2
        AND created_at <= datetime('now', CASE followups WHEN 0 THEN '-3 hours' ELSE '-24 hours' END)
        AND (last_followup_at IS NULL OR last_followup_at <= datetime('now', '-24 hours'))
      LIMIT 10`).all();
    for (const l of results) {
      const ok = await sendWhatsApp(env, template(l.phone, env.KAPSO_FOLLOWUP_TEMPLATE, lang,
        [l.name.split(' ')[0], INTENT_NAMES[l.intent] || 'tu negocio', `${origin}/?r=${l.id}`]));
      if (ok) await env.DB.prepare("UPDATE leads SET followups = followups + 1, last_followup_at = datetime('now') WHERE id = ?").bind(l.id).run();
    }
  }
}

/* ---------- WhatsApp vía Kapso ---------- */
async function notifyOwner(env, lead) {
  if (!env.KAPSO_API_KEY || !env.KAPSO_PHONE_NUMBER_ID || !env.OWNER_WHATSAPP) return;
  const icon = { A: '🔥', B: '⭐', C: '🌱' }[lead.tier];
  const summary = [
    `${icon} Lead ${lead.tier} (${lead.points}/27): ${lead.name} +${lead.phone}`,
    `Tema: ${INTENT_NAMES[lead.intent] || 'Sin clasificar'}`,
    `${LABELS.budget[lead.budget]} · ${LABELS.timing[lead.timing]} · ${LABELS.decider[lead.decider]}`,
    `Agenda: ${lead.calendar === 'loggro' ? 'calendario Loggro' : 'calendario personal'}`,
    `Problema: ${(lead.problem || 'Nota de voz sin transcribir').slice(0, 300)}`,
  ];
  // Fuera de la ventana de 24 h, WhatsApp solo permite plantillas aprobadas.
  const payload = env.KAPSO_NOTIFY_TEMPLATE
    ? template(env.OWNER_WHATSAPP, env.KAPSO_NOTIFY_TEMPLATE, env.KAPSO_TEMPLATE_LANG, [summary.join(' · ')])
    : { messaging_product: 'whatsapp', to: env.OWNER_WHATSAPP, type: 'text', text: { body: summary.join('\n') } };
  const ok = await sendWhatsApp(env, payload);
  if (ok) await env.DB.prepare("UPDATE leads SET notified_at = datetime('now') WHERE id = ?").bind(lead.id).run();
}

// Mensaje a un cliente real: apagado por defecto (AUTO_CONTACT_LEADS = "false").
async function contactLead(env, lead) {
  if (!env.KAPSO_API_KEY || !env.KAPSO_PHONE_NUMBER_ID || !env.KAPSO_LEAD_TEMPLATE) return;
  const first = lead.name.split(' ')[0];
  await sendWhatsApp(env, template(lead.phone, env.KAPSO_LEAD_TEMPLATE, env.KAPSO_TEMPLATE_LANG, [first, INTENT_NAMES[lead.intent] || 'tu negocio']));
}

function template(to, name, lang, params) {
  return {
    messaging_product: 'whatsapp', to, type: 'template',
    template: {
      name, language: { code: lang || 'es' },
      components: [{ type: 'body', parameters: params.map(t => ({ type: 'text', text: String(t).replace(/\s*\n\s*/g, ' · ').slice(0, 1000) })) }],
    },
  };
}

async function sendWhatsApp(env, payload) {
  const res = await fetch(`https://api.kapso.ai/meta/whatsapp/v24.0/${env.KAPSO_PHONE_NUMBER_ID}/messages`, {
    method: 'POST',
    headers: { 'X-API-Key': env.KAPSO_API_KEY, 'content-type': 'application/json' },
    body: JSON.stringify(payload),
  });
  if (!res.ok) console.error('Kapso', res.status, await res.text());
  return res.ok;
}

/* ---------- utilidades ---------- */
function json(data, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' } });
}
function clean(v, max) {
  return typeof v === 'string' ? v.replace(/[\u0000-\u0008\u000b-\u001f]/g, '').trim().slice(0, max) : '';
}
// Colombia por defecto: 3001234567 → 573001234567
function normalizePhone(v) {
  const d = String(v || '').replace(/\D/g, '');
  if (d.length === 10 && d.startsWith('3')) return '57' + d;
  return d.length >= 11 && d.length <= 15 ? d : null;
}
function sameOrigin(request) {
  const origin = request.headers.get('origin');
  return !origin || origin === new URL(request.url).origin;
}
async function hashIp(request, env) {
  const ip = request.headers.get('cf-connecting-ip') || 'local';
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(ip + (env.IP_SALT || '')));
  return [...new Uint8Array(buf)].slice(0, 12).map(x => x.toString(16).padStart(2, '0')).join('');
}
// Máximo 30 mensajes por IP cada 10 minutos, para cuidar el costo de la IA
async function overLimit(env, ipHash) {
  const row = await env.DB.prepare("SELECT COUNT(*) AS n FROM chat_messages WHERE ip_hash = ? AND role = 'user' AND created_at > datetime('now', '-10 minutes')")
    .bind(ipHash).first();
  return (row?.n || 0) >= 30;
}
