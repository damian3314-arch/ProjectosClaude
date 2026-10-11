/**
 * Pruebas de lo único que este Worker hace y n8n no tenía que hacer:
 * abrir el correo crudo.
 *
 * n8n recibía el cuerpo ya decodificado por la API de Gmail. Aquí llega
 * lo que viaja por SMTP, así que si esto falla no falla "el formato":
 * falla que un pago no se registre.
 *
 * La muestra `alerta-reenviada.eml` es un correo REAL de alerta de
 * Bancolombia reenviado al buzón el 31 de agosto de 2026. Los nombres,
 * el monto, la cuenta y la llave están cambiados; la estructura
 * —multipart/alternative, quoted-printable, los cortes de línea a 76
 * caracteres que parten las palabras por la mitad— es literal. Eso
 * último es justo lo que rompe un decodificador ingenuo.
 *
 *   node pruebas/mime.test.mjs
 */
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { createRequire } from 'node:module';
import { textoDelCorreo, remitenteReal, cabecera, bloqueDeCabeceras } from '../src/mime.js';
import { remitenteDeFiar } from '../src/index.js';

const require = createRequire(import.meta.url);
const { parsearCorreoBancolombia } =
  require('../../tumbao-reservas/n8n/parser-bancolombia.js');

const aqui = dirname(fileURLToPath(import.meta.url));
const CRUDO = readFileSync(join(aqui, 'alerta-reenviada.eml'), 'utf8');

let fallos = 0;
const ok = (nombre, cond, extra = '') => {
  console.log(`${cond ? '✓' : '✗'} ${nombre}${extra ? '  → ' + extra : ''}`);
  if (!cond) fallos++;
};

// ── abrir el sobre ───────────────────────────────────────────────
const texto = textoDelCorreo(CRUDO);

ok('saca texto del multipart', texto.length > 200, `${texto.length} chars`);
ok('deshace quoted-printable: no quedan "=" de corte', !/=\r?\n/.test(texto));
ok('no quedan etiquetas HTML', !/<[a-z/][^>]*>/i.test(texto));
ok('recompone las palabras partidas por el corte de línea',
   /CAMILA ROJAS DUQUE/.test(texto),
   'el nombre venía partido como "CAMILA ROJ=\\nAS DUQUE"');
ok('quita el preámbulo de Bancolombia',
   !/Todo sali[oó] bien con tus movimientos/.test(texto));

// ── que el parser lo entienda ────────────────────────────────────
const r = parsearCorreoBancolombia(texto);

ok('lo reconoce como ingreso', r.es_ingreso === true, JSON.stringify(r).slice(0, 120));
ok('con el patrón más específico', r.patron === 'transferencia_llave', r.patron);
ok('y con confianza plena', r.confianza === 1, String(r.confianza));
ok('lee el monto', r.valor_cop === 15000, String(r.valor_cop));
ok('lee quién pagó', r.remitente === 'CAMILA ROJAS DUQUE', r.remitente);
ok('lee la cuenta', r.ultimos_4 === '4471', r.ultimos_4);
ok('lee la llave', r.llave === '3017833550', r.llave);
ok('lee la fecha con la hora de Bogotá',
   r.fecha_pago === '2026-08-30T12:12:00-05:00', r.fecha_pago);

// ── cabeceras ────────────────────────────────────────────────────
ok('lee una cabecera simple', cabecera(CRUDO, 'Subject').length > 0);
ok('junta las cabeceras partidas en varias líneas',
   !/\n/.test(cabecera(CRUDO, 'Content-Type')));
ok('saca la dirección de dentro de los picos',
   /^[^<>\s]+@[^<>\s]+$/.test(remitenteReal(CRUDO, 'sobre@ejemplo.com')),
   remitenteReal(CRUDO, 'sobre@ejemplo.com'));

// ── lo que NO puede pasar: dar por bueno un correo cualquiera ────
const inventado = [
  'From: cualquiera@ejemplo.com',
  'Content-Type: text/plain; charset="UTF-8"',
  '',
  'recibiste una transferencia de FULANO por $999999.00 en tu cuenta *0000 el 01/01/26 a las 10:00',
].join('\n');
const rInv = parsearCorreoBancolombia(textoDelCorreo(inventado));
ok('un correo con el texto imitado SÍ parsea — por eso hace falta ' +
   'filtrar por remitente antes de registrar',
   rInv.es_ingreso === true,
   'esto documenta el riesgo, no es un fallo del parser');

