/**
 * La tiquetera de la página cuenta el día que se PAGÓ (0179, 13 oct).
 *
 * Damián: «el cierre no está incluyendo las tiqueteras; necesito que esos valores se incluyan y sumen a lo vendido del día,
 * porque se queda por fuera y me afecta el valor». Pasaba así: Yenifer y Tania dijeron «ya pagué» en la tarde del 13 y
 * recepción las validó en la noche, con la caja del 13 cerrada; el ingreso se fue al 14 y la venta del 13 salió corta
 * ($620.000 en vez de $812.000).
 *
 * La regla se probó en la base real con tiqueteras falsas dentro de una transacción que se deshizo (pagó hoy con el día
 * cerrado → hoy; pagó el 10 → el 10; pagó en septiembre → hoy o mañana como antes). Aquí se protege lo que queda escrito:
 *
 *   node tiquetera-cierre.test.mjs
 */
import { readFileSync } from 'node:fs';

let fallos = 0;
const ok = (n, c, extra = '') => { if (!c) fallos++; console.log(`${c ? '✓' : '✗'} ${n}${extra ? '  → ' + extra : ''}`); };
const titulo = t => console.log(`\n-- ${t} ${'-'.repeat(Math.max(0, 54 - t.length))}`);

const m = readFileSync(new URL('../supabase/migrations/0179_tiquetera_cuenta_el_dia_que_se_pago.sql', import.meta.url), 'utf8')
  .replace(/--.*$/gm, '');

titulo('1. El ingreso cuenta el día que el cliente pagó');
{
  ok('toma el día del pago: cuando dijo «ya pagué» (o cuando recepción la validó), y si no hay, cuando se creó',
     /v_pago date := \(coalesce\(new\.pagado_en, new\.creada_en, now\(\)\) at time zone 'America\/Bogota'\)::date/.test(m));
  ok('si ese día es del mes en curso, el ingreso va a ese día aunque ya esté cerrado',
     /if v_pago between date_trunc\('month', v_hoy\)::date and v_hoy then\s+v_dia := v_pago;/.test(m));
  ok('un pago de un mes anterior (cuyo informe ya salió) sigue entrando hoy, o mañana si hoy está cerrado',
     /else\s+v_dia := v_hoy;\s+if exists \(select 1 from caja_cierres where dia = v_dia\) then\s+v_dia := v_dia \+ 1;/.test(m));
  ok('ya no manda a mañana a quien pagó hoy (se quitó el «día cerrado → mañana» general)',
     (m.match(/v_dia := v_dia \+ 1/g) || []).length === 1);
}

titulo('2. No toca el efectivo ni duplica el ingreso');
{
  ok('el ingreso de la tiquetera de la página sigue entrando como TRANSFERENCIA (no mueve el efectivo del arqueo)',
     /'ingreso', 'tiquetera', new\.precio_cop, 'transferencia'/.test(m));
  ok('solo la comprada en la página (creada_por nulo), con precio, y una sola vez por tiquetera',
     /new\.creada_por is null/.test(m) && /coalesce\(new\.precio_cop, 0\) > 0/.test(m) &&
     /not exists \(select 1 from caja_movimientos m\s+where m\.tiquetera_id = new\.id and not m\.anulado\)/.test(m));
  ok('sigue anotando la referencia del comprobante y el depósito si lo hay (como en 0112)',
     /' · ref ' \|\| nullif\(btrim\(new\.referencia\), ''\)/.test(m) && /null, new\.pago_id, 1, 'caja_menor', new\.id/.test(m));
}

titulo('3. Corrige las dos de hoy y nada más');
{
  ok('mueve del 14 al 13 solo las tiqueteras 43 (Yenifer) y 44 (Tania), transferencias sin anular',
     /set dia = date '2026-10-13'/.test(m) && /m\.tiquetera_id in \(43, 44\)/.test(m) && /m\.dia = date '2026-10-14'/.test(m) &&
     /m\.medio = 'transferencia'/.test(m) && /not m\.anulado/.test(m));
  ok('se puede correr de nuevo sin efecto (si ya están en el 13, no hay nada que mover)', /m\.dia = date '2026-10-14'/.test(m));
  ok('no borra nada ni toca el cierre guardado (efectivo, contado, esperado)',
     !/\bdelete\b|\bdrop\b|\btruncate\b|caja_cierres\s+set|update\s+(public\.)?caja_cierres/i.test(m));
}

console.log(`\n${fallos ? '✗ ' + fallos + ' con problemas' : '✓ todo bien'}`);
process.exit(fallos ? 1 : 0);
