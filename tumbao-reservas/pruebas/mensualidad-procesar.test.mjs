/**
 * «Ya la procesé» y el cupo que se explica.
 *
 * POR QUÉ EXISTE ESTA PRUEBA
 * El 9 de septiembre la pestaña Mensualidad decía 30 personas a las
 * 7:00 pm y el listado de AdminGym decía 25. Ninguno mentía:
 *
 *   25  membresías activas (lo que ve AdminGym)
 *  + 5  mensualidades pagadas por la página, sin pasar a AdminGym
 *
 * Y DOS de esas cinco ya se habían pasado a mano, así que se contaban
 * dos veces. El número de verdad era 28.
 *
 * El doble conteo es estructural, no un descuido: mientras una pagada no
 * tenga forma de decir «ya está en AdminGym», se cuenta aparte para
 * siempre. El botón «Ya la procesé» es lo que cierra ese círculo, y por
 * eso se prueba junto con el desglose: son la misma cosa vista desde los
 * dos lados.
 *
 * El gancho window.__e2e lo pone instrumentar.mjs sobre una copia
 * temporal de docs/admin.html. Sin argumentos:
 *
 *   node mensualidad-procesar.test.mjs
 *
 * Admite una ruta suelta para apuntar a otra copia del panel.
 */
import { chromium } from 'playwright-core';
import { rutaDelPanel } from './instrumentar.mjs';
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';

const PANEL = rutaDelPanel();
const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
const p = await b.newPage({ viewport: { width: 430, height: 1000 } });
const errs = []; p.on('pageerror', e => errs.push(String(e)));

let fallos = 0;
const ok = (n, c, extra = '') => { if (!c) fallos++;
  console.log(`${c ? '✓' : '✗'} ${n}${extra ? '  → ' + extra : ''}`); };

/* El día real del 9 de septiembre, con los números que se vieron: 25 en
   AdminGym a las 7pm y 5 pagadas por la página sin pasar. */
const CUPOS = { ok: true, tope: 25, valor_cop: 125000, horas: [
  { hora: '07:00', etiqueta: '7:00 am', tope: 25, ocupadas: 21,
    activas: 21, por_procesar: 0, apartadas: 0, libres: 4 },
  { hora: '18:00', etiqueta: '6:00 pm', tope: 25, ocupadas: 25,
    activas: 25, por_procesar: 0, apartadas: 0, libres: 0 },
  { hora: '19:00', etiqueta: '7:00 pm', tope: 25, ocupadas: 30,
    activas: 25, por_procesar: 5, apartadas: 0, libres: 0 },
] };

const SOLIS = [
  { id: '11111111-1111-4111-8111-111111111111', nombre: 'Johanna Vargas',
    celular: '3001112233', hora: '19:00', estado: 'pagada',
    cuando: '07/09 14:31', dias: 2, valor_cop: 125000 },
  { id: '22222222-2222-4222-8222-222222222222', nombre: 'Leslie Otálora',
    celular: '3004445566', hora: '19:00', estado: 'lista_espera',
    cuando: '07/09 14:32', dias: 2, valor_cop: 125000 },
  { id: '33333333-3333-4333-8333-333333333333', nombre: 'Bibiana Pinilla',
    celular: '3007778899', hora: '19:00', estado: 'atendida',
    cuando: '08/09 18:08', dias: 1, valor_cop: 125000 },
];

const enviado = [];
let lista = { ok: true, cupos: CUPOS, solicitudes: SOLIS };

/* EN PLAYWRIGHT MANDA LA ÚLTIMA RUTA REGISTRADA, no la más específica.
   Por eso van de lo general a lo particular: con el genérico al final,
   se come /api/mensualidad y la pestaña sale vacía sin que nada falle. */
await p.route('**/api/**', r => r.fulfill({ status: 200,
  contentType: 'application/json',
  body: JSON.stringify({ ok: true, dias: [], reservas: [], pagos_libres: [],
                         movimientos: [], resumen_conceptos: [] }) }));
await p.route('**/api/mensualidad', r => r.fulfill({ status: 200,
  contentType: 'application/json', body: JSON.stringify(lista) }));
await p.route('**/api/mensualidad/atender', async r => {
  enviado.push(JSON.parse(r.request().postData() || '{}'));
  await r.fulfill({ status: 200, contentType: 'application/json',
    body: JSON.stringify({ ok: true, ya_estaba: false,
      nombre: 'Johanna Vargas', estado_antes: 'pagada' }) });
});

// Sirve la copia instrumentada por http: el panel guarda la sesión en
// localStorage, y en file:// ese almacén es inservible entre cargas.
const srv = createServer(async (q, s) => {
  try {
    const cuerpo = await readFile(PANEL);
    s.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' }); s.end(cuerpo);
  } catch (_) { s.writeHead(404); s.end('no'); }
});
await new Promise(r => srv.listen(8126, r));

