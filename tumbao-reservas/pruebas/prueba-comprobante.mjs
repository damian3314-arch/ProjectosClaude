/**
 * La pantalla de pago: subir el comprobante y que se llenen los campos.
 *
 * El orden importa y por eso se comprueba: PRIMERO se sube la captura,
 * DESPUÉS salen los campos que esa captura llena. Al revés —pidiéndolos
 * a mano antes de ofrecer leerlos— nadie usa la lectura.
 *
 * Lo que de verdad no puede fallar es el camino de abajo: que la lectura
 * NO encuentre nada. Va a pasar seguido (bancos raros, capturas
 * recortadas, sin credencial de OpenAI) y ahí la persona tiene que poder
 * escribir los datos y seguir como si nada.
 *
 * Se corre en tres modos, según cómo esté levantado el espejo:
 *
 *   node pruebas/espejo-api.mjs                    # lee bien
 *   LECTURA_VACIA=1 node pruebas/espejo-api.mjs    # no saca nada
 *   LECTURA_OTRO=1  node pruebas/espejo-api.mjs    # pagó otra persona
 *
 * y con la misma variable puesta al correr esta prueba.
 */
import { chromium } from 'playwright-core';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const RAIZ = join(dirname(fileURLToPath(import.meta.url)), '..');
const IMG = join(RAIZ, '..', 'docs', 'img', 'qr-breb.png');
const BASE = 'http://localhost:8899/';
const CHROME = process.env.CHROME_PATH || '/opt/pw-browsers/chromium-1194/chrome-linux/chrome';

const VACIA = process.env.LECTURA_VACIA === '1';
const OTRO  = process.env.LECTURA_OTRO === '1';
const MODO  = VACIA ? 'no lee nada' : OTRO ? 'pagó otra persona' : 'lee bien';

let fallos = 0;
const ok = (n, c, extra = '') => {
  console.log(`${c ? '✓' : '✗'} ${n}${extra ? '  → ' + extra : ''}`);
  if (!c) fallos++;
};

console.log(`modo del espejo: ${MODO}\n`);

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

// Esperar a que TERMINE de leer. No basta con "el aviso no dice
// Leyendo": el del intento anterior sigue en pantalla y la espera
// pasaría de largo. Se espera un mensaje terminal.
const esperarLectura = () => p.waitForFunction(() => {
  const a = document.querySelector('#aviso-qr');
  if (!a || a.hidden) return false;
  return /listo|no pudimos|no parece una imagen|no encontramos la hora/i
    .test(a.textContent);
}, { timeout: 30000 });

await irAPago();

// ───────── el orden de la pantalla ─────────
// Subir primero, campos después. Si esto se invierte, la lectura deja
// de usarse y volvemos a que todo el mundo escriba a mano.
const orden = await p.evaluate(() => {
  const c = document.querySelector('.comprobante');
  const pos = s => Array.from(c.querySelectorAll('*')).indexOf(c.querySelector(s));
  return { subir: pos('#soltar'), hora: pos('#hora-transf'), ref: pos('#referencia') };
});
ok('primero se sube la captura, después vienen los campos',
   orden.subir >= 0 && orden.subir < orden.hora && orden.hora < orden.ref,
   `subir ${orden.subir} · hora ${orden.hora} · ref ${orden.ref}`);

ok('pide la hora de la transferencia', await p.locator('#hora-transf').isVisible());
ok('hay campo de referencia', await p.locator('#referencia').isVisible());
ok('ofrece subir el comprobante', await p.locator('#soltar').isVisible());
ok('el campo de quien paga arranca escondido', await p.locator('#caja-pagador').isHidden());

// La promesa que se le hace al cliente tiene que decir la verdad: la
// imagen SÍ sale del celular, lo que no pasa es que se guarde.
const priv = await p.locator('.pista.privacidad').innerText();
ok('la nota de privacidad dice que no se guarda', /no se guarda/i.test(priv), priv.trim());
ok('y ya no promete que no se sube', !/no se sube/i.test(priv));

// ───────── la hora sigue siendo obligatoria ─────────
await p.locator('#ya-pague').click();
await p.waitForTimeout(300);
ok('sin hora no deja seguir', await p.locator('#s3').evaluate(e => e.classList.contains('on')));

// ───────── algo que no es imagen ─────────
await p.locator('#archivo').setInputFiles({
  name: 'notas.txt', mimeType: 'text/plain', buffer: Buffer.from('no soy una imagen'),
});
await p.waitForTimeout(500);
ok('rechaza lo que no es imagen',
   /no parece una imagen/i.test(await p.locator('#aviso-qr').innerText()),
   await p.locator('#aviso-qr').innerText());

// ───────── leer la captura ─────────
await p.locator('#archivo').setInputFiles(IMG);
await esperarLectura();
const aviso = await p.locator('#aviso-qr').innerText();