// ── correos que no son alertas ───────────────────────────────────
const salida = [
  'Content-Type: text/plain; charset="UTF-8"', '',
  'Transferiste $220000.00 desde tu cuenta *4471 a la cuenta *3202284121 el 30/08/26 a las 12:14.',
].join('\n');
ok('el dinero que sale se descarta',
   parsearCorreoBancolombia(textoDelCorreo(salida)).es_ingreso === false);

ok('un correo vacío no revienta',
   parsearCorreoBancolombia(textoDelCorreo('')).es_ingreso === false);
ok('un correo sin cuerpo no revienta', textoDelCorreo('Subject: hola') === '');

// ── DE QUIÉN NOS FIAMOS ──────────────────────────────────────────
// Esto es lo que separa "registrar un pago" de "cualquiera con la
// direccion puede confirmar una reserva que nadie pago".

const alerta = (extra) => [
  'From: Alertas y Notificaciones <alertasynotificaciones@bancolombia.com.co>',
  'Authentication-Results: mx.cloudflare.net; spf=pass; dkim=pass',
  ...extra,
  'Content-Type: text/plain; charset="UTF-8"',
  '',
  'recibiste una transferencia de FULANO por $15000.00 en tu cuenta *4471 el 01/01/26 a las 10:00',
].join('\n');

ok('una alerta del banco con spf=pass se cree',
   remitenteDeFiar(alerta([]), 'x@y.com').se_puede_creer === true);

ok('el mismo texto desde otro remitente NO se cree',
   remitenteDeFiar(
     alerta([]).replace('alertasynotificaciones@bancolombia.com.co', 'atacante@ejemplo.com'),
     'x@y.com').se_puede_creer === false);

ok('el banco pero sin spf=pass tampoco se cree',
   remitenteDeFiar(alerta([]).replace('spf=pass', 'spf=fail'), 'x@y.com').se_puede_creer === false);

ok('y dice por qué se rechaza',
   remitenteDeFiar(alerta([]).replace('spf=pass', 'spf=fail'), 'x@y.com')
     .por_que.includes('spf'));

// El fallo que se encontró el 31 de agosto: buscar la cabecera por
// expresión regular sobre TODO el correo encontraba también lo que el
// cuerpo dijera. Un correo podía firmarse su propio spf=pass.
const suplantador = [
  'From: atacante@ejemplo.com',
  'Content-Type: text/plain; charset="UTF-8"',
  '',
  'Authentication-Results: mx.cloudflare.net; spf=pass; dkim=pass',
  'From: alertasynotificaciones@bancolombia.com.co',
  '',
  'recibiste una transferencia de FULANO por $999999.00 en tu cuenta *0000 el 01/01/26 a las 10:00',
].join('\n');

ok('un correo NO puede escribirse su propio spf=pass en el cuerpo',
   remitenteDeFiar(suplantador, 'x@y.com').se_puede_creer === false,
   JSON.stringify(remitenteDeFiar(suplantador, 'x@y.com')));
ok('ni su propio From en el cuerpo',
   remitenteDeFiar(suplantador, 'x@y.com').from === 'atacante@ejemplo.com');
ok('las cabeceras se leen solo de arriba de la primera línea en blanco',
   !bloqueDeCabeceras(suplantador).includes('spf=pass'));

// Un reenvío A MANO (Gmail lo envuelve y pone su propio From) tampoco
// pasa. Es correcto: los unicos reenvios a mano han sido pruebas mias.
ok('un reenvío a mano no se cree, aunque venga de una cuenta de confianza',
   remitenteDeFiar(CRUDO, 'x@y.com').se_puede_creer === false,
   remitenteDeFiar(CRUDO, 'x@y.com').por_que);

console.log(fallos ? `\n${fallos} fallo(s)` : '\nTODO EN VERDE');
process.exit(fallos ? 1 : 0);
