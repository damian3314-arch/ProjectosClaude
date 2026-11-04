/**
 * Vender una tiquetera desde el panel, y verla con su saldo (0097).
 *
 * POR QUÉ EXISTE
 * Recepción vende la tiquetera aquí (genera el código) y necesita verla
 * en la lista con cuántas clases le quedan -- si algo de esto se rompe
 * en silencio, nadie más se entera hasta que una clienta reclama.
 *
 * Dos cosas que no pueden fallar:
 *
 *   1. Los tres roles (cajero, administrador, propietario) pueden
 *      vender -- es caja de mostrador, no algo que dependa del dueño.
 *   2. El formulario no manda nada al servidor si faltan datos básicos
 *      (nombre, celular, número de clases, vigencia): se avisa en la
 *      pantalla y ya.
 *
 *   node tiquetera-panel.test.mjs
 */
import { chromium } from 'playwright-core';
import { rutaDelPanel, irASeccion } from './instrumentar.mjs';
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';

const PANEL = rutaDelPanel();
const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });

let fallos = 0;
const ok = (n, c, extra = '') => { if (!c) fallos++;
  console.log(`${c ? '✓' : 'FALLO'} ${n}${extra ? '  → ' + extra : ''}`); };
const titulo = t => console.log(`\n-- ${t} ${'-'.repeat(Math.max(0, 54 - t.length))}`);

const srv = createServer(async (q, s) => {
  try {
    const cuerpo = await readFile(PANEL);
    s.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' }); s.end(cuerpo);
  } catch (_) { s.writeHead(404); s.end('no'); }
});
await new Promise(r => srv.listen(8132, r));

/* Lo que ya existe cuando se abre la pestaña, y lo que se agrega al
   vender. La lista se sirve desde aquí mismo para que la prueba pueda
   comprobar que, tras vender, la pantalla la vuelve a pedir y la pinta. */
let vendidas = [];

async function abrirPanel(rol) {
  const p = await b.newPage({ viewport: { width: 390, height: 900 } });
  const errs = []; p.on('pageerror', e => errs.push(String(e)));

  await p.route('**/api/**', r => r.fulfill({ status: 200,
    contentType: 'application/json',
    body: JSON.stringify({ ok: true, dias: [], reservas: [], pagos_libres: [],
                           movimientos: [], resumen_conceptos: [] }) }));
  await p.route('**/api/admin/tiqueteras-listar', r => r.fulfill({ status: 200,
    contentType: 'application/json', body: JSON.stringify({ ok: true, tiqueteras: vendidas }) }));
  await p.route('**/api/admin/tiquetera-crear', async r => {
    const body = r.request().postDataJSON();
    const nueva = {
      id: vendidas.length + 1, codigo: 'COD' + (vendidas.length + 1),
      nombre: body.nombre, telefono: body.telefono,
      clases_totales: body.clases, clases_usadas: 0,
      clases_restantes: body.clases, precio_cop: body.precio_cop,
      vence_el: '2026-11-08', activa: true,
    };
    vendidas = [nueva, ...vendidas];
    return r.fulfill({ status: 200, contentType: 'application/json',
      body: JSON.stringify({ ok: true, id: nueva.id, codigo: nueva.codigo,
                             nombre: nueva.nombre, clases: nueva.clases_totales,
                             vence_el: nueva.vence_el }) });
  });

  await p.addInitScript((r) => {
    localStorage.setItem('tumbao_admin_token',
      JSON.stringify({ token: 'x', rol: r, nombre: 'Prueba' }));
  }, rol);
  await p.goto('http://localhost:8132/', { waitUntil: 'load' });
  await p.waitForTimeout(400);
  return { p, errs };
}

/* ═══════ 1 · un cajero puede vender, no solo el propietario ═══════ */

