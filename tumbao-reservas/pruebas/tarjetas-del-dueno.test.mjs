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

const cuantas = await p.locator('#fichas-resumen .ficha').count();
ok('son cinco tarjetas, las que pidió', cuantas === 5, `${cuantas} tarjetas`);

const txt = () => p.locator('#fichas-resumen').innerText()
  .then(s => s.replace(/\s+/g, ' '));
let t = await txt();

/* ═══════════ 2. hoy ═══════════ */

ok('la tarjeta de hoy dice lo que entró', /\$995\.000/.test(t), t.slice(0, 160));
ok('y cuánta gente entró a clase suelta', /34 personas/.test(t));
ok('y de dónde salió la plata',
   /\$575\.000 en caja/.test(t) && /\$420\.000 por la página/.test(t));
// Un renglón que dice «$0 apuntado a mano» hay que leerlo para descubrir
// que no dice nada. Los ceros no se imprimen.
ok('sin renglones en cero, que solo se leen para nada',
   !/\$0 apuntado a mano/.test(t), t);
ok('se compara contra el mismo día de la semana pasada',
   /\+232%/.test(t), 'de 300.000 a 995.000');

/* ═══════════ 3. el comparativo del mes, con su advertencia ═══════════
   ESTE es el chequeo que importa. El +180% es cierto y es engañoso a la
   vez: compara doce días de septiembre contra tres de agosto, porque la
   Caja no existía antes del 10. Sin el aviso al lado, ese número se lee
   como que el negocio casi triplicó. */

ok('el mes se compara contra el mes anterior al mismo día',
   /\+180%/.test(t), 'de 2.340.000 a 6.560.000');
ok('y avisa de que la comparación todavía no es justa',
   /todavía no es justo/.test(t), t);
ok('diciendo desde cuándo hay Caja de verdad',
   /empezó a registrar el 10 de ago/.test(t), t.slice(300, 700));
ok('el aviso no tapa el número: se enseñan los dos',
   /\$6\.560\.000/.test(t) && /\+180%/.test(t));
ok('la semana, que sí es comparable, no lleva ese aviso',
   (t.match(/está incompleto/g) || []).length <= 1, t);

/* ═══════════ 4. ingresos contra gastos, y en qué se fue ═══════════ */

ok('dice lo que queda del mes', /\$6\.440\.000/.test(t));
ok('con las dos puntas a la vista',
   /Entró \$6\.560\.000/.test(t) && /salió \$120\.000/.test(t));
// Lo que se le entrega al dueño al cerrar NO es un gasto, y confundirlo
// haría que el mes pareciera costar el doble de lo que cuesta.
ok('aclara que lo entregado al dueño no es un gasto',
   /no es un gasto/.test(t), t);
ok('el gasto se desglosa por concepto, no en un solo bulto',
   /Profesores/i.test(t) && /\$120\.000/.test(t), t);
ok('y dice de qué caja salió', /del cajón de la caja/.test(t), t);
ok('con su total, para poder cuadrarlo', /Total \$120\.000/.test(t), t);

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
ok('lo dice con palabras', /nuevo/.test(t), t);
ok('y explica que no había nada que comparar',
   /no hubo nada que comparar/.test(t), t);

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
ok('y sin gastos lo dice con una frase, no con una tabla vacía',
   /no se ha registrado ninguna salida/.test(t), t);
ok('cero contra cero no es «nuevo»: es igual',
   /nada entonces, nada ahora/.test(t), t);

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

ok('una caída se dice como caída', /−50%/.test(t), t.slice(300, 620));
ok('y cuánta plata es, no solo el porcentaje',
   /abajo \$1\.170\.000/.test(t));
const bajas = await p.locator('#fichas-resumen .delta.baja').count();
ok('pintada distinto de una subida', bajas === 1, `${bajas} en rojo`);
ok('los tres números de la tarjeta cuadran entre ellos',
   /\$1\.050\.000 Entró \$1\.170\.000 · salió \$120\.000/.test(t),
   'la resta se hace en la tarjeta, no se cree un total de fuera');

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
