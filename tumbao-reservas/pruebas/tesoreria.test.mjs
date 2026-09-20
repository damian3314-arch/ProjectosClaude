/**
 * Tesorería — entradas contra salidas, y qué revisar.
 *
 * POR QUÉ EXISTE
 * Damián pidió «cómo está el negocio, entradas vs salidas, y qué cosas
 * se deben revisar para tener más utilidad». Lo delicado no son los
 * totales: es que esta pantalla es la primera del panel donde un número
 * puede estar MAL sin que nada falle.
 *
 *   · Un adelanto de quincena que nadie ha emparejado con su saldo deja
 *     una pregunta abierta sobre la nómina. Los que SÍ se emparejaron
 *     (350.000 + 600.000 el 6 y el 15 de agosto; 300.000 + 650.000 el 12
 *     y el 15 de septiembre, los dos de 950.000) no son ningún misterio:
 *     salieron una vez y están bien contados. Avisar de esos era ruido, y
 *     ruido que no se podía apagar.
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
  // Los 300.000 del 12 de septiembre quedaron cuadrados con el saldo del
  // 15, así que ya no cuentan como adelanto abierto y las dos utilidades
  // son la misma. Antes esta segunda cifra estaba 300.000 por encima.
  caja_menor_cop: 120000, adelantos_cop: 0,
  utilidad_cop: 1932010, utilidad_sin_adelantos_cop: 1932010,
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
    // Sigue marcado como adelanto —lo fue— pero ya sin nota de revisar:
    // el saldo del 15 lo cuadró. Que `es_adelanto` y `revisar` puedan ir
    // por separado es justo lo que hace que el aviso se pueda apagar.
    { id: '2', dia: '2026-09-12', concepto: 'adelanto Fabián', categoria: 'nomina',
      cop: 300000, medio: 'banco', a_quien: 'Fabián', es_adelanto: true,
      revisar: null, fuente: 'whatsapp' },
    { id: '3', dia: '2026-08-10', concepto: 'adelanto Luisa', categoria: 'nomina',
      cop: 250000, medio: 'banco', a_quien: 'Luisa', es_adelanto: true,
      revisar: 'Sus tres quincenas se pagaron enteras y ninguna dice «saldo».',
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

/* Un adelanto ya cuadrado con su saldo no se avisa. Esto es lo que pidió
   Damián el 19 de septiembre —«dejar eso validado»— y es la diferencia
   entre una lista que se vacía cuando trabajas y una que te grita lo
   mismo todos los meses hasta que dejas de mirarla. */
ok('un adelanto ya cuadrado no vuelve a aparecer',
   !/[Aa]delanto/.test(t), t.slice(0, 160));
ok('y la utilidad es una sola cifra, no dos',
   !/sin adelantos/i.test(await txt('#tes-fichas')));

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
ok('marca los adelantos', /adelanto/i.test(t),
   'aunque ya esté cuadrado, sigue siendo un adelanto y el libro lo dice');
ok('y trae la nota de qué revisar del que sí sigue abierto',
   /ninguna dice «saldo»/.test(t));
ok('la caja menor sale en la misma lista y marcada', /caja menor/.test(t),
   'si saliera aparte, el total de arriba no cuadraría con lo de abajo');

/* ═══════════ 5. el adelanto que SÍ sigue abierto ═══════════
   Apagar el aviso de los cuadrados no sirve de nada si de paso apaga los
   otros. Agosto es el caso real: quedan dos sin emparejar —los 250.000 de
   Luisa del 10/8 y los 350.000 del «ajuste» del 15/8— por $600.000. Esta
   es la respuesta que devolvió producción el 19 de septiembre. */

tes = {
  ...REAL, desde: '2026-08-01', hasta: '2026-08-31', dias: 31,
  antes_desde: '2026-07-01', antes_hasta: '2026-07-31',
  salidas_cop: 11986900, adelantos_cop: 600000,
  utilidad_cop: -2171900, utilidad_sin_adelantos_cop: -1571900,
  margen_pct: -22,
  revisar: [
    { clave: 'adelantos', peso: 1, cop: 600000,
      titulo: 'Adelantos sin cuadrar con su quincena',
      detalle: '2 adelantos sin descontar de ninguna quincena. La plata ' +
        'salió, eso no se discute; falta saber si se recupera o ya se ' +
        'descontó. Ábrelos abajo: cada uno dice qué mirar.' },
    { clave: 'con_nota', peso: 2, cop: 2400000,
      titulo: '3 gastos con algo por confirmar',
      detalle: 'Ábrelos abajo: cada uno dice qué hay que mirar.' },
  ],
};
await p.click('#tes-recargar');
await p.waitForTimeout(500);
t = await txt('#tes-revisar');
ok('el que sigue abierto sí se avisa',
   /Adelantos sin cuadrar/.test(t), t.slice(0, 140));
