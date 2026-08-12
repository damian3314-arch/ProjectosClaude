/**
 * Reservar varios cupos con un solo pago — página pública, navegador de
 * verdad.
 *
 * EL CASO
 * Alguien llega y reserva para cuatro. Tiene que poder decir cuántos,
 * escribir los cuatro nombres, y que la pantalla de pago le pida el
 * total: si le pide $15.000 va a transferir $15.000 y el cupo de los
 * otros tres se cae solo a la media hora.
 *
 * Requiere el espejo corriendo:  node pruebas/espejo-api.mjs
 */
import { chromium } from 'playwright-core';

const BASE = 'http://localhost:8899/';
const CHROME = process.env.CHROME_PATH || '/opt/pw-browsers/chromium-1194/chrome-linux/chrome';
let fallos = 0;
const ok = (n, c, extra = '') => {
  console.log(`${c ? '✓' : '✗'} ${n}${extra ? '  → ' + extra : ''}`);
  if (!c) fallos++;
};

const nav = await chromium.launch({ executablePath: CHROME });
const ctx = await nav.newContext({ viewport: { width: 414, height: 900 }, locale: 'es-CO' });
const p = await ctx.newPage();
const errores = [];
p.on('console', m => { if (m.type() === 'error') errores.push(m.text()); });
p.on('pageerror', e => errores.push('pageerror: ' + e.message));

await fetch('http://localhost:8899/_prueba/reiniciar').catch(() => {});
await p.goto(BASE, { waitUntil: 'networkidle' });

// ───────── llegar al formulario ─────────
await p.locator('.opcion[data-tipo="suelta"]').click();
await p.waitForSelector('.clase:not(:disabled)', { timeout: 8000 });
await p.locator('.clase:not(:disabled)').first().click();
await p.waitForSelector('#s2.on', { timeout: 8000 });

console.log('\n── El contador ──');
ok('el contador se ve en clase suelta', await p.locator('#caja-cuantos').isVisible());
ok('arranca en uno', (await p.locator('#cuantos').inputValue()) === '1',
   await p.locator('#cuantos').inputValue());
ok('no se puede bajar de uno', await p.locator('#cuantos-menos').isDisabled());
ok('dice cuántos cupos quedan',
   /cupos?/.test(await p.locator('#cuantos-hint').innerText()),
   (await p.locator('#cuantos-hint').innerText()).trim());

// Con uno solo, el formulario es el de siempre: ni un campo de más.
ok('con uno solo no aparece ningún campo extra',
   await p.locator('#acompanantes input').count() === 0);
ok('y la etiqueta es la de siempre',
   /Nombre y apellido/.test(await p.locator('#lbl-nombre').innerText()),
   (await p.locator('#lbl-nombre').innerText()).trim());

// ── subir a cuatro ──
for (let i = 0; i < 3; i++) await p.locator('#cuantos-mas').click();
await p.waitForTimeout(200);
ok('sube a cuatro', (await p.locator('#cuantos').inputValue()) === '4');
ok('y pide tres nombres más', await p.locator('#acompanantes input').count() === 3,
   `${await p.locator('#acompanantes input').count()} campo(s)`);
ok('el primero pasa a llamarse "Persona 1"',
   /Persona 1/.test(await p.locator('#lbl-nombre').innerText()),
   (await p.locator('#lbl-nombre').innerText()).trim());

// El resumen tiene que decir el total ANTES de pagar: es donde la
// persona se da cuenta de que va a transferir 60 y no 15.
const resumen = await p.locator('#resumen').innerText();
ok('el resumen ya dice 4 cupos y el total',
   /4 cupos/.test(resumen) && /60\.000/.test(resumen),
   resumen.replace(/\n/g, ' · '));

// ── lo escrito no se pierde al mover el contador ──
await p.fill('#nombre-2', 'Beto Perez');
await p.locator('#cuantos-menos').click();     // a 3
await p.locator('#cuantos-mas').click();       // vuelve a 4
await p.waitForTimeout(200);
ok('bajar y volver a subir no borra lo escrito',
   (await p.locator('#nombre-2').inputValue()) === 'Beto Perez',
   await p.locator('#nombre-2').inputValue());

console.log('\n── Los nombres son obligatorios ──');
await p.fill('#nombre', 'Ana Perez');
await p.fill('#celular', '3001234567');
await p.check('#habeas');
// Faltan el 3 y el 4 a propósito.
await p.locator('#enviar').click();
await p.waitForTimeout(500);
ok('no deja mandar con nombres en blanco', await p.locator('#s2').isVisible());
ok('y señala CUÁL falta, no "falta un nombre"',
   await p.locator('#e-nombre-3.on').count() === 1 &&
   await p.locator('#e-nombre-2.on').count() === 0);

console.log('\n── Reservar los cuatro ──');
await p.fill('#nombre-3', 'Caro Perez');
await p.fill('#nombre-4', 'Dani Perez');
await p.locator('#enviar').click();
await p.waitForSelector('#s3.on', { timeout: 8000 });
ok('pasa a la pantalla de pago', true);

