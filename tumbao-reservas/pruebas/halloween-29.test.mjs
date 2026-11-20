/**
 * Halloween, jueves 29 de octubre (22 oct): franja en la página con cuenta regresiva, Timba lo sabe y no inventa detalles.
 *
 *   node halloween-29.test.mjs
 */
import { readFileSync } from 'node:fs';
import { INSTRUCCIONES_VENTAS } from '../../tumbao-caja/src/ventas.js';
import { INSTRUCCIONES_ASISTENTE } from '../../tumbao-caja/src/asistente.js';
const mens = readFileSync(new URL('../../docs/mensualidad.html', import.meta.url), 'utf8');

let fallos = 0;
const ok = (n, c, extra = '') => { if (!c) fallos++; console.log(`${c ? '✓' : '✗'} ${n}${extra ? '  → ' + extra : ''}`); };
const titulo = t => console.log(`\n-- ${t} ${'-'.repeat(Math.max(0, 54 - t.length))}`);
const html = readFileSync(new URL('../../docs/index.html', import.meta.url), 'utf8');
const franja = html.slice(html.indexOf('FRANJA: {'), html.indexOf('NUEVA: {'));

titulo('1. La franja de la página');
ok('la franja de campaña quedó apagada (Damián, 1 nov)', /activo:\s+false/.test(franja) && /Navidad/.test(franja) && /premiamos tu constancia/.test(franja));
ok('la franja cuenta los días hasta Navidad y se apaga sola', /fecha:\s+'2026-12-24'/.test(franja) && /if \(dias < 0\) return;/.test(html));
ok('lleva a la página de tiqueteras', /enlace:\s+'mensualidad\.html'/.test(franja));
ok('el bloque de la franja ya no está en la página', !/id="franja"/.test(html));
ok('no promete rebajas, regalos ni sorpresas', !/(descuento|rebaja|regalo|gratis|sorpresa|disfraz|2x1)/i.test(franja));

titulo('2. Timba');
ok('Halloween terminó: Timba ya no habla de la temporada (pasó a Navidad)', [INSTRUCCIONES_VENTAS, INSTRUCCIONES_ASISTENTE].every(t => !/TEMPORADA DE HALLOWEEN/.test(t) && /TEMPORADA DE NAVIDAD/.test(t)));

titulo('4. La página navideña')
for (const [n, h] of [['index', html], ['mensualidad', mens]]) {
  ok(`${n}: la capa se enciende sola del 1 nov al 6 ene y se puede forzar o quitar`,
     /d>='2026-11-01'&&d<='2027-01-06'/.test(h) && /navidad=\(\\d\)/.test(h) && /html\.navidad::before/.test(h));
  ok(`${n}: guirnalda de luces y nada de Halloween`, /class="guirnalda"/.test(h) && !/halloween|fr-luna|fr-m1/i.test(h));
  ok(`${n}: respeta a quien pide menos movimiento`, /prefers-reduced-motion:reduce\)\{\s*html\.navidad::after/.test(h));
}
ok('index: sin árbol ni tarjeta de campaña', !/fr-arbol|class="franja"/.test(html));
ok('nunca se habla de obsequio ni de regalo de clases (el único «regalo» es el producto «Regala Tumbao»)', (() => {
  const limpio = (t) => t.replace(/\/\/.*|\/\*[\s\S]*?\*\//g, '').replace(/<section class="esp rv" id="esp-regalo"[\s\S]*?<\/section>/, '').replace(/Te regalo clases en Tumbao|¿Es para regalar\?|Enviar como regalo por WhatsApp|Regala movimiento|Regalar una tiquetera|btn-regalo|esp-regalo|REGALO|regala|Regala/g, '');
  return !/obsequio|regalo/i.test(limpio(html)) && !/obsequio|regalo/i.test(limpio(mens));
})());

console.log(`\n${fallos ? '✗ ' + fallos + ' con problemas' : '✓ todo bien'}`);
process.exit(fallos ? 1 : 0);
