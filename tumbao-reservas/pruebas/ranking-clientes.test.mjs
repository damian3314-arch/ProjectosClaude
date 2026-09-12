/**
 * Quiénes vienen más — el ranking de clientes.
 *
 * POR QUÉ EXISTE ESTA PRUEBA
 * Un ranking equivocado no se nota: se cree. Y aquí hay tres maneras
 * distintas de equivocarse sin que nada falle.
 *
 * 1. LA IDENTIDAD. Damián la fijó: celular + nombre. Esta base no tiene
 *    clientes, tiene reservas con el nombre escrito a mano cada vez, así
 *    que la misma persona aparece como «Ludys Herazo», «Ludys herazo» y
 *    «ludis herazo», y tres amigas comparten un teléfono. Quien decide
 *    qué filas son la misma persona es Postgres (cliente_clave, 0083);
 *    lo que se prueba aquí es que la pantalla no estropee ese trabajo.
 *
 * 2. EL LÍMITE DE LA REGLA. Una errata de tecleo parte a una persona en
 *    dos fichas y ninguna regla honesta lo arregla sola: «LUDIS» y
 *    «LUDYS» no se parecen más que «KAREN YEPES» y «KAREN HERRERA», que
 *    sí son dos personas. Así que el panel tiene que DECIR cuándo un
 *    teléfono tiene varias fichas. Si ese aviso no sale, el número de
 *    días se lee como exacto cuando no lo es.
 *
 * 3. LO QUE NO SE MIDE. Las afiliadas no generan reserva, así que las
 *    personas que de verdad más vienen no están en esta lista ni pueden
 *    estar. Sin esa frase en pantalla, el ranking se lee como «estas son
 *    mis mejores clientas», que es falso.
 *
 *   node ranking-clientes.test.mjs
 */
import { chromium } from 'playwright-core';
import { rutaDelPanel } from './instrumentar.mjs';
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';

const PANEL = rutaDelPanel();
const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
const p = await b.newPage({ viewport: { width: 390, height: 1100 } });
const errs = []; p.on('pageerror', e => errs.push(String(e)));

let fallos = 0;
const ok = (n, c, extra = '') => { if (!c) fallos++;
  console.log(`${c ? '✓' : 'FALLO'} ${n}${extra ? '  → ' + extra : ''}`); };

const RESUMEN = {
  ok: true, hoy: '2026-09-12', primer_dato: '2026-07-28', primer_caja: '2026-08-10',
  dia: { desde: '2026-09-12', hasta: '2026-09-12', dias: 1, personas: 34,
         ingreso_cop: 995000, egreso_cop: 60000, queda_cop: 935000,
         de_caja_cop: 575000, de_pagina_cop: 420000, a_mano_cop: 0,
         mensualidades_n: 2, mensualidades_cop: 250000 },
  dia_semana_antes: { desde: '2026-09-05', hasta: '2026-09-05', dias: 1,
         personas: 20, ingreso_cop: 300000, egreso_cop: 0 },
  semana: { desde: '2026-09-07', hasta: '2026-09-12', dias: 6, personas: 99,
         ingreso_cop: 4540000, egreso_cop: 120000, mensualidades_n: 24 },
  semana_antes: { desde: '2026-08-31', hasta: '2026-09-05', dias: 6, ingreso_cop: 3315000 },
  mes: { desde: '2026-09-01', hasta: '2026-09-12', dias: 12, personas: 168,
         ingreso_cop: 6560000, egreso_cop: 120000, mensualidades_n: 32,
         mensualidades_cop: 3910000 },
  mes_antes: { desde: '2026-08-01', hasta: '2026-08-12', dias: 12, ingreso_cop: 2340000 },
  mes_antes_parcial: true, semana_antes_parcial: false,
  gastos_mes: [{ concepto: 'profesores', cop: 120000, n: 2, de_caja_menor: true }],
};

/* Lo que devolvió admin_clientes_ranking contra producción el 12 de
   septiembre de 2026, sin recortar. Ludys sale con 8 días y no con 11
   porque dos de sus escrituras llevan errata —«ludis» y «haerazo»— y la
   regla no las junta: el aviso de fichas compartidas es lo que lo dice. */
