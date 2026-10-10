/**
 * La tiquetera se ofrece donde la persona ya está contenta, no donde paga.
 *
 * Damián (3 oct): «ya tenemos 3 tiqueteras vendidas, ¿qué podría ser lindo y
 * lograr convertir en la página?». Se ofrece en dos pantallas:
 *   · docs/index.html, al CONFIRMARSE una clase suelta: «baila a $12.000 la clase»
 *     con la cuenta real contra los $15.000 de la suelta.
 *   · docs/mensualidad.html, al quedar en la LISTA DE ESPERA: «mientras te
 *     avisamos, baila desde ya», con un botón que abre la compra de esa tiquetera.
 * Y las tarjetas de tiquetera muestran el precio POR CLASE.
 * Nunca en la pantalla de pago (ahí estorba y se pierde la compra de hoy), y si
 * el servidor no contesta los paquetes, no se muestra nada.
 *
 *   node tiquetera-oferta.test.mjs
 */
import { chromium } from 'playwright-core';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const AQUI = dirname(fileURLToPath(import.meta.url));
const BASE = 'http://localhost:8899/';
const CHROME = process.env.CHROME_PATH || '/opt/pw-browsers/chromium-1194/chrome-linux/chrome';
const MENSUALIDAD = 'file:///home/user/ProjectosClaude/docs/mensualidad.html';

let fallos = 0;
const ok = (n, c, extra = '') => { if (!c) fallos++;
  console.log(`${c ? '✓' : '✗'} ${n}${extra ? '  → ' + extra : ''}`); };
const titulo = t => console.log(`\n-- ${t} ${'-'.repeat(Math.max(0, 54 - t.length))}`);

const PAQUETES = { ok: true, paquetes: [
  { clave: 'tq4',  clases: 4, precio_cop: 52000, vigencia_dias: 30 },
  { clave: 'tq8',  clases: 8, precio_cop: 96000, vigencia_dias: 30 },
] };

const hijo = spawn(process.execPath, [join(AQUI, 'espejo-api.mjs')], { stdio: 'ignore' });
for (let i = 0; i < 100; i++) {
  try { await fetch(BASE); break; } catch { await new Promise(r => setTimeout(r, 100)); }
}
const nav = await chromium.launch({ executablePath: CHROME });

/* Reserva una suelta en la página de reservas y la deja confirmada
   (el estado se reescribe: el espejo no sabe de pagos). */
// Cupos de mensualidad que devuelve el servidor. Por defecto NO hay ninguno libre: la tarjeta cae en la tiquetera, que es
// lo que probaban los casos 1 y 2 antes de que la mensualidad pudiera ir primero (10 oct).
const SIN_CUPOS = { ok: true, tope: 25, valor_cop: 125000, horas: [
  { hora: '07:00', etiqueta: '7:00 am', ocupadas: 35, tope: 35, libres: 0 },
  { hora: '18:00', etiqueta: '6:00 pm', ocupadas: 23, tope: 23, libres: 0 },
  { hora: '19:00', etiqueta: '7:00 pm', ocupadas: 23, tope: 23, libres: 0 },
] };
const CON_CUPOS = { ok: true, tope: 25, valor_cop: 125000, horas: [
  { hora: '07:00', etiqueta: '7:00 am', ocupadas: 27, tope: 35, libres: 8 },
  { hora: '18:00', etiqueta: '6:00 pm', ocupadas: 20, tope: 23, libres: 3 },
  { hora: '19:00', etiqueta: '7:00 pm', ocupadas: 23, tope: 23, libres: 0 },
] };

async function reservarConfirmada(paquetes, cupos = SIN_CUPOS) {
  const ctx = await nav.newContext({ viewport: { width: 390, height: 844 }, locale: 'es-CO' });
  const p = await ctx.newPage();
  const errores = [];
  p.on('pageerror', e => errores.push(e.message));
  await p.route('**/tumbao/tiquetera/paquetes', r =>
    paquetes ? r.fulfill({ json: paquetes }) : r.abort());
  await p.route('**/tumbao/mensualidad', r =>
    cupos ? r.fulfill({ json: cupos }) : r.abort());
  await p.route('**/tumbao/estado**', async (ruta) => {
    const r = await ruta.fetch();
    const d = await r.json();
    await ruta.fulfill({ response: r, json: { ...d, ok: true, estado: 'confirmada' } });
  });
  await p.goto(BASE, { waitUntil: 'networkidle' });
  await p.locator('.opcion[data-tipo="suelta"]').click();
  await p.waitForSelector('.clase:not(:disabled)', { timeout: 8000 });
  await p.locator('.clase:not(:disabled)').first().click();
  await p.waitForSelector('#s2.on', { timeout: 8000 });
  await p.fill('#nombre', 'Clienta Oferta');
  await p.fill('#celular', '3005550002');
  await p.check('#habeas');
  await p.locator('#enviar').click();
  await p.waitForSelector('#s3.on', { timeout: 8000 });
  const pago = await p.locator('#s3').innerText();
  await p.fill('#hora-transf', '10:00');
  await p.locator('#ya-pague').click();
  await p.waitForSelector('#s5.on', { timeout: 30000 });
  return { p, ctx, errores, pago };
}

