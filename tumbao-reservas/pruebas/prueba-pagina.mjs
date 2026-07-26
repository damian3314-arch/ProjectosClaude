/**
 * Prueba de la página de reservas con Chromium, en viewport de celular.
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
const ctx = await nav.newContext({ viewport: { width: 390, height: 844 }, locale: 'es-CO' });
const p = await ctx.newPage();
const errores = [];
p.on('console', m => { if (m.type() === 'error') errores.push(m.text()); });
p.on('pageerror', e => errores.push('pageerror: ' + e.message));

const irInicio = async () => { await p.goto(BASE, { waitUntil: 'networkidle' }); };
const elegirTipo = async t => { await p.locator(`.opcion[data-tipo="${t}"]`).click(); await p.waitForTimeout(500); };
const elegirDiaConDow = async dow => {
  // dow 6 = sábado
  const n = await p.locator('.dia').count();
  for (let i = 0; i < n; i++) {
    const txt = (await p.locator('.dia .dow').nth(i).innerText()).toLowerCase();
    const esSab = txt.startsWith('sá') || txt.startsWith('sa');
    if ((dow === 6) === esSab) { await p.locator('.dia').nth(i).click(); await p.waitForTimeout(300); return true; }
  }
  return false;
};
// Recorre los dias hasta encontrar uno con esa clase habilitada.
const buscarDiaConClase = async fragmento => {
  const n = await p.locator('.dia').count();
  for (let i = 0; i < n; i++) {
    const esSab = (await p.locator('.dia .dow').nth(i).innerText()).toLowerCase().startsWith('s');
    if (esSab) continue;
    await p.locator('.dia').nth(i).click();
    await p.waitForTimeout(300);
    if (await clicClasePorHora(fragmento)) return true;
  }
  return false;
};
const clicClasePorHora = async fragmento => {
  const habilitadas = p.locator('.clase:not(:disabled)');
  const n = await habilitadas.count();
  for (let i = 0; i < n; i++) {
    const h = await habilitadas.nth(i).locator('.hora').innerText();
    if (h.includes(fragmento)) { await habilitadas.nth(i).click(); await p.waitForTimeout(350); return true; }
  }
  return false;
};
const volverAHorario = async () => {
  if (await p.locator('#s2').isVisible()) { await p.locator('[data-volver="1"]').click(); await p.waitForTimeout(350); }
};
const llenarDatos = async (nombre, cel) => {
  await p.fill('#nombre', nombre);
  await p.fill('#celular', cel);
  await p.check('#habeas');
  await p.locator('#enviar').click();
};

await irInicio();

// ───────── paso 0 ─────────
ok('arranca preguntando cómo viene', await p.locator('#s0').isVisible());
ok('ofrece los dos caminos', await p.locator('.opcion').count() === 2);

// ───────── CLASE SUELTA: camino completo ─────────
console.log('\n── Clase suelta ──');
await elegirTipo('suelta');
await p.waitForSelector('.clase:not(:disabled)', { timeout: 8000 });
ok('carga los días', await p.locator('.dia').count() > 0, `${await p.locator('.dia').count()} días`);
ok('el chip de Pago está visible', !(await p.locator('#chip-pago').isHidden()));

const horaTxt = await p.locator('.clase .hora').first().innerText();
ok('la hora sale compacta', /\d{1,2}:\d{2}\s?(am|pm)/i.test(horaTxt), `"${horaTxt}"`);

const agotadas = await p.locator('.clase:disabled').count();
ok('la clase agotada queda deshabilitada', agotadas >= 1, `${agotadas} agotada(s)`);

await p.locator('.clase:not(:disabled)').first().click();
await p.waitForTimeout(400);
ok('pasa a datos', await p.locator('#s2').isVisible());
ok('el resumen muestra el precio', (await p.locator('#resumen').innerText()).includes('$'),
   (await p.locator('#resumen').innerText()).replace(/\n/g, ' · '));

await p.locator('#enviar').click();
await p.waitForTimeout(300);
ok('bloquea sin nombre',  await p.locator('#e-nombre').isVisible());
ok('bloquea sin celular', await p.locator('#e-celular').isVisible());
ok('bloquea sin habeas data', await p.locator('#e-habeas').isVisible());

await llenarDatos('Camila Rojas', '+57 300 222 3344');
await p.waitForSelector('#s3.on', { timeout: 8000 });
ok('pasa a la pantalla de pago', true);
ok('muestra el monto', (await p.locator('#pago-monto').innerText()).includes('15.000'),
   await p.locator('#pago-monto').innerText());
ok('avisa que el QR no trae el monto', (await p.locator('.monto .ojo').innerText()).includes('no trae el monto'));
ok('el QR carga', await p.locator('#pago-qr').evaluate(i => i.complete && i.naturalWidth > 0));
ok('muestra la llave Bre-B', (await p.locator('#d-llave').innerText()).trim() === '1096803067');
ok('muestra la cuenta', (await p.locator('#d-cuenta').innerText()).trim() === '91289724619');

await p.locator('#ya-pague').click();
await p.waitForSelector('#s4.on', { timeout: 8000 });
ok('pasa a la espera con barra', true);
const reloj1 = await p.locator('#reloj').innerText();
await p.waitForTimeout(2500);
const reloj2 = await p.locator('#reloj').innerText();
ok('el reloj corre', reloj1 !== reloj2, `${reloj1} → ${reloj2}`);

await p.waitForSelector('#s5.on', { timeout: 25000 });
ok('confirma sola cuando llega el pago', true);
const cod = (await p.locator('#ok-codigo').innerText()).trim();
ok('muestra el código', /^[A-Z0-9]{4,8}$/.test(cod), cod);
ok('el título dice pago confirmado', (await p.locator('#t5').innerText()).toLowerCase().includes('confirmado'),
   await p.locator('#t5').innerText());

// ───────── MIEMBRO: los tres casos ─────────
console.log('\n── Miembro ──');
await irInicio();
await elegirTipo('miembro');
await p.waitForSelector('.clase:not(:disabled)', { timeout: 8000 });
ok('el chip de Pago se esconde', await p.locator('#chip-pago').isHidden());

// 1) su propio horario entre semana -> "tu plan ya te cubre"
//    Se usa martes: el lunes a las 6pm esta agotada a proposito.
if (await buscarDiaConClase('6:00 pm')) {
  await llenarDatos('Alba Camacho', '3001111111');
  await p.waitForTimeout(900);
  const msg = await p.locator('#err2').innerText();
  ok('entre semana en su horario: le dice que ya está cubierto',
     msg.toLowerCase().includes('ya te cubre'), msg.slice(0, 90));
} else { ok('entre semana en su horario', false, 'no se encontro clase de 6:00 pm habilitada'); }

// 2) otra hora entre semana -> "eso es clase suelta"
await volverAHorario();
if (await buscarDiaConClase('7:00 pm')) {
  await llenarDatos('Alba Camacho', '3001111111');
  await p.waitForTimeout(900);
  const msg = await p.locator('#err2').innerText();
  ok('otra hora entre semana: le dice que es clase suelta',
     msg.toLowerCase().includes('clase suelta'), msg.slice(0, 90));
} else { ok('otra hora entre semana', false, 'no se encontro clase de 7:00 pm habilitada'); }

// 3) sabado -> confirma sin pasar por pago
await volverAHorario();
if (await elegirDiaConDow(6)) {
  await p.locator('.clase:not(:disabled)').first().click();
  await p.waitForTimeout(350);
  await llenarDatos('Alba Camacho', '3001111111');
  await p.waitForSelector('#s5.on', { timeout: 8000 });
  ok('sábado: confirma sin pasar por la pantalla de pago', true);
  ok('nunca mostró la pantalla de pago', !(await p.locator('#s3').isVisible()));
  ok('el título es de bienvenida', (await p.locator('#t5').innerText()).toLowerCase().includes('esperamos'),
     await p.locator('#t5').innerText());
} else { ok('sábado', false, 'no se encontro sabado en los proximos 7 dias'); }

// 4) quien no es miembro
await irInicio();
await elegirTipo('miembro');
await p.waitForSelector('.clase:not(:disabled)', { timeout: 8000 });
await elegirDiaConDow(6);
await p.locator('.clase:not(:disabled)').first().click();
await p.waitForTimeout(350);
await llenarDatos('Coladito', '3009998877');
await p.waitForTimeout(900);
const msgNo = await p.locator('#err2').innerText();
ok('quien no es miembro no entra gratis',
   msgNo.toLowerCase().includes('no encontramos'), msgNo.slice(0, 80));

// ───────── consola ─────────
console.log('');
const inesperados = errores.filter(e => !/40[0-9]|Conflict|Not Found/.test(e));
ok('sin errores de JavaScript inesperados', inesperados.length === 0, inesperados.join(' | ') || 'ninguno');

// capturas
const dir = process.env.CAPTURAS || '/tmp';
await irInicio();
await p.screenshot({ path: `${dir}/p0-tipo.png` });
await elegirTipo('suelta');
await p.waitForSelector('.clase:not(:disabled)', { timeout: 8000 });
await p.screenshot({ path: `${dir}/p1-horario.png` });
await p.locator('.clase:not(:disabled)').first().click();
await p.waitForSelector('#s2.on', { timeout: 8000 });
await llenarDatos('Camila Rojas', '3002223344');
try {
  await p.waitForSelector('#s3.on', { timeout: 8000 });
} catch {
  console.log('  [captura] no llego a pago. err2 =', JSON.stringify(await p.locator('#err2').innerText()));
  console.log('  [captura] seccion visible =', await p.evaluate(() =>
    ['s0','s1','s2','s3','s4','s5'].find(id => document.getElementById(id).classList.contains('on'))));
  throw new Error('captura de pago fallida');
}
await p.waitForTimeout(600);   // que termine el fundido de entrada
await p.screenshot({ path: `${dir}/p2-pago.png`, fullPage: true });
await p.locator('#ya-pague').click();
await p.waitForSelector('#s4.on');
await p.waitForTimeout(1200);
await p.screenshot({ path: `${dir}/p3-esperando.png` });

await nav.close();
console.log(`\n${fallos === 0 ? 'TODO EN VERDE' : fallos + ' FALLOS'}`);
process.exit(fallos ? 1 : 0);
