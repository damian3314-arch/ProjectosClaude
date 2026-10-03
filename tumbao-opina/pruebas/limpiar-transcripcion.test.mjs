/**
 * Las alucinaciones de Whisper, filtradas.
 *
 * POR QUÉ ESTA PRUEBA
 * Con audio en silencio o puro ruido Whisper no devuelve vacío: devuelve
 * frases de subtítulos de YouTube que se aprendió de memoria. Sin filtro,
 * eso entra al chat como si la persona lo hubiera dicho y termina en la
 * hoja y en el reporte del lunes como opinión de un cliente. Un dato
 * falso en una herramienta que existe para escuchar es peor que no tener
 * la herramienta.
 *
 * Los dos lados importan igual. Descartar de más es tan malo como
 * descartar de menos: si alguien deja una nota larga y de verdad que
 * casualmente dice "gracias por ver", tirarla a la basura es perder la
 * única opinión sincera del día. Por eso hay tope de largo, y por eso
 * aquí se prueban los textos reales tanto como las alucinaciones.
 *
 *   node tumbao-opina/pruebas/limpiar-transcripcion.test.mjs
 */
import { readFileSync } from 'node:fs';

// Se extrae la función del Worker en vez de duplicarla: si allá cambia y
// aquí no, la prueba dejaría de decir la verdad sin que nadie lo note.
const fuente = readFileSync(new URL('../src/index.js', import.meta.url), 'utf8');
const desde = fuente.indexOf('const ALUCINACIONES');
const hasta = fuente.indexOf('\n}', fuente.indexOf('function limpiarTranscripcion')) + 2;
if (desde < 0 || hasta < 2) {
  console.error('✗ no se encontró limpiarTranscripcion() en src/index.js');
  process.exit(1);
}
const limpiar = new Function(fuente.slice(desde, hasta) + '\nreturn limpiarTranscripcion;')();

let ok = 0, mal = 0;
const t = (que, entra, esperado) => {
  const sale = limpiar(entra);
  sale === esperado
    ? (ok++, console.log(`  ✓ ${que}`))
    : (mal++, console.log(`  ✗ ${que}\n      entró: ${JSON.stringify(entra)}` +
                          `\n      esperaba: ${JSON.stringify(esperado)}` +
                          `\n      salió:    ${JSON.stringify(sale)}`));
};

console.log('\n── Alucinaciones de Whisper ──\n');

// ---- lo que hay que tirar ----
t('"gracias por ver el video"', 'Gracias por ver el video.', '');
t('los subtítulos de Amara', 'Subtítulos por la comunidad de Amara.org', '');
t('la variante en inglés', 'Thanks for watching!', '');
t('la de suscribirse', '¡Suscríbete al canal!', '');
t('solo signos de puntuación', '...', '');
t('vacío', '', '');
t('un espacio', '   ', '');
t('una sola letra no es una opinión', 'a', '');

// ---- lo que NO se puede tirar ----
t('una queja corta y real',
  'La música muy duro', 'La música muy duro');
t('un elogio corto',
  'Todo excelente, gracias', 'Todo excelente, gracias');

// EL CASO QUE JUSTIFICA EL TOPE DE LARGO. Sin él, esta persona —que dio
// la opinión más útil del día— habría desaparecido del reporte.
const larga = 'Quería agradecerles por el video que subieron a Instagram, ' +
  'pero la verdad el salón a las 6 está muy lleno y no se puede bailar bien. ' +
  'Gracias por ver mi mensaje.';
t('una nota larga que dice "gracias por ver" NO se tira', larga, larga);

// Justo por encima del tope: aunque diga la frase, es demasiado larga
// para ser una alucinación.
const justo = 'Gracias por ver mi mensaje, quiero decirles que el aire acondicionado no sirve';
t(`una de ${justo.length} caracteres tampoco`, justo, justo);

// Y justo por debajo: corta y con la frase, se va.
t('una corta con la frase sí se va', 'Gracias por ver', '');

// Se recortan los espacios, como antes del filtro.
t('recorta los espacios', '  el piso resbala  ', 'el piso resbala');

console.log(`\n${mal ? mal + ' FALLOS' : 'todo en verde'}  (${ok} comprobaciones)\n`);
process.exit(mal ? 1 : 0);