if (VACIA) {
  ok('cuando no saca nada lo dice sin alarmar', /escríbelos abajo|escribe los datos/i.test(aviso),
     aviso.replace(/\n/g, ' '));
  ok('y deja los campos vacíos para escribirlos',
     (await p.locator('#hora-transf').inputValue()) === '' &&
     (await p.locator('#referencia').inputValue()) === '');

  // Lo que importa de este camino: se puede seguir igual.
  await p.fill('#hora-transf', '07:15');
  await p.locator('#ya-pague').click();
  await p.waitForSelector('#s4.on', { timeout: 10000 });
  ok('a mano la reserva avanza igual', true);

} else {
  ok('dice que quedó listo', /listo/i.test(aviso), aviso.replace(/\n/g, ' '));
  ok('llenó la hora', (await p.locator('#hora-transf').inputValue()) === '18:31',
     await p.locator('#hora-transf').inputValue());
  ok('llenó la referencia', (await p.locator('#referencia').inputValue()) === 'M25418019',
     await p.locator('#referencia').inputValue());
  // Se marcan para que se note qué hay que revisar.
  ok('marca lo que llenó, para que se revise',
     await p.locator('#hora-transf').evaluate(e => e.classList.contains('leido')));
  // Y la marca se va en cuanto la persona lo toca: de ahí en adelante
  // el dato es suyo.
  await p.fill('#referencia', 'M99999999');
  await p.waitForTimeout(150);
  ok('al corregirlo deja de estar marcado',
     !(await p.locator('#referencia').evaluate(e => e.classList.contains('leido'))));

  if (OTRO) {
    ok('si pagó otra persona, abre el campo solo',
       await p.locator('#caja-pagador').isVisible());
    ok('y pone el nombre', (await p.locator('#pagador').inputValue()) === 'LUISA GOMEZ MORA',
       await p.locator('#pagador').inputValue());
    ok('con la casilla marcada', await p.locator('#otro-paga').isChecked());
  }
}

ok('el input de archivo queda vacío: la imagen no se conserva',
   (await p.locator('#archivo').inputValue()) === '');

// ───────── no pisa lo que la persona ya escribió ─────────
// Alguien puede escribir la hora y DESPUÉS subir la captura. Lo suyo
// manda: si la lectura se equivoca, no puede borrar lo correcto.
if (!VACIA) {
  await irAPago();
  await p.fill('#hora-transf', '06:05');
  await p.locator('#archivo').setInputFiles(IMG);
  await esperarLectura();
  ok('no pisa la hora que ya había escrito la persona',
     (await p.locator('#hora-transf').inputValue()) === '06:05',
     await p.locator('#hora-transf').inputValue());
}

// ───────── lo que llega al servidor ─────────
if (!VACIA) {
  await irAPago();
  await p.locator('#archivo').setInputFiles(IMG);
  await esperarLectura();
  await p.fill('#hora-transf', '18:42');
  await p.locator('#ya-pague').click();
  await p.waitForSelector('#s4.on', { timeout: 10000 });

  const enviado = await p.evaluate(async () => {
    const r = await fetch('http://localhost:8899/_prueba/ultimo-comprobante');
    return (await r.json()).ultimo;
  });
  ok('llegó la referencia', enviado && enviado.referencia === 'M25418019',
     enviado && enviado.referencia);
  ok('NO se mandó ninguna imagen con la reserva', !!enviado && !enviado.archivo,
     enviado && enviado.archivo ? 'llegó una imagen' : 'ninguna');
  const h = enviado && enviado.pagado_en
    ? new Intl.DateTimeFormat('es-CO', { timeZone: 'America/Bogota', hour: '2-digit',
        minute: '2-digit', hour12: false }).format(new Date(enviado.pagado_en)) : null;
  ok('la hora llegó como instante, en hora de Bogotá', h === '18:42', String(h));
}

// ───────── consola ─────────
console.log('');
const inesperados = errores.filter(e => !/40[0-9]|Conflict|Not Found/.test(e));
ok('sin errores de JavaScript inesperados', inesperados.length === 0,
   inesperados.join(' | ') || 'ninguno');

// ───────── comprobante ya usado en otra reserva ─────────
// El backend rechaza reusar la misma referencia en dos reservas
// distintas (alguien sube por error la captura vieja). La página tiene
// que decir esa razón real, no un "inténtalo otra vez" que nunca se va
// a arreglar solo porque la persona vuelva a intentarlo.
if (!VACIA) {
  await irAPago();
  await p.fill('#hora-transf', '18:42');
  await p.fill('#referencia', 'YA_USADA');
  await p.locator('#ya-pague').click();
  await p.waitForFunction(() => {
    const a = document.querySelector('#err3');
    return a && a.textContent.trim() !== '';
  }, { timeout: 8000 });
  const msg = await p.locator('#err3').innerText();
  ok('dice la razón real, no un "inténtalo otra vez" genérico',
     /ya se uso para otra reserva/i.test(msg), msg);
  ok('no avanza a la pantalla de espera',
     !(await p.locator('#s4').evaluate(e => e.classList.contains('on'))));
}

if (!VACIA && !OTRO) {
  const dir = process.env.CAPTURAS || '/tmp';
  await irAPago();
  await p.locator('#archivo').setInputFiles(IMG);
  await esperarLectura();
  await p.waitForTimeout(400);
  await p.screenshot({ path: `${dir}/p5-comprobante.png`, fullPage: true });
}

await nav.close();
console.log(`\n${fallos === 0 ? 'TODO EN VERDE' : fallos + ' FALLOS'}`);
process.exit(fallos ? 1 : 0);
