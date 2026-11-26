/** Quien dice que pagó y no ha enviado el comprobante: Timba le explica con amabilidad (26 nov, Damián). node espera-de-comprobante.test.mjs */
import { readFileSync } from 'node:fs';
const leer = (r) => readFileSync(new URL(r, import.meta.url), 'utf8');
const pago = leer('../../tumbao-caja/src/pago.js');
const asis = leer('../../tumbao-caja/src/asistente.js');
let fallos = 0;
const ok = (n, c) => { if (!c) fallos++; console.log(`${c ? '✓' : '✗'} ${n}`); };
ok('si dice que pagó y no mandó el comprobante: su clase está en espera de validación, lo debe enviar al número de recepción para que lo confirmen, y si no, no se garantiza el cupo (pago por WhatsApp)',
   /Si NO la ha enviado[\s\S]{0,200}en espera de validación[\s\S]{0,300}\$\{WHATSAPP_EQUIPO\}[\s\S]{0,200}quede confirmada[\s\S]{0,120}no se puede garantizar el cupo/.test(pago));
ok('lo dice con amabilidad y sin pedirlo otra vez a quien ya lo mandó', /sin regaños/.test(pago) && /no se lo pidas otra vez/.test(pago));
ok('lo mismo en el asistente general (quien escribe «ya reservé/pagué»)',
   /NO ha mandado el comprobante[\s\S]{0,300}en espera de validación[\s\S]{0,200}301 783 3550[\s\S]{0,200}no se puede garantizar el cupo/.test(asis));
ok('no afirma que esté confirmada ni promete que alguien le escribirá', /sin decir que ya está confirmada/.test(asis) && !/te escribimos/.test(asis.split('REGLAS DURAS')[0].split('7. Si ya tiene')[1] || ''));
console.log(`\n${fallos ? '✗ ' + fallos + ' con problemas' : '✓ todo bien'}`);
process.exit(fallos ? 1 : 0);
