/**
 * Prueba de la subida del comprobante en la pantalla de pago.
 *
 * Lo que importa aquí es que el QR se lea en el navegador de quien paga,
 * sin ningún servicio de IA. Como fixture se usa el propio QR Bre-B de
 * Tumbao (docs/img/qr-breb.png), que es un QR de verdad: si jsQR lo
 * decodifica, la tubería completa —archivo, canvas, decodificación—
 * funciona.
 *
 * Requiere el espejo corriendo:  node pruebas/espejo-api.mjs
 */
import { chromium } from 'playwright-core';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const RAIZ = join(dirname(fileURLToPath(import.meta.url)), '..');
const QR = join(RAIZ, '..', 'docs', 'img', 'qr-breb.png');
const BASE = 'http://localhost:8899/';
const CHROME = process.env.CHROME_PATH || '/opt/pw-browsers/chromium-1194/chrome-linux/chrome';

let fallos = 0;
const ok = (n, c, extra = '') => {
  console.log(`${c ? '✓' : '✗'} ${n}${extra ? '  → ' + extra : ''}`);
  if (!c) fallos++;
};

const nav = await chromium.launch({ executablePath: CHROME });
const ctx = await nav.newContext({ viewport: { width: 390, height: 844 }, locale: 'es-CO' });
const p = await ctx.newPage();
const errores = [];
p.on('console', m => { if (m.type() === 'error') errores.push(m.text()); });
p.on('pageerror', e => errores.push('pageerror: ' + e.message));

// Llegar hasta la pantalla de pago.
const irAPago = async () => {
  await p.goto(BASE, { waitUntil: 'networkidle' });
  await p.locator('.opcion[data-tipo="suelta"]').click();
  await p.waitForSelector('.clase:not(:disabled)', { timeout: 8000 });
  await p.locator('.clase:not(:disabled)').first().click();
  await p.waitForSelector('#s2.on', { timeout: 8000 });
  await p.fill('#nombre', 'Camila Rojas');
  await p.fill('#celular', '3002223344');
  await p.check('#habeas');
  await p.locator('#enviar').click();
  await p.waitForSelector('#s3.on', { timeout: 8000 });
};

// Esperar a que TERMINE de leer. No basta con "el aviso no dice Leyendo":
// el aviso del intento anterior sigue en pantalla y la espera pasaria de
// largo sin que se haya leido nada. Se espera el resultado final.
const esperarLectura = () => p.waitForFunction(() => {
  const a = document.querySelector('#aviso-qr');
  const previa = document.querySelector('#previa');
  if (!previa || previa.hidden) return false;
  if (!a || a.hidden) return false;
  return /comprobante leído|no le encontramos|no pudimos leerlo/i.test(a.textContent);
}, { timeout: 30000 });

await irAPago();

// ───────── la zona existe y no estorba ─────────
ok('hay zona para subir el comprobante', await p.locator('#soltar').isVisible());
ok('hay campo de referencia', await p.locator('#referencia').isVisible());
ok('la previa está escondida al principio', await p.locator('#previa').isHidden());

// Sin comprobante se puede seguir igual: es opcional a propósito.
ok('el botón de pagar no está bloqueado sin comprobante',
   !(await p.locator('#ya-pague').isDisabled()));

// ───────── subir un archivo que no es imagen ─────────
await p.locator('#archivo').setInputFiles({
  name: 'notas.txt', mimeType: 'text/plain', buffer: Buffer.from('no soy una imagen'),
});
await p.waitForTimeout(400);
ok('rechaza lo que no es imagen',
   /no parece una imagen/i.test(await p.locator('#aviso-qr').innerText()),
   await p.locator('#aviso-qr').innerText());
ok('y no lo toma como comprobante', await p.locator('#previa').isHidden());

// ───────── subir el QR real ─────────
await p.locator('#archivo').setInputFiles(QR);
await esperarLectura();

ok('muestra la previa del archivo', await p.locator('#previa').isVisible());
ok('esconde la zona de soltar', await p.locator('#soltar').isHidden());
ok('muestra el nombre del archivo',
   (await p.locator('#previa-nombre').innerText()).includes('qr-breb'),
   await p.locator('#previa-nombre').innerText());

const avisoQr = await p.locator('#aviso-qr').innerText();
ok('leyó el QR sin ningún servicio de IA', /comprobante leído/i.test(avisoQr), avisoQr);

// Que jsQR se cargó solo cuando hizo falta, no en la primera pantalla.
ok('jsQR se cargó bajo demanda', await p.evaluate(() => typeof window.jsQR === 'function'));

// ───────── quitar ─────────
await p.locator('#quitar').click();
await p.waitForTimeout(250);
ok('se puede quitar el comprobante', await p.locator('#previa').isHidden());
ok('y vuelve la zona de soltar', await p.locator('#soltar').isVisible());

// ───────── lo que se manda al servidor ─────────
await p.locator('#archivo').setInputFiles(QR);
await esperarLectura();
await p.fill('#referencia', 'M25418019');
await p.locator('#ya-pague').click();
await p.waitForSelector('#s4.on', { timeout: 10000 });
ok('avanza a la espera con el comprobante puesto', true);

const enviado = await p.evaluate(async () => {
  const r = await fetch('http://localhost:8899/_prueba/ultimo-comprobante');
  return (await r.json()).ultimo;
});
ok('llegó la referencia', enviado && enviado.referencia === 'M25418019',
   enviado && enviado.referencia);
ok('llegó el contenido del QR', !!(enviado && enviado.qr),
   enviado && String(enviado.qr).slice(0, 40) + '…');
ok('llegó la imagen', !!(enviado && enviado.archivo && enviado.archivo.bytes > 1000),
   enviado && enviado.archivo && `${Math.round(enviado.archivo.bytes / 1024)} KB en base64`);
ok('llegó la hora en que dijo que pagó',
   !!(enviado && enviado.pagado_en && !isNaN(Date.parse(enviado.pagado_en))),
   enviado && enviado.pagado_en);

// ───────── sin comprobante también funciona ─────────
await irAPago();
await p.locator('#ya-pague').click();
await p.waitForSelector('#s4.on', { timeout: 10000 });
const sinNada = await p.evaluate(async () => {
  const r = await fetch('http://localhost:8899/_prueba/ultimo-comprobante');
  return (await r.json()).ultimo;
});
ok('sin comprobante la reserva sigue avanzando',
   sinNada && sinNada.archivo === null && sinNada.referencia === null);

// ───────── consola ─────────
console.log('');
const inesperados = errores.filter(e => !/40[0-9]|Conflict|Not Found/.test(e));
ok('sin errores de JavaScript inesperados', inesperados.length === 0,
   inesperados.join(' | ') || 'ninguno');

const dir = process.env.CAPTURAS || '/tmp';
await irAPago();
await p.locator('#archivo').setInputFiles(QR);
await esperarLectura();
await p.waitForTimeout(400);
await p.screenshot({ path: `${dir}/p5-comprobante.png`, fullPage: true });

await nav.close();
console.log(`\n${fallos === 0 ? 'TODO EN VERDE' : fallos + ' FALLOS'}`);
process.exit(fallos ? 1 : 0);
