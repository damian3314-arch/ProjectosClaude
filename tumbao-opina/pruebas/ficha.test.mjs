/**
 * La ficha — prueba
 *
 * EL CASO
 * El primer reporte de verdad salió con quince filas que decían
 * "Sin nombre · (sin resumen)". La conversación estaba entera en la
 * base; lo que falló fue el paso de convertirla en ficha. Un JSON que
 * llega partido a la mitad, o envuelto en ```json, deja la fila vacía y
 * el lunes parece que no se guardó nada.
 *
 * Esto comprueba que de una conversación guardada SIEMPRE sale algo
 * legible, aunque el modelo conteste mal.
 *
 *   node pruebas/ficha.test.mjs
 */
import {
  sacarJSON, taparComillas, limpiarFicha, loQueDijo, primerNombre,
} from '../src/index.js';

let fallos = 0, hechas = 0;
const chk = (que, obtenido, esperado) => {
  hechas++;
  const ok = JSON.stringify(obtenido) === JSON.stringify(esperado);
  if (!ok) { fallos++; console.log(`  \x1b[31mx ${que}\x1b[0m\n     esperaba ${JSON.stringify(esperado)}\n     llegó    ${JSON.stringify(obtenido)}`); }
  else console.log(`  \x1b[32mv\x1b[0m ${que}`);
};

const CHARLA = [
  'TUMBAO: ¡Hola! Soy de Tumbao. ¿Cómo te llamas?',
  'CLIENTE: Camila',
  'TUMBAO: ¿Qué te hizo volver la segunda vez?',
  'CLIENTE: el ambiente, nadie lo mira raro aunque no sepa bailar',
  'TUMBAO: ¿Y si dejaras de venir?',
  'CLIENTE: una vez un profe me hizo sentir mal delante de todos',
].join('\n');

console.log('\n-- 1. Sacar el JSON de donde venga -------------------------');

chk('JSON pelado', sacarJSON('{"nombre":"Ana"}'), { nombre: 'Ana' });
chk('envuelto en ```json',
  sacarJSON('```json\n{"nombre":"Ana"}\n```'), { nombre: 'Ana' });
chk('con cháchara delante',
  sacarJSON('Aquí está el objeto:\n{"nombre":"Ana"}\nEspero que sirva.'), { nombre: 'Ana' });
chk('vacío si no hay nada', sacarJSON('no encontré nada'), {});
chk('vacío si viene partido a la mitad',
  sacarJSON('{"nombre":"Ana","resumen":"le gusta el ambi'), {});
chk('vacío si llega null', sacarJSON(null), {});

// Esta es la que costó encontrar. Cuando el modelo contesta bien —JSON
// limpio, sin vallas— Workers AI lo entrega YA parseado, como objeto.
// Sin esto, String(objeto) daba "[object Object]" y la ficha se perdía
// justo en el caso bueno.
chk('si ya viene como objeto, se usa tal cual',
  sacarJSON({ nombre: 'Ana', urgente: true }), { nombre: 'Ana', urgente: true });
chk('sin confundirse con undefined', sacarJSON(undefined), {});

console.log('\n-- 1b. La comilla suelta, que es como se rompió de verdad --');
// Caso real, sacado de una corrida contra el modelo: al pedirle que
// conserve la frase textual del cliente, la metió entre comillas dobles
// dentro de la cadena JSON y se llevó la ficha entera por delante.

const REAL = '```json\n{\n  "nombre": "Camila",\n  "telefono": "3001234567",\n' +
  '  "tipo": "mixto",\n  "resumen": "Le gustó el ambiente porque "nadie lo ' +
  'mira raro aunque no sepa bailar", pero un profesor la hizo sentir mal",\n' +
  '  "urgente": false,\n  "motivo": null\n}\n```';

const salvada = sacarJSON(REAL);
chk('se recupera el nombre', salvada.nombre, 'Camila');
chk('y el teléfono, que era lo que más dolía perder', salvada.telefono, '3001234567');
chk('y el resumen entero, con su cita',
  salvada.resumen,
  'Le gustó el ambiente porque "nadie lo mira raro aunque no sepa bailar", ' +
  'pero un profesor la hizo sentir mal');

chk('un JSON que ya era válido no se toca',
  taparComillas('{"a":"hola, mundo","b":null}'), '{"a":"hola, mundo","b":null}');
