/**
 * Las salidas de la cuenta, por clasificar.
 *
 * POR QUÉ EXISTE
 * Damián, 20 de septiembre: «cada vez que sale dinero de la cuenta de
 * Tumbao llega ese correo del banco… que exista como algo de
 * notificación que hay gastos sin procesar, y que al momento que se tome
 * esa información se pueda poner el gasto a que corresponde».
 *
 * El correo ya llegaba. El parser lo reconocía —`movimiento_de_salida`—
 * y lo botaba. De los últimos veinte correos del banco, cuatro eran
 * salidas: una quinta parte de los movimientos de la cuenta no tenía
 * nombre.
 *
 * LO QUE ESTA PRUEBA PROTEGE
 *
 *   1. QUE SE NOTE. Un contador que solo aparece al entrar a la pestaña
 *      no avisa de nada. El globo tiene que estar antes de abrirla.
 *
 *   2. QUE NO SE CUENTE DOS VECES. Tanya reporta esos mismos pagos en el
 *      chat, y de ahí salieron los renglones ya cargados. Si hay un
 *      gasto del mismo valor por esas fechas, la pantalla lo dice y
 *      ofrece descartar. Es lo único que separa esto de volver a romper
 *      la tesorería, ahora inflándola.
 *
 *   3. QUE NO SE DESCARTE A CIEGAS. Sin decir por qué, no se descarta.
 *
 *   4. QUE RECEPCIÓN LA VEA. Es de quien es el trabajo. La pestaña va en
 *      «Hoy», no en «Negocio», y no se esconde con rol de cajero.
 *
 *   node salidas-por-clasificar.test.mjs
 */
import { chromium } from 'playwright-core';
import { rutaDelPanel } from './instrumentar.mjs';
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';

// Sin argumentos: rutaDelPanel() lee `process.argv` entera y saca la
// copia de ahí. Pasarle `process.argv[2]` a mano parece lo mismo y no lo
// es —`argv[2]` de una cadena es su tercer carácter— y el fallo solo
// aparece al correr la suite completa, que es cuando llega esa copia.
const PANEL = rutaDelPanel();

/* Servido por HTTP y no por file://: el rol entra por localStorage, que
   en file:// no es de fiar. Es el mismo montaje que usa la prueba de
   tesorería. */
const srv = createServer(async (q, s) => {
  try {
    const cuerpo = await readFile(PANEL);
    s.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    s.end(cuerpo);
  } catch (e) { s.writeHead(500); s.end(String(e)); }
});
await new Promise(r => srv.listen(8134, r));
const BASE = 'http://localhost:8134/';
const b = await chromium.launch({
  executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });

let fallos = 0;
const ok = (n, c, extra = '') => { if (!c) fallos++;
  console.log(`${c ? '✓' : '✗'} ${n}${extra ? '  → ' + extra : ''}`); };
const titulo = t => console.log(`\n-- ${t} ${'-'.repeat(Math.max(0, 52 - t.length))}`);

/* La respuesta real de `admin_salidas_pendientes`, con las dos ayudas
   que trae del servidor: la sugerencia por cuenta repetida y el aviso de
   posible duplicado. Los montos y las cuentas son los de los correos de
   verdad del 18 y 19 de septiembre. */
const PENDIENTES = {
  ok: true, hoy: '2026-09-20', cuantas: 3, cop: 300000,
  salidas: [
    { id: '11111111-1111-4111-8111-111111111111',
      valor_cop: 180000, ocurrio_at: '2026-09-18T20:39:00-05:00',
      dia: '2026-09-18', cuenta_destino: '3123500203', destinatario: null,
      confianza: 'alta',
      sugerencia: null,
      // Ya está en gastos: «180000 clases viví bc tumbao», del chat.
      quizas_repetida: { dia: '2026-09-18', concepto: 'clases viví',
                         categoria: 'profesores' } },
    { id: '22222222-2222-4222-8222-222222222222',
      valor_cop: 60000, ocurrio_at: '2026-09-19T10:07:00-05:00',
      dia: '2026-09-19', cuenta_destino: '3222608325', destinatario: null,
      confianza: 'alta',
      sugerencia: { categoria: 'profesores', a_quien: 'Nagle',
                    concepto: 'clase profe Nagle' },
      quizas_repetida: null },
    { id: '33333333-3333-4333-8333-333333333333',
      valor_cop: 60000, ocurrio_at: '2026-09-19T19:21:00-05:00',
      dia: '2026-09-19', cuenta_destino: null, destinatario: null,
      confianza: 'baja', sugerencia: null, quizas_repetida: null },
  ],
  /* Lo que la máquina clasificó sola desde que conoce la cuenta. Ya
     cuentan en la tesorería; están aquí para poder pillarle un error
     antes de que lo repita. */
  solas: [
    { id: '44444444-4444-4444-8444-444444444444',
      valor_cop: 60000, ocurrio_at: '2026-09-20T09:00:00-05:00',
      dia: '2026-09-20', cuenta_destino: '3222608325',
      concepto: 'clase profe Nagle', categoria: 'profesores', a_quien: 'Nagle' },
  ],
};

