/**
 * Timba, 21 oct: la persona de Redes puede pedirle datos públicos e ideas de contenido, sin rebajas, regalos ni datos de clientes.
 *
 *   node timba-modo-redes.test.mjs
 */
import { readFileSync } from 'node:fs';
import { esRedes, INSTRUCCIONES_REDES, PLAN_CONTENIDO, guardarRespuestaRedes, RESPUESTA_REDES_SEGURA } from '../../tumbao-caja/src/redes.js';

let fallos = 0;
const ok = (n, c, extra = '') => { if (!c) fallos++; console.log(`${c ? '✓' : '✗'} ${n}${extra ? '  → ' + extra : ''}`); };
const titulo = t => console.log(`\n-- ${t} ${'-'.repeat(Math.max(0, 54 - t.length))}`);
const index = readFileSync(new URL('../../tumbao-caja/src/index.js', import.meta.url), 'utf8');

titulo('1. Quién es Redes');
ok('reconoce el número autorizado en sus formas', esRedes('573215460550') && esRedes('3215460550') && esRedes('+57 321 546 0550'));
ok('no reconoce a un cliente', !esRedes('573001112233') && !esRedes('') && !esRedes(null));

titulo('2. Qué se le dice');
ok('las instrucciones prohíben rebajas, regalos y datos de clientes',
   /No ofrezcas ni propongas descuentos/.test(INSTRUCCIONES_REDES) && /No des datos de clientes/.test(INSTRUCCIONES_REDES));
ok('el plan de contenido no trae rebajas ni regalos', PLAN_CONTENIDO.length >= 6 && PLAN_CONTENIDO.every(p => guardarRespuestaRedes(p).ok));
ok('una idea normal pasa', guardarRespuestaRedes('Te propongo un reel: 30 minutos de baile para cambiar el ánimo.').ok);
ok('un descuento no pasa', !guardarRespuestaRedes('Publica un descuento del 20% esta semana').ok);
ok('un regalo o sorteo no pasa', !guardarRespuestaRedes('Haz un sorteo de una mensualidad').ok && !guardarRespuestaRedes('Regalo de una clase').ok);
ok('lo vacío o larguísimo no pasa', !guardarRespuestaRedes('').ok && !guardarRespuestaRedes('a'.repeat(1600)).ok);
ok('la respuesta de seguridad no ofrece nada', guardarRespuestaRedes(RESPUESTA_REDES_SEGURA).ok);

titulo('3. Conexión en el Worker');
ok('el Worker atiende a Redes antes de la lógica de reservas',
   index.indexOf('if (esRedes(tel))') > 0 && index.indexOf('if (esRedes(tel))') < index.indexOf('const boton = leerBoton'));

console.log(`\n${fallos ? '✗ ' + fallos + ' con problemas' : '✓ todo bien'}`);
process.exit(fallos ? 1 : 0);
