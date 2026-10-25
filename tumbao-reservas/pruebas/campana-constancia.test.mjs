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

titulo('1. La página de mensualidad y tiquetera');
ok('la campaña está configurada del 25 al 31 de octubre y se apaga sola', /CAMPANA: \{ activa: true, desde: '2026-10-25', hasta: '2026-10-31' \}/.test(mens) && /h >= c\.desde && h <= c\.hasta/.test(mens));
ok('el banner dice «clase adicional» por constancia', /Cumple todas tus clases y recibe una clase adicional/.test(mens) && /constancia y tu disciplina/.test(mens));
ok('cada tiquetera lleva su franja «+1»', /class="extra"><span class="mas">\+1<\/span>/.test(mens));
ok('hay un «cómo funciona» en tres pasos y las condiciones', /Así funciona la tiquetera/.test(mens) && /legal-campana/.test(mens) && /válida por 30 días/.test(mens));
const textoCampana = mens.slice(mens.indexOf('function pintarCampana'), mens.indexOf('function pintarEleccion'));
ok('la campaña no habla de premio, regalo, gratis ni promoción', !/(premio|regalo|gratis|promoci)/i.test(textoCampana));
ok('la mensualidad no se anuncia con la campaña (solo las tiqueteras)', !/tarjetaMensualidad = `[\s\S]{0,900}Completa tus/.test(mens));

titulo('2. Timba');
for (const [n, t] of [['ventas', INSTRUCCIONES_VENTAS], ['asistente', INSTRUCCIONES_ASISTENTE]]) {
  ok(`${n}: sabe la campaña, la dice como «clase adicional» y no como premio`, /CAMPAÑA DE CONSTANCIA \(del 25 al 31 de octubre\)/.test(t) && /UNA CLASE ADICIONAL/.test(t) && /NUNCA como premio, regalo, gratis ni promoción/.test(t));
  ok(`${n}: sabe por qué no aplica a mensualidad ni a clase suelta`, /mensualidad ya tiene una tarifa muy baja/.test(t) && /la persona decide cuándo reserva/.test(t));
  ok(`${n}: no promete nada distinto`, /NO prometas nada distinto/.test(t));
}

console.log(`\n${fallos ? '✗ ' + fallos + ' con problemas' : '✓ todo bien'}`);
process.exit(fallos ? 1 : 0);
