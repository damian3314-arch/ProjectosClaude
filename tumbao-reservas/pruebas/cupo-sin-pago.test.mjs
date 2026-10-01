/**
 * El cupo sin pago: se guarda 15 minutos, la página lo cuenta a la vista y lo
 * libera avisando.
 *
 * Damián (30 sep): «esa gente que nunca dijo que pagó nos está inflando las
 * reservas: guardarle 15 min el cupo y luego liberarlo; y que la página le
 * avise antes de cerrar o después de esos 15 min que no completó el proceso».
 *
 * Qué protege
 *   1. Quien aparta una suelta ve un reloj con el tiempo que le queda.
 *   2. Si intenta cerrar o recargar con el cupo guardado, el navegador le avisa.
 *   3. Cuando se acaba el tiempo la página lo dice, esconde el pago y ofrece
 *      reservar de nuevo (y sale el aviso de «ya pagué» por WhatsApp).
 *   4. Al pulsar «Ya pagué» el cupo deja de vencer: nada de avisos ni reloj.
 *   5. Si el servidor no mandara la hora, se usa el respaldo de 15 minutos.
 *   6. En los últimos 3 minutos el reloj se pone en alerta.
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

titulo('1. El reloj se ve y cuenta');
{
  const { p, ctx, errores } = await apartar();           // el espejo manda 15 minutos
  ok('el reloj está a la vista', await p.locator('#cupo-reloj').isVisible());
  const t = (await p.locator('#cupo-tiempo').innerText()).trim();
  ok('arranca cerca de 15:00', /^1[45]:\d\d$/.test(t), t);
  ok('dice que el cupo se libera si no paga',
     /se libera para otra persona/.test(await p.locator('#cupo-reloj').innerText()));
  await p.waitForTimeout(2200);
  const t2 = (await p.locator('#cupo-tiempo').innerText()).trim();
  ok('el tiempo baja solo', t2 !== t, `${t} → ${t2}`);
  ok('todavía no está en alerta', !(await p.locator('#cupo-reloj.urgente').count()));
  ok('no está la pantalla de «se acabó»', await p.locator('#cupo-vencido').isHidden());
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
  ok('dice que se acabó el tiempo', /Se acabó el tiempo/.test(texto), texto.replace(/\n/g, ' ').slice(0, 120));
  ok('dice que el cupo se liberó para otra persona', /Liberamos tu cupo/.test(texto));
  ok('el reloj desaparece', await p.locator('#cupo-reloj').isHidden());
  ok('ya no se puede pagar ese cupo: el botón y los datos se esconden',
     await p.locator('#ya-pague').isHidden() && await p.locator('.datos-pago').isHidden() && await p.locator('#pago-qr').isHidden());
  ok('el título cambia', /Se liberó tu cupo/.test(await p.locator('#t3').innerText()));
  ok('ya no frena la salida (no hay nada que perder)', !(await frena(p)));
  const wa = await p.locator('#cupo-wa').getAttribute('href');
  ok('si ya había pagado, tiene salida por WhatsApp con su código',
     /wa\.me\/573017833550/.test(wa) && /ya%20pagu/.test(wa), wa);
  await p.locator('#cupo-reservar-otra').click();
  await p.waitForSelector('#s0.on', { timeout: 5000 });
  ok('«Reservar de nuevo» vuelve al inicio', await p.locator('#s0.on').isVisible());
  ok('y limpia todo: sin reloj ni aviso de salida',
     await p.locator('#cupo-reloj').isHidden() && !(await frena(p)));
  ok('sin errores de JS', errores.length === 0, errores.join(' | '));
  await ctx.close();
}

titulo('4. «Ya pagué» detiene el reloj');
{
  const { p, ctx, errores } = await apartar();
  await p.fill('#hora-transf', '12:00');
  await p.locator('#ya-pague').click();
  await p.waitForSelector('#s4.on', { timeout: 8000 });
  ok('pasa a «confirmando tu pago»', await p.locator('#s4.on').isVisible());
  ok('el reloj no sigue (esa reserva ya no vence sola)', await p.locator('#cupo-reloj').isHidden());
  ok('y no avisa al salir', !(await frena(p)));
  ok('sin errores de JS', errores.length === 0, errores.join(' | '));
  await ctx.close();
}

titulo('5. Si el servidor no manda la hora, el respaldo es de 15 minutos');
{
  const { p, ctx } = await apartar(null);
  const t = (await p.locator('#cupo-tiempo').innerText()).trim();
  ok('arranca cerca de 15:00', /^1[45]:\d\d$/.test(t), t);
  await ctx.close();
}

titulo('6. Últimos 3 minutos: alerta');
{
  const { p, ctx } = await apartar(2 * 60000);
  ok('el reloj se pone en alerta', (await p.locator('#cupo-reloj.urgente').count()) === 1);
  const t = (await p.locator('#cupo-tiempo').innerText()).trim();
  ok('y marca cerca de 2:00', /^[12]:\d\d$/.test(t), t);
  await ctx.close();
}

titulo('7. El código de la página');
{
  const html = readFileSync(join(AQUI, '../../docs/index.html'), 'utf8');
  ok('el respaldo es de 15 minutos', /MINUTOS_CUPO:\s*15/.test(html));
  ok('usa la hora que manda el servidor', /arrancarCupo\(data\.expira_en\)/.test(html));
  ok('revisa al volver a la pestaña', /visibilitychange/.test(html));
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