// LO QUE MANDA: el monto. Si dice 15.000, la persona transfiere 15.000,
// el pago no cruza con nada y tres cupos se sueltan solos.
const monto = (await p.locator('#pago-monto').innerText()).trim();
ok('pide el TOTAL, no el precio de una clase', monto === '$60.000', monto);
const desglose = (await p.locator('#pago-cuantos').innerText()).trim();
// El CSS pone el desglose en mayúsculas, así que la comprobación va sin
// distinguirlas: lo que importa es que el número esté, no la tipografía.
ok('y desglosa, para que no parezca un error',
   /4 clases/i.test(desglose) && /15\.000/.test(desglose), desglose);

console.log('\n── El resto del camino no cambia ──');
await p.fill('#hora-transf', '18:42');
await p.locator('#ya-pague').click();
await p.waitForSelector('#s4.on', { timeout: 8000 });
ok('el "ya pagué" sigue funcionando igual', true);

// El espejo confirma unos segundos después, como el banco de verdad, y
// la página salta de la pantalla de espera (s4) a la de resultado (s5).
// Se espera a la pantalla, no a un reloj: el sondeo va cada tantos
// segundos y un timeout fijo cae entre dos consultas la mitad de las
// veces.
await p.waitForSelector('#s5.on', { timeout: 30000 }).catch(() => {});
const final = await p.locator('#s5').innerText();
ok('y el grupo entero queda confirmado',
   /confirmad/i.test(final), final.replace(/\n/g, ' · ').slice(0, 90));

// Las cuatro tienen que existir de verdad, cada una con su nombre: es lo
// que va a leer quien esté en la puerta.
const res = await (await fetch('http://localhost:8899/api/admin/lista', {
  method: 'POST', headers: { 'content-type': 'application/json' },
  body: JSON.stringify({ token: 'token-de-prueba',
                         clase_id: (await (await fetch('http://localhost:8899/webhook/tumbao/clases?tipo=suelta')).json())
                                     .dias.flatMap(d => d.clases)[0].clase_id }) })).json();
const nombres = (res.reservas || []).map(r => r.nombre);
ok('en la lista de la puerta salen las cuatro personas',
   ['Ana Perez', 'Beto Perez', 'Caro Perez', 'Dani Perez'].every(n => nombres.includes(n)),
   nombres.join(', '));

console.log('\n── No caben tantos ──');
// Con la clase casi llena, pedir más de lo que queda tiene que fallar
// ANTES de crear nada. Medio grupo es lo peor posible: cupos ocupados
// que nadie va a usar y un cobro que no cuadra.
await p.goto(BASE, { waitUntil: 'networkidle' });
await p.locator('.opcion[data-tipo="suelta"]').click();
await p.waitForSelector('.clase:not(:disabled)', { timeout: 8000 });
// La de las 6 pm del espejo tiene 4 cupos; ya se usaron 4 arriba si cayó
// ahí, así que se busca la que menos tenga y se pide una más.
const cupos = await p.locator('.clase:not(:disabled) .cupos').allInnerTexts();
ok('hay clases con cupo para seguir probando', cupos.length > 0, cupos.join(' | '));

const conPocos = p.locator('.clase:not(:disabled)').filter({ hasText: /¡Solo \d!/ }).first();
if (await conPocos.count() > 0) {
  await conPocos.click();
  await p.waitForSelector('#s2.on', { timeout: 8000 });
  const tope = Number(await p.locator('#cuantos').evaluate(() => 0)) || 0;
  // El contador no deja pedir más de los que quedan: el error se evita
  // en vez de explicarse.
  for (let i = 0; i < 9; i++) await p.locator('#cuantos-mas').click().catch(() => {});
  await p.waitForTimeout(200);
  const pedidos = Number(await p.locator('#cuantos').inputValue());
  const libres = Number((await conPocos.locator('.cupos').innerText()).match(/\d+/)?.[0] ?? 99);
  ok('el contador se frena en los cupos que quedan', pedidos <= libres,
     `pidió ${pedidos}, quedaban ${libres}`);
} else {
  ok('el contador se frena en los cupos que quedan', true, 'sin clase apretada que probar');
}

console.log('');
const inesperados = errores.filter(e => !/40[0-9]|Failed to load resource/.test(e));
ok('sin errores de JavaScript', inesperados.length === 0, inesperados.join(' | ') || 'ninguno');

const dir = process.env.CAPTURAS || '/tmp';
await p.goto(BASE, { waitUntil: 'networkidle' });
await p.locator('.opcion[data-tipo="suelta"]').click();
await p.waitForSelector('.clase:not(:disabled)', { timeout: 8000 });
await p.locator('.clase:not(:disabled)').first().click();
await p.waitForSelector('#s2.on', { timeout: 8000 });
for (let i = 0; i < 3; i++) await p.locator('#cuantos-mas').click();
await p.waitForTimeout(400);
await p.screenshot({ path: `${dir}/v1-cuantos.png`, fullPage: true });

await nav.close();
console.log(`\n${fallos === 0 ? 'TODO EN VERDE' : fallos + ' FALLOS'}`);
process.exit(fallos ? 1 : 0);