await p.addInitScript(() => {
  localStorage.setItem('tumbao_admin_token',
    JSON.stringify({ token: 'x', rol: 'propietario', nombre: 'Prueba' }));
});
/* El confirm() del botón. La respuesta es una BANDERA en la página, no
   una función expuesta desde node: `exposeFunction` devuelve una
   promesa, y una promesa siempre es cierta, así que el confirm aceptaba
   siempre y el bloque de «me arrepentí» pasaba sin probar nada. */
await p.addInitScript(() => {
  window.__quiere = true;
  window.__confirmado = [];
  window.confirm = (t) => { window.__confirmado.push(t); return window.__quiere; };
});
const responder = (v) => p.evaluate(x => { window.__quiere = x; }, v);

await p.goto('http://localhost:8126/', { waitUntil: 'load' });
await p.waitForTimeout(500);
await p.click('#tab-mensualidad');
await p.waitForTimeout(600);

/* ═══════════ 1. el cupo dice de dónde sale ═══════════ */

const cupos = (await p.locator('#mens-cupos').innerText()).replace(/\s+/g, ' ');
ok('el 7pm sigue diciendo el total que suma el sistema',
   /30 de 25/.test(cupos), cupos);
ok('y ahora dice cuántas de esas ve AdminGym',
   /25 en AdminGym/.test(cupos),
   'sin esto, 30 contra 25 no se podía explicar');
ok('y cuántas faltan por pasarle', /5 por pasar/.test(cupos));

// El horario sin pendientes no repite el mismo número dos veces: una
// segunda línea que dice lo mismo enseña a no leer la tarjeta.
ok('un horario sin pendientes no se desglosa',
   !/21 en AdminGym/.test(cupos), 'el 7am no tiene nada por pasar');

/* ═══════════ 2. el botón sale donde tiene que salir ═══════════ */

const conBoton = await p.locator('[data-atender]').count();
ok('hay botón en la pagada y en la de lista de espera', conBoton === 2,
   `${conBoton} botones`);
ok('la pagada lo tiene',
   await p.locator('[data-atender="11111111-1111-4111-8111-111111111111"]').count() === 1);
ok('la de lista de espera también',
   await p.locator('[data-atender="22222222-2222-4222-8222-222222222222"]').count() === 1,
   'ahí quiere decir «ya la llamé»');
ok('la que ya está atendida NO lo tiene',
   await p.locator('[data-atender="33333333-3333-4333-8333-333333333333"]').count() === 0,
   'no hay nada que hacer con ella');

/* ═══════════ 3. pregunta antes de sacar a alguien de la lista ═══════════ */

await responder(false);
enviado.length = 0;
await p.click('[data-atender="11111111-1111-4111-8111-111111111111"]');
await p.waitForTimeout(300);
ok('preguntó antes de hacer nada',
   (await p.evaluate(() => window.__confirmado.length)) === 1);
ok('y nombra a quién se va a procesar',
   /Johanna Vargas/.test(await p.evaluate(() => window.__confirmado[0] || '')),
   await p.evaluate(() => (window.__confirmado[0] || '').slice(0, 60)));
ok('diciendo que no, no se manda nada', enviado.length === 0,
   'un roce del dedo en el celular no puede perder a una clienta');

/* ═══════════ 4. diciendo que sí, se procesa ═══════════ */

await responder(true);
enviado.length = 0;
// La respuesta de después: ya sin la pagada, y el cupo cerrado en 25.
lista = { ok: true,
  cupos: { ...CUPOS, horas: CUPOS.horas.map(h => h.hora === '19:00'
    ? { ...h, ocupadas: 25, por_procesar: 0, libres: 0 } : h) },
  solicitudes: SOLIS.map(x => x.estado === 'pagada'
    ? { ...x, estado: 'atendida' } : x) };

await p.click('[data-atender="11111111-1111-4111-8111-111111111111"]');
await p.waitForTimeout(700);

ok('llama a la ruta de atender', enviado.length === 1, JSON.stringify(enviado));
ok('con el id de esa solicitud',
   enviado[0] && enviado[0].id === '11111111-1111-4111-8111-111111111111',
   enviado[0] && enviado[0].id);
ok('y con el token, como toda ruta de admin',
   enviado[0] && enviado[0].token === 'x');

const avisos = await p.evaluate(() => window.__e2e.avisos());
ok('avisa que quedó procesada',
   avisos.length > 0 && /Procesada/.test(avisos[0].texto), avisos[0] && avisos[0].texto);
ok('y dice qué significa para el cupo',
   avisos[0] && /ya cuenta solo por AdminGym/.test(avisos[0].texto),
   avisos[0] && avisos[0].texto);

const despues = (await p.locator('#mens-cupos').innerText()).replace(/\s+/g, ' ');
ok('el cupo del 7pm baja a lo que ve AdminGym',
   /25 de 25/.test(despues), despues);
ok('y ya no dice que falte nada por pasar', !/por pasar/.test(despues), despues);
ok('el botón desaparece de esa fila',
   await p.locator('[data-atender="11111111-1111-4111-8111-111111111111"]').count() === 0);

ok('sin errores de JS', errs.length === 0, errs.join(' | '));
console.log(fallos ? `\n${fallos} fallo(s)` : '\nTodo bien');
await b.close(); srv.close();
process.exit(fallos ? 1 : 0);
