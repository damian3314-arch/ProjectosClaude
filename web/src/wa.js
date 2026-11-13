/**
 * WhatsApp Cloud API de Meta, directo (sin intermediarios).
 *
 *   Envío:    POST https://graph.facebook.com/v24.0/{WA_PHONE_NUMBER_ID}/messages   (Authorization: Bearer WA_TOKEN)
 *   Entrada:  Meta llama a POST /api/whatsapp con la firma X-Hub-Signature-256 (HMAC-SHA256 del cuerpo con el secreto de la app, WA_APP_SECRET).
 *   Alta:     Meta verifica el webhook con GET /api/whatsapp?hub.mode=subscribe&hub.verify_token=…&hub.challenge=… (WA_VERIFY_TOKEN).
 *
 * Variables: WA_TOKEN (secreto: token permanente de un usuario del sistema), WA_APP_SECRET (secreto), WA_VERIFY_TOKEN (secreto),
 * WA_PHONE_NUMBER_ID (id del número en Meta, no el teléfono).
 */

const GRAPH = 'https://graph.facebook.com/v24.0';

export const waOn = env => !!(env.WA_TOKEN && env.WA_PHONE_NUMBER_ID);

// Envía un mensaje (texto, plantilla, botones, "escribiendo…"). Devuelve { ok, status, code, wamid }. Nunca lanza: un fallo de red no debe tumbar el cron.
export async function waSend(env, payload) {
  try {
    const res = await fetch(`${GRAPH}/${encodeURIComponent(env.WA_PHONE_NUMBER_ID)}/messages`, {
      method: 'POST',
      headers: { authorization: `Bearer ${env.WA_TOKEN}`, 'content-type': 'application/json' },
      body: JSON.stringify(payload),
      signal: AbortSignal.timeout(10000),
    });
    const body = await res.json().catch(() => ({}));
    if (!res.ok) {
      // Solo el código y el motivo, con los números enmascarados: la respuesta puede traer teléfonos
      console.error('WhatsApp', res.status, body?.error?.code, String(body?.error?.message || '').replace(/\d{5,}/g, '#').slice(0, 300));
    }
    return { ok: res.ok, status: res.status, code: Number(body?.error?.code) || 0, wamid: body?.messages?.[0]?.id };
  } catch (err) { console.error('WhatsApp', err?.name || 'error'); return { ok: false, status: 0, code: 0 }; }
}

// Meta verifica la dirección del webhook al configurarla
export function waVerify(request, env) {
  const q = new URL(request.url).searchParams;
  if (env.WA_VERIFY_TOKEN && q.get('hub.mode') === 'subscribe' && q.get('hub.verify_token') === String(env.WA_VERIFY_TOKEN).trim()) {
    return new Response(q.get('hub.challenge') || '', { status: 200, headers: { 'content-type': 'text/plain' } });
  }
  return new Response('No autorizado', { status: 403 });
}

// El cuerpo de Meta trae lotes (entry → changes → messages). Se aplana a un elemento por mensaje, con la forma que usa el agente.
export function waItems(body) {
  const out = [];
  for (const entry of Array.isArray(body?.entry) ? body.entry : []) {
    for (const ch of Array.isArray(entry?.changes) ? entry.changes : []) {
      if (ch?.field !== 'messages') continue;
      const v = ch.value || {};
      for (const m of Array.isArray(v.messages) ? v.messages : []) {
        const contact = (v.contacts || []).find(c => c.wa_id === m.from) || (v.contacts || [])[0];
        out.push({ message: m, conversation: { contact_name: contact?.profile?.name || '' }, phone_number_id: v.metadata?.phone_number_id || '' });
      }
    }
  }
  return out;
}

// Nota de voz que llega por WhatsApp: se descarga de Meta y se transcribe (máx. 4 MB). Devuelve '' si no se pudo.
export async function waTranscribe(env, mediaId) {
  if (!mediaId || !env.OPENAI_API_KEY) return '';
  try {
    const auth = { authorization: `Bearer ${env.WA_TOKEN}` };
    const meta = await (await fetch(`${GRAPH}/${encodeURIComponent(mediaId)}`, { headers: auth, signal: AbortSignal.timeout(8000) })).json();
    if (!meta?.url || Number(meta.file_size) > 4 * 1024 * 1024) return '';
    const audio = await fetch(meta.url, { headers: auth, signal: AbortSignal.timeout(15000) });
    if (!audio.ok) return '';
    const fd = new FormData();
    fd.append('file', new Blob([await audio.arrayBuffer()], { type: meta.mime_type || 'audio/ogg' }), 'nota.ogg');
    fd.append('model', env.OPENAI_TRANSCRIBE_MODEL || 'whisper-1');
    fd.append('language', 'es');
    const res = await fetch('https://api.openai.com/v1/audio/transcriptions', { method: 'POST', headers: { authorization: `Bearer ${env.OPENAI_API_KEY}` }, body: fd, signal: AbortSignal.timeout(30000) });
    return res.ok ? String((await res.json()).text || '').trim() : '';
  } catch (err) { console.error('audio', err?.name || 'error'); return ''; }
}
