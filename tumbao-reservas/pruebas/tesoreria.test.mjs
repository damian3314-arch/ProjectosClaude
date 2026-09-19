/**
 * Tesorería — entradas contra salidas, y qué revisar.
 *
 * POR QUÉ EXISTE
 * Damián pidió «cómo está el negocio, entradas vs salidas, y qué cosas
 * se deben revisar para tener más utilidad». Lo delicado no son los
 * totales: es que esta pantalla es la primera del panel donde un número
 * puede estar MAL sin que nada falle.
 *
 *   · Un adelanto de quincena sumado y luego pagado completo se cuenta
 *     dos veces, y la utilidad sale peor de lo que es. En agosto son
 *     $950.000 así.
 *   · Un gasto que sube se pinta de verde si se reusa el comparativo de
 *     las ventas sin darle la vuelta — y gastar más se leería como una
 *     buena noticia.
 *   · Un mes sin gastos cargados enseña una utilidad preciosa que es
 *     mentira: son los ingresos completos menos la caja menor.
 *
 * Los tres se comprueban aquí con la respuesta real que devolvió
 * `admin_tesoreria` contra producción el 19 de septiembre.
 *
 *   node tesoreria.test.mjs
 */
import { chromium } from 'playwright-core';
import { rutaDelPanel } from './instrumentar.mjs';
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';

const PANEL = rutaDelPanel();
const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
const p = await b.newPage({ viewport: { width: 390, height: 900 } });
const errs = []; p.on('pageerror', e => errs.push(String(e)));

let fallos = 0;
const ok = (n, c, extra = '') => { if (!c) fallos++;
  console.log(`${c ? '✓' : 'FALLO'} ${n}${extra ? '  → ' + extra : ''}`); };

/* La respuesta de verdad del 19 de septiembre. No es inventada: así la
   prueba también documenta cómo estaba el negocio ese día. */
const REAL = {
  ok: true, hoy: '2026-09-19',
  desde: '2026-09-01', hasta: '2026-09-19', dias: 19,
  antes_desde: '2026-08-01', antes_hasta: '2026-08-19',
  entradas:       { ingreso_cop: 9335000, egreso_cop: 120000, personas: 258 },
  entradas_antes: { ingreso_cop: 4305000, egreso_cop: 0, personas: 120 },
  salidas_cop: 7402990, salidas_antes_cop: 8756900,
  caja_menor_cop: 120000, adelantos_cop: 300000,
  utilidad_cop: 1932010, utilidad_sin_adelantos_cop: 2232010,
  utilidad_antes_cop: -4451900, margen_pct: 21,
  categorias: [
    { categoria: 'nomina',        cop: 2872400, n: 6,  cop_antes: 2955000 },
    { categoria: 'arriendo',      cop: 1800000, n: 1,  cop_antes: 1800000 },
    { categoria: 'sistema',       cop: 1355000, n: 2,  cop_antes: 1355000 },
    { categoria: 'profesores',    cop: 1160000, n: 13, cop_antes: 840000 },
    { categoria: 'mantenimiento', cop: 95590,   n: 3,  cop_antes: 50000 },
    { categoria: 'mercadeo',      cop: 0,       n: 0,  cop_antes: 830000 },
  ],
  revisar: [
    { clave: 'adelantos', peso: 1, cop: 300000,
      titulo: 'Adelantos de quincena que pueden estar contados dos veces',
      detalle: '1 pago de adelanto. Si la quincena se pagó después completa, ' +
        'este dinero salió una vez pero está sumado dos, y la utilidad sale ' +
        'peor de lo que es.' },
    { clave: 'repetidos', peso: 3, cop: 120000,
      titulo: '2 pagos repetidos el mismo día por el mismo valor',
      detalle: 'Puede ser correcto o puede ser el mismo pago anotado dos veces.' },
    { clave: 'subio', peso: 4, cop: 320000, categoria: 'profesores',
      titulo: 'Lo que más subió contra el mismo tramo del mes pasado: profesores',
      detalle: 'Es lo que más creció contra el mes pasado en las mismas fechas.' },
  ],
};

