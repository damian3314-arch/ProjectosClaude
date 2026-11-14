/**
 * El tope de 25 en 6 pm y 7 pm (0183, 14 oct).
 *
 * Damián: «ajustemos el tope a 25 mensualidades». Se aplicó en la base real (la página pasó a vender hasta 25 y los cupos
 * libres de 6 y 7 pm subieron en 2). Aquí se protege lo que queda escrito:
 *
 *   node tope-25.test.mjs
 */
import { readFileSync } from 'node:fs';
import { INSTRUCCIONES_PREMIUM } from '../../tumbao-caja/src/premium.js';

let fallos = 0;
const ok = (n, c, extra = '') => { if (!c) fallos++; console.log(`${c ? '✓' : '✗'} ${n}${extra ? '  → ' + extra : ''}`); };
const m = readFileSync(new URL('../supabase/migrations/0183_tope_de_25_en_6_y_7_pm.sql', import.meta.url), 'utf8').replace(/^\s*--.*$/gm, '');

ok('la página pasa a 25 en 6 pm y 7 pm y 7 am queda en 35',
   /set valor = '07:00=35,18:00=25,19:00=25'/.test(m) && /where clave = 'mensualidad_topes' and valor = '07:00=35,18:00=23,19:00=23'/.test(m));
ok('la fidelidad y el aviso a la lista de espera usan el mismo tope (premium_topes); 7 am sigue «abierto» (99)',
   /set valor = '07:00=99,18:00=25,19:00=25'/.test(m) && /where clave = 'premium_topes' and valor = '07:00=99,18:00=23,19:00=23'/.test(m));
ok('solo se cambia si el valor sigue siendo el de antes (no pisa un ajuste a mano) y no toca precios, gracia ni nada más',
   (m.match(/update public\.ajustes/g) || []).length === 2 && !/mensualidad_valor_cop|mensualidad_gracia_dias|premium_fidelidad/.test(m) && !/\bdelete\b|\bdrop\b/i.test(m));
ok('el asistente interno dice 25 y ya no dice 23',
   /máximo 25 personas cada uno/.test(INSTRUCCIONES_PREMIUM) && /tope 35, 25 y 25/.test(INSTRUCCIONES_PREMIUM) && !/máximo 23 personas/.test(INSTRUCCIONES_PREMIUM) && !/tope de 23 en/.test(INSTRUCCIONES_PREMIUM));

console.log(`\n${fallos ? '✗ ' + fallos + ' con problemas' : '✓ todo bien'}`);
process.exit(fallos ? 1 : 0);
