/**
 * El tema de la conversación — prueba
 *
 * POR QUÉ EXISTE
 * La franja de la página promete una conversación, y el bot tiene que
 * hacer ESA. Si alguien pulsa «cuéntanos qué mejoramos» y recibe «¿qué
 * te hizo volver la segunda vez?», cierra la pestaña. Y no es una
 * suposición: de 53 personas que abrieron la burbuja, 38 no llegaron a
 * escribir nada.
 *
 * Por eso la campaña es un dato —un `tema`— y no tres ediciones a mano
 * del guion cada vez que Damián cambia de idea. Ya cambió dos veces en
 * un día: del aniversario a la escucha.
 *
 * Lo que se prueba aquí es que el tema de verdad cambia lo que pregunta
 * el bot, que se queda guardado con la conversación, que los temas
 * viejos siguen disponibles y que uno inventado no rompe nada.
 *
 *   node pruebas/tema.test.mjs
 */
import worker from '../src/index.js';
import { entorno, chat } from './entorno-falso.mjs';

let fallos = 0;
const ok = (n, c, extra = '') => {
  console.log(`  ${c ? '\x1b[32mv\x1b[0m' : '\x1b[31mx\x1b[0m'} ${n}${extra ? '  → ' + extra : ''}`);
  if (!c) fallos++;
};
const titulo = (t) => console.log(`\n-- ${t} ${'-'.repeat(Math.max(0, 52 - t.length))}`);

const CONV_A = 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa';
const CONV_B = 'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb';
const CONV_C = 'cccccccc-3333-4333-8333-cccccccccccc';

// Sin modelo: el saludo no se le pide a ninguno, es fijo. Y el resto de
// los turnos caen en el guion de ensayo, que también depende del tema.
const { env, base } = entorno({ conModelo: false });

titulo('1. Sin tema, el bot escucha (la campaña del 15 de septiembre)');

/* Damián: «una campaña para que la gente nos cuente qué le gusta, qué
   podemos mejorar y qué les gustaría encontrar… y esa debe ser la
   conversación con el bot». Por defecto, no solo por la franja: quien
   pulsa la burbuja flotante tiene que encontrar lo mismo. */
const siempre = chat(worker, env, CONV_A);
const s1 = await siempre.abrir();
ok('saluda presentándose',
   /Somos Tumbao/.test(s1.respuesta), s1.respuesta.slice(0, 60));
ok('dice para qué pregunta',
   /mejor espacio/.test(s1.respuesta), s1.respuesta.slice(0, 110));
ok('y arranca por lo que más le gusta',
   /¿Qué es lo que más te gusta de Tumbao\?/.test(s1.respuesta), s1.respuesta.slice(-60));
ok('sin hablar del aniversario', !/aniversario/i.test(s1.respuesta));

const s2 = await siempre.escribir('La energía de las clases');
ok('la segunda pregunta es qué mejorar',
   /podemos mejorar/i.test(s2.respuesta), s2.respuesta.slice(0, 90));
const s3 = await siempre.escribir('El sonido a veces se escucha bajo');
ok('y la tercera, qué les gustaría encontrar',
   /te gustaría encontrar/i.test(s3.respuesta), s3.respuesta.slice(0, 110));

titulo('2. Con tema aniversario, pregunta por la fiesta');

const fiesta = chat(worker, env, CONV_B, 'aniversario');
const f1 = await fiesta.abrir();
ok('dice para qué es', /aniversario/i.test(f1.respuesta), f1.respuesta.slice(0, 80));
ok('y que se arma entre todos',
   /con ustedes|de todos/i.test(f1.respuesta), f1.respuesta.slice(0, 120));
ok('arranca con la pregunta abierta',
   /¿Cómo sería un aniversario genial para ti\?/.test(f1.respuesta),
   f1.respuesta.slice(-70));
ok('y NO con la de por qué volviste',
   !/volver la segunda vez/.test(f1.respuesta),
   'es justo lo que hace cerrar la pestaña a quien viene a proponer');

const f2 = await fiesta.escribir('Una rumba con show de los profes');
ok('la segunda pregunta también es de la fiesta',
   /no puede faltar/i.test(f2.respuesta), f2.respuesta.slice(0, 90));

titulo('3. El tema se guarda con la conversación');

const fila = (id) => base.crudo
  .prepare('select tema from conversaciones where id = ?').get(id);
ok('la del aniversario queda marcada',
   fila(CONV_B).tema === 'aniversario', JSON.stringify(fila(CONV_B)));
ok('y la de la burbuja queda como escuchamos',
   fila(CONV_A).tema === 'escuchamos', JSON.stringify(fila(CONV_A)));

// Sin esto, el reporte del lunes mezcla dos preguntas distintas en la
// misma bolsa y ninguna de las dos se puede leer.
ok('así se pueden contar por separado',
   base.crudo.prepare(
     "select count(*) as n from conversaciones where tema = 'aniversario'"
   ).get().n === 1);

titulo('4. Un tema inventado no rompe nada');

const raro = chat(worker, env, CONV_C, 'lo-que-sea');
const r1 = await raro.abrir();
ok('cae en el de por defecto, no en un guion vacío',
   /¿Qué es lo que más te gusta de Tumbao\?/.test(r1.respuesta), r1.respuesta.slice(-60));
ok('y se guarda como escuchamos, no como «lo-que-sea»',
   fila(CONV_C).tema === 'escuchamos', JSON.stringify(fila(CONV_C)));

/* Las tres preguntas de retención no se borraron: siguen ahí y volver a
   ellas es una línea. Perderlas habría sido tirar el trabajo del 21 de
   agosto por un cambio de campaña. */
const D = 'dddddddd-4444-4444-8444-dddddddddddd';
const retencion = chat(worker, env, D, 'opinion');
const d1 = await retencion.abrir();
ok('el tema de retención sigue disponible',
   /¿Qué te hizo volver la segunda vez\?/.test(d1.respuesta), d1.respuesta.slice(-60));

titulo('5. La academia está donde está');

// Estuvo mal desde el primer día: el guion decía Bucaramanga, que está a
// 120 km. El bot se lo podía repetir a una clienta de Barrancabermeja.
const guion = (await import('node:fs')).readFileSync(
  new URL('../src/index.js', import.meta.url), 'utf8');
ok('el guion dice Barrancabermeja', guion.includes('Barrancabermeja'));
ok('y ya no dice Bucaramanga', !guion.includes('Bucaramanga'));

console.log(fallos ? `\n\x1b[31m${fallos} fallo(s)\x1b[0m`
                   : '\n\x1b[32mtodo en verde\x1b[0m');
process.exit(fallos ? 1 : 0);
