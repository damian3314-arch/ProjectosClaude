/**
 * Backend de la página de Damián Barragán (Cloudflare Worker).
 *
 *   GET   /api/health      → estado
 *   POST  /api/chat        → la IA (OpenAI) entiende el problema y responde
 *   POST  /api/transcribe  → nota de voz → texto (OpenAI)
 *   POST  /api/lead        → guarda el lead, calcula prioridad, prepara el brief y avisa a Damián por WhatsApp (Kapso)
 *   POST  /api/event       → eventos del embudo (visita, preguntas, formulario); responde siempre 204
 *   GET   /api/leads       → lista de leads con su brief (requiere ADMIN_TOKEN)
 *   PATCH /api/leads/:id   → estado y nota del lead (requiere ADMIN_TOKEN)
 *   GET   /api/stats       → métricas del embudo (requiere ADMIN_TOKEN)
 *   cron (cada hora)       → empujón a Damián por leads sin contactar y resumen diario de las 7 am (solo le escribe a él)
 *
 * Damián agenda a mano: el sistema solo le prepara el terreno y mide el embudo.
 * Todo lo demás lo sirve la carpeta /public (la página).
 */

import { generateBrief, fallbackBrief } from './brief.js';

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
      const path = url.pathname;
      if (path === '/api/health') return json({ ok: true, ai: !!env.OPENAI_API_KEY, whatsapp: !!(env.KAPSO_API_KEY && env.KAPSO_PHONE_NUMBER_ID) });
      if (request.method === 'POST' && path === '/api/chat') return await chat(request, env);
      if (request.method === 'POST' && path === '/api/transcribe') return await transcribe(request, env);
      if (request.method === 'POST' && path === '/api/lead') return await createLead(request, env, ctx);
      if (request.method === 'POST' && path === '/api/event') return await trackEvent(request, env);
      if (request.method === 'GET' && path === '/api/leads') return await listLeads(request, env);
      const m = path.match(/^\/api\/leads\/([A-Za-z0-9-]{1,64})$/);
      if (request.method === 'PATCH' && m) return await updateLead(request, env, m[1]);
      if (request.method === 'GET' && path === '/api/stats') return await stats(request, env, url);
      return json({ error: 'No encontrado' }, 404);
    } catch (err) {
      console.error('error', err?.message || 'desconocido'); // sin el objeto completo: puede traer datos del lead
      return json({ error: 'Error interno' }, 500);
    }
  },
  async scheduled(event, env, ctx) {
    ctx.waitUntil(ownerPush(env).catch(err => console.error('ownerPush', err?.message || 'desconocido')));
  },
};

/* ---------- /api/chat ---------- */
async function chat(request, env) {
  if (!sameOrigin(request)) return json({ error: 'Origen no permitido' }, 403);
  const body = await readJson(request, 8 * 1024);
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
  if (!res.ok) { console.error('OpenAI chat', res.status); return json({ error: 'IA no disponible' }, 502); }
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
  if (!res.ok) { console.error('OpenAI transcribe', res.status); return json({ error: 'No pude transcribir el audio' }, 502); }
  const { text } = await res.json();
  return json({ text: clean(text, 3000) });
}