const REAL = {
  ok: true, hoy: '2026-09-12', desde: null, dias_pedidos: null,
  solo_clase_suelta: true,
  clientes: [
    { puesto: 1, nombre: 'Ludys Herazo', telefono: '3118708421', dias: 8,
      plata_cop: 120000, primera: '2026-08-12', ultima: '2026-09-11',
      hace_dias: 1, hora: '19:00', escrituras: 1, fichas_del_telefono: 4,
      afiliada: false },
    { puesto: 2, nombre: 'Yira Zahira', telefono: '3213487086', dias: 7,
      plata_cop: 105000, primera: '2026-08-10', ultima: '2026-09-07',
      hace_dias: 5, hora: '19:00', escrituras: 2, fichas_del_telefono: 3,
      afiliada: false },
    { puesto: 3, nombre: 'Maria fernanda Bernal vidales', telefono: '3044605577',
      dias: 7, plata_cop: 105000, primera: '2026-07-28', ultima: '2026-08-18',
      hace_dias: 25, hora: '19:00', escrituras: 1, fichas_del_telefono: 1,
      afiliada: true },
    { puesto: 4, nombre: 'Adriana Méndez', telefono: '3012041386', dias: 5,
      plata_cop: 75000, primera: '2026-08-15', ultima: '2026-09-12',
      hace_dias: 0, hora: '08:00', escrituras: 1, fichas_del_telefono: 2,
      afiliada: false },
    { puesto: 5, nombre: 'Karen Vivian Yepes', telefono: '3024327694', dias: 5,
      plata_cop: 75000, primera: '2026-08-13', ultima: '2026-09-10',
      hace_dias: 2, hora: '18:00', escrituras: 2, fichas_del_telefono: 3,
      afiliada: false },
  ],
  telefonos_compartidos: [
    { telefono: '3118708421', cuantas: 4,
      nombres: ['LUDIS HERAZO', 'Ludys Herazo', 'Ludys haerazo', 'Yurley Egea'] },
    { telefono: '3024327694', cuantas: 3,
      nombres: ['Jessica Paba', 'Karen Julieth Herrera Arcia', 'Karen Vivian Yepes'] },
    { telefono: '3213487086', cuantas: 3,
      nombres: ['Giuliana', 'Paloma', 'Yira Zahira'] },
    { telefono: '3012041386', cuantas: 2,
      nombres: ['Adriana Méndez', 'Elaine quintero'] },
    // Un teléfono que NO sale en la lista de arriba: no debe aparecer en
    // el aviso. Avisar de los sesenta que hay es una pared que nadie lee.
    { telefono: '3005550000', cuantas: 2, nombres: ['Fulana Uno', 'Fulana Dos'] },
  ],
};

let ranking = REAL;
const pedidos = [];

/* EN PLAYWRIGHT MANDA LA ÚLTIMA RUTA REGISTRADA, no la más específica. */
await p.route('**/api/**', r => r.fulfill({ status: 200,
  contentType: 'application/json',
  body: JSON.stringify({ ok: true, dias: [], reservas: [], pagos_libres: [],
                         movimientos: [], resumen_conceptos: [] }) }));
await p.route('**/api/admin/resumen-gerencia', r => r.fulfill({ status: 200,
  contentType: 'application/json', body: JSON.stringify(RESUMEN) }));
await p.route('**/api/admin/clientes-ranking', r => {
  pedidos.push(JSON.parse(r.request().postData() || '{}'));
  return r.fulfill({ status: 200, contentType: 'application/json',
    body: JSON.stringify(ranking) });
});

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
await p.waitForTimeout(700);

const txt = () => p.locator('#ranking-clientes').innerText().then(s => s.replace(/\s+/g, ' '));
let t = await txt();

/* ═══════════ 1. sale solo, junto a las tarjetas ═══════════ */

ok('el ranking se pinta al abrir el resumen, sin tocar nada',
   await p.locator('.cliente-fila').count() === 5,
   await p.locator('.cliente-fila').count() + ' filas');
ok('arranca pidiendo los últimos 90 días',
   pedidos.length >= 1 && pedidos[0].dias === 90, JSON.stringify(pedidos[0]));
ok('y pide diez, no la base entera', pedidos[0].limite === 10);

/* ═══════════ 2. SOLO VALORES, cuatro por fila ═══════════
   Damián, 12 de septiembre: «muy cargado todooo… necesitamos es algo
   sencillo pero que yo tenga presente a esos buenos clientes… si vas a
   poner algún texto, que sea muy poco».

   Se comprueba que los cuatro datos están y que las frases NO. Sin la
   segunda mitad, la prosa vuelve a colarse a la primera vez que alguien
   toque esta lista. */

ok('cada fila dice cuántas veces vino', /\b8\b/.test(t), t.slice(0, 140));
ok('quién es', /Ludys Herazo/.test(t));
ok('su teléfono, que es para llamarla', /3118708421/.test(t));
ok('y lo que lleva pagado', /\$120\.000/.test(t));
// La fecha es el mismo dato que «vino ayer» en menos sitio.
ok('la última visita va como fecha, no como frase',
   /11 de sept/i.test(t) && !/vino ayer/.test(t) && !/vino hoy/.test(t), t);
ok('sin «hace N días»', !/hace \d+ días/.test(t), t);
ok('sin la hora a la que viene casi siempre',
   !/casi siempre/.test(t) && !/7:00 pm/.test(t), t);
ok('sin la coletilla «en sueltas» en cada renglón',
   !/en sueltas/.test(t), t);

/* ═══════════ 3. quien ya tiene plan se marca ═══════════
   Es la diferencia entre una clienta a la que venderle una mensualidad y
   una a la que ya se le vendió. La marca se queda, en una palabra. */