chk('las comillas ya escapadas se respetan',
  JSON.parse(taparComillas('{"a":"dijo \\"hola\\" y se fue"}')).a,
  'dijo "hola" y se fue');
chk('una llave dentro de un texto no confunde',
  JSON.parse(taparComillas('{"a":"esto } no cierra nada"}')).a,
  'esto } no cierra nada');

console.log('\n-- 2. Nunca una fila en blanco -----------------------------');
// Este es el punto: aunque el modelo devuelva basura, el lunes hay algo
// que leer. Las palabras de la persona valen más que "(sin resumen)".

const rota = limpiarFicha({}, CHARLA);
chk('el resumen cae a lo que dijo la persona', rota.resumen,
  'Camila · el ambiente, nadie lo mira raro aunque no sepa bailar · ' +
  'una vez un profe me hizo sentir mal delante de todos');
chk('y el nombre sale de su primer mensaje', rota.nombre, 'Camila');
chk('sin inventar urgencia', rota.urgente, false);
chk('tipo por defecto', rota.tipo, 'mixto');

const sinNada = limpiarFicha({}, '');
chk('sin conversación sí dice que no hay resumen', sinNada.resumen, '(sin resumen)');
chk('y el nombre queda vacío', sinNada.nombre, null);

console.log('\n-- 3. Lo que el modelo sí devolvió manda -------------------');

const buena = limpiarFicha({
  nombre: 'Camila Ríos', telefono: '300 123 4567', tipo: 'queja',
  resumen: 'Le gusta el ambiente pero un profesor la humilló.',
  urgente: true, motivo: 'Trato irrespetuoso de un profesor',
}, CHARLA);
chk('nombre', buena.nombre, 'Camila Ríos');
chk('el teléfono queda en dígitos', buena.telefono, '3001234567');
chk('tipo', buena.tipo, 'queja');
chk('urgente', buena.urgente, true);
chk('motivo', buena.motivo, 'Trato irrespetuoso de un profesor');
chk('no lo pisa el paracaídas', buena.resumen,
  'Le gusta el ambiente pero un profesor la humilló.');

chk('urgente solo si es exactamente true',
  limpiarFicha({ urgente: 'true' }, CHARLA).urgente, false);
chk('un tipo inventado cae a mixto',
  limpiarFicha({ tipo: 'reclamo' }, CHARLA).tipo, 'mixto');
chk('un teléfono sin dígitos queda en nada',
  limpiarFicha({ telefono: 'no quiero' }, CHARLA).telefono, null);

console.log('\n-- 4. El nombre no se adivina de cualquier cosa ------------');
// El filtro es de forma, no de significado: una o dos palabras de
// letras pasan, aunque sean "bien". Se acepta a propósito. Esto solo
// corre cuando la extracción YA falló, y a la pregunta "¿cómo te
// llamas?" casi nadie contesta "bien". Lo que sí se corta es lo que
// claramente no es un nombre: una frase entera o un teléfono, que en
// el reporte se leería como un error del sistema.

const con = (primero) => primerNombre(`CLIENTE: ${primero}\nTUMBAO: ok`);
chk('un nombre simple', con('Camila'), 'Camila');
chk('nombre y apellido', con('Camila Ríos'), 'Camila Ríos');
chk('con tilde y apóstrofo', con("D'Angelo Peña"), "D'Angelo Peña");
chk('quita el punto final', con('Camila.'), 'Camila');
chk('una palabra suelta pasa, aunque sea "bien"', con('bien'), 'bien');
chk('una frase larga no', con('quiero poner una queja del profesor'), null);
chk('un teléfono no', con('3001234567'), null);
chk('vacío si no habló', primerNombre('TUMBAO: hola'), null);

console.log('\n-- 5. Solo lo que dijo la persona --------------------------');
chk('se quedan sus frases, no las del bot', loQueDijo(CHARLA),
  'Camila · el ambiente, nadie lo mira raro aunque no sepa bailar · ' +
  'una vez un profe me hizo sentir mal delante de todos');

console.log(fallos === 0
  ? `\n\x1b[32mtodo en verde\x1b[0m  (${hechas} comprobaciones)\n`
  : `\n\x1b[31m${fallos} FALLOS\x1b[0m de ${hechas}\n`);
process.exit(fallos === 0 ? 0 : 1);