/* ---------- /api/lead ---------- */
async function createLead(request, env, ctx) {
  if (!sameOrigin(request)) return json({ error: 'Origen no permitido' }, 403);
  const ipHash = await hashIp(request, env);
  // Máximo 5 leads por IP por hora: cada lead dispara IA y un WhatsApp a Damián
  const recent = await env.DB.prepare("SELECT COUNT(*) AS n FROM events WHERE ip_hash = ? AND type = 'lead' AND created_at > datetime('now', '-1 hour')").bind(ipHash).first();
  if ((recent?.n || 0) >= 5) return json({ error: 'Demasiados envíos. Intenta más tarde.' }, 429);
  const b = await readJson(request, 16 * 1024);
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
  // Software (Loggro) usa el calendario de Loggro; lo demás, el de la empresa de Damián (solo para el link opcional)
  const calendar = intent === 'software' ? 'loggro' : 'personal';
  const bookingUrl = action === 'contact' ? (calendar === 'loggro' ? env.BOOKING_URL_LOGGRO : env.BOOKING_URL_PERSONAL) || null : null;

  const id = crypto.randomUUID();
  const lead = {
    id, session_id: clean(b.sessionId, 64), name, phone, intent, problem: clean(b.problem, 3000),
    budget, timing, decider, points, tier, action, calendar,
    utm: cleanUtm(b.utm), page: clean(b.page, 500),
  };
  await env.DB.prepare(`INSERT INTO leads (id, session_id, name, phone, intent, problem, budget, timing, decider, points, tier, action, calendar, consent, utm, page)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?)`)
    .bind(lead.id, lead.session_id, name, phone, intent, lead.problem, budget, timing, decider, points, tier, action, calendar, lead.utm, lead.page).run();

  // Embudo: la etapa 'lead' la registra el servidor (no depende del navegador). Si falla, el lead ya quedó guardado.
  await env.DB.prepare('INSERT INTO events (session_id, ip_hash, type, intent, utm) VALUES (?, ?, ?, ?, ?)')
    .bind(lead.session_id || id, ipHash, 'lead', intent, lead.utm).run().catch(err => console.error('event lead', err?.message));

  ctx.waitUntil(prepareAndNotify(env, lead));
  if (env.AUTO_CONTACT_LEADS === 'true' && action === 'contact') ctx.waitUntil(contactLead(env, lead));

  return json({ id, tier, action, bookingUrl });
}

// Brief (IA o plantilla) → se guarda → aviso a Damián con la apertura lista para copiar.
async function prepareAndNotify(env, lead) {
  let brief;
  try { brief = await generateBrief(env, lead); } catch { brief = fallbackBrief(lead); }
  try {
    await env.DB.prepare("UPDATE leads SET brief = ?, brief_at = datetime('now') WHERE id = ?").bind(JSON.stringify(brief), lead.id).run();
  } catch (err) { console.error('guardar brief', err?.message); }
  await notifyOwner(env, lead, brief);
}

/* ---------- /api/event (embudo, público) ---------- */
const EVENT_TYPES = ['visit', 'start', 'intent', 'q_budget', 'q_timing', 'q_decider', 'contact_form', 'lead'];

// Nunca falla ruidosamente: lo inválido se ignora y siempre responde 204.
async function trackEvent(request, env) {
  const ok = () => new Response(null, { status: 204 });
  try {
    if (!sameOrigin(request)) return ok();
    const b = await readJson(request, 2 * 1024);
    const sessionId = clean(b?.sessionId, 64);
    // 'lead' lo registra solo el servidor al guardar el lead; aquí no se acepta
    if (!sessionId || !EVENT_TYPES.includes(b.type) || b.type === 'lead') return ok();
    const intent = [...INTENTS, 'otro'].includes(b.intent) ? b.intent : null;
    const ipHash = await hashIp(request, env);
    const row = await env.DB.prepare("SELECT COUNT(*) AS n FROM events WHERE ip_hash = ? AND created_at > datetime('now', '-10 minutes')").bind(ipHash).first();
    if ((row?.n || 0) >= 120) return ok();
    await env.DB.prepare('INSERT INTO events (session_id, ip_hash, type, intent, utm) VALUES (?, ?, ?, ?, ?)')
      .bind(sessionId, ipHash, b.type, intent, cleanUtm(b.utm)).run();
  } catch (err) { console.error('event', err?.message); }
  return ok();
}

/* ---------- Admin (solo Damián) ---------- */
async function isAdmin(request, env) {
  if (!env.ADMIN_TOKEN) return false;
  const token = (request.headers.get('authorization') || '').replace(/^Bearer\s+/i, '');
  // Se comparan los hashes: tiempo constante y sin filtrar el largo de la clave
  const [a, b] = await Promise.all([sha256(token), sha256(env.ADMIN_TOKEN)]);
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}

const STATUSES = ['nuevo', 'contactado', 'agendado', 'cliente', 'descartado'];