titulo('1. Reserva confirmada: se ofrece la tiquetera con la cuenta real');
{
  const { p, ctx, errores, pago } = await reservarConfirmada(PAQUETES);
  ok('en la pantalla de pago NO se ofrece nada', !/tiquetera/i.test(pago));
  await p.waitForSelector('#oferta-tiq:not([hidden])', { timeout: 5000 });
  const t = await p.locator('#oferta-tiq').innerText();
  ok('baila a $12.000 la clase (el paquete más barato por clase)', /\$12\.000 la clase/.test(t), t.replace(/\n/g, ' '));
  ok('dice cuánto ahorra: 8 × $15.000 − $96.000 = $24.000', /ahorras \$24\.000/.test(t));
  ok('y la vigencia', /30 días/.test(t));
  ok('el botón lleva a la página de la tiquetera',
     (await p.locator('#oferta-tiq-ir').getAttribute('href')) === 'mensualidad.html');
  ok('sin errores de JS', errores.length === 0, errores.join(' | '));
  await ctx.close();
}

titulo('2. Sin paquetes del servidor no se muestra nada');
{
  const { p, ctx, errores } = await reservarConfirmada(null);
  await p.waitForTimeout(800);
  ok('la oferta sigue escondida', await p.locator('#oferta-tiq').isHidden());
  ok('y la confirmación se ve normal', await p.locator('#s5.on').isVisible());
  ok('sin errores de JS', errores.length === 0, errores.join(' | '));
  await ctx.close();
}

titulo('2b. Con cupos de mensualidad, la mensualidad va primero');
{
  const { p, ctx, errores } = await reservarConfirmada(PAQUETES, CON_CUPOS);
  await p.waitForSelector('#oferta-tiq:not([hidden])', { timeout: 5000 });
  const tit = (await p.locator('#oferta-tiq-tit').innerText()).trim();
  const txt = (await p.locator('#oferta-tiq-txt').innerText()).replace(/\s+/g, ' ');
  ok('el título dice el mes por $125.000 y $5.000 la clase', /\$125\.000/.test(tit) && /\$5\.000 la clase/.test(tit), tit);
  ok('dice cuánto cuesta cada vez que no es mensualidad ($15.000)', /\$15\.000/.test(txt), txt);
  ok('lista los cupos REALES por horario y calla el horario lleno', /8 cupos a las 7:00 am/.test(txt) && /3 cupos a las 6:00 pm/.test(txt) && !/7:00 pm/.test(txt), txt);
  ok('deja la tiquetera como la forma suave de empezar, con la cuenta real', /tiquetera de 8 clases/.test(txt) && /\$12\.000 cada una/.test(txt), txt);
  ok('el botón es de la mensualidad y lleva a su página', (await p.locator('#oferta-tiq-ir').innerText()).trim() === 'Apartar mi mensualidad'
     && (await p.locator('#oferta-tiq-ir').getAttribute('href')) === 'mensualidad.html');
  ok('sin errores de JS', errores.length === 0, errores.join(' | '));
  await ctx.close();
}
{
  const { p, ctx, errores } = await reservarConfirmada(PAQUETES, { ...CON_CUPOS, horas: [{ hora: '18:00', etiqueta: '6:00 pm', ocupadas: 22, tope: 23, libres: 1 }] });
  await p.waitForSelector('#oferta-tiq:not([hidden])', { timeout: 5000 });
  ok('con un solo cupo dice «1 cupo» (no «1 cupos»)', /Quedan 1 cupo a las 6:00 pm\./.test((await p.locator('#oferta-tiq-txt').innerText()).replace(/\s+/g, ' ')));
  ok('sin errores de JS', errores.length === 0, errores.join(' | '));
  await ctx.close();
}
{
  const { p, ctx, errores } = await reservarConfirmada(PAQUETES, null);
  await p.waitForSelector('#oferta-tiq:not([hidden])', { timeout: 5000 });
  ok('si los cupos no cargan, queda la tiquetera de siempre (no se promete un cupo que no se conoce)',
     /Baila a \$12\.000 la clase/.test(await p.locator('#oferta-tiq-tit').innerText()) && (await p.locator('#oferta-tiq-ir').innerText()).trim() === 'Ver la tiquetera');
  ok('sin errores de JS', errores.length === 0, errores.join(' | '));
  await ctx.close();
}
{
  const { p, ctx } = await reservarConfirmada(null, CON_CUPOS);
  await p.waitForSelector('#oferta-tiq:not([hidden])', { timeout: 5000 });
  const txt = (await p.locator('#oferta-tiq-txt').innerText()).replace(/\s+/g, ' ');
  ok('sin tiquetera pero con cupos, igual ofrece la mensualidad (y no menciona una tiquetera que no existe)', /Quedan 8 cupos/.test(txt) && !/tiquetera/i.test(txt), txt);
  await ctx.close();
}

