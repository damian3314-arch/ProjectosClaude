/**
 * Páginas de venta (9 oct): reservas y mensualidad dicen la cuenta real y lo mismo que el bot.
 *
 * Damián (9 oct): «revisa la página de reservas y mensualidad y haz algo para vender más». Sin tocar precios ni inventar
 * descuentos. Esta prueba protege que:
 *   1. la mensualidad se diga de lunes a sábado (sin domingos ni festivos), como la dice el bot;
 *   2. el precio por clase salga del valor del sistema y se diga «alrededor de» (el mes tiene entre 23 y 26 clases);
 *   3. cada tiquetera diga para quién es, y la franja de reservas muestre la cuenta real o, si falla, el texto de siempre;
 *   4. nada nuevo suene a descuento, regalo ni promoción.
 *
 *   node paginas-venta.test.mjs
 */
import { readFileSync } from 'node:fs';
let fallos = 0;
const ok = (n, c, extra = '') => { if (!c) fallos++; console.log(`${c ? '✓' : '✗'} ${n}${extra ? '  → ' + extra : ''}`); };
const titulo = t => console.log(`\n-- ${t} ${'-'.repeat(Math.max(0, 54 - t.length))}`);
const men = readFileSync(new URL('../../docs/mensualidad.html', import.meta.url), 'utf8');
const idx = readFileSync(new URL('../../docs/index.html', import.meta.url), 'utf8');

titulo('1. Mensualidad: lunes a sábado');
{
  ok('ningún texto de la página dice «lunes a viernes» como lo que cubre la mensualidad',
     !/Todas tus clases de (<b>)?lunes a viernes/.test(men) && !/'Lunes a viernes'/.test(men));
  ok('el detalle del plan dice lunes a sábado, sin domingos ni festivos', /Entras a todas tus clases de <b>lunes a sábado<\/b>, sin domingos ni festivos/.test(men));
  ok('la tarjeta de entrada dice lo mismo', /Todas tus clases de lunes a sábado, sin domingos ni festivos/.test(men));
  ok('entre semana no se reserva y el sábado sí se aparta cupo', /no reservas<\/b>: solo llegas y entras/.test(men) && /sábado<\/b> sí se aparta cupo/.test(men));
  ok('las filas de horarios dicen lunes a sábado', /libre \? 'Lunes a sábado'/.test(men) && /'Sin domingos ni festivos'/.test(men));
}

titulo('2. Precio por clase');
{
  ok('sale del valor del sistema (valorCop) dividido entre las clases del mes de referencia (25)',
     /CLASES_MES_REF: 25/.test(men) && /Math\.round\(valorCop \/ CONFIG\.CLASES_MES_REF \/ 100\) \* 100/.test(men));
  ok('siempre «alrededor de» y contra la clase suelta, nunca como descuento',
     /Alrededor de \$\{pesos\(porClasePlan\(\)\)\} por clase si vienes a todas \(la suelta cuesta/.test(men));
  ok('se pinta en la tarjeta y en el detalle del plan, y se repinta cuando llega el valor del sistema',
     /\$\{textoPorClasePlan\(\)\}<\/span>/.test(men) && /id="plan-por-clase"/.test(men) && /getElementById\('plan-por-clase'\)/.test(men));
  const por = Math.round(125000 / 25 / 100) * 100;
  ok('con $125.000 y 25 clases da $5.000 (igual que el bot)', por === 5000, String(por));
}

titulo('3. Para quién es cada tiquetera y la franja de reservas');
{
  ok('la de 8: dos veces por semana o parte del mes; la de 4: empezar o una vez por semana',
     /clases >= 8\s*\? 'Ideal si vienes dos veces por semana o solo una parte del mes\.'\s*: 'Ideal para empezar o para venir una vez por semana\.'/.test(men));
  ok('la franja de reservas pone la cuenta real de los paquetes del sistema (precio por clase y ahorro)',
     /async function pintarFranjaPromo/.test(idx) && /tiquetera\/paquetes/.test(idx) && /cada clase te sale a <b>\$\{pesos\(porClase\)\}<\/b>/.test(idx));
  ok('si los paquetes no cargan, se queda el texto de siempre (el catch no cambia nada)', /catch\(_\)\{ \/\* se queda el texto de siempre \*\/ \}/.test(idx)
     && /¿Vienes seguido\? Con la <b>tiquetera<\/b> compras varias clases de una/.test(idx));
  ok('se llama DESPUÉS de declarar paquetesTiq (let): antes daría «aún no definida»',
     idx.indexOf('let paquetesTiq') > 0 && idx.indexOf('\n  pintarFranjaPromo();') > idx.indexOf('let paquetesTiq'));
}

titulo('4. Nada suena a descuento');
{
  const nuevo = [
    /Alrededor de \$\{pesos\(porClasePlan\(\)\)\}[^`]*/.exec(men)[0],
    'Ideal si vienes dos veces por semana o solo una parte del mes. Ideal para empezar o para venir una vez por semana.',
    /cada clase te sale a <b>[^`]*/.exec(idx)[0],
  ].join(' ');
  ok('el texto nuevo no dice descuento, regalo, promoción, oferta ni «gratis»', !/descuento|regalo|promoci|oferta|gratis|últimos? cupos?/i.test(nuevo), nuevo.slice(0, 90));
}

console.log(fallos ? `\n${fallos} fallo(s)` : '\nTodo bien');
process.exit(fallos ? 1 : 0);
