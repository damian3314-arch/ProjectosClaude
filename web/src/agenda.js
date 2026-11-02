/**
 * Agenda de Damián para Alter (solo lectura de lo que ya sabemos).
 *
 * Los horarios libres salen de: lunes a viernes, 9 am a 5 pm (hora de Colombia, igual que su enlace de reuniones de HubSpot), menos festivos,
 * menos lo que ya está ocupado en `agenda_busy`. Esa tabla la llena la rutina horaria con las reuniones de HubSpot y el propio Alter cuando
 * un cliente elige una hora. Lo que solo esté en Outlook y no en HubSpot no se ve: por eso Damián confirma y agenda a mano cada cita.
 */
const BOGOTA_MS = 5 * 3600e3;
const DEFAULT_HOURS = [9, 10, 11, 14, 15, 16]; // citas de 1 hora; se salta el almuerzo. Se cambia con AGENDA_HOURS (ej. "10,15")
const hoursOf = env => { const h = String(env?.AGENDA_HOURS || '').split(',').map(x => Number(x.trim())).filter(x => x >= 7 && x <= 18); return h.length ? h : DEFAULT_HOURS; };
const BUFFER_MS = 15 * 60e3;
const NOTICE_MS = 3 * 3600e3;                 // mínimo 3 horas de anticipación
const HOLIDAYS = new Set(['2026-11-02', '2026-11-16', '2026-12-08', '2026-12-25', '2027-01-01', '2027-01-11']);
const DAYS = ['domingo', 'lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado'];
const MONTHS = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];
const sqlTime = ms => new Date(ms).toISOString().slice(0, 19).replace('T', ' ');

export function slotLabel(startMs) {
  const t = new Date(startMs - BOGOTA_MS);
  const h = t.getUTCHours(), m = t.getUTCMinutes();
  const h12 = h % 12 === 0 ? 12 : h % 12;
  return `${DAYS[t.getUTCDay()]} ${t.getUTCDate()} de ${MONTHS[t.getUTCMonth()]} a las ${h12}:${String(m).padStart(2, '0')} ${h < 12 ? 'a. m.' : 'p. m.'}`;
}

// Hasta `n` horarios libres (máximo 2 por día, en los próximos 10 días). Cada uno: { iso, label }
export async function freeSlots(env, now = Date.now(), n = 6) {
  const busy = ((await env.DB.prepare('SELECT start_utc, end_utc FROM agenda_busy WHERE end_utc > ?').bind(sqlTime(now - 3600e3)).all().catch(() => ({ results: [] }))).results || [])
    .map(b => [Date.parse(b.start_utc.replace(' ', 'T') + 'Z'), Date.parse(b.end_utc.replace(' ', 'T') + 'Z')]);
  const out = [];
  const bog = new Date(now - BOGOTA_MS);
  for (let d = 0; d < 11 && out.length < n; d++) {
    const day = new Date(Date.UTC(bog.getUTCFullYear(), bog.getUTCMonth(), bog.getUTCDate() + d));
    const dow = day.getUTCDay();
    const key = day.toISOString().slice(0, 10);
    if (dow === 0 || dow === 6 || HOLIDAYS.has(key)) continue;
    let perDay = 0;
    for (const h of hoursOf(env)) {
      if (perDay >= 2) break;
      const start = Date.UTC(day.getUTCFullYear(), day.getUTCMonth(), day.getUTCDate(), h) + BOGOTA_MS;
      const end = start + 3600e3;
      if (start < now + NOTICE_MS) continue;
      if (busy.some(([bs, be]) => start < be + BUFFER_MS && end > bs - BUFFER_MS)) continue;
      out.push({ iso: new Date(start).toISOString().slice(0, 19) + 'Z', label: slotLabel(start) });
      perDay++;
      if (out.length >= n) break;
    }
  }
  return out;
}

export const slotsPromptText = slots => slots.map(s => `${s.iso} = ${s.label}`).join('\n');

// El cliente eligió uno de los horarios ofrecidos: se reserva para que no se le ofrezca a otro
export async function reserveSlot(env, phone, slot) {
  const start = Date.parse(slot.iso);
  await env.DB.prepare("INSERT OR REPLACE INTO agenda_busy (id, start_utc, end_utc, label) VALUES (?, ?, ?, ?)")
    .bind(`alter:${phone}`, sqlTime(start), sqlTime(start + 3600e3), 'Alter: elegido por el cliente').run();
}
