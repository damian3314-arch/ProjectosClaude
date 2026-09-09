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

/* ═══════════ 5. LA COLA SE VE, Y TIENE TURNO (0075) ═══════════

   Damián: «importante que la lista de espera de mensualidad sí muestre
   a la gente que está en espera, para tenerlos en prioridad».

   Salían todas mezcladas en un solo listado, ordenadas pero sin decir
   dónde acaba un grupo y empieza el otro, así que la cola no se leía
   como cola. Y el globo de la pestaña las ignoraba siempre — incluso
   cuando se liberaba un cupo de su horario, que es justo cuando hay que
   llamarlas.

   El día que se prueba: las 7pm llenas con tres esperando, y las 7am
   con un cupo libre y alguien esperándolo desde hace días. */
lista = { ok: true,
  cupos: { ok: true, tope: 25, valor_cop: 125000, horas: [
    { hora: '07:00', etiqueta: '7:00 am', tope: 25, ocupadas: 24,
      activas: 24, por_procesar: 0, apartadas: 0, en_espera: 1, libres: 1 },
    { hora: '18:00', etiqueta: '6:00 pm', tope: 25, ocupadas: 25,
      activas: 25, por_procesar: 0, apartadas: 0, en_espera: 0, libres: 0 },
    { hora: '19:00', etiqueta: '7:00 pm', tope: 25, ocupadas: 25,
      activas: 25, por_procesar: 0, apartadas: 0, en_espera: 3, libres: 0 },
  ] },
  solicitudes: [
    { id: 'aaaaaaaa-0000-4000-8000-000000000001', nombre: 'Paga Uno',
      celular: '3000000001', hora: '19:00', estado: 'pagada',
      cuando: '09/09 10:00', dias: 0, valor_cop: 125000 },
    // La cola del 7pm, en el orden en que llegaron.
    { id: 'bbbbbbbb-0000-4000-8000-000000000001', nombre: 'Espera Primera',
      celular: '3000000011', hora: '19:00', estado: 'lista_espera',
      cuando: '02/09 08:00', dias: 7, valor_cop: 125000 },
    { id: 'bbbbbbbb-0000-4000-8000-000000000002', nombre: 'Espera Segunda',
      celular: '3000000012', hora: '19:00', estado: 'lista_espera',
      cuando: '05/09 09:00', dias: 4, valor_cop: 125000 },
    { id: 'bbbbbbbb-0000-4000-8000-000000000003', nombre: 'Espera Tercera',
      celular: '3000000013', hora: '19:00', estado: 'lista_espera',
      cuando: '08/09 20:00', dias: 1, valor_cop: 125000 },
    // Otra cola, la del 7am, que tiene su propia numeración.
    { id: 'cccccccc-0000-4000-8000-000000000001', nombre: 'Espera Mañanera',
      celular: '3000000021', hora: '07:00', estado: 'lista_espera',
      cuando: '01/09 06:00', dias: 8, valor_cop: 125000 },
  ] };

await p.click('#mens-recargar');
await p.waitForTimeout(700);

const txt = (await p.locator('#mens-lista').innerText()).replace(/\s+/g, ' ');
const tarj = (await p.locator('#mens-cupos').innerText()).replace(/\s+/g, ' ');

ok('la lista de espera tiene su propia sección',
   /LISTA DE ESPERA · POR ORDEN DE LLEGADA/i.test(txt), txt.slice(0, 200));
ok('y dice cuántas hay en ella', /LISTA DE ESPERA · POR ORDEN DE LLEGADA 4/i.test(txt),
   'tres del 7pm y una del 7am');
ok('las pagadas van en su propia sección y primero',
   txt.indexOf('YA PAGARON') < txt.indexOf('LISTA DE ESPERA'));

ok('la que lleva más tiempo esperando sale de primera',
   txt.indexOf('Espera Primera') < txt.indexOf('Espera Segunda') &&
   txt.indexOf('Espera Segunda') < txt.indexOf('Espera Tercera'),
   'es lo que decide a quién se llama cuando se libere un cupo');
