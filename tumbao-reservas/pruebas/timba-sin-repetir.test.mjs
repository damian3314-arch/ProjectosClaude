/**
 * Timba, 22 oct: no se presenta otra vez ante un «gracias», no repite el mismo mensaje y atiende pedidos de varios cupos.
 *
 *   node timba-sin-repetir.test.mjs
 */
import { readFileSync } from 'node:fs';
import { INSTRUCCIONES_ASISTENTE, repiteMensaje } from '../../tumbao-caja/src/asistente.js';

let fallos = 0;
const ok = (n, c, extra = '') => { if (!c) fallos++; console.log(`${c ? '✓' : '✗'} ${n}${extra ? '  → ' + extra : ''}`); };
const titulo = t => console.log(`\n-- ${t} ${'-'.repeat(Math.max(0, 54 - t.length))}`);
const index = readFileSync(new URL('../../tumbao-caja/src/index.js', import.meta.url), 'utf8');

titulo('1. Presentación una sola vez');
ok('solo se presenta si no hay mensajes previos de Tumbao', /SOLO si en "conversacion" todavía no hay ningún mensaje de Tumbao/.test(INSTRUCCIONES_ASISTENTE));
ok('ante un «gracias» contesta corto sin presentarse', /«gracias», «ok», «listo», «perfecto»[\s\S]{0,40}NO te presentes otra vez/.test(INSTRUCCIONES_ASISTENTE));

titulo('2. Mensajes repetidos');
const a = 'Soy el asistente virtual de Tumbao 💃 ¡Con gusto te ayudo! Veo que ya tienes una reserva confirmada para el *viernes 23 de octubre a las 7:00 am*.';
ok('el mismo mensaje se detecta aunque cambien tildes o signos', repiteMensaje(a, a.toUpperCase().replace('Í', 'I')));
ok('uno que solo es el inicio del anterior también', repiteMensaje('Soy el asistente virtual de Tumbao 💃 ¡Con gusto te ayudo!', a));
ok('dos mensajes distintos no se confunden', !repiteMensaje('Claro, el viernes hay clase a las *7:00 am*, *6:00 pm* y *7:00 pm*.', a));
ok('lo cortísimo no cuenta como repetido', !repiteMensaje('Listo 💛', 'Listo 💛'));
ok('el Worker pasa a recepción en vez de repetir',
   /repiteMensaje\(g\.texto, ultimaSaliente\.texto\)[\s\S]{0,300}conRecepcion\(/.test(index));
ok('no frena una propuesta ni el horario', /!\['proponer_reserva', 'mostrar_horarios'\]\.includes\(accion\)/.test(index));

titulo('3. Varios cupos');
ok('las instrucciones piden ir de a una reserva por vez y preguntar a nombre de quién',
   /de a una reserva por vez/.test(INSTRUCCIONES_ASISTENTE) && /a nombre de quién va cada una/.test(INSTRUCCIONES_ASISTENTE));
ok('y no repetir «ya tienes una reserva» sin más', /NUNCA mandes dos veces el mismo mensaje/.test(INSTRUCCIONES_ASISTENTE));

console.log(`\n${fallos ? '✗ ' + fallos + ' con problemas' : '✓ todo bien'}`);
process.exit(fallos ? 1 : 0);