const enviado = [];
async function abrir({ rol = 'propietario', datos = PENDIENTES } = {}) {
  const p = await b.newPage({ viewport: { width: 430, height: 940 } });
  const errs = [];
  p.on('pageerror', e => errs.push(String(e)));

  // De lo general a lo particular: la última ruta registrada manda.
  await p.route('**/api/**', r => r.fulfill({ status: 200,
    contentType: 'application/json',
    body: JSON.stringify({ ok: true, dias: [], reservas: [], pagos_libres: [],
                           movimientos: [], resumen_conceptos: [], rol }) }));
  await p.route('**/api/admin/salidas-pendientes', r => r.fulfill({
    status: 200, contentType: 'application/json', body: JSON.stringify(datos) }));
  for (const ruta of ['salida-clasificar', 'salida-descartar',
                      'salida-corregir']) {
    await p.route(`**/api/admin/${ruta}`, r => {
      enviado.push({ ruta, cuerpo: JSON.parse(r.request().postData() || '{}') });
      return r.fulfill({ status: 200, contentType: 'application/json',
        body: JSON.stringify({ ok: true, quedan: 2 }) });
    });
  }

  await p.addInitScript((r) => {
    localStorage.setItem('tumbao_admin_token',
      JSON.stringify({ token: 'x', rol: r, nombre: 'Prueba' }));
  }, rol);
  await p.goto(BASE, { waitUntil: 'load' });
  await p.waitForTimeout(700);
  return { p, errs };
}

titulo('1. Se nota antes de abrir la pestaña');

/* El arranque la pide, sin esperar al latido. Si el globo solo saliera a
   los quince segundos, o al entrar a la pestaña, no avisaría de nada:
   quien abre el panel ya dejó de mirar la barra para entonces. */
let { p, errs } = await abrir();
let globo = await p.locator('#globo-sal');
ok('el globo trae las tres que faltan',
   (await globo.textContent()).trim() === '3',
   'un contador que solo sale al entrar no avisa de nada');
ok('y se ve', !(await globo.getAttribute('hidden') !== null));

titulo('2. La bandeja');

await p.click('#tab-salidas');
await p.waitForTimeout(600);
let t = (await p.locator('#sal-lista').innerText()).replace(/\s+/g, ' ');
ok('están las tres salidas',
   await p.locator('#sal-lista [data-sal]').count() === 3);
ok('con el valor de cada una', /\$180\.000/.test(t) && /\$60\.000/.test(t), t.slice(0, 90));
ok('y la cuenta de destino, que es lo único que trae el correo',
   /3123500203/.test(t));
ok('sin destino, lo dice en vez de inventarlo',
   /sin destino en el correo/.test(t));
ok('la de confianza baja queda marcada',
   /revisar el correo/.test(t));
ok('el resumen no es un total de tesorería, es cuántas faltan',
   /3 sin clasificar/.test(await p.locator('#sal-resumen').innerText()));

titulo('3. Las dos ayudas que evitan el error caro');

// La fecha se pinta con el mismo formato que el resto del panel («18 de
// sept»), no con el crudo del servidor. Se comprueba así a propósito:
// una fecha en otro formato en una sola pantalla se lee como un error.
ok('avisa de que ya hay un gasto de ese valor',
   /Ya hay un gasto de este valor el 18 de sept/.test(t), t.slice(0, 200));
ok('y dice cuál, para poder compararlo', /«clases viví»/.test(t));
ok('la sugerencia por cuenta repetida llega escrita',
   /La última vez a esta cuenta fue «clase profe Nagle»/.test(t));

const fila2 = p.locator('[data-sal="22222222-2222-4222-8222-222222222222"]');
ok('y viene ya rellenada, no solo dicha',
   (await fila2.locator('[data-campo="concepto"]').inputValue()) === 'clase profe Nagle');
ok('con su categoría',
   (await fila2.locator('[data-campo="categoria"]').inputValue()) === 'profesores');
ok('y a quién', (await fila2.locator('[data-campo="a_quien"]').inputValue()) === 'Nagle');

titulo('4. Clasificar');

enviado.length = 0;
await fila2.locator('[data-hacer="clasificar"]').click();
await p.waitForTimeout(500);
ok('manda lo que se ve en pantalla', enviado.length === 1 &&
   enviado[0].cuerpo.concepto === 'clase profe Nagle' &&
   enviado[0].cuerpo.categoria === 'profesores' &&
   enviado[0].cuerpo.a_quien === 'Nagle',
   JSON.stringify(enviado[0] && enviado[0].cuerpo));

