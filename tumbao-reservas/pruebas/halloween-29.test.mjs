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
ok('la franja pasó de Halloween a Navidad', /activo:\s+true/.test(franja) && /Navidad/.test(franja) && /clases de obsequio/.test(franja));
ok('la franja cuenta los días hasta Navidad y se apaga sola', /fecha:\s+'2026-12-24'/.test(franja) && /if \(dias < 0\) return;/.test(html));
ok('lleva directo a reservar una clase', /accion:\s+'suelta'/.test(franja) && /a\.accion === 'suelta'/.test(html));
ok('está arriba, antes de «¿Cómo vienes?»', html.indexOf('id="franja"') < html.indexOf('<h2 id="t0">'));
ok('no promete rebajas, regalos ni sorpresas', !/(descuento|rebaja|regalo|gratis|sorpresa|disfraz|2x1)/i.test(franja));

titulo('2. Timba');
ok('Halloween terminó: Timba ya no habla de la temporada (pasó a Navidad)', [INSTRUCCIONES_VENTAS, INSTRUCCIONES_ASISTENTE].every(t => !/TEMPORADA DE HALLOWEEN/.test(t) && /TEMPORADA DE NAVIDAD/.test(t)));

titulo('4. La página oscura de Halloween')
for (const [n, h] of [['index', html], ['mensualidad', mens]]) {
  ok(`${n}: la capa se enciende sola del 22 al 31 de octubre y se puede forzar o quitar`,
     /d>='2026-10-22'&&d<='2026-10-31'/.test(h) && /halloween=\(\\d\)/.test(h) && /html\.halloween\{/.test(h));
  ok(`${n}: respeta a quien pide menos movimiento`, /prefers-reduced-motion:reduce\)\{\s*html\.halloween \.franja\{animation:none/.test(h));
}

console.log(`\n${fallos ? '✗ ' + fallos + ' con problemas' : '✓ todo bien'}`);
process.exit(fallos ? 1 : 0);
