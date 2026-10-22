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
ok('está encendida y habla de las clases de Halloween del 29', /activo:\s+true/.test(franja) && /Clases de Halloween/.test(franja) && /29 de octubre/.test(franja));
ok('se apaga sola pasado el día', /fecha:\s+'2026-10-29'/.test(franja) && /if \(dias < 0\) return;/.test(html));
ok('lleva directo a reservar una clase', /accion:\s+'suelta'/.test(franja) && /a\.accion === 'suelta'/.test(html));
ok('está arriba, antes de «¿Cómo vienes?»', html.indexOf('id="franja"') < html.indexOf('<h2 id="t0">'));
ok('no promete rebajas, regalos ni sorpresas', !/(descuento|rebaja|regalo|gratis|sorpresa|disfraz|2x1)/i.test(franja));

titulo('2. Timba');
ok('Timba de ventas sabe del 29 y no inventa detalles', /HALLOWEEN: el jueves 29 de octubre/.test(INSTRUCCIONES_VENTAS) && /NO inventes detalles \(disfraces, sorpresas, premios, descuentos/.test(INSTRUCCIONES_VENTAS));

titulo('3. Actitud de Halloween')
ok('Timba de ventas y el asistente hablan con la temporada, sin ofrecer nada',
   [INSTRUCCIONES_VENTAS, INSTRUCCIONES_ASISTENTE].every(t => /TEMPORADA DE HALLOWEEN \(hasta el 31 de octubre\)/.test(t) && /NO ofrezcas dulces, premios, descuentos ni regalos/.test(t)));
ok('con quien está de luto o molesta, solo calidez',
   [INSTRUCCIONES_VENTAS, INSTRUCCIONES_ASISTENTE].every(t => /NO uses ese tono con quien está de luto/.test(t)));

titulo('4. La página oscura de Halloween')
for (const [n, h] of [['index', html], ['mensualidad', mens]]) {
  ok(`${n}: la capa se enciende sola del 22 al 31 de octubre y se puede forzar o quitar`,
     /d>='2026-10-22'&&d<='2026-10-31'/.test(h) && /halloween=\(\\d\)/.test(h) && /html\.halloween\{/.test(h));
  ok(`${n}: respeta a quien pide menos movimiento`, /prefers-reduced-motion:reduce\)\{\s*html\.halloween \.franja\{animation:none/.test(h));
}

console.log(`\n${fallos ? '✗ ' + fallos + ' con problemas' : '✓ todo bien'}`);
process.exit(fallos ? 1 : 0);
