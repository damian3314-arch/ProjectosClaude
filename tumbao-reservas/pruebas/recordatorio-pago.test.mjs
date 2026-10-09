/**
 * Recordatorio de pago de la reserva (0165) y prioridad de la lista de espera.
 *
 * Damián (9 oct, «sí»): recordar a quien reservó y no pagó, y darle prioridad al primero de la lista de espera.
 *   node recordatorio-pago.test.mjs
 */
import { readFileSync } from 'node:fs';
let fallos = 0;
const ok = (n, c, extra = '') => { if (!c) fallos++; console.log(`${c ? '✓' : '✗'} ${n}${extra ? '  → ' + extra : ''}`); };
const m = readFileSync(new URL('../supabase/migrations/0165_recordatorio_de_pago_de_la_reserva.sql', import.meta.url), 'utf8').replace(/--.*$/gm, '');
const w = readFileSync(new URL('../../tumbao-caja/src/index.js', import.meta.url), 'utf8');
const i = w.indexOf("name: 'reserva_pendiente_pago'"); const t = w.slice(i, i + 1100);

ok('nace apagado y se apaga con el mismo ajuste', /'wa_recordar_pago', 'apagado'/.test(m) && /<> 'encendido' then\s+return 0/.test(m));
ok('solo reservas sueltas pendientes de pago creadas hace 7 a 12 minutos con el cupo todavía guardado y la clase por venir',
   /estado = 'pendiente_pago' and r\.tipo = 'suelta'/.test(m) && /between now\(\) - interval '12 minutes' and now\(\) - interval '7 minutes'/.test(m) && /expira_en > now\(\) \+ interval '1 minute'/.test(m) && /cl\.fecha_hora > now\(\)/.test(m));
ok('respeta bajas, dueños y quien ya tiene la clase confirmada', /wa_bajas/.test(m) && /wa_es_dueno/.test(m) && /h\.estado = 'confirmada'/.test(m));
ok('uno por persona y por día, y uno por reserva', /tipo = 'recordatorio_pago'/.test(m) && /'recordatorio_pago:' \|\| e\.id/.test(m) && /on conflict \(clave\) do nothing/.test(m));
ok('el aviso vence cuando vence el cupo y no es de mercadeo (tipo propio)', /coalesce\(e\.expira_en/.test(m) && !/'campana'/.test(m));
ok('cron cada 2 minutos de 6 am a 10 pm Bogotá', /'\*\/2 11-23,0-2 \* \* \*'/.test(m));
ok('plantilla de UTILIDAD, sobre su reserva, sin oferta ni descuento',
   i > 0 && /category: 'UTILITY'/.test(t) && !/descuento|gratis|promoci|oferta|regalo/i.test(t) && /Si ya pagaste, no hagas nada/.test(t));
ok('sin DROP ni DELETE', !/\bdrop\b/i.test(m) && !/\bdelete\b/i.test(m));
console.log(fallos ? `\n${fallos} fallo(s)` : '\nTodo bien');
process.exit(fallos ? 1 : 0);
