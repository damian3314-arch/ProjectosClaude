/** Jueves 26 de noviembre: 2 × $24.000 solo en la Rumba de las 5:00 pm (25 nov, Damián). node promo-jueves-26.test.mjs */
import { readFileSync } from 'node:fs';
const leer = (r) => readFileSync(new URL(r, import.meta.url), 'utf8');
const mig = leer('../supabase/migrations/0219_promo_jueves_26_solo_clase_de_5pm.sql').replace(/--.*$/gm, '');
const idx = leer('../../docs/index.html');
let fallos = 0;
const ok = (n, c) => { if (!c) fallos++; console.log(`${c ? '✓' : '✗'} ${n}`); };
ok('el 26 de noviembre entra a las fechas de la promo y solo para la clase de las 17:00', /"2026-11-26"/.test(mig) && /"2026-11-26": \["17:00"\]/.test(mig));
ok('promo_total_cupos limita por hora solo en los días que traen solo_horas (los demás días siguen valiendo para todas)',
   /jsonb_typeof\(v->''solo_horas''\) = ''object''/.test(mig) && /to_char\(p_fecha_clase at time zone ''America\/Bogota'', ''HH24:MI''\)/.test(mig));
ok('la página lo sabe: el jueves 26 a las 17:00, con la etiqueta en esa clase y no en las demás',
   /'2026-11-26'\], hasta_visible: '2026-11-27T00:00:00-05:00'/.test(idx) && /solo_horas: \{ '2026-11-26': \['17:00'\] \}/.test(idx) && /function claseConPromo/.test(idx) && /claseConPromo\(fecha, c\)/.test(idx) && /claseConPromo\(diaActivo, elegida\)/.test(idx));
ok('Timba conoce la promo del jueves y que no aplica a otras clases', ['asistente.js', 'ventas.js', 'index.js'].every(f => /PROMO DEL JUEVES 26 DE NOVIEMBRE[\s\S]{0,400}5:00 p\. m\.[\s\S]{0,500}NO aplica a las otras clases/.test(leer('../../tumbao-caja/src/' + f))));
ok('no borra nada', !/\bdrop\s+(table|function|index|column|constraint)|\bdelete\s+from/i.test(mig));
console.log(`\n${fallos ? '✗ ' + fallos + ' con problemas' : '✓ todo bien'}`);
process.exit(fallos ? 1 : 0);