async function listLeads(request, env) {
  if (!(await isAdmin(request, env))) return json({ error: 'No autorizado' }, 401);
  const { results } = await env.DB.prepare('SELECT * FROM leads ORDER BY created_at DESC LIMIT 200').all();
  return json({ leads: results.map(l => ({ ...l, brief: parseJson(l.brief) })) });
}

async function updateLead(request, env, id) {
  if (!(await isAdmin(request, env))) return json({ error: 'No autorizado' }, 401);
  const b = await readJson(request, 4 * 1024);
  if (!b || typeof b !== 'object' || Array.isArray(b)) return json({ error: 'Datos inválidos' }, 400);
  const hasStatus = b.status !== undefined, hasNote = b.note !== undefined;
  if (!hasStatus && !hasNote) return json({ error: 'Nada que actualizar' }, 400);
  if (hasStatus && !STATUSES.includes(b.status)) return json({ error: 'Estado inválido' }, 400);
  if (hasNote && (typeof b.note !== 'string' || b.note.length > 1000)) return json({ error: 'La nota supera 1000 caracteres' }, 400);

  const sets = [], vals = [];
  if (hasStatus) {
    sets.push('status = ?', "status_at = datetime('now')");
    vals.push(b.status);
    // Tiempo de respuesta: solo cuenta cuando Damián realmente habló con el lead
    if (['contactado', 'agendado', 'cliente'].includes(b.status)) sets.push("contacted_at = COALESCE(contacted_at, datetime('now'))");
  }
  if (hasNote) { sets.push('owner_note = ?'); vals.push(clean(b.note, 1000)); }
  const res = await env.DB.prepare(`UPDATE leads SET ${sets.join(', ')} WHERE id = ?`).bind(...vals, id).run();
  if (!res.meta?.changes) return json({ error: 'No encontrado' }, 404);
  return json({ ok: true });
}

async function stats(request, env, url) {
  if (!(await isAdmin(request, env))) return json({ error: 'No autorizado' }, 401);
  const n = Number.parseInt(url.searchParams.get('days') || '30', 10);
  const days = Number.isFinite(n) ? Math.min(90, Math.max(1, n)) : 30;

  // Ventana en días calendario de Bogotá (UTC-5): la medianoche de Bogotá son las 05:00 UTC
  const list = [];
  for (let i = days - 1; i >= 0; i--) list.push(new Date(Date.now() - BOGOTA_MS - i * 864e5).toISOString().slice(0, 10));
  const since = `${list[0]} 05:00:00`;
  const q = (sql, ...args) => env.DB.prepare(sql).bind(since, ...args).all().then(r => r.results);

  const [stages, leadRows, leadDays, visitDays, visitRows, contact] = await Promise.all([
    q('SELECT type, COUNT(DISTINCT session_id) AS n FROM events WHERE created_at >= ? GROUP BY type'),
    q('SELECT tier, intent, status, utm FROM leads WHERE created_at >= ? LIMIT 5000'),
    q("SELECT date(created_at, '-5 hours') AS d, COUNT(*) AS n FROM leads WHERE created_at >= ? GROUP BY d"),
    q("SELECT date(created_at, '-5 hours') AS d, COUNT(DISTINCT session_id) AS n FROM events WHERE type = 'visit' AND created_at >= ? GROUP BY d"),
    q("SELECT session_id, utm FROM events WHERE type = 'visit' AND created_at >= ? GROUP BY session_id LIMIT 20000"),
    q("SELECT AVG((julianday(contacted_at) - julianday(created_at)) * 24) AS h FROM leads WHERE created_at >= ? AND contacted_at IS NOT NULL"),
  ]);

  const by = Object.fromEntries(stages.map(s => [s.type, s.n]));
  const funnel = {
    visits: by.visit || 0, started: by.start || 0, classified: by.intent || 0, budget: by.q_budget || 0,
    timing: by.q_timing || 0, decider: by.q_decider || 0, contact_form: by.contact_form || 0, leads: by.lead || 0,
  };
  const tiers = { A: 0, B: 0, C: 0 };
  const byIntent = { nomina: 0, software: 0, ia: 0, procesos: 0, datos: 0, otro: 0 };
  const statusCounts = Object.fromEntries(STATUSES.map(s => [s, 0]));
  const bySource = {}, bySourceVisits = {};
  const source = utm => parseJson(utm)?.utm_source || 'directo';
  for (const l of leadRows) {
    if (l.tier in tiers) tiers[l.tier]++;
    byIntent[l.intent in byIntent ? l.intent : 'otro']++;
    if (l.status in statusCounts) statusCounts[l.status]++;
    const s = String(source(l.utm)).slice(0, 60);
    bySource[s] = (bySource[s] || 0) + 1;
  }
  for (const v of visitRows) { const s = String(source(v.utm)).slice(0, 60); bySourceVisits[s] = (bySourceVisits[s] || 0) + 1; }
  const ld = Object.fromEntries(leadDays.map(r => [r.d, r.n])), vd = Object.fromEntries(visitDays.map(r => [r.d, r.n]));
  const h = contact[0]?.h;
  return json({
    days, funnel, tiers, byIntent,
    bySource,                // leads por utm_source
    bySourceVisits,          // visitas (sesiones únicas) por utm_source
    byDay: list.map(day => ({ day, leads: ld[day] || 0, visits: vd[day] || 0 })),
    statusCounts,
    avgHoursToContact: typeof h === 'number' ? Math.round(h * 10) / 10 : null,
  });
}

