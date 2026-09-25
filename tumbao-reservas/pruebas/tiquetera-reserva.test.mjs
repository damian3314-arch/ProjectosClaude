/**
 * Reservar con tiquetera: sin pagar, con su propio saldo (0097).
 *
 * POR QUÉ EXISTE
 * Damián: «que las personas que compren tiquetera... puedan reservar sin
 * que se les cobre otra vez... pone una clave, y esa clase se descuenta
 * de las clases sueltas que están en venta para ese día».
 *
 * Tres cosas que no pueden fallar en la página pública:
 *
 *   1. Con un código válido, la reserva queda confirmada de una —sin
 *      pasar por la pantalla de pago— y la persona ve cuántas clases le
 *      quedan.
 *   2. Con un código inventado o ya sin saldo, la página no revienta: da
 *      el mismo trato que cualquier otro error de reserva, con el enlace
 *      de WhatsApp de siempre.
 *   3. El botón "Tengo tiquetera" no reintroduce el contador de "para
 *      cuántas personas" (eso es solo de clase suelta) ni pide pago.
 *
 * CÓMO
 * Con el espejo del API, que trae un código fijo de prueba (ABC123, con
 * 4 clases) para no depender de Supabase.
 *
 *   node tiquetera-reserva.test.mjs
 */
import { chromium } from 'playwright-core';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const AQUI = dirname(fileURLToPath(import.meta.url));
const BASE = 'http://localhost:8899/';
const CHROME = process.env.CHROME_PATH ||
  '/opt/pw-browsers/chromium-1194/chrome-linux/chrome';

let fallos = 0;
const ok = (n, c, extra = '') => { if (!c) fallos++;
  console.log(`${c ? '✓' : '✗'} ${n}${extra ? '  → ' + extra : ''}`); };
const titulo = t => console.log(`\n-- ${t} ${'-'.repeat(Math.max(0, 54 - t.length))}`);

const hijo = spawn(process.execPath, [join(AQUI, 'espejo-api.mjs')], { stdio: 'ignore' });
for (let i = 0; i < 100; i++) {
  try { await fetch(BASE); break; } catch { await new Promise(r => setTimeout(r, 100)); }
}

const nav = await chromium.launch({ executablePath: CHROME });

async function nuevaPagina() {
  const ctx = await nav.newContext({ viewport: { width: 390, height: 844 }, locale: 'es-CO' });
  const p = await ctx.newPage();
  const errores = [];
  p.on('pageerror', e => errores.push('pageerror: ' + e.message));
  await p.goto(BASE, { waitUntil: 'networkidle' });
  return { p, ctx, errores };
}

/* ═══════ 1 · código válido: reserva sin pagar, con el saldo ═══════ */

titulo('1. Código válido');
{
  const { p, ctx, errores } = await nuevaPagina();

  await p.locator('.opcion[data-tipo="tiquetera"]').click();
  ok('no pide pago: salta el chip de pago',
     await p.locator('#chip-pago').isHidden());

  await p.waitForSelector('.clase:not(:disabled)', { timeout: 8000 });
  ok('no reaparece el contador de "para cuántas personas"',
     await p.locator('#caja-cuantos').isHidden());
  await p.locator('.clase:not(:disabled)').first().click();
  await p.waitForSelector('#s2.on', { timeout: 8000 });

  ok('pide el código de la tiquetera',
     await p.locator('#caja-codigo-tiquetera').isVisible());

  await p.fill('#nombre', 'Clienta Tiquetera');
  await p.fill('#celular', '3002223344');
  await p.fill('#codigo-tiquetera', 'abc123'); // en minúscula, a propósito
  await p.check('#habeas');
  await p.locator('#enviar').click();

  await p.waitForSelector('#s5.on', { timeout: 8000 });
  const t = await p.locator('#t5').innerText();
  ok('dice "nos vemos en la pista", igual que cualquier confirmación',
     /nos vemos en la pista/i.test(t), t);

  const cuerpo = await p.locator('#s5').innerText();
  ok('dice cuántas clases le quedan', /3.*clase/i.test(cuerpo), cuerpo.replace(/\n/g, ' '));
  ok('sin ofrecer WhatsApp (salió bien)', !(await p.locator('#ok-wa').isVisible()));
  ok('con su código de reserva', /^[A-Z0-9]{4,8}$/.test(
     (await p.locator('#ok-codigo').innerText()).trim()));

  ok('sin errores de JS', errores.length === 0, errores.join(' | '));
  await ctx.close();
}

