/**
 * La burbuja de opiniones en tumbaobaila.com — navegador de verdad.
 *
 * EL RIESGO QUE MIDE
 * Esta página existe para reservar. Una burbuja que se abre sola, que
 * tapa el formulario o que descarga un chat entero a quien solo vino a
 * mirar horarios es peor que no tenerla.
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
const ctx = await nav.newContext({ viewport: { width: 414, height: 820 }, locale: 'es-CO' });
const p = await ctx.newPage();
const errores = [];
p.on('console', m => { if (m.type() === 'error') errores.push(m.text()); });
p.on('pageerror', e => errores.push('pageerror: ' + e.message));

// Qué se pide al cargar la página. Si el chat estuviera aquí, aparecería.
const pedidos = [];
p.on('request', r => pedidos.push(r.url()));

await p.goto(BASE, { waitUntil: 'networkidle' });

console.log('\n── Antes de tocarla ──');
ok('la burbuja se ve', await p.locator('#burbuja').isVisible());
ok('el chat NO está abierto', await p.locator('#opina').isHidden());
// Cargar el iframe con la página sería descargarle un chat entero a
// quien solo vino a mirar horarios.
ok('y el chat ni se ha descargado',
   !pedidos.some(u => u.includes('opina-falso')),
   `${pedidos.length} peticiones, ninguna al chat`);

// No puede taparle nada a quien está reservando.
const tapa = await p.evaluate(() => {
  const b = document.querySelector('#burbuja').getBoundingClientRect();
  // El punto central de la burbuja: ¿qué hay debajo?
  const debajo = document.elementFromPoint(b.left + b.width / 2, b.top + b.height / 2);
  return debajo && debajo.id;
});
ok('nada del formulario queda debajo', tapa === 'burbuja', `debajo hay: ${tapa}`);

console.log('\n── Al abrirla ──');
await p.locator('#burbuja').click();
await p.waitForTimeout(800);
ok('se abre', await p.locator('#opina').isVisible());
ok('y la burbuja se quita de en medio', await p.locator('#burbuja').isHidden());
ok('ahora sí carga el chat',
   await p.locator('#opina iframe').count() === 1);

const src = await p.locator('#opina iframe').getAttribute('src');
ok('en modo burbuja, para que no repita el encabezado',
   /burbuja=1/.test(src), src);
ok('con permiso de micrófono, que las notas de voz lo necesitan',
   (await p.locator('#opina iframe').getAttribute('allow') || '').includes('microphone'));

// El contenido tiene que llegar de verdad: un iframe que no carga se ve
// igual que uno vacío.
const dentro = p.frameLocator('#opina iframe');
ok('el chat responde dentro de la ventanita',
   /volver la segunda vez/.test(await dentro.locator('#saludo').innerText()),
   (await dentro.locator('#saludo').innerText()).slice(0, 50));

console.log('\n── Al cerrarla ──');
await p.locator('#opina-cerrar').click();
await p.waitForTimeout(300);
ok('se cierra con la ×', await p.locator('#opina').isHidden());
ok('y vuelve la burbuja', await p.locator('#burbuja').isVisible());

await p.locator('#burbuja').click();
await p.waitForTimeout(300);
await p.keyboard.press('Escape');
await p.waitForTimeout(300);
ok('también se cierra con Escape', await p.locator('#opina').isHidden());

// Reabrir no puede crear un segundo iframe: sería empezar la
// conversación de cero cada vez que alguien cierra sin querer.
await p.locator('#burbuja').click();
await p.waitForTimeout(300);
ok('reabrir no arranca otra conversación',
   await p.locator('#opina iframe').count() === 1,
   `${await p.locator('#opina iframe').count()} iframe(s)`);

console.log('\n── En un celular ──');
// Una ventanita de 24rem dentro de una pantalla de 24rem es un marco
// alrededor de nada.
const caja = await p.locator('#opina').boundingBox();
const vp = p.viewportSize();
ok('ocupa la pantalla entera', caja.width >= vp.width - 2 && caja.height >= vp.height - 2,
   `${Math.round(caja.width)}×${Math.round(caja.height)} de ${vp.width}×${vp.height}`);

console.log('\n── Reservar sigue funcionando ──');
// Lo importante de esta página. Si la burbuja estorbara al formulario,
// aquí se caería.
await p.locator('#opina-cerrar').click();
await p.waitForTimeout(300);
await p.locator('.opcion[data-tipo="suelta"]').click();
await p.waitForSelector('.clase:not(:disabled)', { timeout: 8000 });
await p.locator('.clase:not(:disabled)').first().click();
await p.waitForSelector('#s2.on', { timeout: 8000 });
await p.fill('#nombre', 'Camila Rojas');
await p.fill('#celular', '3001234567');
await p.check('#habeas');
await p.locator('#enviar').click();
await p.waitForSelector('#s3.on', { timeout: 8000 });
ok('se puede reservar con la burbuja puesta', true);

/* ─────────────────────────────────────────────────────────────
   La invitación de la pantalla final

   POR QUÉ EXISTE
   En dos días seis personas abrieron el chat y ninguna escribió. La
   burbuja llegaba en mal momento: un globito a los 6 segundos le cae
   encima a quien está tecleando su nombre. La invitación de verdad va
   donde la persona ya terminó y está contenta.

   Va en un contexto nuevo a propósito: el de arriba ya abrió el chat y
   tiene la marca puesta en localStorage.
   ───────────────────────────────────────────────────────────── */