/* ---------- Empujón al dueño (cron cada hora) ----------
 * Solo le escribe a Damián (OWNER_WHATSAPP), nunca a leads. Entre 7 am y 9 pm hora de Bogotá.
 *  - Lead A en 'nuevo' hace más de 2 h, o lead B hace más de 24 h → un aviso por lead (nudged_at).
 *  - Resumen diario: la primera corrida desde las 7 am (owner_digest evita repetirlo).
 */
const BOGOTA_MS = 5 * 3600e3;

async function ownerPush(env) {
  if (!env.KAPSO_API_KEY || !env.KAPSO_PHONE_NUMBER_ID || !env.OWNER_WHATSAPP) return;
  const bog = new Date(Date.now() - BOGOTA_MS);
  const hour = bog.getUTCHours();
  if (hour < 7 || hour >= 21) return;

  // 1. Resumen diario
  const today = bog.toISOString().slice(0, 10);
  const sent = await env.DB.prepare('SELECT 1 AS x FROM owner_digest WHERE day = ?').bind(today).first();
  if (!sent) {
    const yesterday = new Date(bog.getTime() - 864e5).toISOString().slice(0, 10);
    const text = await dailyDigest(env, yesterday);
    // Sin nada que contar no se manda mensaje, pero el día queda marcado
    if (!text || (await ownerMessage(env, text))) await env.DB.prepare('INSERT OR IGNORE INTO owner_digest (day) VALUES (?)').bind(today).run();
  }

  // 2. Leads sin contactar (máx. 1 aviso por lead; solo los de la última semana)
  const { results } = await env.DB.prepare(`SELECT * FROM leads
    WHERE status = 'nuevo' AND nudged_at IS NULL AND created_at > datetime('now', '-7 days')
      AND ((tier = 'A' AND created_at <= datetime('now', '-2 hours')) OR (tier = 'B' AND created_at <= datetime('now', '-24 hours')))
    ORDER BY created_at LIMIT 10`).all();
  for (const lead of results) {
    const hours = Math.max(1, Math.floor((Date.now() - Date.parse(lead.created_at.replace(' ', 'T') + 'Z')) / 3600e3));
    const brief = parseJson(lead.brief) || fallbackBrief(lead);
    const icon = lead.tier === 'A' ? '🔥' : '⭐';
    const ok = await ownerMessage(env, composeLeadMessage(lead, brief, `${icon} Lead ${lead.tier} sin contactar hace ${hours} h`));
    if (ok) await env.DB.prepare("UPDATE leads SET nudged_at = datetime('now') WHERE id = ?").bind(lead.id).run();
  }
}

