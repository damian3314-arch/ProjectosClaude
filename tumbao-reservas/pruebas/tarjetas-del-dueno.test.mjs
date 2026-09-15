/**
 * Las tarjetas del dueño — hoy, la semana, el mes y contra qué.
 *
 * POR QUÉ EXISTE ESTA PRUEBA
 * Damián pidió «una visual tipo tarjetas con las cosas importantes para
 * ese día… comparativos rápidos de ventas con el mes anterior y de
 * ingresos versus gastos del mes». Un comparativo es justo la clase de
 * número que se lee mal sin que nada falle:
 *
 *   · un porcentaje sobre cero no existe, y «+Infinity%» o «+100%» son
 *     las dos formas de mentir que salen solas;
 *   · comparar doce días de septiembre contra tres de agosto da un
 *     +180% que no significa nada, y NADIE lo nota si la pantalla no lo
 *     dice — ese es exactamente el caso de hoy, porque la Caja empezó a
 *     registrar el 10 de agosto;
 *   · y una tarjeta que sume distinto que la tirilla de cierre del mismo
 *     día vuelve a abrir el problema del 5 de septiembre, cuando una
 *     hoja decía 300.000 y la otra 315.000.
 *
 * Lo tercero lo cuida humo-tarjetas.sql contra la base. Lo primero y lo
 * segundo se cuidan aquí: con los datos de verdad del 12 de septiembre
 * de 2026 y con los casos de borde que esos datos no tienen.
 *
 *   node tarjetas-del-dueno.test.mjs
 */
import { chromium } from 'playwright-core';
import { rutaDelPanel } from './instrumentar.mjs';
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';

const PANEL = rutaDelPanel();
const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
// Ancho de celular a propósito: es la pantalla para la que se pidió.
const p = await b.newPage({ viewport: { width: 390, height: 900 } });
const errs = []; p.on('pageerror', e => errs.push(String(e)));

let fallos = 0;
const ok = (n, c, extra = '') => { if (!c) fallos++;
  console.log(`${c ? '✓' : 'FALLO'} ${n}${extra ? '  → ' + extra : ''}`); };

/* Los números reales que devolvió admin_resumen_gerencia el 12 de
   septiembre de 2026 contra producción. No son inventados: así la prueba
   también documenta cómo se veía el negocio ese día. */
const REAL = {
  ok: true,
  hoy: '2026-09-12',
  primer_dato: '2026-07-28',
  primer_caja: '2026-08-10',
  dia: { desde: '2026-09-12', hasta: '2026-09-12', dias: 1, personas: 34,
         ingreso_cop: 995000, egreso_cop: 60000, queda_cop: 935000,
         de_caja_cop: 575000, de_pagina_cop: 420000, a_mano_cop: 0,
         mensualidades_n: 2, mensualidades_cop: 250000, egreso_caja_menor_cop: 60000 },
  dia_semana_antes: { desde: '2026-09-05', hasta: '2026-09-05', dias: 1, personas: 20,
         ingreso_cop: 300000, egreso_cop: 0, queda_cop: 300000,
         de_caja_cop: 45000, de_pagina_cop: 255000, a_mano_cop: 0,
         mensualidades_n: 0, mensualidades_cop: 0, egreso_caja_menor_cop: 0 },
  semana: { desde: '2026-09-07', hasta: '2026-09-12', dias: 6, personas: 99,
         ingreso_cop: 4540000, egreso_cop: 120000, queda_cop: 4420000,
         de_caja_cop: 3430000, de_pagina_cop: 1110000, a_mano_cop: 0,
         mensualidades_n: 24, mensualidades_cop: 2910000, egreso_caja_menor_cop: 120000 },
  semana_antes: { desde: '2026-08-31', hasta: '2026-09-05', dias: 6, personas: 78,
         ingreso_cop: 3315000, egreso_cop: 0, queda_cop: 3315000,
         de_caja_cop: 2430000, de_pagina_cop: 885000, a_mano_cop: 0,
         mensualidades_n: 17, mensualidades_cop: 2125000, egreso_caja_menor_cop: 0 },
  mes: { desde: '2026-09-01', hasta: '2026-09-12', dias: 12, personas: 168,
         ingreso_cop: 6560000, egreso_cop: 120000, queda_cop: 6440000,
         de_caja_cop: 4610000, de_pagina_cop: 1950000, a_mano_cop: 0,
         mensualidades_n: 32, mensualidades_cop: 3910000, egreso_caja_menor_cop: 120000 },
  mes_antes: { desde: '2026-08-01', hasta: '2026-08-12', dias: 12, personas: 48,
         ingreso_cop: 2340000, egreso_cop: 0, queda_cop: 2340000,
         de_caja_cop: 1815000, de_pagina_cop: 435000, a_mano_cop: 90000,
         mensualidades_n: 9, mensualidades_cop: 1125000, egreso_caja_menor_cop: 0 },
  mes_antes_parcial: true,
  semana_antes_parcial: false,
  gastos_mes: [{ concepto: 'profesores', cop: 120000, n: 2, de_caja_menor: true }],
};