titulo('1. El cajero vende una tiquetera');
{
  vendidas = [];
  const { p, errs } = await abrirPanel('cajero');

  await irASeccion(p, 'tab-tiqueteras');
  await p.waitForTimeout(200);
  ok('la pestaña abre sin errores', errs.length === 0, errs.join(' | '));
  ok('el título dice Tiqueteras', (await p.locator('#donde').innerText()) === 'Tiqueteras');
  ok('sin nada vendido todavía, la lista lo dice',
     /no hay tiqueteras/i.test(await p.locator('#tiq-lista').innerText()));

  await p.fill('#tiq-nombre', 'Camila Rojas');
  await p.fill('#tiq-telefono', '3001234567');
  await p.fill('#tiq-clases', '4');
  await p.fill('#tiq-vigencia', '45');
  await p.fill('#tiq-precio', '52000');
  await p.locator('#tiq-crear-btn').click();
  await p.waitForTimeout(300);

  ok('limpia el nombre después de vender', (await p.inputValue('#tiq-nombre')) === '');
  const lista = await p.locator('#tiq-lista').innerText();
  ok('la nueva tiquetera aparece en la lista', /Camila Rojas/.test(lista), lista);
  ok('con su código', /COD1/.test(lista), lista);
  ok('y las 4 clases completas, ninguna usada', /4 de 4/.test(lista), lista);

  ok('sin errores de JS', errs.length === 0, errs.join(' | '));
  await p.close();
}

/* ═══════ 2 · sin datos básicos, no se manda nada ═══════ */

titulo('2. Formulario incompleto');
{
  vendidas = [];
  const { p, errs } = await abrirPanel('administrador');
  await irASeccion(p, 'tab-tiqueteras');
  await p.waitForTimeout(200);

  let pedido = false;
  await p.route('**/api/admin/tiquetera-crear', r => { pedido = true; r.continue(); });

  // Celular incompleto, el resto en blanco.
  await p.fill('#tiq-telefono', '123');
  await p.locator('#tiq-crear-btn').click();
  await p.waitForTimeout(200);

  ok('no llega a pedirle nada al servidor', !pedido);
  ok('avisa en la pantalla, no en silencio',
     (await p.locator('#tiq-crear-estado').innerText()).length > 0);

  ok('sin errores de JS', errs.length === 0, errs.join(' | '));
  await p.close();
}

/* ═══════ 3 · el pase de regalo se distingue de una tiquetera comprada ═══════
   0121: quien va a todas las clases de su tiquetera gana un pase (una
   tiquetera de 1 clase, sin precio). En la lista tiene que leerse como
   regalo y no como una venta de $0. */

titulo('3. Pase de regalo por constancia');
{
  vendidas = [
    { id: 30, codigo: 'PASE01', nombre: 'Laura Gómez', telefono: '3001112233',
      clases_totales: 1, clases_usadas: 0, clases_restantes: 1, precio_cop: 0,
      vence_el: '2026-11-15', activa: true, estado: 'confirmada', premio: true },
    { id: 31, codigo: 'COMP02', nombre: 'Marta Ruiz', telefono: '3004445566',
      clases_totales: 4, clases_usadas: 1, clases_restantes: 3, precio_cop: 52000,
      vence_el: '2026-11-10', activa: true, estado: 'confirmada', premio: false },
  ];
  const { p, errs } = await abrirPanel('administrador');
  await irASeccion(p, 'tab-tiqueteras');
  await p.waitForTimeout(500);
  const filas = p.locator('#tiq-lista .fila');
  ok('salen las dos', await filas.count() === 2, String(await filas.count()));
  const pase = (await filas.nth(0).innerText()).toLowerCase();
  const comprada = (await filas.nth(1).innerText()).toLowerCase();
  ok('el pase dice que es un regalo', pase.includes('pase de regalo'), pase.replace(/\s+/g, ' ').slice(0, 90));
  ok('y no enseña un precio', !/\$\s*0|52\.000/.test(pase));
  ok('la comprada NO dice regalo', !comprada.includes('regalo'));
  ok('y sí enseña lo que pagó', /52\.000/.test(comprada));
  ok('sin errores de JS', errs.length === 0, errs.join(' | '));
  await p.close();
}

srv.close();
await b.close();
console.log(fallos ? `\n\x1b[31m${fallos} fallo(s)\x1b[0m`
                   : '\n\x1b[32mtodo en verde\x1b[0m');
process.exit(fallos ? 1 : 0);
