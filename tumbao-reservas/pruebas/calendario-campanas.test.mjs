/** Calendario de campañas autónomo (2 nov): plantilla de sábados, públicos, fechas especiales y tope de gasto.   node calendario-campanas.test.mjs */
import { readFileSync } from 'node:fs';
const leer = (r) => readFileSync(new URL(r, import.meta.url), 'utf8');
const caja = leer('../../tumbao-caja/src/index.js');
const mig = leer('../supabase/migrations/0199_calendario_de_campanas_autonomo.sql');
let fallos = 0;
const ok = (n, c) => { if (!c) fallos++; console.log(`${c ? '✓' : '✗'} ${n}`); };
const titulo = t => console.log(`\n-- ${t} ${'-'.repeat(Math.max(0, 54 - t.length))}`);

titulo('1. Plantilla de los sábados');
const a = caja.indexOf("name: 'tiquetera_sabados'"), t = caja.slice(a, caja.indexOf('\n  },\n', a));
ok('existe y ofrece la tiquetera de 4 con su precio de siempre', a > 0 && /\$52\.000/.test(t) && /\$15\.000/.test(t));
ok('habla de «premiamos tu constancia» con 1 clase más', /premiamos tu constancia con 1 clase más/.test(t));
ok('sin descuento, regalo, obsequio, promoción ni «gratis»', !/descuento|regalo|obsequio|promoci|gratis|gana un premio|recompensa/i.test(t));
ok('lenguaje neutro (sin «alumna»)', !/alumn/i.test(t));
ok('deja salir con «No quiero más mensajes»', /No quiero más mensajes/.test(t));

titulo('2. Calendario');
const cal = JSON.parse(mig.match(/\$j\$(\[[\s\S]*?\])\$j\$/)[1]);
const festivos = ['2026-11-16', '2026-12-08', '2026-12-25', '2027-01-01'];
ok('ninguna fecha cae en domingo ni festivo', cal.every((e) => new Date(e.fecha + 'T12:00:00Z').getUTCDay() !== 0 && !festivos.includes(e.fecha)));
ok('toda entrada tiene plantilla, respaldo y público conocido', cal.every((e) => e.plantilla && e.respaldo && ['solo_sabados', 'frecuentes_sin_plan', 'con_plan', 'inactivos'].includes(e.publico)));
ok('solo usa plantillas que existen en el Worker', cal.every((e) => caja.includes(`name: '${e.plantilla}'`) && caja.includes(`name: '${e.respaldo}'`)));
ok('incluye a quienes solo vienen los sábados', cal.filter((e) => e.publico === 'solo_sabados').length >= 2);
ok('las claves no se repiten', new Set(cal.map((e) => e.clave)).size === cal.length);

titulo('3. Guardas');
ok('respeta bajas, dueños, campañas recientes y no repite plantilla en 30 días', /wa_bajas/.test(mig) && /wa_es_dueno/.test(mig) && /interval '3 days'/.test(mig) && /< 2/.test(mig) && /a\.plantilla = p_plantilla and a\.creado_at > now\(\) - interval '30 days'/.test(mig));
ok('no hace nada en domingo ni festivo', /isodow from v_hoy\) = 7 or exists \(select 1 from festivos/.test(mig));
ok('tiene tope de gasto y se puede apagar', /campanas_presupuesto_cop/.test(mig) && /campanas_autonomas/.test(mig) && /v_cupo/.test(mig));
ok('solo envía con plantilla aprobada por Meta', /v_pl = any\(v_aprob\)/.test(mig) && /wa_plantillas_anotar/.test(caja));
ok('no excluye a quien ya tiene plan solo en «con_plan»', /not in \(select plan\.t from plan\)/.test(mig));

console.log(fallos ? `\n✗ ${fallos} con problemas` : '\n✓ todo bien');
process.exit(fallos ? 1 : 0);
