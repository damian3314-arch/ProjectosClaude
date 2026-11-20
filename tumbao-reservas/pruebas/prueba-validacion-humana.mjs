/**
 * El camino que se activa cuando el correo del banco no llega: pasados
 * los minutos de espera la reserva queda en validación humana y la
 * página tiene que decirlo claro, sin dejar a la persona colgada.
 *
 * Requiere el espejo con el pago desactivado y la espera acortada:
 *   NUNCA_LLEGA=1 MINUTOS_ESPERA=0.15 node pruebas/espejo-api.mjs
 */
import { chromium } from 'playwright-core';

const BASE = 'http://localhost:8899/';
const CHROME = process.env.CHROME_PATH || '/opt/pw-browsers/chromium-1194/chrome-linux/chrome';
let fallos = 0;
const ok = (n, c, extra = '') => {
  console.log(`${c ? '✓' : '✗'} ${n}${extra ? '  → ' + extra : ''}`);
  if (!c) fallos++;
};

// El espejo guarda estado en memoria y estas suites reservan y marcan.
// Sin volver al principio, correr dos seguidas hace fallar a la segunda
// por los restos de la primera, y el fallo no se parece a su causa.
await fetch('http://localhost:8899/_prueba/reiniciar').catch(() => {});

const nav = await chromium.launch({ executablePath: CHROME });
const ctx = await nav.newContext({ viewport: { width: 390, height: 844 }, locale: 'es-CO' });
const p = await ctx.newPage();
const errores = [];
p.on('console', m => { if (m.type() === 'error') errores.push(m.text()); });
p.on('pageerror', e => errores.push('pageerror: ' + e.message));

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
await p.fill('#hora-transf', '18:42');
await p.locator('#ya-pague').click();
await p.waitForSelector('#s4.on', { timeout: 8000 });
ok('entra a la espera', true);

// La espera está acortada, pero la barra tiene que llegar al final sola.
await p.waitForSelector('#s5.on', { timeout: 30000 });
ok('sale de la espera sin quedarse colgada', true);

const titulo = await p.locator('#t5').innerText();
const cuerpo = await p.locator('#s5').innerText();
ok('no dice que el pago fue confirmado',
   !titulo.toLowerCase().includes('confirmado'), titulo);
// Aqui la persona tiene algo QUE HACER. "Te escribimos" la deja
// esperando; lo que resuelve el caso es que mande el soporte.
ok('le pide el soporte, no la deja esperando',
   /soporte/i.test(cuerpo) && /whatsapp/i.test(cuerpo), cuerpo.replace(/\n/g, ' '));
ok('y le deja el botón con el mensaje ya escrito',
   /soporte/i.test(await p.locator('#ok-wa').innerText()),
   (await p.locator('#ok-wa').innerText()).trim());
ok('el enlace de WhatsApp lleva el código',
   decodeURIComponent(await p.locator('#ok-wa').getAttribute('href')).includes('soporte'));
ok('dice que el cupo sigue apartado', /cupo sigue apartado/i.test(cuerpo));
ok('conserva el código de la reserva',
   /^[A-Z0-9]{4,8}$/.test((await p.locator('#ok-codigo').innerText()).trim()),
   (await p.locator('#ok-codigo').innerText()).trim());

const inesperados = errores.filter(e => !/40[0-9]|Conflict|Not Found/.test(e));
ok('sin errores de JavaScript inesperados', inesperados.length === 0, inesperados.join(' | ') || 'ninguno');

const dir = process.env.CAPTURAS || '/tmp';
await p.screenshot({ path: `${dir}/p4-validacion-humana.png`, fullPage: true });

await nav.close();
console.log(`\n${fallos === 0 ? 'TODO EN VERDE' : fallos + ' FALLOS'}`);
process.exit(fallos ? 1 : 0);
