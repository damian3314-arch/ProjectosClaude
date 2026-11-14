/**
 * Timba, 15-16 oct: (1) una imagen (comprobante) ya no se ignora: se responde y recepción se entera, y
 * (2) el saludo automático «¡Bienvenid@ a TravelLovers!» tampoco se contesta.
 *
 *   node timba-imagenes-y-automaticos.test.mjs
 */
import { readFileSync } from 'node:fs';
import { esRespuestaAutomatica, esImagenDeChat, RESPUESTA_IMAGEN_VENTAS, guardarRespuestaVentas } from '../../tumbao-caja/src/ventas.js';

let fallos = 0;
const ok = (n, c, extra = '') => { if (!c) fallos++; console.log(`${c ? '✓' : '✗'} ${n}${extra ? '  → ' + extra : ''}`); };
const titulo = t => console.log(`\n-- ${t} ${'-'.repeat(Math.max(0, 54 - t.length))}`);

const index = readFileSync(new URL('../../tumbao-caja/src/index.js', import.meta.url), 'utf8');

titulo('1. Imágenes (comprobantes)');
{
  ok('se reconoce una imagen con y sin texto', esImagenDeChat('[imagen:1396180962221172] Para iniciar clase mañana a las 6pm gracias') && esImagenDeChat('[imagen:123]'));
  ok('un texto normal o una nota de voz NO es imagen', !esImagenDeChat('Y los días lunes miércoles y viernes a las 6 pm gracias') && !esImagenDeChat('[audio:55]') && !esImagenDeChat(null));
  ok('la respuesta dice que la recibió y que recepción la revisa, sin confirmar ningún pago',
     /Recibí tu imagen/.test(RESPUESTA_IMAGEN_VENTAS) && /recepción lo revise/.test(RESPUESTA_IMAGEN_VENTAS) && !/(confirmad|aprobad|ya pagaste|quedó pagad|activad)/i.test(RESPUESTA_IMAGEN_VENTAS));
  ok('trae el enlace para escribir a recepción y pasa la baranda (sin cifras, promesas ni enlaces ajenos)',
     /wa\.me\/573017833550/.test(RESPUESTA_IMAGEN_VENTAS) && guardarRespuestaVentas(RESPUESTA_IMAGEN_VENTAS, {}).ok);
  ok('el Worker contesta y avisa a recepción en vez de ignorar la imagen',
     /if \(esImagenDeChat\(m\.texto\)\) \{[\s\S]{0,200}responderYGuardar\(env, m\.telefono, RESPUESTA_IMAGEN_VENTAS\)[\s\S]{0,400}avisarRecepcionImagen\([\s\S]{0,200}imagen: true/.test(index));
  ok('va ANTES de esperar los mensajes seguidos (quien manda la imagen y un texto a la vez no pierde el aviso)',
     index.indexOf('esImagenDeChat(m.texto)') > 0 && index.indexOf('esImagenDeChat(m.texto)') < index.indexOf('ESPERA_MENSAJES_SEGUIDOS_MS));'.replace('));', ')')));
  ok('la nota a recepción es una por conversación y día, dice que Timba NO confirma pagos y qué hacer',
     /p_clave: `venta-imagen:\$\{chat\.id\}:\$\{dia\}`/.test(index) && /Timba NO lee comprobantes ni confirma pagos/.test(index) && /301 783 3550/.test(index));
  ok('la conversación sigue abierta (no se cierra por mandar una imagen)', /p_texto_entrante: '\(imagen\)', p_cerrar: false/.test(index));
}

titulo('2. Saludos automáticos');
{
  const travel = '🌍✨ ¡Bienvenid@ a TravelLovers!\nAquí no solo armamos viajes… creamos experiencias que te hacen vibrar 💫✈️\nContanos:\n📍 ¿A dónde sueñas viajar?';
  ok('«¡Bienvenid@ a TravelLovers!» se reconoce como automático', esRespuestaAutomatica(travel));
  ok('los anteriores siguen reconociéndose',
     esRespuestaAutomatica('¡Hola! Gracias por comunicarte con Jessica Andrades Odontología Integral y Estética.') &&
     esRespuestaAutomatica('🦷 ¡Hola, hola! 😊\n¡Bienvenid@ a mi consultorio!') && esRespuestaAutomatica('Este número no revisa mensajes.'));
  const personas = ['Cuéntame más', 'Si', 'Es que yo vivo en Med :(', 'Me encantó', 'hola me queda mejor en horario de 7:00pm', 'Oki gracias',
    'Y los días lunes Miércoles y viernes a las 6 pm gracias 😇', 'Bienvenida a Barranca, ¿dónde queda la academia?', 'Gracias por el dato'];
  personas.forEach((t) => ok(`persona «${t.slice(0, 34)}»: sí se contesta`, !esRespuestaAutomatica(t)));
}

console.log(`\n${fallos ? '✗ ' + fallos + ' con problemas' : '✓ todo bien'}`);
process.exit(fallos ? 1 : 0);
