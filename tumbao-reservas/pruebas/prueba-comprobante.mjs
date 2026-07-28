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
  if (!a || a.hidden) return false;
  return /leído|no le encontramos|no pudimos leer|no parece una imagen/i.test(a.textContent);
}, { timeout: 30000 });

await irAPago();

// ───────── la zona existe y no estorba ─────────
ok('pide la hora de la transferencia', await p.locator('#hora-transf').isVisible());
ok('hay campo de referencia', await p.locator('#referencia').isVisible());
ok('ofrece leer el QR', await p.locator('#soltar').isVisible());
ok('dice que la imagen no se guarda',
   /no se sube ni se guarda/i.test(await p.locator('.pista.privacidad').innerText()));
ok('el campo de quien paga arranca escondido', await p.locator('#caja-pagador').isHidden());

// ───────── la hora es obligatoria ─────────
await p.locator('#ya-pague').click();
await p.waitForTimeout(300);
ok('sin hora no deja seguir', await p.locator('#s3').evaluate(e => e.classList.contains('on')));
ok('y lo dice', /hora que sale en tu comprobante/i.test(await p.locator('#e-hora').innerText()),
   await p.locator('#e-hora').innerText());

// ───────── pagó otra persona ─────────
await p.check('#otro-paga');
await p.waitForTimeout(200);
ok('al marcar que pagó otro, pide el nombre', await p.locator('#caja-pagador').isVisible());
await p.uncheck('#otro-paga');
await p.waitForTimeout(200);
ok('al desmarcar se vuelve a esconder', await p.locator('#caja-pagador').isHidden());

// ───────── subir algo que no es imagen ─────────
await p.locator('#archivo').setInputFiles({
  name: 'notas.txt', mimeType: 'text/plain', buffer: Buffer.from('no soy una imagen'),
});
await p.waitForTimeout(400);
ok('rechaza lo que no es imagen',
   /no parece una imagen/i.test(await p.locator('#aviso-qr').innerText()),
   await p.locator('#aviso-qr').innerText());

// ───────── leer el QR real ─────────
await p.locator('#archivo').setInputFiles(QR);
await esperarLectura();
const avisoQr = await p.locator('#aviso-qr').innerText();
ok('leyó el QR sin ningún servicio de IA', /leído/i.test(avisoQr), avisoQr);
ok('jsQR se cargó bajo demanda', await p.evaluate(() => typeof window.jsQR === 'function'));
ok('el input de archivo queda vacío: la imagen no se conserva',
   (await p.locator('#archivo').inputValue()) === '');

// ───────── lo que se manda al servidor ─────────
await p.locator('#archivo').setInputFiles(QR);
await esperarLectura();
await p.fill('#referencia', 'M25418019');
await p.fill('#hora-transf', '18:42');
await p.check('#otro-paga');
await p.fill('#pagador', 'Marta Rojas de Camila');
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
ok('NO se mandó ninguna imagen', !!enviado && !enviado.archivo,
   enviado && enviado.archivo ? 'llegó una imagen' : 'ninguna');
ok('llegó el nombre de quien pagó', enviado && enviado.pagador === 'Marta Rojas de Camila',
   enviado && enviado.pagador);
const h = enviado && enviado.pagado_en
  ? new Intl.DateTimeFormat('es-CO', { timeZone: 'America/Bogota', hour: '2-digit',
      minute: '2-digit', hour12: false }).format(new Date(enviado.pagado_en)) : null;
ok('la hora llegó como instante, en hora de Bogotá', h === '18:42', String(h));

// ───────── sin comprobante también funciona ─────────
await irAPago();
await p.fill('#hora-transf', '07:15');
await p.locator('#ya-pague').click();
await p.waitForSelector('#s4.on', { timeout: 10000 });
const sinNada = await p.evaluate(async () => {
  const r = await fetch('http://localhost:8899/_prueba/ultimo-comprobante');
  return (await r.json()).ultimo;
});
ok('sin QR ni referencia la reserva sigue avanzando, solo con la hora',
   !!sinNada && sinNada.referencia === null && sinNada.qr === null && !!sinNada.pagado_en);

// ───────── consola ─────────
console.log('');
const inesperados = errores.filter(e => !/40[0-9]|Conflict|Not Found/.test(e));
ok('sin errores de JavaScript inesperados', inesperados.length === 0,
   inesperados.join(' | ') || 'ninguno');

const dir = process.env.CAPTURAS || '/tmp';
await irAPago();
await p.fill('#hora-transf', '18:42');
await p.locator('#archivo').setInputFiles(QR);
await esperarLectura();
await p.waitForTimeout(400);
await p.screenshot({ path: `${dir}/p5-comprobante.png`, fullPage: true });

await nav.close();
console.log(`\n${fallos === 0 ? 'TODO EN VERDE' : fallos + ' FALLOS'}`);
process.exit(fallos ? 1 : 0);