// Sin concepto no se manda nada: el servidor también lo rechaza, pero
// gastar un viaje para que le digan que no es un viaje perdido.
const fila3 = p.locator('[data-sal="33333333-3333-4333-8333-333333333333"]');
enviado.length = 0;
await fila3.locator('[data-campo="concepto"]').fill('');
await fila3.locator('[data-hacer="clasificar"]').click();
await p.waitForTimeout(400);
ok('sin decir qué era, no se manda', enviado.length === 0);
ok('y el botón se puede volver a pulsar',
   !(await fila3.locator('[data-hacer="clasificar"]').isDisabled()),
   'si se quedara apagado habría que recargar para reintentar');

titulo('5. Descartar pide el porqué');

enviado.length = 0;
p.once('dialog', d => d.dismiss());          // cancelar el prompt
await p.locator('[data-sal="11111111-1111-4111-8111-111111111111"]')
       .locator('[data-hacer="descartar"]').click();
await p.waitForTimeout(400);
ok('cancelar no descarta nada', enviado.length === 0);

p.once('dialog', d => d.accept('ya estaba en el chat de gastos'));
await p.locator('[data-sal="11111111-1111-4111-8111-111111111111"]')
       .locator('[data-hacer="descartar"]').click();
await p.waitForTimeout(500);
ok('con la razón sí, y la razón viaja', enviado.length === 1 &&
   enviado[0].cuerpo.nota === 'ya estaba en el chat de gastos',
   JSON.stringify(enviado[0] && enviado[0].cuerpo));

titulo('6. Lo que se clasificó solo se ve, y se puede corregir');

/* Damián: «salida debe ser inteligente… solo debe quedar pendiente
   cuando se envíe dinero a una cuenta o persona que nunca se ha
   enviado». El servidor ya lo hace; lo que esta pantalla no puede hacer
   es esconderlo. Si se equivoca y nadie lo ve, la siguiente
   transferencia a esa cuenta repite el error: el aprendizaje sale de
   ahí. */
ok('hay una sección para lo automático',
   await p.locator('#sal-solas').count() === 1);
ok('con cuántas van', (await p.locator('#sal-solas-n').textContent()).trim() === '1');
ok('va cerrada, para no competir con lo que sí hay que atender',
   await p.locator('#sal-solas').evaluate(e => !e.open));

await p.locator('#sal-solas summary').click();
await p.waitForTimeout(250);
const tSolas = (await p.locator('#sal-solas-lista').innerText()).replace(/\s+/g, ' ');
ok('dice qué entendió', /clase profe Nagle/.test(tSolas), tSolas.slice(0, 90));
ok('y en qué categoría lo metió', /Profesores/.test(tSolas));

enviado.length = 0;
let respondidos = 0;
p.on('dialog', d => { respondidos++;
  d.accept(respondidos === 1 ? 'taller de salsa' : 'talleres'); });
await p.locator('[data-sal="44444444-4444-4444-8444-444444444444"]')
       .locator('[data-hacer="corregir"]').click();
await p.waitForTimeout(600);
ok('se puede corregir, y la corrección viaja entera',
   enviado.length === 1 && enviado[0].ruta === 'salida-corregir' &&
   enviado[0].cuerpo.concepto === 'taller de salsa' &&
   enviado[0].cuerpo.categoria === 'talleres',
   JSON.stringify(enviado[0] && enviado[0].cuerpo));

ok('sin errores de JS', errs.length === 0, errs.join(' | '));
await p.close();

titulo('7. Vacía no asusta');

({ p, errs } = await abrir({ datos: { ok: true, cuantas: 0, cop: 0, salidas: [] } }));
await p.click('#tab-salidas');
await p.waitForTimeout(500);
ok('lo dice en positivo',
   /están clasificadas/.test(await p.locator('#sal-lista').innerText()));
ok('y el globo desaparece',
   await p.locator('#globo-sal').getAttribute('hidden') !== null);
ok('sin errores de JS', errs.length === 0, errs.join(' | '));
await p.close();

titulo('8. Recepción sí la ve');

/* Es de quien es el trabajo. La tesorería se le esconde porque lleva la
   nómina de sus compañeros; esto no: es decir a qué corresponde un
   movimiento que ya ocurrió, y no toca su caja. */
({ p, errs } = await abrir({ rol: 'cajero' }));
await p.waitForTimeout(400);
ok('la pestaña no se le esconde',
   await p.locator('#tab-salidas').getAttribute('hidden') === null);
ok('mientras la tesorería sí',
   await p.locator('#tab-tesoreria').getAttribute('hidden') !== null,
   'la diferencia es a propósito');
await p.click('#tab-salidas');
await p.waitForTimeout(500);
ok('y puede clasificar',
   await p.locator('#sal-lista [data-hacer="clasificar"]').count() === 3);
ok('sin errores de JS', errs.length === 0, errs.join(' | '));
await p.close();

await b.close();
srv.close();
console.log(fallos ? `\n\x1b[31m${fallos} fallo(s)\x1b[0m`
                   : '\n\x1b[32mtodo en verde\x1b[0m');
process.exit(fallos ? 1 : 0);
