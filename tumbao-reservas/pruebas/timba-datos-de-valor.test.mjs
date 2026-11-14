/**
 * Timba aporta valor (Damián, 15 oct): el seguimiento comparte primero un dato curioso o útil sobre moverse, y en la
 * conversación puede usar esos mismos datos (y solo esos).
 *
 *   node timba-datos-de-valor.test.mjs
 */
import { DATOS_DE_VALOR, datoDeValor, textoSeguimientoVentas, guardarRespuestaVentas, INSTRUCCIONES_VENTAS } from '../../tumbao-caja/src/ventas.js';

let fallos = 0;
const ok = (n, c, extra = '') => { if (!c) fallos++; console.log(`${c ? '✓' : '✗'} ${n}${extra ? '  → ' + extra : ''}`); };
const titulo = t => console.log(`\n-- ${t} ${'-'.repeat(Math.max(0, 54 - t.length))}`);

const perfil = { precio_suelta: 15000, valor_mensualidad: 125000, paquetes_tiquetera: [] };

titulo('1. Los datos');
{
  ok('hay varios datos distintos (al menos 6)', DATOS_DE_VALOR.length >= 6 && new Set(DATOS_DE_VALOR).size === DATOS_DE_VALOR.length);
  ok('incluyen los que pidió Damián: endorfinas y «30 minutos valen más que no hacer nada»',
     DATOS_DE_VALOR.some(d => /endorfinas/i.test(d)) && DATOS_DE_VALOR.some(d => /30 minutos[^.]*valen mucho más que no hacer nada/i.test(d)));
  ok('cada dato es corto (cabe en un mensaje de WhatsApp)', DATOS_DE_VALOR.every(d => d.length <= 230));
  ok('todos pasan la baranda: sin cifras de dinero, enlaces ni promesas', DATOS_DE_VALOR.every(d => guardarRespuestaVentas(d, perfil).ok));
  ok('ninguno promete salud ni inventa estudios: nada de curar, adelgazar, prevenir, bajar de peso, porcentajes ni «estudios»',
     DATOS_DE_VALOR.every(d => !/cura|adelgaz|previene|prevenir|bajar de peso|quema|%|por ciento|estudios? (demuestra|dice|muestra)|cient[ií]fic/i.test(d)));
  ok('hablan con prudencia (suele, ayuda): ninguno afirma algo médico como absoluto', DATOS_DE_VALOR.every(d => !/\b(siempre|garantiza|elimina|todos los)\b/i.test(d)));
  ok('el único número que aparece es el 30 y el 150 de la OMS', DATOS_DE_VALOR.every(d => (d.match(/\d+/g) || []).every(n => ['30', '150'].includes(n))));
}

titulo('2. El seguimiento');
{
  const t = textoSeguimientoVentas({ nombre: 'Laura', objetivo: 'mensualidad_7am', chat: 5 });
  ok('empieza con el saludo, sigue con un dato y termina con la pregunta de siempre',
     /^Hola Laura 😊\n\n/.test(t) && t.includes(datoDeValor(5)) && /¿Pudiste ver el enlace para tu mensualidad\?\s*Si tienes dudas/.test(t) && t.indexOf(datoDeValor(5)) < t.indexOf('¿Pudiste'));
  ok('el mismo chat siempre recibe el mismo dato y chats distintos reciben datos distintos',
     datoDeValor(7) === datoDeValor(7) && new Set(Array.from({ length: DATOS_DE_VALOR.length }, (_, i) => datoDeValor(i))).size === DATOS_DE_VALOR.length);
  ok('sin número de chat no falla (usa el primero)', datoDeValor(undefined) === DATOS_DE_VALOR[0] && datoDeValor('x') === DATOS_DE_VALOR[0]);
  const todos = [
    textoSeguimientoVentas({ nombre: 'Ana', chat: 1 }), textoSeguimientoVentas({ nombre: 'Ana', hora: '19:00', chat: 2 }),
    textoSeguimientoVentas({ nombre: 'Ana', hora: '18:00', chat: 3 }), textoSeguimientoVentas({ nombre: 'Ana', visito: true, chat: 4 }),
    textoSeguimientoVentas({}),
  ];
  ok('todas las variantes pasan la baranda y caben en un mensaje', todos.every(x => guardarRespuestaVentas(x, perfil).ok && x.length < 520));
  ok('la variante de «abrió la página y no terminó» sigue preguntando qué la frenó (y no «¿lo viste?»)',
     /duda para terminar tu inscripción/.test(todos[3]) && !/Pudiste ver el enlace/.test(todos[3]));
  ok('la de lista de espera sigue nombrando el horario correcto', /cupo de las 7 pm/.test(todos[1]) && /cupo de las 6 pm/.test(todos[2]));
  ok('sin descuentos ni promesas en ninguna', todos.every(x => !/descuento|gratis|promo|regalo/i.test(x)));
}

titulo('3. En la conversación');
{
  ok('el prompt le pide aportar valor y compartir UN dato, solo de la lista, no uno en cada mensaje',
     /APORTA VALOR, NO SOLO VENDAS/.test(INSTRUCCIONES_VENTAS) && /UN dato de la lista/.test(INSTRUCCIONES_VENTAS) && /Un dato por conversación/.test(INSTRUCCIONES_VENTAS));
  ok('el prompt trae todos los datos permitidos, tal cual', DATOS_DE_VALOR.every(d => INSTRUCCIONES_VENTAS.includes(d)));
  ok('si no tiene tiempo, el de los 30 minutos', /no tiene tiempo[^.]*el de los 30 minutos es el indicado/.test(INSTRUCCIONES_VENTAS));
  ok('prohíbe inventar cifras, estudios y promesas de salud, y manda a su médico si menciona lesión, enfermedad o embarazo',
     /Nunca inventes cifras, estudios ni beneficios/.test(INSTRUCCIONES_VENTAS) && /no digas que cura, adelgaza ni previene nada/.test(INSTRUCCIONES_VENTAS) &&
     /lesión, una enfermedad o un embarazo[^.]*consulte con su médico/.test(INSTRUCCIONES_VENTAS));
  ok('sigue sin permitir descuentos ni promesas', /Nunca inventes un descuento/.test(INSTRUCCIONES_VENTAS));
}

console.log(`\n${fallos ? '✗ ' + fallos + ' con problemas' : '✓ todo bien'}`);
process.exit(fallos ? 1 : 0);
