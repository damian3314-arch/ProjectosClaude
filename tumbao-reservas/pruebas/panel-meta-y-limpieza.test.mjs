/**
 * El panel más liviano (29 oct, Damián): «cuánto falta por vender para la meta» a la vista, la tesorería cerrada hasta que se
 * toque, el ranking sin quienes ya pagaron mensualidad, lo viejo plegado y el panel instalable como aplicación.
 *
 *   node panel-meta-y-limpieza.test.mjs
 */
import { chromium } from 'playwright-core';
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { readFileSync } from 'node:fs';

const RAIZ = new URL('../../docs/', import.meta.url).pathname;
const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });

let fallos = 0;
const ok = (n, c, extra = '') => { if (!c) fallos++; console.log(`${c ? '✓' : '✗'} ${n}${extra ? '  → ' + extra : ''}`); };
const titulo = t => console.log(`\n-- ${t} ${'-'.repeat(Math.max(0, 54 - t.length))}`);

const RES = { ok: true, hoy: '2026-10-29', primer_caja: '2026-08-10',
  dia: { ingreso_cop: 640000, personas: 30 }, dia_semana_antes: { ingreso_cop: 500000 },
  semana: { ingreso_cop: 3100000, personas: 120 }, semana_antes: { ingreso_cop: 2800000 },
  mes: { ingreso_cop: 11567000, personas: 347, mensualidades_n: 51 }, mes_antes: { ingreso_cop: 9000000 },
  plata_mes: { entro_cop: 11567000, salio_cop: 7400000, utilidad_cop: 4167000 }, plata_mes_antes: { entro_cop: 9000000 },
  plata_semana: { entro_cop: 3100000 }, plata_semana_antes: { entro_cop: 2800000 }, gastos_mes: [{ concepto: 'profesores', cop: 3000000 }] };
const META = { ok: true, mes: '2026-10', hoy: '2026-10-29', meta_cop: 16000000, meta_definida_para: '2026-10', vendido_cop: 11567000,
  falta_cop: 4433000, pct: 72, dias_restantes: 3, por_dia_cop: 1477667, cumplida: false, puede_cambiar: true };
const CL = (n, t, d, a) => ({ nombre: n, telefono: t, dias: d, plata_cop: d * 15000, ultima: '2026-10-27', afiliada: a });
const RANK = { ok: true, clientes: [CL('Ana ConPlan', '3001111111', 9, false), CL('Beatriz Libre', '3002222222', 8, false), CL('Carla Afiliada', '3003333333', 7, true),
  CL('Diana Libre', '3004444444', 6, false), CL('Eva Libre', '3005555555', 5, false), CL('Flor Libre', '3006666666', 4, false), CL('Gina Libre', '3007777777', 3, false), CL('Hilda Libre', '3008888888', 2, false)] };
const ayer = (d) => new Date(Date.now() - d * 24 * 3600 * 1000).toISOString();
const PEND = [
  { codigo: 'NUEVA1', nombre: 'Reciente Rosa', telefono: '3001230001', estado: 'pendiente_validacion', tipo: 'suelta', creada_at: ayer(0), clase_id: 'c1', clase: 'Rumba', fecha_hora: new Date(Date.now() + 3600e3).toISOString(), precio_cop: 15000, cupos: 1, acompanantes: [], pagos_sueltos: [] },
  { codigo: 'VIEJA1', nombre: 'Antigua Ana', telefono: '3001230002', estado: 'pendiente_validacion', tipo: 'suelta', creada_at: ayer(9), clase_id: 'c2', clase: 'Rumba', fecha_hora: ayer(8), precio_cop: 15000, cupos: 1, acompanantes: [], pagos_sueltos: [] },
  { codigo: 'VIEJA2', nombre: 'Antigua Bea', telefono: '3001230003', estado: 'pendiente_validacion', tipo: 'suelta', creada_at: ayer(9), clase_id: 'c2', clase: 'Rumba', fecha_hora: ayer(8), precio_cop: 15000, cupos: 1, acompanantes: [], pagos_sueltos: [] },
];

