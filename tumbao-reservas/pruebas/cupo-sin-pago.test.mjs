/**
 * El cupo sin pago: se guarda 15 minutos, la página lo cuenta a la vista y lo
 * libera avisando.
 *
 * Damián (30 sep): «esa gente que nunca dijo que pagó nos está inflando las
 * reservas: guardarle 15 min el cupo y luego liberarlo; y que la página le
 * avise antes de cerrar o después de esos 15 min que no completó el proceso».
 *
 * Qué protege
 *   1. Quien aparta una suelta NO ve ningún reloj ni cuenta regresiva: los 15
 *      minutos son internos (1 oct: la gente creía que le esperábamos todo
 *      ese tiempo y no pagaba).
 *   2. Si intenta cerrar o recargar con el cupo guardado, el navegador le avisa.
 *   3. Cuando se acaba el tiempo la página lo dice, esconde el pago y ofrece
 *      reservar de nuevo (y sale el aviso de «ya pagué» por WhatsApp).
 *   4. Al pulsar «Ya pagué» el cupo deja de vencer: nada de avisos ni reloj.
 *   5. Si el servidor no mandara la hora, se usa el respaldo de 15 minutos.
 *   6. Al vencer con la pestaña en segundo plano (está en el banco), el título
 *      cambia y, si dio permiso, sale una notificación del navegador.
 *   7. Con un solo cupo, el pago dice «por 1 persona» y deja sumar a alguien.
 *
 * Usa el espejo del API (que ahora manda expira_en como el servidor real) y,
 * para no esperar 15 minutos de verdad, reescribe esa hora en la respuesta.
 *
 *   node pruebas/cupo-sin-pago.test.mjs
 */
import { chromium } from 'playwright-core';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { readFileSync } from 'node:fs';

const AQUI = dirname(fileURLToPath(import.meta.url));
const BASE = 'http://localhost:8899/';
const CHROME = process.env.CHROME_PATH || '/opt/pw-browsers/chromium-1194/chrome-linux/chrome';

let fallos = 0;
const ok = (n, c, extra = '') => { if (!c) fallos++;
  console.log(`${c ? '✓' : '✗'} ${n}${extra ? '  → ' + extra : ''}`); };
const titulo = t => console.log(`\n-- ${t} ${'-'.repeat(Math.max(0, 54 - t.length))}`);

const hijo = spawn(process.execPath, [join(AQUI, 'espejo-api.mjs')], { stdio: 'ignore' });
for (let i = 0; i < 100; i++) {
  try { await fetch(BASE); break; } catch { await new Promise(r => setTimeout(r, 100)); }
}
const nav = await chromium.launch({ executablePath: CHROME });

/* Abre la página y aparta una suelta hasta la pantalla de pago. `expira`:
   milisegundos de vida que tendrá el cupo (se reescribe la respuesta), o
   null para que el servidor no mande la hora. */
async function apartar(expira) {
  const ctx = await nav.newContext({ viewport: { width: 390, height: 844 }, locale: 'es-CO' });
  const p = await ctx.newPage();
  const errores = [];
  p.on('pageerror', e => errores.push(e.message));
  if (expira !== undefined) {
    await p.route('**/tumbao/reservar', async (ruta) => {
      const r = await ruta.fetch();
      const d = await r.json();
      if (expira === null) delete d.expira_en; else d.expira_en = new Date(Date.now() + expira).toISOString();
      await ruta.fulfill({ response: r, json: d });
    });
  }
  await p.goto(BASE, { waitUntil: 'networkidle' });
  await p.locator('.opcion[data-tipo="suelta"]').click();
  await p.waitForSelector('.clase:not(:disabled)', { timeout: 8000 });
  await p.locator('.clase:not(:disabled)').first().click();
  await p.waitForSelector('#s2.on', { timeout: 8000 });
  await p.fill('#nombre', 'Clienta Reloj');
  await p.fill('#celular', '3005550001');
  await p.check('#habeas');
  await p.locator('#enviar').click();
  await p.waitForSelector('#s3.on', { timeout: 8000 });
  return { p, ctx, errores };
}

// ¿Frenaría el navegador una salida? (lo que hace beforeunload)
const frena = (p) => p.evaluate(() => {
  const ev = new Event('beforeunload', { cancelable: true });
  window.dispatchEvent(ev);
  return ev.defaultPrevented;
});

