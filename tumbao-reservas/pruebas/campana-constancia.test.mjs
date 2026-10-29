/**
 * Campaña de constancia (25 al 31 oct): quien compra una tiquetera esta semana y cumple todas sus clases recibe una clase
 * adicional. La página lo dice, Timba lo sabe y nadie lo llama premio, regalo ni promoción.
 *
 *   node campana-constancia.test.mjs
 */
import { readFileSync } from 'node:fs';
import { INSTRUCCIONES_VENTAS } from '../../tumbao-caja/src/ventas.js';
import { INSTRUCCIONES_ASISTENTE } from '../../tumbao-caja/src/asistente.js';

let fallos = 0;
const ok = (n, c, extra = '') => { if (!c) fallos++; console.log(`${c ? '✓' : '✗'} ${n}${extra ? '  → ' + extra : ''}`); };
const titulo = t => console.log(`\n-- ${t} ${'-'.repeat(Math.max(0, 54 - t.length))}`);
const mens = readFileSync(new URL('../../docs/mensualidad.html', import.meta.url), 'utf8');

titulo('1. La clase adicional por constancia se desmontó (26 oct, la dueña no la aprobó)');
ok('la página no menciona clases adicionales, extra ni constancia', !/(clase[s]? adicional|clases? extra|constancia)/i.test(mens.replace(/\/\/ 26 oct:.*\n/, '')));
ok('ya no existe la configuración de la campaña', !/CAMPANA:|EXTRA:|campanaActiva|extraTxt/.test(mens));

titulo('1b. Los pases');
ok('la mensualidad va primero y cada producto es un pase con su botón', mens.indexOf("tipo: 'mensualidad'") < mens.indexOf('for (const p of [...tiqPaquetes]') && /class="pase /.test(mens) && /id="btn-pase" data-elegir=/.test(mens));
ok('el botón del pase sigue llevando al flujo de siempre (mensualidad o tiquetera)', /elegirTiqueteraDirecta\(p\.clave\)/.test(mens) && /\$\('#pasos'\)\.hidden = false/.test(mens));
ok('el botón de comprar va pegado a los pases, antes de lo que incluye', mens.indexOf('id="cta-pase"') > mens.indexOf('id="tarjetas-eleccion"') && mens.indexOf('id="cta-pase"') < mens.indexOf('id="detalle"'));
ok('tocar el pase elegido arranca la compra', /if \(i === paseActivo\) \{ comprarPase\(pasesActuales\[i\]\); return; \}/.test(mens));
ok('hay preguntas frecuentes y el enlace a WhatsApp para más dudas', /Preguntas frecuentes/.test(mens) && /¿Tengo más dudas\?/.test(mens));
ok('orden: mensualidad, la de 8 y luego la de 4 (Damián, 25 oct)', /sort\(\(a, b\) => Number\(b\.clases\) - Number\(a\.clases\)\)/.test(mens));
ok('sin la palabra «Elegido» en los pases', !/>Elegido</.test(mens));
ok('cada pase lleva su foto de gente bailando (CONFIG.FOTOS)', /FOTOS: \{ mensualidad: 'img\/pase-mensualidad\.jpg', '4': 'img\/pase-4\.jpg', '8': 'img\/pase-8\.jpg' \}/.test(mens));
ok('el movimiento respeta a quien pide menos movimiento', /prefers-reduced-motion:reduce\)\{\s*\.pase,\.puntos-pager i,\.detalle \.det\{transition:none\}/.test(mens));

titulo('2. Timba');
for (const [n, t] of [['ventas', INSTRUCCIONES_VENTAS], ['asistente', INSTRUCCIONES_ASISTENTE]]) {
  ok(`${n}: ya no habla de la campaña de constancia`, !/CAMPAÑA DE CONSTANCIA/.test(t));
  ok(`${n}: sabe que NO existe clase extra por completar clases y no la menciona`, /NO EXISTE ninguna clase extra, adicional, de regalo ni pase por completar las clases de una tiquetera/.test(t) && /No lo menciones nunca/.test(t));
}

console.log(`\n${fallos ? '✗ ' + fallos + ' con problemas' : '✓ todo bien'}`);
process.exit(fallos ? 1 : 0);