async function dailyDigest(env, yesterday) {
  const since = `${yesterday} 05:00:00`;
  const until = `${new Date(Date.parse(yesterday + 'T00:00:00Z') + 864e5).toISOString().slice(0, 10)} 05:00:00`;
  const fresh = (await env.DB.prepare('SELECT tier, COUNT(*) AS n FROM leads WHERE created_at >= ? AND created_at < ? GROUP BY tier').bind(since, until).all()).results;
  const pending = (await env.DB.prepare("SELECT name, tier, created_at FROM leads WHERE status = 'nuevo' AND tier IN ('A', 'B') ORDER BY tier, created_at LIMIT 5").all()).results;
  const total = fresh.reduce((s, r) => s + r.n, 0);
  if (!total && !pending.length) return null;
  const tiers = fresh.map(r => `${r.n} ${r.tier}`).join(', ');
  const lines = [`☀️ Buen día, Damián. Ayer llegaron ${total} leads${tiers ? ` (${tiers})` : ''}.`];
  if (pending.length) {
    lines.push(`Pendientes por contactar: ${pending.map(p => `${waSafe(p.name, 40)} (${p.tier})`).join(', ')}.`);
  }
  return lines.join('\n');
}

/* ---------- WhatsApp vía Kapso ---------- */
const TIER_ICON = { A: '🔥', B: '⭐', C: '🌱' };

// Aviso de lead nuevo: prioridad, quién es, resumen y la apertura lista para copiar + link directo a WhatsApp.
async function notifyOwner(env, lead, brief) {
  if (!env.KAPSO_API_KEY || !env.KAPSO_PHONE_NUMBER_ID || !env.OWNER_WHATSAPP) return;
  const ok = await ownerMessage(env, composeLeadMessage(lead, brief, `${TIER_ICON[lead.tier]} Lead ${lead.tier} (${lead.points}/27)`));
  if (ok) await env.DB.prepare("UPDATE leads SET notified_at = datetime('now') WHERE id = ?").bind(lead.id).run();
}

// Mensaje corto para Damián. Todo lo que viene del lead o de la IA pasa por waSafe (sin formato ni links ajenos).
// Cabe en un parámetro de plantilla (límite de WhatsApp ≈ 1024): si no cabe, primero se omite la apertura en texto
// (el link la lleva igual), después se acorta el resumen, y al final el link va sin texto. El link nunca se corta.
function composeLeadMessage(lead, brief, header) {
  const LIMIT = 900;
  const phone = String(lead.phone).replace(/\D/g, '');
  const apertura = waSafe(brief.apertura, 350);
  const link = (text) => `https://wa.me/${phone}${text ? `?text=${encodeURIComponent(text)}` : ''}`;
  const build = ({ resumen, withOpening, textInLink }) => [
    `${header}: ${waSafe(lead.name, 60)} +${phone}`,
    `${INTENT_NAMES[lead.intent] || 'Sin clasificar'} · ${LABELS.budget[lead.budget]} · ${LABELS.timing[lead.timing]} · ${LABELS.decider[lead.decider]}`,
    resumen && `Resumen: ${resumen}`,
    brief.alertas?.length ? `Ojo: ${brief.alertas.slice(0, 3).map(a => waSafe(a, 80)).join('; ')}` : '',
    withOpening && `Apertura sugerida: ${apertura}`,
    `Escríbele: ${link(textInLink ? apertura : '')}`,
  ].filter(Boolean).join('\n');
  const resumen = waSafe(brief.resumen, 300);
  const tries = [
    { resumen, withOpening: true, textInLink: true },
    { resumen, withOpening: false, textInLink: true },
    { resumen: resumen.slice(0, 120), withOpening: false, textInLink: true },
    { resumen: resumen.slice(0, 120), withOpening: false, textInLink: false },
  ];
  for (const t of tries) { const m = build(t); if (m.length <= LIMIT) return m; }
  return build(tries[3]).slice(0, LIMIT);
}

// Texto libre solo funciona dentro de las 24 h desde que Damián le escribió al número; fuera de eso, plantilla aprobada.
async function ownerMessage(env, text) {
  if (!env.KAPSO_API_KEY || !env.KAPSO_PHONE_NUMBER_ID || !env.OWNER_WHATSAPP) return false;
  return sendWhatsApp(env, env.KAPSO_NOTIFY_TEMPLATE
    ? template(env.OWNER_WHATSAPP, env.KAPSO_NOTIFY_TEMPLATE, env.KAPSO_TEMPLATE_LANG, [text])
    : { messaging_product: 'whatsapp', to: env.OWNER_WHATSAPP, type: 'text', text: { body: text, preview_url: false } });
}

