/**
 * Campaña «rescatar el mes» (29 oct, 0189): lo que queda escrito en el archivo.
 *
 * Damián: un mensaje lindo que empuje a la conversión, sin descuentos ni regalos (la dueña no los autoriza). La función
 * NO envía sola: con p_ejecutar = false solo cuenta, y no hay cron. Enviarla es decisión de Damián.
 *
 *   node campana-rescate-mes.test.mjs
 */
import { readFileSync } from 'node:fs';

let fallos = 0;
const ok = (n, c, extra = '') => { if (!c) fallos++; console.log(`${c ? '✓' : '✗'} ${n}${extra ? '  → ' + extra : ''}`); };
const titulo = t => console.log(`\n-- ${t} ${'-'.repeat(Math.max(0, 54 - t.length))}`);

const sql = readFileSync(new URL('../supabase/migrations/0189_campana_rescate_del_mes.sql', import.meta.url), 'utf8');
const m = sql.replace(/^\s*--.*$/gm, '');
const w = readFileSync(new URL('../../tumbao-caja/src/index.js', import.meta.url), 'utf8');
const plantilla = n => { const i = w.indexOf(`name: '${n}'`); return w.slice(i, w.indexOf('\n  },\n', i)); };

titulo('1. Las dos plantillas');
for (const n of ['rescate_mes_frecuentes', 'rescate_mes_general']) {
  const t = plantilla(n);
  ok(`${n}: marketing, con su botón a la página y la baja «No quiero más mensajes»`,
     /category: 'MARKETING'/.test(t) && /tumbaobaila\.com\/mensualidad/.test(t) && /No quiero más mensajes/.test(t));
  ok(`${n}: sin descuentos, regalos, promociones ni «últimos cupos»`, !/descuento|regalo|gratis|promo|sorteo|2x1|últimos cupos|últimas/i.test(t));
  ok(`${n}: solo precios y datos que ya existen (mensualidad $125.000, tiqueteras de 4 y 8 clases)`, /\$125\.000/.test(t) && /4/.test(t) && /8/.test(t));
}
ok('la de frecuentes lleva dos variables (nombre y veces) y la general una', /\{\{2\}\}/.test(plantilla('rescate_mes_frecuentes')) && !/\{\{2\}\}/.test(plantilla('rescate_mes_general')));

titulo('2. La función solo cuenta si no se le dice que ejecute');
ok('p_ejecutar es false por defecto', /campana_rescate_mes\(p_ejecutar boolean default false\)/.test(m));
ok('las inserciones en la cola van detrás de if p_ejecutar', /if p_ejecutar then[\s\S]*insert into wa_avisos/.test(m) && (m.match(/insert into wa_avisos/g) || []).length === 1);
ok('no hay ningún cron: no sale sola', !/cron\.schedule/.test(m));
ok('nadie puede llamarla desde fuera (revoke a public, anon y authenticated)', /revoke all on function public\.campana_rescate_mes\(boolean\) from public, anon, authenticated/.test(m));
ok('se encola como «campana»: el despachador la retiene fuera del horario de mercadeo (Ley 2300)', /'campana'/.test(m));
ok('una sola vez por persona (clave única) y vence en 4 días', /'rescate-mes:' \|\| t/.test(m) && /on conflict \(clave\) do nothing/.test(m) && /interval '4 days'/.test(m));

titulo('3. A quién: los mismos filtros de siempre');
ok('sin SALIR, sin dueñas y con celular válido', /wa_bajas/.test(m) && /not wa_es_dueno/.test(m) && /\^3\[0-9\]\{9\}\$/.test(m));
ok('sin plan vigente (con su gracia) ni tiquetera vigente', /m\.fin \+ v_gracia/.test(m) && /q\.vence_el >= current_date/.test(m));
ok('ninguna campaña en 3 días y máximo 2 en 14', /interval '3 days'/.test(m) && /interval '14 days'[\s\S]*< 2/.test(m));
ok('sin «no me interesa» de ventas en 45 días ni conversación abierta', /c\.estado = 'abierta' or c\.cerrada_at > now\(\) - interval '45 days'/.test(m));
ok('sin solicitud de mensualidad por pagar o pagada', /s\.estado in \('esperando_pago', 'pagada'\)/.test(m));

console.log(`\n${fallos ? '✗ ' + fallos + ' con problemas' : '✓ todo bien'}`);
process.exit(fallos ? 1 : 0);
