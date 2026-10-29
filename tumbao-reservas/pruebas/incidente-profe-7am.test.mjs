/**
 * El profe de las 7 am no llegó el 14 oct: Timba (ventas) y el asistente solo se disculpan SI la persona lo menciona.
 * Sin avisos masivos y sin inventar compensación.
 *
 *   node incidente-profe-7am.test.mjs
 */
import { INSTRUCCIONES_VENTAS } from '../../tumbao-caja/src/ventas.js';
import { INSTRUCCIONES_ASISTENTE } from '../../tumbao-caja/src/asistente.js';

let fallos = 0;
const ok = (n, c) => { if (!c) fallos++; console.log(`${c ? '✓' : '✗'} ${n}`); };

for (const [nombre, p] of [['Timba (ventas)', INSTRUCCIONES_VENTAS], ['asistente', INSTRUCCIONES_ASISTENTE]]) {
  const linea = (p.split('\n').find(l => l.includes('INCIDENTE DEL 14 DE OCTUBRE')) || '');
  ok(`${nombre}: conoce el incidente y responde solo si la persona lo menciona`, /SOLO si la persona lo menciona/.test(linea));
  ok(`${nombre}: pide disculpa, escucha y agradece`, /disculpa sincera/.test(linea) && /agradece su comprensión/.test(linea));
  ok(`${nombre}: avisará con anticipación y anunciará lo extra, sin prometer compensación`,
     /avisar siempre con anticipación/.test(linea) && /lo anunciaremos/.test(linea) && /NO inventes ni prometas compensación/.test(linea));
}

console.log(`\n${fallos ? '✗ ' + fallos + ' con problemas' : '✓ todo bien'}`);
process.exit(fallos ? 1 : 0);