let resumen = REAL;

/* EN PLAYWRIGHT MANDA LA ÚLTIMA RUTA REGISTRADA, no la más específica:
   de lo general a lo particular, o el genérico se come a los demás. */
await p.route('**/api/**', r => r.fulfill({ status: 200,
  contentType: 'application/json',
  body: JSON.stringify({ ok: true, dias: [], reservas: [], pagos_libres: [],
                         movimientos: [], resumen_conceptos: [] }) }));
await p.route('**/api/admin/resumen-gerencia', r => r.fulfill({ status: 200,
  contentType: 'application/json', body: JSON.stringify(resumen) }));

const srv = createServer(async (q, s) => {
  try {
    const cuerpo = await readFile(PANEL);
    s.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' }); s.end(cuerpo);
  } catch (_) { s.writeHead(404); s.end('no'); }
});
await new Promise(r => srv.listen(8131, r));

await p.addInitScript(() => {
  localStorage.setItem('tumbao_admin_token',
    JSON.stringify({ token: 'x', rol: 'propietario', nombre: 'Prueba' }));
});

await p.goto('http://localhost:8131/', { waitUntil: 'load' });
await p.waitForTimeout(600);

/* ═══════════ 1. en el celular abre aquí, sin buscar nada ═══════════
   Si hay que encontrar la pestaña cada vez, no se mira. Y para eso se
   pidió. */

ok('en pantalla de celular el panel abre en el resumen',
   await p.getAttribute('#tab-resumen', 'aria-selected') === 'true',
   'abrió en ' + await p.evaluate(() =>
     [...document.querySelectorAll('.tab')].find(t => t.getAttribute('aria-selected') === 'true')?.id));
ok('y las tarjetas ya están pintadas sin tocar nada',
   await p.locator('#fichas-resumen .ficha').count() >= 4);

const cifras = await p.locator('#fichas-resumen .ficha:not(.detalle)').count();
const plegados = await p.locator('#fichas-resumen details.detalle').count();
ok('son cuatro tarjetas de cifra', cifras === 4, `${cifras} tarjetas`);
ok('y un solo desplegable con el resto', plegados === 1, `${plegados} desplegables`);

const txt = () => p.locator('#fichas-resumen').innerText()
  .then(s => s.replace(/\s+/g, ' '));
let t = await txt();

/* ═══════════ 2. SOLO VALORES ═══════════
   Damián, 12 de septiembre: «muy cargado todooo… las tarjetas de los
   valores también tienen como una explicación, no la necesito en esta
   versión, solo valores y si vas a poner algún texto, que sea muy poco».

   Así que aquí se comprueban dos cosas al tiempo: que los números están,
   y que las frases NO. Sin la segunda mitad, las explicaciones vuelven a
   colarse a la primera tarjeta que alguien retoque. */

ok('la tarjeta de hoy dice lo que entró', /\$995\.000/.test(t), t.slice(0, 160));
ok('y el comparativo, como porcentaje y ya', /\+232%/.test(t));
/* Damián, 15 de septiembre: «aún no me termina de convencer la vista
   administrativa de las tarjetas, siento todo muy cargado».

   La ronda anterior quitó las frases pero dejó tres cifras por tarjeta.
   Ahora la cara de la tarjeta lleva UNA cifra y su comparativo; cuántas
   personas fueron sigue existiendo, pero plegado. Las dos mitades se
   comprueban juntas: que no está arriba, y que sí está abajo. Sin la
   segunda, «simplificar» sería un sinónimo educado de perder el dato. */
