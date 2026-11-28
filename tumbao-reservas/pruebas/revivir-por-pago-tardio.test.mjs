/** Reservas liberadas que se reviven solas cuando el depósito llega después (26 nov, Damián). node revivir-por-pago-tardio.test.mjs */
import { readFileSync } from 'node:fs';
const leer = (r) => readFileSync(new URL(r, import.meta.url), 'utf8');
const sql = leer('../supabase/migrations/0220_revivir_reservas_por_pago_tardio.sql').replace(/--.*$/gm, '');
const idx = leer('../../docs/index.html');
let fallos = 0;
const ok = (n, c) => { if (!c) fallos++; console.log(`${c ? '✓' : '✗'} ${n}`); };
ok('solo revive reservas de clase suelta liberadas por falta de pago (vencidas, o rechazadas por pago/comprobante/banco/soporte), de los últimos 3 días',
   /r\.estado = 'expirada'/.test(sql) && /r\.motivo_rechazo ~\* 'pago\|comprobante\|banco\|soporte'/.test(sql) && /r\.created_at > now\(\) - interval '3 days'/.test(sql));
ok('busca un depósito sin reclamar con el valor exacto del grupo y un remitente parecido a alguien del grupo (>= 0.5)',
   /p\.valor_cop = v_total/.test(sql) && /not p\.consumido/.test(sql) && /unnest\(g\.quienes\)[\s\S]{0,80}>= 0\.5/.test(sql));
ok('si la clase aún no termina, solo revive si hay cupo para todo el grupo y toma el cupo; si ya terminó, no toca el cupo (la persona reprograma)',
   /g\.termina > now\(\) and coalesce\(v_libres, 0\) < g\.n then continue/.test(sql) && /if g\.termina > now\(\) then update clases set cupo_tomado = cupo_tomado \+ g\.n/.test(sql));
ok('confirma todo el grupo con el depósito, lo marca consumido y lo deja en la auditoría como «Sistema»',
   /estado = 'confirmada', pago_id = v_pago/.test(sql) && /update pagos set consumido = true/.test(sql) && /'Sistema', 'revivir_por_pago_tardio'/.test(sql));
ok('no pone expira_en en null (la columna no lo admite)', !/expira_en = null/.test(sql));
ok('corre cada 2 minutos y solo el servicio puede llamarla', /cron\.schedule\('tumbao-revivir-pago-tardio', '\*\/2 \* \* \* \*'/.test(sql) && /grant execute on function public\.revivir_reservas_por_pago_tardio\(\) to service_role/.test(sql));
ok('no borra nada', !/\bdrop\s+(table|function|index|column|constraint)|\bdelete\s+from/i.test(sql));
ok('la pantalla de «no pudimos confirmar tu pago» tranquiliza: si el pago llega después, la reserva se reactiva sola', (idx.match(/Si tu pago llega después, tu reserva se reactiva sola/g) || []).length >= 2);
console.log(`\n${fallos ? '✗ ' + fallos + ' con problemas' : '✓ todo bien'}`);
process.exit(fallos ? 1 : 0);
