/**
 * Todo objetivo que Timba o la campaña escriben en ventas_chats.objetivo debe estar en la restricción (0184).
 * Pasó el 14 oct: 0180 agregó «mensualidad_7pm» y la restricción no, y la campaña de las 9 am falló.
 *
 *   node objetivo-7pm.test.mjs
 */
import { readFileSync, readdirSync } from 'node:fs';

let fallos = 0;
const ok = (n, c, extra = '') => { if (!c) fallos++; console.log(`${c ? '✓' : '✗'} ${n}${extra ? '  → ' + extra : ''}`); };

const dir = new URL('../supabase/migrations/', import.meta.url);
const m84 = readFileSync(new URL('0184_objetivo_mensualidad_7pm_en_ventas_chats.sql', dir), 'utf8').replace(/--.*$/gm, '');
const permitidos = [...(m84.match(/array\[([^\]]+)\]/)?.[1] ?? '').matchAll(/'([a-z0-9_]+)'/g)].map(x => x[1]);

ok('la restricción admite los cinco objetivos, incluido mensualidad_7pm',
   ['mensualidad_6pm', 'mensualidad_7pm', 'mensualidad_7am', 'tiquetera', 'reactivar'].every(o => permitidos.includes(o)));
ok('solo agrega un valor y falla en vez de dejar algo a medias',
   /raise exception '0184:/.test(m84) && /ya estaba/.test(m84));

const usados = new Set();
for (const f of readdirSync(dir).filter(f => /^018[0-3]_/.test(f))) {
  const t = readFileSync(new URL(f, dir), 'utf8').replace(/--.*$/gm, '');
  for (const x of t.matchAll(/'(mensualidad_(?:6pm|7pm|7am))'/g)) usados.add(x[1]);
}
ok('todo objetivo de mensualidad que usan 0180–0183 está permitido',
   [...usados].every(o => permitidos.includes(o)), [...usados].join(', '));

console.log(`\n${fallos ? '✗ ' + fallos + ' con problemas' : '✓ todo bien'}`);
process.exit(fallos ? 1 : 0);