console.log('\n── Contarnos, al final de la reserva ──');
await fetch('http://localhost:8899/_prueba/reiniciar').catch(() => {});
const ctx2 = await nav.newContext({ viewport: { width: 414, height: 820 }, locale: 'es-CO' });
const q = await ctx2.newPage();
q.on('console', m => { if (m.type() === 'error') errores.push('ctx2: ' + m.text()); });
q.on('pageerror', e => errores.push('ctx2 pageerror: ' + e.message));

const reservar = async (pag) => {
  await pag.goto(BASE, { waitUntil: 'networkidle' });
  await pag.locator('.opcion[data-tipo="suelta"]').click();
  await pag.waitForSelector('.clase:not(:disabled)', { timeout: 8000 });
  await pag.locator('.clase:not(:disabled)').first().click();
  await pag.waitForSelector('#s2.on', { timeout: 8000 });
  await pag.fill('#nombre', 'Lucia Mena');
  await pag.fill('#celular', '3009998877');
  await pag.check('#habeas');
  await pag.locator('#enviar').click();
  await pag.waitForSelector('#s3.on', { timeout: 8000 });
  await pag.fill('#hora-transf', '18:42');
  await pag.locator('#ya-pague').click();
  await pag.waitForSelector('#s4.on', { timeout: 8000 });
  // El espejo confirma unos segundos después, como el banco.
  await pag.waitForSelector('#s5.on', { timeout: 30000 });
};

await reservar(q);
ok('la reserva quedó confirmada',
   /confirmad/i.test(await q.locator('#s5').innerText()));
ok('la invitación aparece al confirmar', await q.locator('#ok-opina').isVisible());
// La pregunta concreta es lo que hace que se conteste: "cuéntanos cómo
// te ha ido" obliga a inventar qué decir; una pregunta se responde en
// tres palabras.
const invita = (await q.locator('#ok-opina').innerText()).replace(/\n/g, ' · ');
ok('y lleva la pregunta, no una fórmula vaga',
   /volver la segunda vez/i.test(invita), invita);

// El globito no puede haber salido: la persona pasó por el formulario y
// por la pantalla de pago, y ahí estorba.
ok('el globito no apareció durante la reserva',
   await q.locator('#burbuja-pista').isHidden());

await q.locator('#ok-opina-ir').click();
await q.waitForTimeout(800);
ok('al pulsarla se abre el chat', await q.locator('#opina').isVisible());
ok('y es el mismo chat de la burbuja',
   /burbuja=1/.test(await q.locator('#opina iframe').getAttribute('src')));

// A quien ya dijo que sí no se le vuelve a pedir. Es la diferencia entre
// una invitación y una cantaleta.
console.log('\n── Y no se pide dos veces ──');
const q2 = await ctx2.newPage();
q2.on('pageerror', e => errores.push('ctx2b pageerror: ' + e.message));
await reservar(q2);
ok('a quien ya abrió el chat no se le vuelve a pedir',
   await q2.locator('#ok-opina').isHidden());
await ctx2.close();

console.log('');
const inesperados = errores.filter(e => !/40[0-9]|Failed to load resource/.test(e));
ok('sin errores de JavaScript', inesperados.length === 0, inesperados.join(' | ') || 'ninguno');

const dir = process.env.CAPTURAS || '/tmp';
await p.goto(BASE, { waitUntil: 'networkidle' });
await p.waitForTimeout(400);
await p.screenshot({ path: `${dir}/b1-burbuja.png` });
await p.locator('#burbuja').click();
await p.waitForTimeout(700);
await p.screenshot({ path: `${dir}/b2-abierta.png` });

await nav.close();
console.log(`\n${fallos === 0 ? 'TODO EN VERDE' : fallos + ' FALLOS'}`);
process.exit(fallos ? 1 : 0);