const GASTOS = {
  ok: true,
  gastos: [
    { id: '1', dia: '2026-09-16', concepto: 'sistema tumbao', categoria: 'sistema',
      cop: 1250000, medio: 'banco', a_quien: null, es_adelanto: false, revisar: null, fuente: 'whatsapp' },
    { id: '2', dia: '2026-09-12', concepto: 'adelanto Fabián', categoria: 'nomina',
      cop: 300000, medio: 'banco', a_quien: 'Fabián', es_adelanto: true,
      revisar: 'Adelanto. El 15 se pagó «saldo nómina quincena» de $650.000.',
      fuente: 'whatsapp' },
  ],
  caja_menor: [{ dia: '2026-09-12', concepto: 'profesores', cop: 60000, medio: 'efectivo' }],
};

let tes = REAL;

/* EN PLAYWRIGHT MANDA LA ÚLTIMA RUTA REGISTRADA: de lo general a lo
   particular, o el genérico se come a los demás. */
await p.route('**/api/**', r => r.fulfill({ status: 200,
  contentType: 'application/json',
  body: JSON.stringify({ ok: true, dias: [], reservas: [], pagos_libres: [],
                         movimientos: [], resumen_conceptos: [] }) }));
await p.route('**/api/admin/tesoreria', r => r.fulfill({ status: 200,
  contentType: 'application/json', body: JSON.stringify(tes) }));
await p.route('**/api/admin/gastos-lista', r => r.fulfill({ status: 200,
  contentType: 'application/json', body: JSON.stringify(GASTOS) }));

const srv = createServer(async (q, s) => {
  try {
    const cuerpo = await readFile(PANEL);
    s.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' }); s.end(cuerpo);
  } catch (_) { s.writeHead(404); s.end('no'); }
});
await new Promise(r => srv.listen(8133, r));

await p.addInitScript(() => {
  localStorage.setItem('tumbao_admin_token',
    JSON.stringify({ token: 'x', rol: 'propietario', nombre: 'Prueba' }));
});
await p.goto('http://localhost:8133/', { waitUntil: 'load' });
await p.waitForTimeout(600);
await p.click('#tab-tesoreria');
await p.waitForTimeout(600);

const txt = async (sel) => (await p.locator(sel).innerText()).replace(/\s+/g, ' ');

/* ═══════════ 1. entradas vs salidas, que es lo que pidió ═══════════ */

let t = await txt('#tes-fichas');
ok('dice lo que entró',  /\$9\.335\.000/.test(t), t);
ok('y lo que salió',     /\$7\.402\.990/.test(t), t);
ok('y lo que queda',     /\$1\.932\.010/.test(t), t);
ok('con el margen sobre lo que entró', /21% de lo que entró/.test(t), t);
ok('son tres tarjetas y ninguna más',
   await p.locator('#tes-fichas .ficha').count() === 3);

/* GASTAR MÁS NO ES UNA BUENA NOTICIA.
   `compara` nació para las ventas y pinta de verde lo que crece. Si se
   reusa tal cual, un mes en el que se gastó el doble sale en verde. */
const salio = p.locator('#tes-fichas .ficha').nth(1);
ok('el gasto bajó un 15%', /−15%/.test((await salio.innerText()).replace(/\s+/g, ' ')));
ok('y gastar menos se pinta como algo bueno',
   await salio.locator('.delta.sube').count() === 1,
   'la clase se invierte a propósito: en un gasto, bajar es subir');

/* ═══════════ 2. qué revisar, arriba del desglose ═══════════ */

t = await txt('#tes-revisar');
ok('avisa de los adelantos', /Adelantos de quincena/.test(t), t.slice(0, 120));
ok('con cuánto hay en juego', /\$300\.000/.test(t));
ok('y explica por qué importa',
   /contados dos veces/.test(t) && /sale peor de lo que es/.test(t));
ok('avisa de los pagos repetidos el mismo día', /repetidos el mismo día/.test(t));
ok('y dice qué categoría se disparó', /profesores/.test(t) && /\$320\.000/.test(t));

// Va ANTES del desglose: un número malo que nadie sabe que es malo hace
// más daño que no tenerlo.
const yRev = await p.locator('#tes-revisar').boundingBox();
const yCat = await p.locator('#tes-categorias').boundingBox();
ok('lo que hay que revisar va antes de en qué se fue', yRev.y < yCat.y,
   `revisar en ${Math.round(yRev.y)}, categorías en ${Math.round(yCat.y)}`);

/* ═══════════ 3. en qué se fue ═══════════ */

t = await txt('#tes-categorias');
ok('la nómina es lo más grande', /Nómina/.test(t) && /\$2\.872\.400/.test(t), t.slice(0, 100));
ok('dice cuántos pagos fueron', /13/.test(t), 'trece pagos a profesores');
ok('y compara cada categoría con el mes pasado',
   /que el mes pasado/.test(t));