titulo('1. No hay reloj a la vista');
{
  const { p, ctx, errores } = await apartar();           // el espejo manda 15 minutos
  ok('no existe el reloj en la página', (await p.locator('#cupo-reloj, #cupo-tiempo').count()) === 0);
  const texto = await p.locator('#s3').innerText();
  ok('la pantalla de pago no habla de minutos ni de «guardado por»',
     !/guardado por|\b15:00\b|minutos/i.test(texto), texto.replace(/\n/g, ' ').slice(0, 100));
  ok('pide pagar ahora, sin prometer espera', /Paga ahora/.test(await p.locator('#sub-pago').innerText()));
  ok('no está la pantalla de «venció»', await p.locator('#cupo-vencido').isHidden());
  ok('sin errores de JS', errores.length === 0, errores.join(' | '));
  await ctx.close();
}

titulo('2. Avisa antes de dejar salir');
{
  const { p, ctx } = await apartar();
  ok('con el cupo guardado, cerrar o recargar pide confirmación', await frena(p));
  await ctx.close();
}

titulo('3. Se acaba el tiempo');
{
  const { p, ctx, errores } = await apartar(2500);
  ok('antes de tiempo el pago se ve', await p.locator('#ya-pague').isVisible());
  await p.waitForSelector('#cupo-vencido:not([hidden])', { timeout: 8000 });
  const texto = await p.locator('#s3').innerText();
  ok('dice que la reserva venció', /Tu reserva venció/.test(texto), texto.replace(/\n/g, ' ').slice(0, 120));
  ok('dice que pasaron 15 minutos y que hay que volver a empezar', /más de 15 minutos/.test(texto) && /Vuelve a empezar/.test(texto));
  ok('dice que el cupo se liberó para otra persona', /liberamos el cupo/.test(texto));
  ok('ya no se puede pagar ese cupo: el botón y los datos se esconden',
     await p.locator('#ya-pague').isHidden() && await p.locator('.datos-pago').isHidden() && await p.locator('#pago-qr').isHidden());
  ok('el título de la pantalla cambia', /Tu reserva venció/.test(await p.locator('#t3').innerText()));
  ok('el título de la pestaña también avisa', /Tu reserva venció/.test(await p.title()), await p.title());
  ok('ya no frena la salida (no hay nada que perder)', !(await frena(p)));
  const wa = await p.locator('#cupo-wa').getAttribute('href');
  ok('si ya había pagado, tiene salida por WhatsApp con su código',
     /wa\.me\/573017833550/.test(wa) && /ya%20pagu/.test(wa), wa);
  await p.locator('#cupo-reservar-otra').click();
  await p.waitForSelector('#s0.on', { timeout: 5000 });
  ok('«Reservar de nuevo» vuelve al inicio', await p.locator('#s0.on').isVisible());
  ok('y limpia todo: título de la pestaña y aviso de salida',
     !/venció/.test(await p.title()) && !(await frena(p)));
  ok('sin errores de JS', errores.length === 0, errores.join(' | '));
  await ctx.close();
}

titulo('4. «Ya pagué» detiene el vencimiento');
{
  const { p, ctx, errores } = await apartar();
  await p.fill('#hora-transf', '12:00');
  await p.locator('#ya-pague').click();
  await p.waitForSelector('#s4.on', { timeout: 8000 });
  ok('pasa a «confirmando tu pago»', await p.locator('#s4.on').isVisible());
  ok('ya no vence sola (esa reserva espera al banco)', await p.locator('#cupo-vencido').isHidden());
  ok('y no avisa al salir', !(await frena(p)));
  ok('sin errores de JS', errores.length === 0, errores.join(' | '));
  await ctx.close();
}

titulo('5. Si el servidor no manda la hora, el respaldo es de 15 minutos');
{
  const { p, ctx } = await apartar(null);
  ok('con el servidor sin hora, la reserva sigue viva (no vence de inmediato)', await p.locator('#cupo-vencido').isHidden() && await p.locator('#ya-pague').isVisible());
  await ctx.close();
}

