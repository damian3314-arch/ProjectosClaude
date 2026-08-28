/**
 * Juntar dos depósitos que son un solo pago — de punta a punta.
 *
 * El caso de Genny: $85.000 por una "media mensualidad" que no existe y
 * $40.000 después para completar la mensualidad. Son dos transferencias
 * y un solo cobro de $125.000.
 *
 * Lo que se cuida aquí es que el modo juntar NO estorbe lo normal:
 * tocar un depósito para cobrarlo es lo que se hace veinte veces al
 * día, y juntar dos es raro. Si al entrar al modo se rompiera el toque
 * de siempre, se cambiaría un problema del mes por uno diario.
 *
 * Los datos usan `pago_id`, que es como los nombra admin_pendientes.
 * Inventar esa forma fue lo que dejó pasar el fallo anterior.
 *
 *   node juntar-depositos.test.mjs <ruta a admin.html con __e2e>
 */
import { chromium } from 'playwright-core';
const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
const p = await b.newPage({ viewport: { width: 430, height: 900 } });

const enviado = [];
await p.route('**/api/**', async r => {
  enviado.push({ url: r.request().url(), cuerpo: JSON.parse(r.request().postData() || '{}') });
  await r.fulfill({ status: 200, contentType: 'application/json',
    body: JSON.stringify({ ok: true, partes: 2, total_cop: 125000, pagos_libres: [], reservas: [] }) });
});
const errs = []; p.on('pageerror', e => errs.push(String(e)));
await p.goto('file://' + process.argv[2]);

const A = '11111111-2222-4333-8444-555555555555';
const B = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';
const C = '99999999-8888-4777-8666-555555555555';
const SUELTOS = [
  { pago_id: A, remitente: 'GENNY PAOLA GONZALEZ VEGA', valor_cop: 85000,
    saldo_cop: 85000, es_grupo: false, partes: [], cuando: '28/08 09:39' },
  { pago_id: B, remitente: 'GENNY PAOLA GONZALEZ VEGA', valor_cop: 40000,
    saldo_cop: 40000, es_grupo: false, partes: [], cuando: '28/08 17:45' },
  { pago_id: C, remitente: 'OTRA PERSONA', valor_cop: 15000,
    saldo_cop: 15000, es_grupo: false, partes: [], cuando: '28/08 12:00' },
];

let fallos = 0;
const ok = (n, c, extra='') => { if (!c) fallos++;
  console.log(`${c ? '✓' : '✗'} ${n}${extra ? '  → ' + extra : ''}`); };

await p.evaluate(l => window.__e2e.sembrarLibres(l), SUELTOS);

// ── 1. lo de siempre sigue igual ──────────────────────────────────
let e = await p.evaluate(() => window.__e2e.libres());
ok('salen los tres depósitos', e.filas === 3, String(e.filas));
ok('sin modo juntar no hay tildes', e.tics === 0);
await p.evaluate(() => window.__e2e.tocarPago(0));
e = await p.evaluate(() => window.__e2e.estadoDep());
ok('tocar uno sigue llevándolo a la Caja', e.avisoVisible, e.aviso.slice(0, 50));
ok('con el depósito correcto', /85\.000/.test(e.aviso) && /GENNY/.test(e.aviso));

// ── 2. entrar al modo juntar ──────────────────────────────────────
await p.evaluate(() => window.__e2e.modoJuntar());
e = await p.evaluate(() => window.__e2e.libres());
ok('el botón de juntar aparece', e.hayBotonJuntar);
ok('el confirmar nace apagado', e.confirmarApagado);

await p.evaluate(() => window.__e2e.tocarPago(0));
e = await p.evaluate(() => window.__e2e.libres());
ok('con uno escogido sigue apagado', e.confirmarApagado, e.cuenta);
ok('y lo marca', e.marcados === 1, String(e.marcados));

await p.evaluate(() => window.__e2e.tocarPago(1));
e = await p.evaluate(() => window.__e2e.libres());
ok('con dos ya deja juntar', !e.confirmarApagado);
ok('y suma los dos', /125\.000/.test(e.cuenta), e.cuenta);

// Destildar vuelve atrás: equivocarse escogiendo no puede ser
// un camino sin regreso.
await p.evaluate(() => window.__e2e.tocarPago(1));
e = await p.evaluate(() => window.__e2e.libres());
ok('destildar vuelve a apagar el confirmar', e.confirmarApagado, e.cuenta);
await p.evaluate(() => window.__e2e.tocarPago(1));

// ── 3. juntar de verdad ───────────────────────────────────────────
enviado.length = 0;
await p.evaluate(() => window.__e2e.confirmarJuntar());
await p.waitForTimeout(300);
const env = enviado.find(x => /juntar-pagos/.test(x.url));
ok('llama a juntar-pagos', !!env, env && env.url);
ok('manda los dos escogidos', env && Array.isArray(env.cuerpo.ids) &&
   env.cuerpo.ids.length === 2 && env.cuerpo.ids.includes(A) && env.cuerpo.ids.includes(B),
   env && JSON.stringify(env.cuerpo.ids));
ok('y NO manda el tercero', env && !env.cuerpo.ids.includes(C));

// ── 4. ya juntos: una fila que dice de qué se compone ─────────────
await p.evaluate(([a, c]) => window.__e2e.sembrarLibres([
  { pago_id: a, remitente: 'GENNY PAOLA GONZALEZ VEGA', valor_cop: 85000,
    saldo_cop: 125000, es_grupo: true, cuando: '28/08 09:39',
    partes: [{ pago_id: a, valor_cop: 85000, cuando: '28/08 09:39' },
             { pago_id: 'x', valor_cop: 40000, cuando: '28/08 17:45' }] },
  { pago_id: c, remitente: 'OTRA PERSONA', valor_cop: 15000,
    saldo_cop: 15000, es_grupo: false, partes: [], cuando: '28/08 12:00' },
]), [A, C]);
e = await p.evaluate(() => window.__e2e.libres());
ok('el grupo es UNA fila', e.filas === 2, String(e.filas));
ok('y muestra el total del grupo', /125\.000/.test(e.textoPrimera), e.textoPrimera.slice(0, 60));
ok('dice de qué transferencias se compone', e.partesVisibles === 2, String(e.partesVisibles));
ok('y ofrece separarlo', e.haySeparar);

// ── 5. tocar el grupo lo cobra por su total ───────────────────────
await p.evaluate(() => window.__e2e.tocarPago(0));
e = await p.evaluate(() => window.__e2e.estadoDep());
ok('cobrar el grupo va por los $125.000', /125\.000/.test(e.aviso), e.aviso.slice(0, 60));

ok('sin errores de JS', errs.length === 0, errs.join(' | '));
console.log(fallos ? `\n${fallos} fallo(s)` : '\nTodo bien');
await b.close();
process.exit(fallos ? 1 : 0);