// El turno va pegado al nombre en `innerText`: la separación la pone el
// margen del CSS, que no deja rastro en el texto.
ok('cada una lleva su turno', /1º\s*Espera Primera/.test(txt) &&
   /2º\s*Espera Segunda/.test(txt) && /3º\s*Espera Tercera/.test(txt),
   txt.slice(txt.indexOf('LISTA DE ESPERA'), txt.indexOf('LISTA DE ESPERA') + 120));
ok('el turno se cuenta por horario, no por el listado entero',
   /1º\s*Espera Mañanera/.test(txt),
   'la cola del 7am empieza en 1 aunque vaya después de las tres del 7pm');
ok('una pagada no lleva turno', !/º Paga Uno/.test(txt),
   'un número ahí parecería una prioridad que no existe');

ok('la tarjeta del 7pm dice cuánta gente hace fila',
   /3 en espera/.test(tarj), tarj);
ok('y no las suma a las ocupadas',
   /25 de 25/.test(tarj), 'quien espera no ocupa cupo');
ok('donde hay cupo libre, la tarjeta pide llamarlas',
   /1 en espera · ¡llámalas!/.test(tarj), tarj);
ok('donde está lleno, no lo pide', !/3 en espera · ¡llámalas!/.test(tarj),
   'no se puede atender hoy lo que no tiene cupo');

const globo = await p.locator('#globo-mens').innerText();
ok('el globo cuenta la pagada y la que ya tiene cupo esperándola',
   globo.trim() === '2', globo);

ok('y no las tres del horario lleno', globo.trim() !== '5',
   'un globo que nunca baja se deja de mirar');

ok('las de espera también traen el botón de procesar',
   await p.locator('[data-atender="bbbbbbbb-0000-4000-8000-000000000001"]').count() === 1,
   'ahí quiere decir «ya la llamé»');

/* ═══════════ 6. UNA HORA SUSPENDIDA LO DICE (0076) ═══════════

   El 8 de septiembre Damián suspendió la venta de mensualidad en 6pm y
   7pm «hasta nueva orden»: quedan en lista de espera. Por dentro eso es
   un tope de 0, y con tope 0 la tarjeta decía «0 libres · 28 de 0», que
   se lee como un error del sistema y no como una decisión.

   Se prueba con el caso incómodo: una hora suspendida que ADEMÁS tiene
   mensualidades pagadas sin pasar a AdminGym. Esa tarea no se puede
   perder de vista solo porque la hora esté cerrada. */
lista = { ok: true,
  cupos: { ok: true, tope: 25, valor_cop: 125000, horas: [
    { hora: '07:00', etiqueta: '7:00 am', tope: 25, ocupadas: 21,
      activas: 21, por_procesar: 0, apartadas: 0, en_espera: 0, libres: 4 },
    { hora: '19:00', etiqueta: '7:00 pm', tope: 0, ocupadas: 28,
      activas: 25, por_procesar: 3, apartadas: 0, en_espera: 2, libres: 0 },
  ] },
  solicitudes: [] };

await p.click('#mens-recargar');
await p.waitForTimeout(700);
const sus = (await p.locator('#mens-cupos').innerText()).replace(/\s+/g, ' ');

ok('la hora suspendida lo dice con la palabra',
   /Suspendida/.test(sus), sus);
ok('y no como «0 de 0», que parece una avería', !/de 0/.test(sus), sus);
ok('dice cuántas quedan comprometidas', /28 comprometidas/.test(sus), sus);
ok('sin perder de vista las que faltan por pasar a AdminGym',
   /3 por pasar/.test(sus),
   'que la hora esté cerrada no borra esa tarea');
ok('ni a quien está haciendo fila', /2 en espera/.test(sus), sus);
ok('la hora que sigue abierta se pinta como siempre',
   /4 libres · 7:00 am 21 de 25/.test(sus), sus);
ok('la tarjeta suspendida se marca aparte',
   await p.locator('.mens-cupo.suspendida').count() === 1,
   'borde punteado: cerrada por decisión, no por llenarse');

ok('sin errores de JS', errs.length === 0, errs.join(' | '));
console.log(fallos ? `\n${fallos} fallo(s)` : '\nTodo bien');
await b.close(); srv.close();
process.exit(fallos ? 1 : 0);