titulo('6. Vence con la pestaña en segundo plano');
{
  // Se simula una pestaña oculta y un permiso ya concedido, y se espía la
  // notificación (no hay forma de ver la real en un navegador de pruebas).
  const { p, ctx } = await apartar(2500);
  await p.evaluate(() => {
    window.__notis = [];
    Object.defineProperty(document, 'hidden', { configurable: true, get: () => true });
    window.Notification = function (t, o) { window.__notis.push({ t, o }); };
    window.Notification.permission = 'granted';
    window.Notification.requestPermission = () => {};
  });
  await p.waitForSelector('#cupo-vencido:not([hidden])', { timeout: 8000 });
  await p.waitForTimeout(300);
  const notis = await p.evaluate(() => window.__notis);
  ok('manda una notificación «Tu reserva venció»', notis.length === 1 && /venció/.test(notis[0].t), JSON.stringify(notis));
  ok('que dice que hay que volver a empezar', /Vuelve a empezar/.test((notis[0] || {}).o?.body || ''));
  ok('y el título de la pestaña lo avisa', /venció/.test(await p.title()), await p.title());
  await ctx.close();

  // Con la pestaña a la vista no se manda notificación: ya lo está viendo.
  const v = await apartar(2500);
  await v.p.evaluate(() => {
    window.__notis = [];
    window.Notification = function (t, o) { window.__notis.push({ t, o }); };
    window.Notification.permission = 'granted';
    window.Notification.requestPermission = () => {};
  });
  await v.p.waitForSelector('#cupo-vencido:not([hidden])', { timeout: 8000 });
  await v.p.waitForTimeout(300);
  ok('con la pestaña a la vista no hay notificación', (await v.p.evaluate(() => window.__notis.length)) === 0);
  await v.ctx.close();
}

titulo('7. El código de la página');
{
  const html = readFileSync(join(AQUI, '../../docs/index.html'), 'utf8');
  ok('el respaldo es de 15 minutos', /MINUTOS_CUPO:\s*15/.test(html));
  ok('usa la hora que manda el servidor', /arrancarCupo\(data\.expira_en\)/.test(html));
  ok('revisa al volver a la pestaña', /visibilitychange/.test(html));
  ok('no queda reloj ni cuenta regresiva en la página', !/cupo-reloj|cupo-tiempo|guardado por/.test(html));
  ok('la notificación se pide al reservar y se puede apagar', /pedirAvisoNavegador\(\)/.test(html) && /AVISO_NAVEGADOR:\s*true/.test(html));
  ok('hay service worker para mostrarla en celular', /sw-avisos\.js/.test(html) && /notificationclick/.test(readFileSync(join(AQUI, '../../docs/sw-avisos.js'), 'utf8')) && /showNotification/.test(html));
}

titulo('8. Un solo cupo: el pago dice que es por una persona y deja sumar a alguien');
{
  // Damián (1 oct): «escojo que voy con alguien y al momento del pago solo sale
  // 15 mil». El contador estaba al final del formulario y casi nadie lo veía.
  const { p, ctx, errores } = await apartar();
  ok('en el pago de un cupo sale el aviso «por 1 persona»',
     await p.locator('#pago-solo').isVisible() && /1 persona/.test(await p.locator('#pago-solo').innerText()));
  ok('el monto sigue siendo el de una clase', /15\.000/.test(await p.locator('#pago-monto').innerText()));
  await p.locator('#pago-agregar').click();
  await p.waitForSelector('#s2.on', { timeout: 5000 });
  ok('«Agregar otra persona» vuelve a los datos con 2 cupos', (await p.inputValue('#cuantos')) === '2');
  ok('aparece el campo del acompañante', await p.locator('#nombre-2').isVisible());
  ok('la cuenta dice 2 × $15.000 = $30.000', /30\.000/.test(await p.locator('#grupo-total').innerText()));
  ok('el reloj del cupo anterior se apagó', await p.locator('#cupo-reloj').isHidden());
  ok('sin errores de JavaScript', errores.length === 0, errores.join(' | '));
  await ctx.close();

  const html = readFileSync(join(AQUI, '../../docs/index.html'), 'utf8');
  const iCuantos = html.indexOf('id="caja-cuantos"');
  ok('el contador va arriba del todo, antes del nombre',
     iCuantos > 0 && iCuantos < html.indexOf('id="nombre"'));
  ok('el botón dice cuánto se paga («Reservar y pagar $…»)',
     /Reservar y pagar\$\{monto\}/.test(html) && !/'Apartar mi cupo y pagar'/.test(html));
  ok('el correo va plegado: no estorba', /<details class="mas-correo">/.test(html));
  ok('el resumen dice «por persona» con un solo cupo', /pesos\(elegida\.precio_cop\) \+ ' por persona'/.test(html));
  ok('con varios cupos el aviso no sale', /\$\('#pago-solo'\)\.hidden = g \|\| tipo !== 'suelta'/.test(html));
}

await nav.close();
hijo.kill();
console.log(fallos ? `\n${fallos} fallo(s)` : '\ntodo en verde');
process.exit(fallos ? 1 : 0);
