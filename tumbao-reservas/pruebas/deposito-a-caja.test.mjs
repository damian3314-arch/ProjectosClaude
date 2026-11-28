/**
 * Cobrar un depósito sin dueño desde el tablero — prueba de punta a punta.
 *
 * Existe por un fallo concreto. La primera versión de esto ponía botones
 * de concepto en el tablero y leía el id del depósito como `p.id`. Pero
 * la lista del tablero sale de admin_pendientes, que nombra esa columna
 * `pago_id`; solo la de la Caja la llama `id`. Resultado: el ingreso se
 * registraba SIN enlazar, el depósito no se descontaba y seguía saliendo
 * en la lista. Dos movimientos reales quedaron sueltos en producción.
 *
 * La prueba que lo dejó pasar usaba datos inventados con `id`, o sea una
 * forma que no existe. Por eso aquí LIBRES usa `pago_id`, que es lo que
 * de verdad manda el servidor.
 *
 * Necesita Chromium. El gancho window.__e2e lo pone instrumentar.mjs
 * sobre una copia temporal de docs/admin.html, así que corre sin
 * argumentos:
 *
 *   node deposito-a-caja.test.mjs
 *
 * Admite una ruta suelta para apuntar a otra copia del panel.
 */
import { chromium } from 'playwright-core';
import { rutaDelPanel } from './instrumentar.mjs';
const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
const p = await b.newPage({ viewport: { width: 430, height: 900 } });
const enviado = [];
await p.route('**/api/**', r => r.fulfill({ status: 200, contentType: 'application/json',
  body: JSON.stringify({ ok: true, pagos_libres: [], resumen_conceptos: [] }) }));
await p.route('**/api/registrar', async r => {
  enviado.push(JSON.parse(r.request().postData() || '{}'));
  await r.fulfill({ status: 200, contentType: 'application/json',
    body: JSON.stringify({ ok: true, id: 'mov-1', dia: '2026-08-28' }) });
});
const errs = []; p.on('pageerror', e => errs.push(String(e)));
await p.goto('file://' + rutaDelPanel());

// LA FORMA REAL: admin_pendientes devuelve `pago_id`, no `id`.
const LIBRES = [
  { pago_id: '11111111-2222-4333-8444-555555555555', remitente: 'GENNY PAOLA GONZALEZ VEGA',
    valor_cop: 85000, cuando: '28/08 09:39' },
  { pago_id: 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee', remitente: 'JENNY LISET VERGARA GONZALEZ',
    valor_cop: 125000, cuando: '27/08 21:47' },
];
const DIA = { ok: true, pagos_libres: LIBRES.map(x => ({ id: x.pago_id, ...x })),
              resumen_conceptos: [], entradas: {}, banco: {}, cierre: {} };
await p.evaluate(([l, d]) => window.__e2e.sembrar(l, d), [LIBRES, DIA]);

const ok = (n, c, extra='') => console.log(`${c ? '✓' : '✗'} ${n}${extra ? '  → ' + extra : ''}`);

// 1) Tocar el SEGUNDO depósito, el de $125.000.
await p.locator('#sin-dueno .pago').nth(1).click();
let e = await p.evaluate(() => window.__e2e.estado());
ok('sale el aviso del depósito reservado', e.avisoVisible, e.aviso.slice(0, 60));
ok('nombra el depósito correcto', /125\.000/.test(e.aviso) && /JENNY/.test(e.aviso));

// 2) Escoger el concepto "Mensualidad" en la Caja.
await p.locator('#p-caja .caja-btn').filter({ hasText: /^Mensualidad/ }).first().click();
e = await p.evaluate(() => window.__e2e.estado());
ok('el modal abre', e.modalAbierto, e.texto);
ok('con el valor del depósito', e.valor === '125000', e.valor);
ok('en transferencia', e.medio === 'transferencia', e.medio);
ok('con el depósito ya escogido', e.pagoElegido === 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee', String(e.pagoElegido));
ok('y el aviso ya no está', !e.avisoVisible);

// 3) Guardar.
await p.evaluate(() => document.getElementById('modal-guardar').click());
await p.waitForTimeout(500);
ok('se envió una sola petición', enviado.length === 1, String(enviado.length));
console.log(JSON.stringify(enviado[0], null, 1));
ok('con el pago_id de verdad',
   enviado[0] && enviado[0].pago_id === 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee');
console.log(errs.length ? 'ERRORES JS: ' + errs.join(' | ') : 'sin errores de JS');
await b.close();
