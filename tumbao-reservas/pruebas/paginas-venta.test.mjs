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
  ok('el pase de entrada dice lo mismo (25 oct: pases)', /linea: 'Tu horario fijo de lunes a sábado\.'/.test(men));
  ok('entre semana no se reserva y el sábado sí se aparta cupo', /no reservas<\/b>: solo llegas y entras/.test(men) && /sábado<\/b> sí se aparta cupo/.test(men));
  ok('las filas de horarios dicen lunes a sábado', /libre \? 'Lunes a sábado'/.test(men) && /'Sin domingos ni festivos'/.test(men));
}

titulo('2. Precio por clase');
{
  ok('sale del valor del sistema (valorCop) dividido entre las clases del mes de referencia (25)',
     /CLASES_MES_REF: 25/.test(men) && /Math\.round\(valorCop \/ CONFIG\.CLASES_MES_REF \/ 100\) \* 100/.test(men));
  ok('siempre «alrededor de» y contra la clase suelta, nunca como descuento',
     /Alrededor de \$\{pesos\(porClasePlan\(\)\)\} por clase si vienes a todas \(la suelta cuesta/.test(men));
  ok('se pinta en el pase y en el detalle del plan, y se repinta cuando llega el valor del sistema',
     /xc: `≈ \$\{pesos\(porClasePlan\(\)\)\} por clase`/.test(men) && /id="plan-por-clase"/.test(men) && /getElementById\('plan-por-clase'\)/.test(men));
  const por = Math.round(125000 / 25 / 100) * 100;
  ok('con $125.000 y 25 clases da $5.000 (igual que el bot)', por === 5000, String(por));
}

titulo('3. Para quién es cada tiquetera y la franja de reservas');
{
  ok('la tiquetera NO se presenta como «una o dos veces por semana»: se usa cuando quieras dentro de los 30 días',
     /Usa tus \$\{clases\} clases cuando quieras, sin horario fijo/.test(men) && !/veces por semana|vez por semana/i.test(men.slice(men.indexOf('function listaDePases'), men.indexOf('function cuposTxt'))));
  // 13 oct: la franja dice primero los cupos REALES de mensualidad (lo que más cayó en octubre) y la tiquetera queda de
  // segunda opción; sin cupos, la cuenta de la tiquetera como antes.
  ok('la franja de reservas pone primero los cupos reales de mensualidad (los dos horarios con menos cupos) y el precio del mes',
     /async function pintarFranjaPromo/.test(idx) && /await cuposMensualidad\(\)/.test(idx) &&
     /sort\(\(a, b\) => a\.libres - b\.libres\)\.slice\(0, 2\)/.test(idx) &&
     /`Mensualidad: quedan \$\{horas\.join\(' y '\)\}\. Todo el mes por <b>\$\{pesos\(m\.valor\)\}<\/b>\.`/.test(idx));
  ok('sin cupos, la cuenta real de los paquetes del sistema (precio por clase y ahorro)',
     /tiquetera\/paquetes/.test(idx) && /cada clase te sale a <b>\$\{pesos\(porClaseTiq\)\}<\/b>/.test(idx) && /\(ahorras \$\{pesos\(ahorro\)\}\)/.test(idx));
  ok('si nada carga, se queda el texto de siempre (sin datos no se escribe nada)',
     /if \(!mejor\) return;/.test(idx) && /cuposMensualidad\(\)\.catch\(\(\) => null\)/.test(idx)
     && /¿Vienes seguido\? Con la <b>tiquetera<\/b> compras varias clases de una/.test(idx));
  ok('se llama DESPUÉS de declarar paquetesTiq (let): antes daría «aún no definida»',
     idx.indexOf('let paquetesTiq') > 0 && idx.indexOf('\n  pintarFranjaPromo();') > idx.indexOf('let paquetesTiq'));
}

titulo('4. Nada suena a descuento');
{
  const nuevo = [
    /Alrededor de \$\{pesos\(porClasePlan\(\)\)\}[^`]*/.exec(men)[0],
    'Usa tus clases cuando quieras, sin horario fijo. Tienes 30 días para usarlas.',
    /cada clase te sale a <b>[^`]*/.exec(idx)[0],
  ].join(' ');
  ok('el texto nuevo no dice descuento, regalo, promoción, oferta ni «gratis»', !/descuento|regalo|promoci|oferta|gratis|últimos? cupos?/i.test(nuevo), nuevo.slice(0, 90));
}

titulo('5. Página del 2027 y /mensualidad directo a elegir pase');
{
  const p27 = readFileSync(new URL('../../docs/2027.html', import.meta.url), 'utf8');
  ok('las barritas del inicio son un enlace a la página del 2027', /<a class="mini-hero"[^>]*href="2027\.html"/.test(idx) && /id="eq"/.test(idx));
  ok('la franja de arriba sigue llevando a /mensualidad', /class="franja-promo" href="mensualidad\.html"/.test(idx));
  ok('/mensualidad ya no abre con la cabecera del 2027, el ticker, «dolor» ni «ruta»', !/id="hero"|class="ticker"|id="dolor"|id="ruta"/.test(men));
  ok('/mensualidad abre directo en elegir pase', men.indexOf('id="el-titulo"') > 0 && men.indexOf('id="tarjetas-eleccion"') > men.indexOf('id="el-titulo"'));
  ok('la página del 2027 lleva a /mensualidad y muestra mensualidad y tiquetera de 8', (p27.match(/href="mensualidad\.html"/g) || []).length >= 3 && /TIQUETERA/.test(p27) && /MENSUALIDAD/.test(p27));
  ok('la página del 2027 usa los cupos y precios reales de la API', /tumbao\/mensualidad/.test(p27) && /tiquetera/.test(p27) && /libres/.test(p27));
  ok('la página del 2027 no promete descuentos, regalos ni premios', !/descuento|obsequio|regalo|gratis|gana un premio|recompensa/i.test(p27));
  ok('la página del 2027 dice que no hay clases domingos ni festivos', /domingos y festivos/i.test(p27));
}

console.log(fallos ? `\n${fallos} fallo(s)` : '\nTodo bien');
process.exit(fallos ? 1 : 0);
