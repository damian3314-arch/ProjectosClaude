/**
 * Un problema no se resuelve en el chat de opiniones.
 *
 * POR QUÉ EXISTE
 * Damián, 21 de septiembre: «cuando la gente abra ese chat y escriba que
 * está teniendo problemas, de una vez generarles el link o que nos
 * contacten por WhatsApp, porque eso no se resuelve ahí… el chat de
 * opiniones solamente es precisamente para escuchar a los clientes».
 *
 * Y no es teórico. El 15 de septiembre alguien escribió aquí:
 *
 *   «quisiera saber si quedaron los dos cupos apartados para el día de
 *    hoy… yo realicé el pago pero no sabía q debía adjuntar el
 *    comprobante y cerré la página»
 *
 * Dos cupos, dos nombres, un pago hecho. El bot siguió con sus tres
 * preguntas de opinión y nadie lo leyó hasta seis días después.
 *
 * LO QUE SE PRUEBA
 * Que el guion que se le manda al modelo lleva las instrucciones para
 * derivar, con el enlace armado y la regla de no seguir el cuestionario;
 * que la ficha del lunes marca urgente un pago en el aire; y que el
 * chat pinta ese enlace como algo que se puede pulsar — decirle
 * «escríbenos al WhatsApp» a alguien en un celular sin darle dónde
 * hacer clic es pedirle que copie diez dígitos a mano.
 *
 *   node pruebas/derivar-a-whatsapp.test.mjs
 */
import { readFileSync } from 'node:fs';

let fallos = 0;
const ok = (n, c, extra = '') => { if (!c) fallos++;
  console.log(`${c ? '\x1b[32mv\x1b[0m' : '\x1b[31mx\x1b[0m'} ${n}${extra ? '  → ' + extra : ''}`); };
const titulo = (t) => console.log(`\n-- ${t} ${'-'.repeat(Math.max(0, 52 - t.length))}`);

const worker = readFileSync(new URL('../src/index.js', import.meta.url), 'utf8');
const front  = readFileSync(new URL('../public/index.html', import.meta.url), 'utf8');

titulo('1. El guion sabe derivar');

ok('dice que este chat no es soporte',
   /no es soporte/i.test(worker));
ok('y nombra los casos que no se resuelven aquí',
   /reserva/i.test(worker) && /comprobante/i.test(worker) &&
   /cupo/i.test(worker) && /factura/i.test(worker));
ok('manda pegar el enlace tal cual',
   /\$\{WHATSAPP_ENLACE\}/.test(worker),
   'si se escribe el número a mano, el día que cambie se queda viejo aquí');
ok('con el WhatsApp de verdad de Tumbao',
   /wa\.me\/573017833550/.test(worker));

/* Lo importante no es que mande el enlace: es que NO siga preguntando.
   Alguien con un pago atascado no está para contar qué le gusta de las
   clases, y seguir el cuestionario es lo que hizo que el caso del 15 se
   perdiera entre respuestas de opinión. */
ok('y cierra ahí, sin seguir el cuestionario',
   /Las tres preguntas no van/.test(worker),
   'seguir preguntando es lo que enterró el caso del 15 de septiembre');
ok('sin prometer lo que no controla',
   /No prometas que lo vas a pasar/.test(worker));

titulo('2. Lo de los profesores, con su porqué');

/* Damián: «las clases son con profesores aleatorios… lo que buscamos es
   que cada una sea dinámica, que cumpla el estándar de Tumbao». No es
   una carencia que haya que disculpar: es una decisión, y el bot la
   puede contar. */
ok('el bot sabe que la rotación es a propósito',
   /rotan de profesor a prop[oó]sito/i.test(worker));
ok('y manda a recepción para el caso concreto',
   /se consulta en recepci[oó]n/i.test(worker));
ok('sin prometer que se publicará en la web',
   !/publicar[eé]|lo pondremos en la p[aá]gina/i.test(worker));

titulo('3. Un pago en el aire no espera al lunes');

ok('la ficha lo marca urgente',
   /pag[oó] y su reserva o\s*\n?\s*su cupo qued[oó] en el aire/i.test(worker)
   || /pag[oó].{0,60}qued[oó] en el aire/is.test(worker),
   'el del 15 de septiembre estuvo seis días sin que nadie lo viera');

titulo('4. El enlace se puede pulsar');

ok('el chat convierte wa.me en un enlace', /rel="noopener"/.test(front));
ok('abriéndolo fuera del iframe', /target="_blank"/.test(front));

/* El orden importa y es lo único delicado de este cambio: lo que escribe
   el bot viene de un modelo, así que se escapa TODO primero y solo
   después se reconstruye wa.me. Al revés, un texto del modelo podría
   traer etiquetas y quedarían vivas. */
const iEsc = front.indexOf('const seguro = texto.replace');
const iEnl = front.indexOf('const conEnlace = seguro.replace');
ok('escapando antes de enlazar, no al revés',
   iEsc > 0 && iEnl > iEsc,
   'lo que escribe el bot pasa por un modelo: primero inerte, luego el enlace');
ok('y solo reconoce wa.me, nada más',
   /https:\\\/\\\/wa\\\.me\\\//.test(front),
   'un patrón abierto dejaría pasar cualquier URL que el modelo invente');

console.log(fallos ? `\n\x1b[31m${fallos} fallo(s)\x1b[0m`
                   : '\n\x1b[32mtodo en verde\x1b[0m');
process.exit(fallos ? 1 : 0);