/* ═══════ 2 · el mismo código, otra vez: sigue descontando ═══════ */

titulo('2. El saldo baja de verdad con cada reserva');
{
  const { p, ctx, errores } = await nuevaPagina();
  await p.locator('.opcion[data-tipo="tiquetera"]').click();
  await p.waitForSelector('.clase:not(:disabled)', { timeout: 8000 });
  await p.locator('.clase:not(:disabled)').first().click();
  await p.waitForSelector('#s2.on', { timeout: 8000 });
  await p.fill('#nombre', 'Clienta Tiquetera');
  await p.fill('#celular', '3002223344');
  await p.fill('#codigo-tiquetera', 'ABC123');
  await p.check('#habeas');
  await p.locator('#enviar').click();
  await p.waitForSelector('#s5.on', { timeout: 8000 });

  const cuerpo = await p.locator('#s5').innerText();
  ok('la segunda clase deja 2, no otra vez 3',
     /2.*clase/i.test(cuerpo), cuerpo.replace(/\n/g, ' '));

  ok('sin errores de JS', errores.length === 0, errores.join(' | '));
  await ctx.close();
}

/* ═══════ 3 · código inventado: el mismo trato que cualquier error ═══ */

titulo('3. Código que no existe');
{
  const { p, ctx, errores } = await nuevaPagina();
  await p.locator('.opcion[data-tipo="tiquetera"]').click();
  await p.waitForSelector('.clase:not(:disabled)', { timeout: 8000 });
  await p.locator('.clase:not(:disabled)').first().click();
  await p.waitForSelector('#s2.on', { timeout: 8000 });
  await p.fill('#nombre', 'Nadie');
  await p.fill('#celular', '3009998877');
  await p.fill('#codigo-tiquetera', 'ZZZZZZ');
  await p.check('#habeas');
  await p.locator('#enviar').click();

  await p.waitForSelector('#err2 .aviso', { timeout: 8000 });
  const aviso = await p.locator('#err2').innerText();
  ok('avisa que el código no sirve', /código/i.test(aviso), aviso);
  ok('y deja el enlace de WhatsApp de siempre', /whatsapp/i.test(aviso), aviso);
  ok('sigue en la pantalla de datos, no se traga el error',
     await p.locator('#s2').evaluate(el => el.classList.contains('on')));

  ok('sin errores de JS', errores.length === 0, errores.join(' | '));
  await ctx.close();
}

/* ═══════ 4 · campo vacío: no deja mandar sin código ═══════ */

titulo('4. Sin escribir el código');
{
  const { p, ctx, errores } = await nuevaPagina();
  await p.locator('.opcion[data-tipo="tiquetera"]').click();
  await p.waitForSelector('.clase:not(:disabled)', { timeout: 8000 });
  await p.locator('.clase:not(:disabled)').first().click();
  await p.waitForSelector('#s2.on', { timeout: 8000 });
  await p.fill('#nombre', 'Sin Codigo');
  await p.fill('#celular', '3001112233');
  await p.check('#habeas');
  await p.locator('#enviar').click();

  ok('se queda en la pantalla de datos', await p.locator('#s2').evaluate(el => el.classList.contains('on')));
  ok('y marca el campo del código',
     await p.locator('#e-codigo-tiquetera').evaluate(el => el.classList.contains('on')));

  ok('sin errores de JS', errores.length === 0, errores.join(' | '));
  await ctx.close();
}

await nav.close();
hijo.kill('SIGTERM');
console.log(fallos ? `\n\x1b[31m${fallos} fallo(s)\x1b[0m`
                   : '\n\x1b[32mtodo en verde\x1b[0m');
process.exit(fallos ? 1 : 0);