ok('cuántas personas ya no estorba en la cara de la tarjeta',
   !/34 personas/.test(t), t);
ok('sin la frase de contra qué se compara',
   !/sábado pasado/.test(t) && !/que el/.test(t), t);
ok('sin el desglose de de dónde salió la plata',
   !/en caja/.test(t) && !/por la página/.test(t), t);

/* ═══════════ 3. el comparativo del mes ═══════════
   El +180% es cierto y engañoso a la vez: compara doce días de
   septiembre contra tres de agosto, porque la Caja no existía antes del
   10. El párrafo que lo explicaba se fue, pero el aviso NO: queda en una
   palabra con el detalle en el title. Quitarlo del todo no sería
   simplificar, sería dejar que ese número se lea como que el negocio
   casi triplicó. */

ok('el mes se compara contra el mes anterior al mismo día',
   /\+180%/.test(t), 'de 2.340.000 a 6.560.000');
ok('el aviso de comparativo injusto queda en una palabra',
   /parcial/.test(t), t);
ok('y el párrafo que lo explicaba ya no está',
   !/todavía no es justo/.test(t) && !/empezó a registrar/.test(t), t);
ok('el porqué sigue estando, en el title, para quien lo busque',
   /La Caja empezó a registrar/.test(
     await p.getAttribute('#fichas-resumen .parcial', 'title') || ''),
   await p.getAttribute('#fichas-resumen .parcial', 'title'));
ok('la semana, que sí es comparable, no lleva ese aviso',
   await p.locator('#fichas-resumen .parcial').count() === 1,
   'solo la del mes');

/* ═══════════ 4. entró menos salió, y las salidas ═══════════ */

ok('dice lo que queda del mes', /\$6\.440\.000/.test(t));
ok('sin la resta escrita al lado', !/\$6\.560\.000 − \$120\.000/.test(t), t);
ok('sin la explicación de qué no cuenta como gasto',
   !/no es un gasto/.test(t) && !/cambiando de sitio/.test(t), t);
ok('la lista de salidas no está abierta de entrada',
   !/Profesores/i.test(t), t);

/* Y lo que se plegó tiene que seguir ahí. Se abre el desplegable y se
   comprueba lo mismo que antes se comprobaba en la cara. */
await p.click('#fichas-resumen details.detalle summary');
await p.waitForTimeout(150);
let d = await txt();

ok('abriendo el detalle vuelven las personas', /34/.test(d), d.slice(0, 200));
ok('y las mensualidades del mes', /Mensualidades del mes/i.test(d), d);
ok('las salidas se desglosan por concepto', /Profesores/i.test(d), d);
ok('con su total, para poder cuadrarlo',
   /Salidas del mes \$120\.000/i.test(d), d);
ok('sin decir cuántas salidas ni de qué caja', !/del cajón/.test(d), d);

await p.click('#fichas-resumen details.detalle summary');
await p.waitForTimeout(150);

/* ═══════════ 5. el porcentaje sobre cero no se inventa ═══════════
   Dividir por cero no da «+100%» ni «+Infinity%»: no da nada. Es el
   primer lunes de cada mes y el primer día de la semana. */

resumen = JSON.parse(JSON.stringify(REAL));
resumen.mes_antes = { ...REAL.mes_antes, ingreso_cop: 0, personas: 0 };
resumen.dia_semana_antes = { ...REAL.dia_semana_antes, ingreso_cop: 0, personas: 0 };
await p.click('#resumen-recargar');
await p.waitForTimeout(500);
t = await txt();

ok('comparar contra cero no escribe un porcentaje falso',
   !/Infinity/.test(t) && !/NaN/.test(t), t);
ok('lo dice en una palabra', /nuevo/.test(t), t);
ok('sin la frase que lo explicaba',
   !/nada que comparar/.test(t), t);

/* ═══════════ 6. un mes sin nada no se ve como una avería ═══════════ */