async function abrir({ rol = 'propietario', meta = META } = {}) {
  const llamadas = [];
  const p = await b.newPage({ viewport: { width: 390, height: 860 } });
  const errs = []; p.on('pageerror', e => errs.push(String(e)));
  const json = (o) => ({ status: 200, contentType: 'application/json', body: JSON.stringify(o) });
  await p.route('**/api/**', r => { llamadas.push(r.request().url().split('/api/admin/')[1]); r.fulfill(json({ ok: true, dias: [], reservas: [], pagos_libres: [], movimientos: [], resumen_conceptos: [], salidas: [], solas: [], cuantas: 0 })); });
  await p.route('**/api/admin/resumen-gerencia', r => { llamadas.push('resumen-gerencia'); r.fulfill(json(RES)); });
  await p.route('**/api/admin/meta-mes', r => { llamadas.push('meta-mes'); r.fulfill(json(meta)); });
  await p.route('**/api/admin/planes-vigentes', r => { llamadas.push('planes-vigentes'); r.fulfill(json({ ok: true, telefonos: ['3001111111'] })); });
  await p.route('**/api/admin/clientes-ranking', r => { llamadas.push('clientes-ranking'); r.fulfill(json(RANK)); });
  await p.route('**/api/admin/pendientes', r => { llamadas.push('pendientes'); r.fulfill(json({ ok: true, reservas: PEND, pagos_libres: [] })); });
  await p.addInitScript((rl) => localStorage.setItem('tumbao_admin_token', JSON.stringify({ token: 'x', rol: rl, nombre: 'Prueba' })), rol);
  await p.goto('http://localhost:8133/', { waitUntil: 'load' });
  await p.waitForTimeout(800);
  return { p, errs, llamadas };
}
const srv = createServer(async (q, s) => {
  try {
    const u = q.url.split('?')[0];
    const f = RAIZ + (u === '/' ? 'admin.html' : u.slice(1));
    const c = await readFile(f);
    s.writeHead(200, { 'Content-Type': f.endsWith('.html') ? 'text/html; charset=utf-8' : 'application/octet-stream' }); s.end(c);
  } catch (_) { s.writeHead(404); s.end('no'); }
});
await new Promise(r => srv.listen(8133, r));

titulo('1. La meta del mes');
{
  const { p, errs } = await abrir();
  const t = (await p.locator('#meta-resumen').innerText()).replace(/\s+/g, ' ');
  ok('lo primero del resumen: cuánto FALTA por vender', /Falta por vender \$4\.433\.000/.test(t), t);
  ok('con lo vendido, la meta y el porcentaje', /Vendido \$11\.567\.000 de \$16\.000\.000 · 72 %/.test(t));
  ok('y el ritmo: días de clase que quedan y cuánto por día', /Quedan 3 días de clase/.test(t) && /\$1\.477\.667 por día/.test(t));
  ok('la barra de avance lleva el 72 %', (await p.locator('#meta-resumen .barra i').getAttribute('style')).includes('72%'));
  ok('el propietario puede cambiar la meta', await p.locator('#meta-resumen [data-cambiar-meta]').count() === 1);
  const r = (await p.locator('#fichas-resumen').innerText()).replace(/\s+/g, ' ');
  ok('el resumen ya no habla de lo que sale ni de lo que «queda»', !/queda/i.test(r) && !/salidas/i.test(r) && !/profesores/i.test(r), r);
  await p.click('#tab-mas'); await p.click('#tab-tablero'); await p.waitForTimeout(400);
  ok('el tablero también la lleva, en pequeño', /Falta por vender \$4\.433\.000/.test((await p.locator('#meta-tablero').innerText()).replace(/\s+/g, ' ')));
  ok('sin errores de JS', errs.length === 0, errs.join(' | '));
  await p.close();
}
{
  const { p } = await abrir({ meta: { ...META, cumplida: true, falta_cop: 0, vendido_cop: 16500000, pct: 103 } });
  const t = (await p.locator('#meta-resumen').innerText()).replace(/\s+/g, ' ');
  ok('con la meta cumplida lo celebra y dice cuánto la pasó', /Meta cumplida/.test(t) && /\$500\.000 por encima/.test(t), t);
  await p.close();
}
{
  const { p } = await abrir({ meta: { ...META, meta_cop: 0, meta_definida_para: null, falta_cop: 0, pct: null } });
  ok('sin meta definida lo dice y deja definirla', /Defínela/.test(await p.locator('#meta-resumen').innerText()));
  await p.close();
}
{
  const { p, llamadas } = await abrir({ rol: 'cajero' });
  ok('la cajera no pide ni ve la meta', !llamadas.includes('meta-mes') && await p.locator('#meta-resumen').isHidden() && await p.locator('#meta-tablero').isHidden());
  await p.close();
}

