/**
 * «Opina» en el panel (2 nov, Damián): la encuesta condensada, con el informe completo a un toque.   node opina-panel.test.mjs
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

// El informe de ejemplo, tal como lo manda el Worker de opiniones.
const { EJEMPLO, paginaInforme } = await import('../../tumbao-opina/src/informe.js');
const LISTO = { ok: true, estado: 'listo', ...EJEMPLO, desde: '', pagina: paginaInforme({ token: '', demo: true, ...EJEMPLO }) };

async function abrir({ rol = 'propietario', respuesta = LISTO, estado = 200 } = {}) {
  const p = await b.newPage({ viewport: { width: 1100, height: 900 } });
  const errs = []; p.on('pageerror', e => errs.push(String(e)));
  const pedidos = [];
  const json = (o, s = 200) => ({ status: s, contentType: 'application/json', headers: { 'Access-Control-Allow-Origin': '*' }, body: JSON.stringify(o) });
  await p.route('**/api/admin/**', r => r.fulfill(json({ ok: true, dias: [], reservas: [], pagos_libres: [], movimientos: [], clientes: [], telefonos: [] })));
  await p.route('**/opina.tumbaobaila.com/api/admin/informe', async r => {
    if (r.request().method() === 'OPTIONS') return r.fulfill({ status: 204, headers: { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': '*' } });
    pedidos.push(JSON.parse(r.request().postData() || '{}')); r.fulfill(json(respuesta, estado));
  });
  await p.addInitScript((rl) => localStorage.setItem('tumbao_admin_token', JSON.stringify({ token: 'x', rol: rl, nombre: 'Prueba' })), rol);
  await p.goto('http://localhost:8134/', { waitUntil: 'load' });
  await p.waitForTimeout(700);
  return { p, errs, pedidos };
}
const srv = createServer(async (q, s) => {
  try { const u = q.url.split('?')[0]; const f = RAIZ + (u === '/' ? 'admin.html' : u.slice(1)); const c = await readFile(f);
    s.writeHead(200, { 'Content-Type': f.endsWith('.html') ? 'text/html; charset=utf-8' : 'application/octet-stream' }); s.end(c); } catch (_) { s.writeHead(404); s.end('no'); }
});
await new Promise(r => srv.listen(8134, r));

titulo('1. La pestaña');
{
  const { p } = await abrir();
  ok('el propietario ve la sección «Opina»', await p.locator('#tab-opina').isVisible());
  const c = await abrir({ rol: 'cajero' });
  ok('la cajera no la ve', await c.p.locator('#tab-opina').isHidden());
}

titulo('2. Condensada');
{
  const { p, errs, pedidos } = await abrir();
  await p.locator('#tab-opina').click(); await p.waitForTimeout(700);
  const t = (await p.locator('#op-cuerpo').innerText()).replace(/\s+/g, ' ');
  ok('le pregunta al Worker de opiniones con el token del panel', pedidos.length === 1 && pedidos[0].token === 'x');
  ok('las cifras de arriba: respondieron, terminaron, datos, casos', /Respondieron 87/i.test(t) && /Terminaron las 5 61/i.test(t) && /Dejaron datos 23/i.test(t) && /Casos para atender 2/i.test(t), t.slice(0, 120));
  ok('trae el resumen, lo urgente, lo que aman y lo que piden cambiar', /En resumen/i.test(t) && /Lo urgente/i.test(t) && /Lo que más aman/i.test(t) && /Lo que más piden cambiar/i.test(t));
  ok('y los primeros pasos y la apuesta 2027', /Primeros pasos/i.test(t) && /La apuesta 2027/i.test(t));
  ok('es condensado: no trae la tabla de acciones ni la matriz', !/Hacer primero/i.test(t) && !/Cómo sabremos/i.test(t));
  ok('sin errores de JS', errs.length === 0, errs.join(' | '));
}

titulo('3. El informe completo');
{
  const { p } = await abrir();
  await p.locator('#tab-opina').click(); await p.waitForTimeout(600);
  ok('el informe completo no está a la vista hasta que se pide', await p.locator('#op-marco').count() === 0);
  await p.locator('#op-completo').click(); await p.waitForTimeout(500);
  const marco = p.frameLocator('#op-marco');
  ok('al tocar, se abre en un marco aislado con todas las secciones', (await marco.locator('body').innerText()).includes('Plan de acción') && (await marco.locator('body').innerText()).includes('Estrategia 2027'));
  ok('el marco no puede tocar el panel (sandbox sin same-origin)', !/allow-same-origin/.test(await p.locator('#op-marco').getAttribute('sandbox')));
  ok('y se puede ocultar de nuevo', (await p.locator('#op-completo').click(), await p.waitForTimeout(200), await p.locator('#op-marco-caja').isHidden()));
}

titulo('4. Sin respuestas y con la cajera');
{
  const { p } = await abrir({ respuesta: { ok: true, estado: 'pocas', total: 1, minimo: 3 } });
  await p.locator('#tab-opina').click(); await p.waitForTimeout(600);
  ok('con pocas respuestas lo dice y ofrece el ejemplo', /van 1/.test(await p.locator('#op-cuerpo').innerText()) && /ver ejemplo/.test(await p.locator('.op-demo').innerText()));
  const q = await abrir({ respuesta: { ok: true, estado: 'avance', avance: { hechas: 2, total: 5 } } });
  await q.p.locator('#tab-opina').click(); await q.p.waitForTimeout(500);
  ok('mientras analiza muestra el avance', /2 de 5/.test(await q.p.locator('#op-cuerpo').innerText()));
}

srv.close(); await b.close();
console.log(`\n${fallos ? '✗ ' + fallos + ' con problemas' : '✓ todo bien'}`);
process.exit(fallos ? 1 : 0);
