/**
 * El saludo, el atropello y el acuse de recibo — prueba
 *
 * LOS TRES CASOS REALES QUE LA MOTIVAN
 * 1. A un «Buena tarde» el bot le contestó con la pregunta 2, como si
 *    hubiera contestado la 1. La persona no volvió a escribir.
 * 2. A un «Hola, quiero contarles algo» le contestó con el guion en vez
 *    de escuchar.
 * 3. Quien escribió la respuesta más larga y más cálida recibió la
 *    siguiente pregunta sin una palabra de vuelta.
 *
 * Los tres son cosas que se le piden al modelo en el guion, y los tres
 * pasaron con el guion puesto. Lo que se prueba aquí es la parte que no
 * depende de que el modelo tenga un buen día.
 *
 *   node pruebas/saludo.test.mjs
 */
import worker, { esArranque, conAcuse } from '../src/index.js';
import { entorno, chat } from './entorno-falso.mjs';

let fallos = 0;
const ok = (n, c, extra = '') => {
  console.log(`  ${c ? '\x1b[32mv\x1b[0m' : '\x1b[31mx\x1b[0m'} ${n}${extra ? '  → ' + extra : ''}`);
  if (!c) fallos++;
};

console.log('\n-- 1. Qué es un saludo y qué es una respuesta ---------------');

for (const t of ['Hola', 'Buena tarde', 'Buenas tardes', 'buenas noches',
                 'Hola!!', 'Buenas, ¿cómo están? 👋', 'Hola buenas',
                 'Qué más', 'Quiubo', 'hola, gracias']) {
  ok(`«${t}» no es respuesta a nada`, esArranque(t) === true);
}

// El otro lado importa igual: si una respuesta corta se toma por saludo,
// el bot repite la pregunta 1 y queda de sordo.
for (const t of ['Trabajooo', 'El clima', 'Los extraño muchoooo de lunes a viernes 😭',
                 'todo bien', 'Que es lo mejor de lo mejor 😃',
                 'Viajar a la ciudad donde resido', 'el ambiente',
                 'Hola, volví por el ambiente', 'buenas clases']) {
  ok(`«${t}» SÍ es una respuesta`, esArranque(t) === false);
}

console.log('\n-- 2. El que viene a contar algo suyo -----------------------');
for (const t of ['Hola, quiero contarles algo', 'quiero poner una queja',
                 'Necesito hablar con alguien', 'les quiero contar algo',
                 'tengo una queja']) {
  ok(`«${t}» no se responde con el guion`, esArranque(t) === true);
}
// Un párrafo ya es la historia, no el anuncio: ahí no hay que esperar.
ok('pero si ya la está contando, no se le interrumpe',
   esArranque('Quiero contarles que el sábado la clase de salsa estuvo ' +
              'increíble, el profe se tomó el tiempo de corregirnos uno por ' +
              'uno y salí feliz de verdad') === false);

console.log('\n-- 3. Nunca una pregunta pelada -----------------------------');

ok('a una pregunta sola se le antepone el acuse',
   conAcuse('¿Qué le dirías a alguien que está pensando en venir?')
     .startsWith('Gracias por contarme.'));
ok('también si la pregunta no arranca con el signo',
   conAcuse('Si mañana dejaras de venir a Tumbao, ¿cuál sería la razón más probable?')
     .startsWith('Gracias por contarme.'));
ok('si el bot ya acusó recibo, no se le mete otro encima',
   conAcuse('Uy, qué bueno leer eso. ¿Y si dejaras de venir?')
     === 'Uy, qué bueno leer eso. ¿Y si dejaras de venir?');
ok('un cierre sin pregunta se queda como está',
   conAcuse('Gracias de verdad, esto nos sirve muchísimo.')
     === 'Gracias de verdad, esto nos sirve muchísimo.');
ok('y una respuesta vacía no se convierte en un acuse suelto',
   conAcuse('') === '');

console.log('\n-- 4. El saludo, en el Worker de verdad ---------------------');
{
  const { env } = entorno();
  const c = chat(worker, env);
  const d = await c.abrir();
  ok('dice para qué se pregunta', /adivinar/.test(d.respuesta));
  ok('dice a quién le llega', /Tania/.test(d.respuesta));
  ok('dice lo poco que cuesta', /una frase basta/.test(d.respuesta));
  ok('y termina en la pregunta de verdad',
     d.respuesta.trim().endsWith('¿Qué te hizo volver la segunda vez?'));
  ok('sin pedir el nombre de entrada', !/c[oó]mo te llamas/i.test(d.respuesta));
  ok('sin anunciar trabajo', !/tres preguntas/i.test(d.respuesta));
}

console.log('\n-- 5. Un saludo no adelanta el cierre -----------------------');
// El bot solo puede terminar cuando la persona ya dijo cuatro cosas: las
// tres respuestas y lo que conteste al final. Si un «Buena tarde»
// contara como una de esas cuatro, la conversación terminaría con una
// pregunta sin hacer. Este modelo de mentiras intenta cerrar en cada
// mensaje, que es justo el peor caso.
{
  const { env } = entorno({ respuesta: 'Listo, gracias.\n\n[FIN]' });
  const c = chat(worker, env);
  await c.abrir();
  const saludo = await c.escribir('Buena tarde');
  ok('con un saludo no cierra', saludo.listo === false);
  const uno = await c.escribir('El ambiente');
  ok('con una respuesta tampoco', uno.listo === false);
  const dos = await c.escribir('Trabajo');
  ok('con dos tampoco', dos.listo === false);
  const tres = await c.escribir('Que vengan');
  ok('con las tres todavía no: falta el cierre', tres.listo === false);
  const cuatro = await c.escribir('Marcela, 3001234567');
  ok('y ahí sí termina', cuatro.listo === true);
}

console.log('\n-- 6. Al que saluda no se le contesta con la pregunta 2 -----');
{
  const { env, modelo } = entorno();
  const c = chat(worker, env);
  await c.abrir();
  await c.escribir('Buena tarde');
  const aviso = modelo.llamadas.at(-1).system;
  ok('el modelo recibe el aviso de no avanzar', /NO avances a la pregunta/.test(aviso));
  ok('y de que eso no era una respuesta', /NO es la respuesta/.test(aviso));

  await c.escribir('El ambiente, uno se siente en casa');
  ok('con una respuesta de verdad, el aviso no va',
     !/AVISO SOBRE EL ÚLTIMO MENSAJE/.test(modelo.llamadas.at(-1).system));
}

console.log('\n-- 7. Al saludo no se le pega un "gracias por contarme" -----');
// El acuse forzado es para cuando la persona contó algo. Detrás de un
// «hola» suena a máquina, que es exactamente lo que se está quitando.
{
  const { env } = entorno({ respuesta: '¿Qué te hizo volver la segunda vez?' });
  const c = chat(worker, env);
  await c.abrir();
  const s = await c.escribir('Hola');
  ok('tras un saludo, la respuesta va tal cual',
     !s.respuesta.startsWith('Gracias por contarme'), JSON.stringify(s.respuesta));
  const r = await c.escribir('El ambiente, uno se siente en casa');
  ok('tras una respuesta de verdad, sí se acusa recibo',
     r.respuesta.startsWith('Gracias por contarme'), JSON.stringify(r.respuesta));
}

console.log(`\n${fallos === 0 ? '\x1b[32mtodo en verde\x1b[0m' : `\x1b[31m${fallos} FALLOS\x1b[0m`}\n`);
process.exit(fallos ? 1 : 0);