titulo('2. La tesorería, cerrada hasta que se toque');
{
  const { p, llamadas } = await abrir();
  await p.click('#tab-mas'); await p.click('#tab-tesoreria'); await p.waitForTimeout(300);
  ok('al entrar solo se ve el candado, sin ninguna cifra', await p.locator('#tes-candado').isVisible() && !(await p.locator('#tes-fichas').isVisible()));
  ok('y ni siquiera se pidieron los datos', !llamadas.includes('tesoreria'));
  await p.click('#tes-abrir'); await p.waitForTimeout(500);
  ok('con un toque se abre y se pide', await p.locator('#tes-candado').isHidden() && llamadas.includes('tesoreria'));
  await p.click('#tab-mas'); await p.click('#tab-tablero'); await p.waitForTimeout(200);
  await p.click('#tab-mas'); await p.click('#tab-tesoreria'); await p.waitForTimeout(300);
  ok('al salir y volver, está cerrada otra vez', await p.locator('#tes-candado').isVisible());
  await p.close();
}

titulo('3. «Vienen más»: sin quienes ya tienen plan');
{
  const { p, llamadas } = await abrir();
  const t = (await p.locator('#lista-ranking').innerText()).replace(/\s+/g, ' ');
  ok('no sale quien tiene mensualidad por su celular', !/Ana ConPlan/.test(t), t);
  ok('no sale quien está marcada como afiliada', !/Carla Afiliada/.test(t));
  ok('la lista se mantiene llena: cinco sin plan', (await p.locator('#lista-ranking .cliente-fila').count()) === 5 && /Beatriz Libre/.test(t) && /Flor Libre/.test(t));
  ok('pidió quiénes tienen plan', llamadas.includes('planes-vigentes'));
  await p.close();
}

titulo('4. Por validar: lo de clases pasadas se pliega');
{
  const { p } = await abrir();
  await p.click('#tab-pendientes'); await p.waitForTimeout(400);
  ok('el globo cuenta solo lo reciente (1), no lo de hace una semana', (await p.locator('#globo-pend').innerText()).trim() === '1');
  ok('lo reciente se ve arriba', /Reciente Rosa/.test(await p.locator('#lista-pend').innerText()));
  const det = p.locator('#lista-pend details.antiguas');
  ok('lo antiguo va plegado, con su cuenta', await det.count() === 1 && /\(2\)/.test(await det.locator('summary').innerText()));
  ok('y no se pierde: abriéndolo están las dos', (await det.evaluate(d => { d.open = true; return d.innerText; })).includes('Antigua Ana'));
  await p.close();
}

titulo('5. Instalable como aplicación');
{
  const html = readFileSync(RAIZ + 'admin.html', 'utf8');
  const man = JSON.parse(readFileSync(RAIZ + 'admin.webmanifest', 'utf8'));
  ok('el panel enlaza su manifiesto y el ícono de iPhone', /rel="manifest" href="admin\.webmanifest"/.test(html) && /rel="apple-touch-icon"/.test(html));
  ok('el manifiesto abre el panel a pantalla completa', man.display === 'standalone' && man.start_url === '/admin' && man.icons.some(i => i.sizes === '512x512'));
  ok('el service worker NO guarda nada en caché (plata y cupos en vivo)', !/caches\./.test(readFileSync(RAIZ + 'sw-panel.js', 'utf8').replace(/\/\*[\s\S]*?\*\//g, '')));
  ok('el celular respeta el borde de arriba y de abajo cuando está instalado', /display-mode:standalone/.test(html) && /safe-area-inset-top/.test(html));
}

srv.close(); await b.close();
console.log(`\n${fallos ? '✗ ' + fallos + ' con problemas' : '✓ todo bien'}`);
process.exit(fallos ? 1 : 0);
