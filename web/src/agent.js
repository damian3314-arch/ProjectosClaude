/**
 * Agente que agenda. La IA conversa en lenguaje natural y usa tres herramientas:
 *   get_slots     → horarios libres (las reglas de horario viven AQUÍ, no en el modelo)
 *   book_meeting  → reserva en Google/Outlook a través de n8n
 *   notify_owner  → te avisa por WhatsApp cuando hace falta una persona
 *
 * n8n expone dos webhooks (ver README):
 *   POST {N8N_BASE_URL}/availability  { calendar, from, to }  → { busy: [{start, end}] }
 *   POST {N8N_BASE_URL}/book          { calendar, start, end, title, description, attendeeName, phone, leadId } → { eventId }
 */

const TZ = 'America/Bogota';
const TZ_OFFSET_MS = 5 * 3600e3; // Bogotá es UTC-5 todo el año
const SLOT_MIN = 30;
const BUFFER_MIN = 15;
const MIN_LEAD_H = 3;
const HORIZON_DAYS = 14;

// Ventanas de inicio de reunión, en horas de Bogotá, por día de la semana (0 = domingo).
//  - personal: consultoría (IA, procesos, datos) fuera del horario de Loggro.
//  - loggro:   ventas de Loggro, dentro del horario laboral (calendario Outlook).
const weekdays = w => ({ 1: w, 2: w, 3: w, 4: w, 5: w });
const WINDOWS = {
  personal: { ...weekdays([[18.5, 21]]), 6: [[8, 12]] },
  loggro: weekdays([[9, 18]]),
};

const fmt = new Intl.DateTimeFormat('es-CO', {
  weekday: 'long', day: 'numeric', month: 'long', hour: 'numeric', minute: '2-digit', hour12: true, timeZone: TZ,
});
export const label = ms => fmt.format(new Date(ms));

/** Horarios libres según las reglas. `busy` = [{s, e}] en ms. */
export function computeSlots(calendar, busy, now, { date, limit = 8 } = {}) {
  const windows = WINDOWS[calendar] || WINDOWS.personal;
  const bog = new Date(now - TZ_OFFSET_MS);
  const base = Date.UTC(bog.getUTCFullYear(), bog.getUTCMonth(), bog.getUTCDate());
  const days = [];
  if (date) {
    const d = Date.parse(date + 'T00:00:00Z');
    const i = Math.round((d - base) / 864e5);
    if (Number.isFinite(d) && i >= 0 && i < HORIZON_DAYS) days.push(d);
  } else {
    for (let i = 0; i < HORIZON_DAYS; i++) days.push(base + i * 864e5);
  }
  const buf = BUFFER_MIN * 60e3, len = SLOT_MIN * 60e3, earliest = now + MIN_LEAD_H * 3600e3;
  const slots = [];
  for (const day of days) {
    const midnight = day + TZ_OFFSET_MS; // medianoche de Bogotá en UTC
    const perDay = [];
    for (const [from, to] of windows[new Date(day).getUTCDay()] || []) {
      for (let h = from; h + SLOT_MIN / 60 <= to + 1e-9; h += SLOT_MIN / 60) {
        const s = midnight + Math.round(h * 3600e3), e = s + len;
        if (s < earliest) continue;
        if (busy.some(b => s < b.e + buf && e > b.s - buf)) continue;
        perDay.push({ startMs: s, endMs: e, label: label(s) });
      }
    }
    // Sin fecha: máximo 3 por día para ofrecer variedad. Con fecha: todos los de ese día.
    slots.push(...(date ? perDay : perDay.slice(0, 3)));
    if (slots.length >= limit && !date) break;
  }
  return slots.slice(0, date ? 12 : limit);
}

export async function fetchBusy(env, calendar, fromMs, toMs) {
  if (!env.N8N_BASE_URL) throw new Error('n8n no configurado');
  const res = await fetch(`${env.N8N_BASE_URL}/availability`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', 'x-api-key': env.N8N_SECRET || '' },
    body: JSON.stringify({ calendar, from: new Date(fromMs).toISOString(), to: new Date(toMs).toISOString() }),
    signal: AbortSignal.timeout(12000),
  });
  if (!res.ok) throw new Error(`n8n availability ${res.status}`);
  const { busy = [] } = await res.json();
  return busy.map(b => ({ s: Date.parse(b.start), e: Date.parse(b.end) })).filter(b => Number.isFinite(b.s) && Number.isFinite(b.e));
}