resumen = JSON.parse(JSON.stringify(REAL));
resumen.mes = { ...REAL.mes, ingreso_cop: 0, egreso_cop: 0, queda_cop: 0,
                personas: 0, mensualidades_n: 0, mensualidades_cop: 0,
                de_caja_cop: 0, de_pagina_cop: 0, a_mano_cop: 0 };
resumen.mes_antes = { ...REAL.mes_antes, ingreso_cop: 0 };
resumen.gastos_mes = [];
await p.click('#resumen-recargar');
await p.waitForTimeout(500);
t = await txt();

ok('un mes en cero se dibuja en cero, sin romperse', /\$0/.test(t), t);
// Sin salidas la tarjeta enseña un cero, no una frase disculpándose.
ok('y sin salidas enseña un cero, no una frase',
   /\$0/.test(t) && !/no se ha registrado/.test(t), t);
ok('cero contra cero es una raya, no «nuevo»',
   !/nuevo/.test(t), t);

/* ═══════════ 7. un mes peor se ve peor ═══════════
   La mitad del valor del comparativo está en que una caída se note. Si
   subir y bajar se pintaran igual, habría que leer el número para saber
   cuál es, y entonces el color no servía para nada. */

resumen = JSON.parse(JSON.stringify(REAL));
// La mitad del mes pasado. Y `queda_cop` se deja a propósito con el
// valor viejo, que ya no cuadra con ingreso − egreso: así se comprueba
// que la tarjeta hace la resta ella misma en vez de creerse un total que
// le llega aparte. Una resta que no da es exactamente el descuadre que
// Damián ya tuvo que reportar una vez.
resumen.mes = { ...REAL.mes, ingreso_cop: 1170000 };
resumen.mes_antes_parcial = false;
await p.click('#resumen-recargar');
await p.waitForTimeout(500);
t = await txt();

ok('una caída se dice como caída', /−50%/.test(t), t.slice(0, 400));
const bajas = await p.locator('#fichas-resumen .delta.baja').count();
ok('pintada distinto de una subida', bajas === 1, `${bajas} en rojo`);
// `queda_cop` llega a propósito con el valor viejo, que ya no cuadra con
// ingreso − egreso: la tarjeta hace la resta ella misma en vez de
// creerse un total que le llega aparte. La resta ya no se escribe en la
// cara, así que se comprueba contra las dos puntas: la del mes arriba y
// la de salidas dentro del detalle.
ok('la tarjeta hace la resta ella misma, no se cree un total de fuera',
   /\$1\.170\.000/.test(t) && /\$1\.050\.000/.test(t) && !/\$6\.440\.000/.test(t),
   t.slice(0, 300));

/* ═══════════ 8. la cajera no ve la plata del negocio ═══════════
   En pestaña aparte y no recargando esta: el addInitScript del arranque
   vuelve a escribir el token de propietario en cada carga, así que un
   reload se comía el cambio y la comprobación pasaba sin probar nada. */

const p2 = await b.newPage({ viewport: { width: 390, height: 900 } });
const errs2 = []; p2.on('pageerror', e => errs2.push(String(e)));
await p2.route('**/api/**', r => r.fulfill({ status: 200,
  contentType: 'application/json',
  body: JSON.stringify({ ok: true, dias: [], reservas: [], pagos_libres: [],
                         movimientos: [], resumen_conceptos: [] }) }));
await p2.addInitScript(() => {
  localStorage.setItem('tumbao_admin_token',
    JSON.stringify({ token: 'x', rol: 'cajero', nombre: 'Cajera' }));
});
await p2.goto('http://localhost:8131/', { waitUntil: 'load' });
await p2.waitForTimeout(600);

ok('con rol de cajero la pestaña no está',
   await p2.locator('#tab-resumen').isHidden(),
   'es la plata del negocio, no su turno');
ok('y el panel le abre en el tablero, como siempre',
   await p2.getAttribute('#tab-tablero', 'aria-selected') === 'true');
ok('sin errores de JS con rol de cajero', errs2.length === 0, errs2.join(' | '));

ok('sin errores de JS', errs.length === 0, errs.join(' | '));
console.log(fallos ? `\n${fallos} fallo(s)` : '\nTodo bien');
await b.close(); srv.close();
process.exit(fallos ? 1 : 0);
