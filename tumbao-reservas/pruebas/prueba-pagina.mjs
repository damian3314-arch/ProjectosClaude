import { chromium } from 'playwright-core';

const BASE = 'http://localhost:8899/';
let fallos = 0;
const ok = (n, c, extra='') => { console.log(`${c ? '✓' : '✗'} ${n}${extra ? '  → ' + extra : ''}`); if (!c) fallos++; };

const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
const ctx = await b.newContext({ viewport: { width: 390, height: 844 }, locale: 'es-CO' });
const p = await ctx.newPage();

const errores = [];
p.on('console', m => { if (m.type() === 'error') errores.push(m.text()); });
p.on('pageerror', e => errores.push('pageerror: ' + e.message));

await p.goto(BASE, { waitUntil: 'networkidle' });

// ---------- PASO 1 ----------
await p.waitForSelector('.dia', { timeout: 8000 });
const nDias = await p.locator('.dia').count();
ok('carga los días disponibles', nDias > 0, `${nDias} días`);

const primerDia = await p.locator('.dia[aria-pressed="true"]').count();
ok('el primer día queda seleccionado solo', primerDia === 1);

const nClases = await p.locator('.clase').count();
ok('lista las clases del día', nClases > 0, `${nClases} clases`);

const horaTxt = await p.locator('.clase .hora').first().innerText();
ok('la hora sale compacta (7:00 pm)', /\d{1,2}:\d{2}\s?(am|pm)/i.test(horaTxt), `"${horaTxt}"`);

// agotadas deshabilitadas
const agotadas = await p.locator('.clase:disabled').count();
const conCero = await p.locator('.cupos.cero').count();
ok('las clases agotadas quedan deshabilitadas', agotadas === conCero, `${agotadas} agotadas`);

// cambiar de día
if (nDias > 1) {
  await p.locator('.dia').nth(1).click();
  await p.waitForTimeout(250);
  ok('cambiar de día repinta las clases', await p.locator('.clase').count() > 0);
  await p.locator('.dia').first().click();
  await p.waitForTimeout(250);
}

// ---------- PASO 2 ----------
await p.locator('.clase:not(:disabled)').first().click();
await p.waitForTimeout(400);
ok('pasa al paso 2 al elegir clase', await p.locator('#s2').isVisible());
const resumen = await p.locator('#resumen').innerText();
ok('muestra el resumen de la clase elegida', resumen.length > 10, resumen.replace(/\n/g, ' · '));

// validación: enviar vacío
await p.locator('#enviar').click();
await p.waitForTimeout(300);
ok('bloquea el envío sin nombre', await p.locator('#e-nombre').isVisible());
ok('bloquea el envío sin celular', await p.locator('#e-celular').isVisible());
ok('bloquea el envío sin habeas data', await p.locator('#e-habeas').isVisible());

// celular corto
await p.fill('#nombre', 'Valentina');
await p.fill('#celular', '30012');
await p.check('#habeas');
await p.locator('#enviar').click();
await p.waitForTimeout(300);
ok('rechaza celular de menos de 10 dígitos', await p.locator('#e-celular').isVisible());

// celular con formato y con +57
await p.fill('#celular', '+57 301 222 3355');
await p.fill('#apellido', 'Duque');
await p.locator('#enviar').click();
await p.waitForSelector('#s3.on', { timeout: 8000 });

// ---------- PASO 3 ----------
const codigo = (await p.locator('#ok-codigo').innerText()).trim();
ok('llega a la confirmación con código', /^[0-9A-F]{6}$/.test(codigo), codigo);
const detalle = await p.locator('#ok-detalle').innerText();
ok('muestra clase, fecha y hora', detalle.split('·').length === 3, detalle);
const wa = await p.locator('#ok-wa').getAttribute('href');
ok('el botón de WhatsApp lleva el código', wa.includes(codigo));

// ---------- doble envío / idempotencia ----------
await p.locator('#otra').click();
await p.waitForSelector('#s1.on');
await p.waitForTimeout(600);
await p.locator('.clase:not(:disabled)').first().click();
await p.waitForTimeout(300);
await p.fill('#nombre', 'Valentina');
await p.fill('#celular', '3012223355');
await p.check('#habeas');
await p.locator('#enviar').click();
await p.waitForSelector('#s3.on', { timeout: 8000 });
const codigo2 = (await p.locator('#ok-codigo').innerText()).trim();
ok('reservar dos veces devuelve el mismo código', codigo2 === codigo, `${codigo} vs ${codigo2}`);

// ---------- honeypot ----------
const r = await p.evaluate(async () => {
  const res = await fetch('http://localhost:8899/webhook/tumbao/reservar', {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ slug: 'tumbao', sesion_id: 1, first_name: 'Bot',
      phone: '3009998888', habeas_data: true, apellido2: 'soy-un-bot' })
  });
  return { status: res.status, body: await res.json() };
});
ok('el honeypot corta al bot sin tocar la base', r.status === 200 && r.body.codigo === 'OK', JSON.stringify(r.body));

// ---------- sin cupo ----------
// Llena una sesión a punta de peticiones reales y comprueba que la
// siguiente rebota. No depende del estado previo de la base.
const sinCupo = await p.evaluate(async () => {
  const reservar = (sesion_id, i) => fetch('http://localhost:8899/webhook/tumbao/reservar', {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ slug: 'tumbao', sesion_id, first_name: 'Relleno' + i,
      phone: '311' + String(i).padStart(7, '0'), habeas_data: true, apellido2: '' })
  });

  const d = await (await fetch('http://localhost:8899/webhook/tumbao/disponibilidad?slug=tumbao&dias=14')).json();
  const s = d.dias.flatMap(x => x.sesiones).find(x => !x.agotada);
  if (!s) return { error: 'no hay sesiones libres para la prueba' };

  for (let i = 0; i < s.cupos_disponibles + 2; i++) {
    const res = await reservar(s.sesion_id, i);
    if (res.status === 409) {
      return { status: res.status, body: await res.json(), tras: i, cupo: s.cupo_total };
    }
  }
  return { error: 'nunca devolvió 409 — la clase se sobrevendió' };
});
ok('clase llena responde 409 sin_cupo',
   sinCupo.status === 409 && sinCupo.body.error === 'sin_cupo',
   sinCupo.error || `rebotó tras llenar ${sinCupo.tras}/${sinCupo.cupo} cupos`);

// ---------- errores de consola ----------
const inesperados = errores.filter(e => !/40[09]|Conflict/.test(e));
ok('sin errores de JavaScript inesperados', inesperados.length === 0, inesperados.join(' | ') || 'ninguno');

// capturas
await p.locator('#otra').click().catch(()=>{});
await p.waitForTimeout(700);
await p.screenshot({ path: '/tmp/claude-0/-home-user-ProjectosClaude/d0121733-6e7e-5341-a1fa-1cbf03ef68ec/scratchpad/paso1.png' });
await p.locator('.clase:not(:disabled)').first().click();
await p.waitForTimeout(400);
await p.screenshot({ path: '/tmp/claude-0/-home-user-ProjectosClaude/d0121733-6e7e-5341-a1fa-1cbf03ef68ec/scratchpad/paso2.png' });

await b.close();
console.log(`\n${fallos === 0 ? 'TODO EN VERDE' : fallos + ' FALLOS'}`);
process.exit(fallos ? 1 : 0);
