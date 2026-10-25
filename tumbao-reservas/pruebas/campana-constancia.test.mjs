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

titulo('1. La página de mensualidad y tiquetera (pases)');
ok('la campaña está configurada del 25 al 31 de octubre y se apaga sola', /CAMPANA: \{ activa: true, desde: '2026-10-25', hasta: '2026-10-31' \}/.test(mens) && /h >= c\.desde && h <= c\.hasta/.test(mens));
ok('cada tiquetera dice cuántas clases adicionales recibe (4 → 1, 8 → 2)', /EXTRA: \(clases\) => \(Number\(clases\) >= 8 \? 2 : 1\)/.test(mens) && /Completa tus \$\{clases\} clases y recibe <b>\$\{extraTxt\(clases\)\}<\/b> por tu constancia/.test(mens));
ok('la pregunta frecuente explica 1 con la de 4 y 2 con la de 8, para todas, nuevas o viejas',
   /<b>1 clase adicional<\/b> con la de 4 y <b>2 clases adicionales<\/b> con la de 8/.test(mens) && /Aplica a todas las tiqueteras, nuevas o ya compradas/.test(mens) && /valen 30 días/.test(mens));
const textoCampana = mens.slice(mens.indexOf('function listaDePases'), mens.indexOf('function pintarEleccion'));
ok('la campaña no habla de premio, regalo, gratis ni promoción', !/(premio|regalo|gratis|promoci)/i.test(textoCampana));
const mensPase = mens.slice(mens.indexOf("tipo: 'mensualidad'"), mens.indexOf('for (const p of [...tiqPaquetes]'));
ok('la mensualidad no se anuncia con la campaña (solo las tiqueteras)', !/extraTxt|constancia/.test(mensPase));

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
  ok(`${n}: sabe la campaña, la dice como «clase adicional» y no como premio`, /CAMPAÑA DE CONSTANCIA \(esta semana, hasta el 31 de octubre\)/.test(t) && /UNA clase adicional con la tiquetera de 4 clases y DOS clases adicionales con la de 8 clases/.test(t) && /Aplica a todas las tiqueteras, nuevas o ya compradas/.test(t) && /NUNCA como premio, gratis ni promoción/.test(t));
  ok(`${n}: sabe por qué no aplica a mensualidad ni a clase suelta`, /mensualidad ya tiene una tarifa muy baja/.test(t) && /la persona decide cuándo reserva/.test(t));
  ok(`${n}: no promete nada distinto`, /NO prometas nada distinto/.test(t));
}

console.log(`\n${fallos ? '✗ ' + fallos + ' con problemas' : '✓ todo bien'}`);
process.exit(fallos ? 1 : 0);