async function freeSlots(env, calendar, opts) {
  const now = Date.now();
  const busy = await fetchBusy(env, calendar, now, now + (HORIZON_DAYS + 1) * 864e5);
  return computeSlots(calendar, busy, now, opts);
}

function systemPrompt(lead, now) {
  const today = new Intl.DateTimeFormat('es-CO', { dateStyle: 'full', timeStyle: 'short', timeZone: TZ }).format(new Date(now));
  const windows = lead.calendar === 'loggro'
    ? 'lunes a viernes entre 9:00 am y 6:00 pm'
    : 'lunes a viernes desde las 6:30 pm y los sábados en la mañana';
  return `Eres el asistente de Damián Barragán (consultor en Colombia). Tu trabajo es agendar la reunión con ${lead.name}, no mandar links.
Hoy es ${today} (hora de Colombia).
Lo que ya sabes de la persona: nombre ${lead.name}; tema: ${lead.intentName || 'sin clasificar'}; problema: "${(lead.problem || '').slice(0, 400)}".
La reunión es una llamada de ${SLOT_MIN} minutos con Damián. Horarios que ofrece: ${windows}.

Cómo trabajas:
- Habla en español de Colombia, cálido, directo, mensajes cortos (máximo 3 frases). Sin listas largas.
- Antes de proponer horarios llama a get_slots. Nunca inventes horas. Ofrece 2 o 3 opciones, no todas.
- Si la persona dice "el jueves después de las 7" o "mañana en la tarde", llama a get_slots con esa fecha (YYYY-MM-DD) y elige del resultado.
- Cuando la persona acepte una hora concreta, llama a book_meeting con el campo start EXACTO que devolvió get_slots. Después confirma día y hora en palabras y di que le llegará un recordatorio por WhatsApp.
- Si pide una hora fuera de esos horarios, explica con amabilidad cuándo sí hay espacio. Si insiste o es una excepción que vale la pena, llama a notify_owner y dile que Damián le confirma personalmente.
- Si quiere cambiar o cancelar una cita ya agendada, pide más detalles y llama a notify_owner.
- Si pregunta por precios, alcance o algo que no sabes, no inventes: dile que lo ve con Damián en la llamada y, si es relevante, llama a notify_owner.
- ${lead.meeting_start ? `Ya tiene una cita agendada: ${label(Date.parse(lead.meeting_start))}. No agendes otra.` : 'Todavía no tiene cita.'}`;
}

const TOOLS = [
  {
    type: 'function',
    function: {
      name: 'get_slots',
      description: 'Devuelve horarios libres para la reunión. Sin fecha: los próximos disponibles. Con fecha: todos los de ese día.',
      parameters: {
        type: 'object', additionalProperties: false, required: [],
        properties: { date: { type: 'string', description: 'Fecha YYYY-MM-DD en hora de Colombia (opcional)' } },
      },
    },
  },
  {
    type: 'function',
    function: {
      name: 'book_meeting',
      description: 'Agenda la reunión en el calendario. Usa solo un start devuelto por get_slots, cuando la persona ya aceptó esa hora.',
      parameters: {
        type: 'object', additionalProperties: false, required: ['start'],
        properties: { start: { type: 'string', description: 'start ISO exacto de get_slots' } },
      },
    },
  },
  {
    type: 'function',
    function: {
      name: 'notify_owner',
      description: 'Avisa a Damián por WhatsApp cuando se necesita una persona: excepción de horario, cambio de cita, pregunta que no sabes responder, lead muy interesado.',
      parameters: {
        type: 'object', additionalProperties: false, required: ['reason'],
        properties: { reason: { type: 'string', description: 'Qué necesita la persona y qué le dijiste, en 1 o 2 frases' } },
      },
    },
  },
];

/**
 * Un turno de conversación. `deps` lo arma el Worker:
 *   saveBooking({startMs, endMs, eventId}), notify(text)
 * Devuelve { reply, booked }.
 */