async function mensualidad(estado) {
  const ctx = await nav.newContext({ viewport: { width: 390, height: 844 }, locale: 'es-CO' });
  const p = await ctx.newPage();
  const errores = [];
  p.on('pageerror', e => errores.push(e.message));
  await p.route('**/tumbao/tiquetera/paquetes', r => r.fulfill({ json: PAQUETES }));
  await p.route('**/tumbao/mensualidad', r => r.fulfill({ json: { ok: true, tope: 25, valor_cop: 125000, horas: [
    { hora: '07:00', etiqueta: '7:00 am', ocupadas: 20, tope: 25, libres: 5 },
    { hora: '18:00', etiqueta: '6:00 pm', ocupadas: 25, tope: 25, libres: 0 },
    { hora: '19:00', etiqueta: '7:00 pm', ocupadas: 25, tope: 25, libres: 0 },
  ] } }));
  await p.route('**/mensualidad/solicitar', r => r.fulfill({ json: { ok: true, id: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
    estado, valor_cop: 125000, ya_estaba: false } }));
  await p.goto(MENSUALIDAD);
  await p.waitForSelector('[data-elegir="mensualidad"]', { timeout: 10000 });
  return { p, ctx, errores };
}

titulo('3. Tarjetas de tiquetera: el precio por clase a la vista');
{
  const { p, ctx, errores } = await mensualidad('lista_espera');
  await p.waitForSelector('.tarjeta .por-clase', { timeout: 5000 });
  const t = await p.locator('#tarjetas-eleccion').innerText();
  ok('4 clases: $13.000 por clase', /\$13\.000 por clase/.test(t), t.replace(/\n/g, ' ').slice(0, 160));
  ok('8 clases: $12.000 por clase', /\$12\.000 por clase/.test(t));
  ok('sin errores de JS', errores.length === 0, errores.join(' | '));
  await ctx.close();
}

titulo('4. Lista de espera: «mientras te avisamos, baila desde ya»');
{
  const { p, ctx, errores } = await mensualidad('lista_espera');
  await p.click('[data-elegir="mensualidad"]');
  await p.waitForSelector('.hora', { timeout: 10000 });
  await p.click('.hora[data-hora="19:00"]');
  await p.fill('#nombre', 'María Espera');
  await p.fill('#celular', '3001234567');
  await p.check('#habeas');
  await p.click('#btn-enviar');
  await p.waitForSelector('#s3:not([hidden])', { timeout: 5000 });
  const t = await p.locator('#s3').innerText();
  ok('sigue diciendo que quedó en la lista y que no pague nada', /Quedaste en la lista/.test(t) && /No pagues nada todavía/.test(t));
  ok('ofrece la tiquetera con la cuenta real', /Mientras te avisamos/.test(t) && /\$12\.000/.test(t) && /8 clases/.test(t), t.replace(/\n/g, ' ').slice(-260));
  await p.click('#espera-ir-tiq');
  await p.waitForTimeout(400);
  const cuerpo = await p.locator('body').innerText();
  ok('el botón abre la compra de esa tiquetera (8 clases, $96.000)', /96\.000/.test(cuerpo) && /8 clases/.test(cuerpo));
  ok('sin errores de JS', errores.length === 0, errores.join(' | '));
  await ctx.close();
}

await nav.close();
hijo.kill();
console.log(fallos ? `\n${fallos} fallo(s)` : '\nTodo bien');
process.exit(fallos ? 1 : 0);