ok('con cuánto hay en juego', /\$600\.000/.test(t));

/* El aviso ya no dice «contados dos veces»: eso era falso. Cada renglón
   es una transferencia distinta y el gasto del mes siempre estuvo bien.
   Lo que falta es saber a qué quincena pertenece cada mitad. */
ok('sin acusar de doble conteo, que era lo que estaba mal',
   !/dos veces/.test(t) && /sin descontar/.test(t));
ok('y en buen castellano', !/no se ve descontados/.test(t),
   'la concordancia se rompía al pluralizar solo una de las dos palabras');

/* ═══════════ 6. la cifra de «entró» sale del mostrador ═══════════
   La Caja no existía antes del 10/8, así que agosto enseñaba 9.815.000
   de entradas y una pérdida de 2.171.900 que nunca ocurrió: le faltaban
   los nueve primeros días. Con el reporte de AdminGym cargado, agosto
   entró 14.170.000 y dejó 2.183.100.

   `entradas` se sigue recibiendo y no desaparece —es el desglose de lo
   que pasó por la página y el banco, que es con lo que se concilia— pero
   ya no manda en la tarjeta. Esta prueba es justo eso: que cuando las
   dos cifras discrepan, gana la del mostrador. */

tes = {
  ...REAL, desde: '2026-08-01', hasta: '2026-08-31', dias: 31,
  ingreso_cop: 14170000, ingreso_antes_cop: 16161000,
  fuente_ingreso: 'mostrador', mostrador_hasta: '2026-09-19',
  // Lo que decía la Caja, que es 4.355.000 menos.
  entradas: { ingreso_cop: 9815000, egreso_cop: 0, personas: 247 },
  entradas_antes: { ingreso_cop: 30000, egreso_cop: 0, personas: 15 },
  salidas_cop: 11986900, adelantos_cop: 600000,
  utilidad_cop: 2183100, utilidad_sin_adelantos_cop: 2783100,
  margen_pct: 15, categorias: [], revisar: [],
};
await p.click('#tes-recargar');
await p.waitForTimeout(500);
t = await txt('#tes-fichas');
ok('la tarjeta enseña lo del mostrador', /\$14\.170\.000/.test(t), t.replace(/\s+/g, ' '));
ok('y no lo que veía la Caja', !/\$9\.815\.000/.test(t),
   'esa cifra era la que ponía agosto en pérdida');
ok('con la utilidad en positivo', /\$2\.183\.100/.test(t));
ok('pintada como algo bueno',
   await p.locator('#tes-fichas .gordo.bueno').count() === 1);

/* Un panel viejo contra un servidor viejo tiene que seguir andando: si
   no llega `ingreso_cop`, se cae a `entradas`. */
tes = { ...REAL, ingreso_cop: undefined, ingreso_antes_cop: undefined };
await p.click('#tes-recargar');
await p.waitForTimeout(500);
ok('sin la cifra nueva, se cae a la de la Caja',
   /\$9\.335\.000/.test(await txt('#tes-fichas')));

/* ═══════════ 7. faltan gastos de media que nadie ve ═══════════
   Es el error más caro de esta pantalla, y volvió disfrazado. Junio
   tiene el ingreso del mes entero contra los gastos de diez días —el
   chat arranca el 21— y daba 69% de margen sin un solo aviso, porque el
   de `sin_gastos` solo salta cuando no hay NINGUNO. */

tes = {
  ...REAL, desde: '2026-06-01', hasta: '2026-06-30', dias: 30,
  ingreso_cop: 12310000, ingreso_antes_cop: 12230000,
  salidas_cop: 3781200, utilidad_cop: 8528800, margen_pct: 69,
  categorias: [],
  revisar: [{ clave: 'gastos_a_medias', peso: 0, cop: 0,
    titulo: 'Faltan los gastos de los primeros 20 días del periodo',
    detalle: 'El primer gasto cargado es del 21/06, pero aquí se está ' +
      'contando el ingreso desde el 01/06. La utilidad y el margen de ' +
      'arriba salen mejores de lo que fueron.' }],
};
await p.click('#tes-recargar');
await p.waitForTimeout(500);
t = await txt('#tes-revisar');
ok('avisa de que los gastos no cubren el periodo',
   /Faltan los gastos/.test(t), t.slice(0, 120));
ok('diciendo cuántos días', /20 días/.test(t));
ok('y que el margen de arriba miente',
   /mejores de lo que fueron/.test(t));

/* ═══════════ 8. un mes sin gastos no es un mes sin gastos ═══════════
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
