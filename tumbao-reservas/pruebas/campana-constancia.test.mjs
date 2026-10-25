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
ok('el banner dice 1 clase adicional con la de 4 y 2 con la de 8, por constancia', /Cumple todas tus clases y recibe clases adicionales/.test(mens) && /<b>1 clase adicional<\/b> y con la de 8\s+clases recibes <b>2 clases adicionales<\/b>/.test(mens) && /constancia y tu disciplina/.test(mens));
ok('cada tiquetera dice cuántas clases adicionales recibe (4 → 1, 8 → 2)', /EXTRA: \(clases\) => \(Number\(clases\) >= 8 \? 2 : 1\)/.test(mens) && /class="extra">Completa tus <b>\$\{clases\} clases<\/b>/.test(mens));
ok('aplica a todas las tiqueteras, nuevas o viejas', /Aplica a todas las tiqueteras, nuevas o ya compradas/.test(mens));
ok('hay un «cómo funciona» en tres pasos y las condiciones', /Así funciona la tiquetera/.test(mens) && /legal-campana/.test(mens) && /Valen 30 días/.test(mens));
const textoCampana = mens.slice(mens.indexOf('function pintarCampana'), mens.indexOf('function pintarEleccion'));
ok('la campaña no habla de premio, regalo, gratis ni promoción', !/(premio|regalo|gratis|promoci)/i.test(textoCampana));
ok('la mensualidad no se anuncia con la campaña (solo las tiqueteras)', !/tarjetaMensualidad = `[\s\S]{0,900}Completa tus/.test(mens));

titulo('2. Timba');
for (const [n, t] of [['ventas', INSTRUCCIONES_VENTAS], ['asistente', INSTRUCCIONES_ASISTENTE]]) {
  ok(`${n}: sabe la campaña, la dice como «clase adicional» y no como premio`, /CAMPAÑA DE CONSTANCIA \(esta semana, hasta el 31 de octubre\)/.test(t) && /UNA clase adicional con la tiquetera de 4 clases y DOS clases adicionales con la de 8 clases/.test(t) && /Aplica a todas las tiqueteras, nuevas o ya compradas/.test(t) && /NUNCA como premio, gratis ni promoción/.test(t));
  ok(`${n}: sabe por qué no aplica a mensualidad ni a clase suelta`, /mensualidad ya tiene una tarifa muy baja/.test(t) && /la persona decide cuándo reserva/.test(t));
  ok(`${n}: no promete nada distinto`, /NO prometas nada distinto/.test(t));
}

console.log(`\n${fallos ? '✗ ' + fallos + ' con problemas' : '✓ todo bien'}`);
process.exit(fallos ? 1 : 0);