ok('una categoría en cero no ocupa sitio', !/Mercadeo/.test(t),
   'en septiembre no hubo, y una barra vacía no dice nada');

/* ═══════════ 4. el detalle solo se pide al abrirlo ═══════════
   Son setenta renglones para pintar nueve totales. */

ok('el detalle arranca cerrado',
   await p.locator('#tes-lista .gasto-fila').count() === 0);
await p.click('#tes-detalle summary');
await p.waitForTimeout(400);
t = await txt('#tes-lista');
ok('al abrirlo trae los gastos', /sistema tumbao/.test(t), t.slice(0, 120));
ok('con su categoría', /Sistema/.test(t));
ok('marca los adelantos', /adelanto/i.test(t));
ok('y trae la nota de qué revisar', /saldo nómina quincena/.test(t));
ok('la caja menor sale en la misma lista y marcada', /caja menor/.test(t),
   'si saliera aparte, el total de arriba no cuadraría con lo de abajo');

/* ═══════════ 5. un mes sin gastos no es un mes sin gastos ═══════════
   Es el error más caro de esta pantalla: enseñar los ingresos completos
   menos la caja menor y llamar a eso utilidad. */

tes = {
  ...REAL, desde: '2026-07-01', hasta: '2026-07-31',
  salidas_cop: 0, salidas_antes_cop: 0, adelantos_cop: 0,
  utilidad_cop: 9335000, categorias: [],
  revisar: [{ clave: 'sin_gastos', peso: 0, cop: 0,
    titulo: 'Este periodo no tiene gastos cargados',
    detalle: 'Solo se ve la caja menor. La utilidad de arriba no es real.' }],
};
await p.click('#tes-recargar');
await p.waitForTimeout(500);
t = await txt('#tes-revisar');
ok('un mes sin gastos lo dice en voz alta',
   /no tiene gastos cargados/.test(t), t);
ok('y avisa de que la utilidad de arriba no es real',
   /no es real/.test(t), t);
ok('sin desglose que pintar, no se pinta un desglose vacío',
   (await txt('#tes-categorias')).trim() === '');

/* ═══════════ 6. la cajera no ve la nómina de sus compañeros ═══════════ */

const p2 = await b.newPage({ viewport: { width: 390, height: 900 } });
const errs2 = []; p2.on('pageerror', e => errs2.push(String(e)));
await p2.route('**/api/**', r => r.fulfill({ status: 200,
  contentType: 'application/json',
  body: JSON.stringify({ ok: true, dias: [], reservas: [], pagos_libres: [],
                         movimientos: [], resumen_conceptos: [] }) }));
await p2.addInitScript(() => {
  localStorage.setItem('tumbao_admin_token',
    JSON.stringify({ token: 'x', rol: 'cajero', nombre: 'Caja' }));
});
await p2.goto('http://localhost:8133/', { waitUntil: 'load' });
await p2.waitForTimeout(600);
ok('con rol de cajero la tesorería no está',
   await p2.locator('#tab-tesoreria').isVisible() === false,
   'lleva la nómina de todo el mundo');
ok('y el rótulo del grupo tampoco queda suelto',
   await p2.locator('#grupo-negocio').isVisible() === false);
ok('sin errores de JS con rol de cajero', errs2.length === 0, errs2.join(' | '));
await p2.close();

/* ═══════════ 7. la navegación sigue siendo una sola ═══════════
   El escritorio y el celular comparten los MISMOS botones. Dos
   navegaciones habrían sido dos sitios donde añadir cada sección
   nueva, y el día que se olvide uno, media app desaparece. */

const cuantas = await p.locator('.lateral .tab').count();
ok('hay una sola navegación', await p.locator('.lateral').count() === 1);
ok('con las nueve secciones dentro', cuantas === 9, `${cuantas} botones`);
ok('agrupadas en tres bloques',
   await p.locator('.lateral .lat-grupo').count() === 3);
ok('y el título dice dónde estás',
   (await txt('#donde')) === 'Tesorería', await txt('#donde'));

ok('sin errores de JS', errs.length === 0, errs.join(' | '));
console.log(fallos ? `\n${fallos} fallo(s)` : '\nTodo bien');
await b.close(); srv.close();
process.exit(fallos ? 1 : 0);
