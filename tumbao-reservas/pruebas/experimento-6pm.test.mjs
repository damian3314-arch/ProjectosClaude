/** Experimento 6 pm (26 nov–2 dic): aforo 40 solo esa hora y esas fechas. node experimento-6pm.test.mjs */
import { readFileSync } from 'node:fs';
const m = readFileSync(new URL('../supabase/migrations/0222_experimento_6pm_seis_cupos_mas.sql', import.meta.url), 'utf8').replace(/--.*$/gm, '');
let fallos = 0;
const ok = (n, c) => { if (!c) fallos++; console.log(`${c ? '✓' : '✗'} ${n}`); };
ok('ajuste con hora 18:00, del 26 nov al 2 dic y 6 de más', /"hora":"18:00","desde":"2026-11-26","hasta":"2026-12-02","extra":6/.test(m));
ok('techo_clase devuelve 34 fuera de la ventana', /return 34;/.test(m) && /between \(v->>'desde'\)::date and \(v->>'hasta'\)::date/.test(m));
ok('el trigger y recalcular_cupos usan techo_clase', /new\.aforo > public\.techo_clase/.test(m) && /least\(c\.aforo, public\.techo_clase\(c\.fecha_hora\)\)/.test(m));
ok('mensualidad 6 pm sube de 25 a 28', /18:00=25', '18:00=28'/.test(m));
console.log(fallos ? '\n✗ fallos' : '\n✓ todo bien'); process.exit(fallos ? 1 : 0);