export async function runAgent({ env, lead, history, message, deps }) {
  const now = Date.now();
  const messages = [{ role: 'system', content: systemPrompt(lead, now) }, ...history, { role: 'user', content: message }];
  let booked = null;

  for (let step = 0; step < 5; step++) {
    const res = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: { authorization: `Bearer ${env.OPENAI_API_KEY}`, 'content-type': 'application/json' },
      body: JSON.stringify({
        model: env.OPENAI_AGENT_MODEL || env.OPENAI_MODEL || 'gpt-4o-mini',
        temperature: 0.3, max_tokens: 400, messages, tools: TOOLS, tool_choice: 'auto',
      }),
    });
    if (!res.ok) { console.error('OpenAI agent', res.status, await res.text()); throw new Error('IA no disponible'); }
    const msg = (await res.json()).choices[0].message;
    if (!msg.tool_calls?.length) return { reply: (msg.content || '').trim(), booked };

    messages.push(msg);
    for (const call of msg.tool_calls) {
      let args = {};
      try { args = JSON.parse(call.function.arguments || '{}'); } catch {}
      let result;
      try { result = await runTool(call.function.name, args, { env, lead, deps, now, onBooked: b => { booked = b; } }); }
      catch (err) { console.error('tool', call.function.name, err); result = { error: 'No pude completar esa acción ahora. Dile a la persona que Damián la contacta, y llama a notify_owner.' }; }
      messages.push({ role: 'tool', tool_call_id: call.id, content: JSON.stringify(result) });
    }
  }
  return { reply: 'Déjame confirmarlo con Damián y te escribo por WhatsApp.', booked };
}

async function runTool(name, args, { env, lead, deps, now, onBooked }) {
  if (name === 'get_slots') {
    const date = /^\d{4}-\d{2}-\d{2}$/.test(args.date || '') ? args.date : undefined;
    const slots = await freeSlots(env, lead.calendar, { date });
    return slots.length
      ? { slots: slots.map(s => ({ start: new Date(s.startMs).toISOString(), cuando: s.label })) }
      : { slots: [], nota: date ? 'No hay espacios ese día.' : 'No hay espacios en los próximos 14 días.' };
  }

  if (name === 'book_meeting') {
    if (lead.meeting_start) return { error: 'Ya tiene una cita agendada.' };
    const startMs = Date.parse(args.start);
    if (!Number.isFinite(startMs)) return { error: 'start inválido' };
    // Se vuelve a calcular: el modelo solo puede reservar un horario que las reglas permiten y que sigue libre.
    const day = new Date(startMs - TZ_OFFSET_MS).toISOString().slice(0, 10);
    const slot = (await freeSlots(env, lead.calendar, { date: day })).find(s => s.startMs === startMs);
    if (!slot) return { error: 'Ese horario ya no está disponible. Llama a get_slots otra vez.' };

    const res = await fetch(`${env.N8N_BASE_URL}/book`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'x-api-key': env.N8N_SECRET || '' },
      body: JSON.stringify({
        calendar: lead.calendar, start: new Date(slot.startMs).toISOString(), end: new Date(slot.endMs).toISOString(),
        title: `Llamada con ${lead.name} · ${lead.intentName || 'consultoría'}`,
        description: `Lead ${lead.tier} · WhatsApp +${lead.phone}\nProblema: ${(lead.problem || '').slice(0, 800)}`,
        attendeeName: lead.name, phone: lead.phone, leadId: lead.id,
      }),
      signal: AbortSignal.timeout(15000),
    });
    if (!res.ok) throw new Error(`n8n book ${res.status}`);
    const { eventId } = await res.json().catch(() => ({}));
    await deps.saveBooking({ startMs: slot.startMs, endMs: slot.endMs, eventId: eventId || null });
    onBooked({ startMs: slot.startMs, label: slot.label });
    return { ok: true, cuando: slot.label };
  }

  if (name === 'notify_owner') {
    const reason = String(args.reason || '').slice(0, 500);
    await deps.notify(reason);
    return { ok: true };
  }
  return { error: 'herramienta desconocida' };
}