ok('quien ya es afiliada lleva su marca',
   await p.locator('.tiene-plan').count() === 1, 'María Fernanda ya compró plan');
// innerText pega la marca al nombre —«vidalesplan»— porque el espacio lo
// pone el CSS; se mira el elemento, no el texto corrido.
ok('y cabe en una palabra',
   (await p.locator('.tiene-plan').innerText()).trim() === 'plan' &&
   !/ya tiene plan/.test(t), t);

/* ═══════════ 4. EL AVISO, reducido a un asterisco ═══════════
   Ludys tiene dos escrituras con errata que la regla no junta. El
   párrafo que lo explicaba se fue —nadie lo leía— pero la marca NO:
   sin ninguna, «8 veces» se lee como exacto cuando no lo es. */

ok('quien comparte teléfono lleva un asterisco',
   await p.locator('.cliente-fila .marca').count() === 4,
   'cuatro de las cinco lo comparten');
ok('quien no lo comparte, no lo lleva',
   await p.locator('.cliente-fila').nth(2).locator('.marca').count() === 0,
   'María Fernanda tiene una sola ficha');
ok('el porqué sigue en el title, para quien lo busque',
   /otras fichas/.test(await p.getAttribute('.cliente-fila .marca', 'title') || ''),
   await p.getAttribute('.cliente-fila .marca', 'title'));
ok('y el párrafo de antes ya no está',
   !/tienen varias fichas/.test(t) && !/grupo de amigas/.test(t), t);
ok('sin listar los teléfonos repetidos debajo',
   !/Fulana/.test(t) && !/LUDIS HERAZO/.test(t), t);

/* ═══════════ 5. lo que no se mide, en dos palabras ═══════════
   Sin esto la lista se lee como «mis mejores clientas», y es falso: las
   que más vienen son las afiliadas y no pueden estar aquí. */

ok('el título dice que es clase suelta', /clase suelta/i.test(t), t);
ok('sin el párrafo que lo explicaba',
   !/no generan reserva/.test(t), t);
ok('el porqué sigue en el title',
   /no generan reserva/.test(
     await p.getAttribute('.cab-ranking .parcial', 'title') || ''),
   await p.getAttribute('.cab-ranking .parcial', 'title'));

/* ═══════════ 6. cambiar la ventana ═══════════ */

await p.click('[data-ventana="30"]');
await p.waitForTimeout(400);
ok('el botón de 30 d pide 30 días',
   pedidos[pedidos.length - 1].dias === 30, JSON.stringify(pedidos));
ok('y se marca cuál está puesta',
   await p.locator('[data-ventana="30"].puesta').count() === 1);
ok('sin dejar dos marcados a la vez',
   await p.locator('[data-ventana].puesta').count() === 1);

await p.click('[data-ventana="0"]');
await p.waitForTimeout(400);
// "Todo" no es "0 días": si viajara un 0, Postgres devolvería la ventana
// de un día y la pantalla diría que nadie viene nunca.
ok('«Todo» manda null, no un cero',
   pedidos[pedidos.length - 1].dias === null,
   JSON.stringify(pedidos[pedidos.length - 1]));

/* ═══════════ 7. un plazo sin nadie no parece una avería ═══════════ */

ranking = { ok: true, hoy: '2026-09-12', clientes: [], telefonos_compartidos: [],
            solo_clase_suelta: true };
await p.click('[data-ventana="30"]');
await p.waitForTimeout(450);
t = await txt();
ok('sin clientas lo dice en una línea corta',
   /Sin clases sueltas en este plazo/.test(t), t);
ok('y no deja filas colgando',
   await p.locator('.cliente-fila').count() === 0);

/* ═══════════ 8. la cajera no ve esto ═══════════ */

const p2 = await b.newPage({ viewport: { width: 390, height: 1100 } });
const errs2 = []; p2.on('pageerror', e => errs2.push(String(e)));
await p2.route('**/api/**', r => r.fulfill({ status: 200,
  contentType: 'application/json',
  body: JSON.stringify({ ok: true, dias: [], reservas: [], pagos_libres: [],
                         movimientos: [], resumen_conceptos: [] }) }));
await p2.addInitScript(() => {
  localStorage.setItem('tumbao_admin_token',
    JSON.stringify({ token: 'x', rol: 'cajero', nombre: 'Cajera' }));
});
await p2.goto('http://localhost:8133/', { waitUntil: 'load' });
await p2.waitForTimeout(600);
ok('con rol de cajero la pestaña del resumen no está',
   await p2.locator('#tab-resumen').isHidden(),
   'ahí van nombres, teléfonos y cuánto paga cada quien');
ok('sin errores de JS con rol de cajero', errs2.length === 0, errs2.join(' | '));

ok('sin errores de JS', errs.length === 0, errs.join(' | '));
console.log(fallos ? `\n${fallos} fallo(s)` : '\nTodo bien');
await b.close(); srv.close();
process.exit(fallos ? 1 : 0);