// Mensaje a un cliente real: apagado por defecto (AUTO_CONTACT_LEADS = "false").
async function contactLead(env, lead) {
  if (!env.KAPSO_API_KEY || !env.KAPSO_PHONE_NUMBER_ID || !env.KAPSO_LEAD_TEMPLATE) return;
  const first = waSafe(lead.name, 40).split(' ')[0];
  await sendWhatsApp(env, template(lead.phone, env.KAPSO_LEAD_TEMPLATE, env.KAPSO_TEMPLATE_LANG, [first, INTENT_NAMES[lead.intent] || 'tu negocio']));
}

function template(to, name, lang, params) {
  return {
    messaging_product: 'whatsapp', to, type: 'template',
    template: {
      name, language: { code: lang || 'es' },
      components: [{ type: 'body', parameters: params.map(t => ({ type: 'text', text: String(t).replace(/\s*\n\s*/g, ' · ').slice(0, 1024) })) }],
    },
  };
}

async function sendWhatsApp(env, payload) {
  const res = await fetch(`https://api.kapso.ai/meta/whatsapp/v24.0/${env.KAPSO_PHONE_NUMBER_ID}/messages`, {
    method: 'POST',
    headers: { 'X-API-Key': env.KAPSO_API_KEY, 'content-type': 'application/json' },
    body: JSON.stringify(payload),
  });
  if (!res.ok) console.error('Kapso', res.status); // sin el cuerpo de la respuesta ni del envío: traen teléfonos y texto del lead
  return res.ok;
}

/* ---------- utilidades ---------- */
function json(data, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' } });
}
function clean(v, max) {
  return typeof v === 'string' ? v.replace(/[\u0000-\u0008\u000b-\u001f]/g, '').trim().slice(0, max) : '';
}
// Texto de terceros que va a un WhatsApp: una línea, sin formato de WhatsApp (* _ ~ `), sin links ni saltos.
function waSafe(v, max) {
  return String(v ?? '')
    .replace(/[\u0000-\u001f\u007f\u200b-\u200f\u2028\u2029\ufeff]/g, ' ')
    .replace(/[*_~`]/g, '')
    .replace(/(https?:\/\/|www\.)/gi, '')
    .replace(/\s+/g, ' ').trim().slice(0, max);
}
// utm: solo claves conocidas y valores cortos, así el JSON guardado nunca queda cortado ni inflado
function cleanUtm(v) {
  let o = v;
  if (typeof o === 'string') { try { o = JSON.parse(o); } catch { o = o ? { utm_source: o } : {}; } }
  const out = {};
  if (o && typeof o === 'object' && !Array.isArray(o)) {
    for (const k of ['utm_source', 'utm_medium', 'utm_campaign', 'utm_term', 'utm_content', 'ref']) {
      const val = clean(typeof o[k] === 'number' ? String(o[k]) : o[k], 100);
      if (val) out[k] = val;
    }
  }
  return JSON.stringify(out);
}
function parseJson(s) {
  if (!s || typeof s !== 'string') return null;
  try { const v = JSON.parse(s); return v && typeof v === 'object' ? v : null; } catch { return null; }
}
// Lee el cuerpo con tope de tamaño (no confía en content-length) y lo parsea como JSON
async function readText(request, max) {
  const len = Number(request.headers.get('content-length'));
  if (Number.isFinite(len) && len > max) return null;
  if (!request.body) return '';
  const reader = request.body.getReader(), dec = new TextDecoder();
  let text = '', size = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.length;
    if (size > max) { reader.cancel().catch(() => {}); return null; }
    text += dec.decode(value, { stream: true });
  }
  return text + dec.decode();
}
async function readJson(request, max) {
  const text = await readText(request, max);
  if (!text) return null;
  try { return JSON.parse(text); } catch { return null; }
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
async function sha256(s) {
  return new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s)));
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
