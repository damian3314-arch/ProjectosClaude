/**
 * La Caja cuenta la gente que entró, y el depósito que llegó tarde.
 *
 * POR QUÉ EXISTE ESTA PRUEBA
 * Las dos cosas que llevaban meses descuadrando la caja de la academia
 * no eran errores de plata: eran errores de significado.
 *
 *  1. Llegan tres personas juntas, pagan $45.000 en efectivo y la cajera
 *     registra UN movimiento. El cierre contaba UNA persona. El arqueo
 *     del efectivo cuadraba y la cuenta de gente no, sin ninguna pista.
 *     Y "Otro ingreso" lo empeoraba: los $15.000 que caían ahí no eran
 *     una clase suelta para nadie.
 *
 *  2. La cajera cobra una transferencia con la clienta delante y la
 *     registra en el momento. Minutos después llega la alerta del banco
 *     y entra un depósito sin asociar que nadie cruza nunca. Esa plata
 *     queda contada en la Caja Y persiguiéndose en la tirilla.
 *
 * Lo que se cuida aquí es que la pantalla no pueda volver a decir esas
 * dos mentiras, y sobre todo que "Ya lo registré" no se pueda confundir
 * con cobrar el depósito: son operaciones contrarias, y confundirlas es
 * exactamente el doble conteo que se está tratando de cerrar.
 *
 * El gancho window.__e2e lo pone instrumentar.mjs sobre una copia
 * temporal de docs/admin.html. Sin argumentos:
 *
 *   node caja-contador-y-enlace.test.mjs
 *
 * Admite una ruta suelta para apuntar a otra copia del panel.
 */
import { chromium } from 'playwright-core';
import { rutaDelPanel } from './instrumentar.mjs';

const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
const p = await b.newPage({ viewport: { width: 430, height: 900 } });

const enviado = [];
// Lo que va a contestar /api/enlazar-deposito. Se cambia entre bloques
// para probar el éxito con sobrante y el error redactado por Postgres.
let respuestaEnlace = { estado: 200, cuerpo: { ok: true } };

await p.route('**/api/**', async r => {
  enviado.push({ url: r.request().url(), cuerpo: JSON.parse(r.request().postData() || '{}') });
  await r.fulfill({ status: 200, contentType: 'application/json',
    body: JSON.stringify({ ok: true, reservas: [], pagos_libres: [],
                           movimientos: [], resumen_conceptos: [] }) });
});
await p.route('**/api/enlazar-deposito', async r => {
  enviado.push({ url: r.request().url(), cuerpo: JSON.parse(r.request().postData() || '{}') });
  await r.fulfill({ status: respuestaEnlace.estado, contentType: 'application/json',
    body: JSON.stringify(respuestaEnlace.cuerpo) });
});

const errs = []; p.on('pageerror', e => errs.push(String(e)));
await p.goto('file://' + rutaDelPanel());

let fallos = 0;
const ok = (n, c, extra = '') => { if (!c) fallos++;
  console.log(`${c ? '✓' : '✗'} ${n}${extra ? '  → ' + extra : ''}`); };

/* Ids con forma de uuid: el Worker los valida antes de llamar a la RPC,
   así que inventar "mov-1" probaría un camino que no existe. */
const MOV_TR   = '11111111-1111-4111-8111-111111111111';  // transferencia sin depósito
const MOV_EF   = '22222222-2222-4222-8222-222222222222';  // efectivo
const MOV_YA   = '33333333-3333-4333-8333-333333333333';  // ya tiene depósito
const MOV_SALE = '44444444-4444-4444-8444-444444444444';  // egreso
const MOV_VIEJO = '55555555-5555-4555-8555-555555555555'; // el "otro ingreso" histórico
const DEP      = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';

// La forma real de caja_del_dia: `cantidad` viene desde la 0065 y
// `con_banco` es `pago_id is not null`.
const MOVS = [
  { id: MOV_TR, hora: '18:40', sentido: 'ingreso', concepto: 'mensualidad',
    medio: 'transferencia', valor_cop: 125000, cantidad: 1, con_banco: false,
    nota: 'la mamá', quien: 'Tania' },
  { id: MOV_EF, hora: '18:05', sentido: 'ingreso', concepto: 'clase_suelta',
    medio: 'efectivo', valor_cop: 45000, cantidad: 3, con_banco: false, quien: 'Tania' },
  { id: MOV_YA, hora: '17:30', sentido: 'ingreso', concepto: 'mensualidad',
    medio: 'transferencia', valor_cop: 125000, cantidad: 1, con_banco: true, quien: 'Tania' },
  { id: MOV_SALE, hora: '17:00', sentido: 'egreso', concepto: 'profesores',
    medio: 'transferencia', valor_cop: 80000, cantidad: 1, con_banco: false, quien: 'Tania' },
  // El histórico: se registró cuando "Otro ingreso" todavía se podía
  // escoger. La plata se cobró de verdad y Postgres no lo borró.
  { id: MOV_VIEJO, hora: '09:12', sentido: 'ingreso', concepto: 'otro_ingreso',
    medio: 'efectivo', valor_cop: 15000, cantidad: 1, con_banco: false, quien: 'Tania' },
];

const dia = (movs) => ({ ok: true, dia: '2026-09-02', cerrado: false,
  movimientos: movs, pagos_libres: [], resumen_conceptos: [],
  entradas: {}, banco: {}, cierre: {} });

/* ═══════════ 1. "Otro ingreso" ya no se puede escoger ═══════════ */

await p.evaluate(d => window.__e2e.sembrarCaja(d), dia(MOVS));

const cs = await p.evaluate(() => window.__e2e.conceptos());
ok('"Otro ingreso" ya no se puede escoger', !cs.includes('Otro ingreso'), cs.join(' · '));
ok('siguen los cinco ingresos buenos',
   ['Clase suelta', 'Media mensualidad', 'Mensualidad', 'Cumpleaños', 'Camiseta']
     .every(x => cs.includes(x)), String(cs.length) + ' conceptos');
ok('y los egresos no se tocaron',
   ['Profesores', 'Cafetería', 'Aseo', 'Papelería', 'Otra salida']
     .every(x => cs.includes(x)));

const lineas = await p.evaluate(() => window.__e2e.movimientos());
const viejo = lineas.find(x => /09:12/.test(x));
ok('el movimiento histórico se sigue pintando con su nombre',
   !!viejo && /Otro ingreso/.test(viejo), viejo);
ok('y no con el código crudo', !!viejo && !/otro_ingreso/.test(viejo), viejo);

/* ═══════════ 2. la lista dice a cuánta gente cubrió ═══════════ */

const tres = lineas.find(x => /18:05/.test(x));
ok('un cobro de tres se ve como "3 × Clase suelta"',
   !!tres && /3 × Clase suelta/.test(tres), tres);
ok('con su valor de $45.000', !!tres && /45\.000/.test(tres), tres);
const una = lineas.find(x => /18:40/.test(x));
ok('y uno de una sola no lleva el "1 ×"', !!una && !/1 × /.test(una), una);

/* ═══════════ 3. el contador solo sale en Clase suelta ═══════════ */

await p.evaluate(() => window.__e2e.tocarConcepto('Mensualidad'));
let m = await p.evaluate(() => window.__e2e.modal());
ok('el modal de Mensualidad abre', m.abierto, m.texto);
ok('sin contador', !m.contadorVisible);
ok('y con el valor tecleable a mano', m.editable, 'valor=' + m.valor);
await p.locator('#modal-cancelar').click();

await p.evaluate(() => window.__e2e.tocarConcepto('Clase suelta'));
m = await p.evaluate(() => window.__e2e.modal());
ok('el de Clase suelta trae el contador', m.contadorVisible, m.texto);
ok('arranca en una', m.cantidad === '1', m.cantidad);
ok('con el valor de una clase', m.valor === '15000', m.valor);
ok('el − nace apagado, que no se baje de una', m.menosApagado);

/* ═══════════ 4. poner 3 deja 45.000 y NO se deja editar ═══════════ */

await p.evaluate(() => window.__e2e.mas(2));
m = await p.evaluate(() => window.__e2e.modal());
ok('subir dos veces deja tres', m.cantidad === '3', m.cantidad);
ok('y el valor en 45.000 solo', m.valor === '45000', m.valor);
ok('lo dice con palabras', /3 clases sueltas/.test(m.resumen) && /45\.000/.test(m.resumen),
   m.resumen);
ok('el valor deja de ser tecleable', !m.editable);

// Lo que de verdad haría una cajera que quiere corregir el monto:
// enfocar el campo y teclear. Con readOnly las teclas no entran.
await p.locator('#modal-valor').click();
await p.keyboard.type('999');
m = await p.evaluate(() => window.__e2e.modal());
ok('teclear encima no cambia el valor', m.valor === '45000', m.valor);

// Y el camino de fuerza bruta: fill() espera a que el campo sea
// editable, así que aquí tiene que rendirse.
let bloqueado = false;
try { await p.locator('#modal-valor').fill('99999', { timeout: 1200 }); }
catch (_) { bloqueado = true; }
ok('ni escribiéndolo a la fuerza', bloqueado);

/* ═══════════ 5. se manda cantidad: 3 al Worker ═══════════ */

enviado.length = 0;
await p.evaluate(() => window.__e2e.guardar());
await p.waitForTimeout(400);
const reg = enviado.find(x => /\/api\/registrar$/.test(x.url));
ok('llama a registrar', !!reg, reg && reg.url);
ok('con cantidad 3', !!reg && reg.cuerpo.cantidad === 3, reg && JSON.stringify(reg.cuerpo));
ok('con el valor calculado', !!reg && String(reg.cuerpo.valor) === '45000',
   reg && String(reg.cuerpo.valor));
ok('y con el concepto de clase suelta', !!reg && reg.cuerpo.concepto === 'clase_suelta');

/* ═══════════ 6. "Ya lo registré" solo ofrece lo enlazable ═══════════ */

const LIBRES = [
  { pago_id: DEP, remitente: 'JENNY LISET VERGARA GONZALEZ', valor_cop: 160000,
    saldo_cop: 160000, es_grupo: false, partes: [], cuando: '02/09 18:44' },
];
await p.evaluate(([l, d]) => window.__e2e.sembrar(l, d), [LIBRES, dia(MOVS)]);

await p.evaluate(() => window.__e2e.yaLoRegistre(0));
await p.waitForTimeout(200);
let e = await p.evaluate(() => window.__e2e.enlace());
ok('"Ya lo registré" abre la lista de cobros', e.abierto, e.texto.slice(0, 60));
ok('ofrece un solo cobro', e.opciones.length === 1, e.opciones.join(' | '));
ok('y es el de transferencia sin depósito',
   /18:40/.test(e.opciones[0] || '') && /Mensualidad/.test(e.opciones[0] || ''), e.opciones[0]);
ok('NO ofrece el cobro en efectivo', !e.opciones.some(x => /18:05/.test(x)));
ok('NO ofrece el que ya tiene depósito', !e.opciones.some(x => /17:30/.test(x)));
ok('NO ofrece el egreso', !e.opciones.some(x => /Profesores/.test(x)));
ok('y deja salirse sin hacer nada', e.hayCancelar);

/* ═══════════ 7. sin candidatos, lo dice con palabras ═══════════ */

await p.evaluate(([l, d]) => window.__e2e.sembrar(l, d),
  [LIBRES, dia([MOVS[1]])]);        // solo el cobro en efectivo
await p.evaluate(() => window.__e2e.yaLoRegistre(0));
await p.waitForTimeout(200);
e = await p.evaluate(() => window.__e2e.enlace());
ok('sin cobros enlazables no sale una lista vacía', e.opciones.length === 0);
ok('lo dice con palabras', /Ningún cobro de hoy/.test(e.vacio), e.vacio.slice(0, 70));
ok('y explica lo del efectivo', /efectivo/.test(e.vacio) && /cajón/.test(e.vacio),
   e.vacio.slice(-90));

/* ═══════════ 8. el sobrante se anuncia ═══════════ */

respuestaEnlace = { estado: 200, cuerpo: { ok: true, mov_id: MOV_TR, pago_id: DEP,
  concepto: 'mensualidad', valor_cop: 125000, sobrante_cop: 35000 } };

await p.evaluate(([l, d]) => window.__e2e.sembrar(l, d), [LIBRES, dia(MOVS)]);
await p.evaluate(() => window.__e2e.yaLoRegistre(0));
await p.waitForTimeout(200);
enviado.length = 0;
await p.evaluate(() => window.__e2e.escogerCobro(0));
await p.waitForTimeout(500);

const enl = enviado.find(x => /enlazar-deposito/.test(x.url));
ok('llama a enlazar-deposito', !!enl, enl && enl.url);
ok('con el movimiento escogido', !!enl && enl.cuerpo.mov_id === MOV_TR,
   enl && enl.cuerpo.mov_id);
ok('y con el depósito de la lista', !!enl && enl.cuerpo.pago_id === DEP,
   enl && enl.cuerpo.pago_id);

let av = await p.evaluate(() => window.__e2e.avisos());
ok('avisa que quedó enlazado', av.length > 0 && /enlazado/i.test(av[0].texto),
   av[0] && av[0].texto.slice(0, 70));
ok('y dice cuánto le sobra al depósito', av[0] && /35\.000/.test(av[0].texto),
   av[0] && av[0].texto);
ok('sin dejarlo como si el depósito se hubiera acabado',
   av[0] && /sigue en la lista/.test(av[0].texto));

// Al refrescar, la lista de sin dueño vuelve vacía y el depósito
// desaparece: es lo que la cajera tiene que ver para dejar de buscarlo.
const quedan = await p.evaluate(() => window.__e2e.libres().filas);
ok('el depósito desaparece de la lista de sin dueño', quedan === 0, String(quedan));

/* ═══════════ 9. el error se muestra con el mensaje de la base ═══════════ */

const MENSAJE = 'Ese cobro se registró en efectivo: esa plata está en el cajón, ' +
  'no en el banco, así que no puede ser esta transferencia. No es el mismo dinero.';
respuestaEnlace = { estado: 400,
  cuerpo: { ok: false, error: 'ES_EFECTIVO', mensaje: MENSAJE } };

await p.evaluate(([l, d]) => window.__e2e.sembrar(l, d), [LIBRES, dia(MOVS)]);
await p.evaluate(() => window.__e2e.yaLoRegistre(0));
await p.waitForTimeout(200);
await p.evaluate(() => window.__e2e.escogerCobro(0));
await p.waitForTimeout(400);

av = await p.evaluate(() => window.__e2e.avisos());
ok('el fallo sale como aviso malo', av.length > 0 && /mal/.test(av[0].clase), av[0] && av[0].clase);
ok('con el mensaje tal cual lo redactó la base',
   av[0] && av[0].texto.includes('esa plata está en el cajón, no en el banco'),
   av[0] && av[0].texto.slice(0, 90));
ok('y no lo cambia por uno del panel',
   av[0] && !/El día ya está cerrado/.test(av[0].texto));

e = await p.evaluate(() => window.__e2e.enlace());
ok('el panel se queda abierto para reintentar', e.abierto);

/* ═══════════ 10. tres que transfieren juntas ═══════════ */

// Cobrar un depósito de $45.000 como clase suelta son TRES personas, y
// el panel ya sabe dividir: obligar a subir el contador a mano hasta
// cuadrar con el depósito sería pedirle a la cajera la división que la
// pantalla puede hacer sola.
await p.evaluate(l => window.__e2e.sembrarLibres(l), [
  { pago_id: DEP, remitente: 'LAS TRES DE LAS 7', valor_cop: 45000,
    saldo_cop: 45000, es_grupo: false, partes: [], cuando: '02/09 18:50' },
]);
await p.evaluate(() => window.__e2e.tocarPago(0));
await p.waitForTimeout(200);
await p.evaluate(() => window.__e2e.tocarConcepto('Clase suelta'));
m = await p.evaluate(() => window.__e2e.modal());
ok('un depósito de $45.000 en clases sueltas son tres', m.cantidad === '3', m.cantidad);
ok('por el valor que llegó al banco', m.valor === '45000', m.valor);
ok('y sigue sin poderse teclear', !m.editable);

/* ═══════════ 11. una transferencia no se guarda a ciegas ═══════════

   EL CASO REAL. El 5 de septiembre se hicieron tres cobros en
   recepción. Dos se registraron como transferencia SIN escoger el
   depósito: el de las 08:00 con la referencia tecleada en la nota en
   vez de enlazada, y el de las 09:40 sin nada. Esos $30.000 no tenían
   respaldo en el banco —ese día no había ningún depósito libre— y el
   cierre terminó enseñando dos cifras que no se podían reconciliar.

   La cajera no hizo nada raro: Guardar funcionaba igual con depósito y
   sin él, así que el camino descuidado costaba lo mismo que el
   cuidadoso. Lo que se cuida aquí es que deje de costar lo mismo.

   Las dos salidas siguen abiertas —escoger el depósito, o decir que no
   está— y las dos son válidas. Lo que deja de poderse es no decir
   nada. */

/* La lista del modal se lee de `cajaDatos.pagos_libres`, que es OTRA
   forma que la del tablero de sin dueño: ahí la llave es `pago_id` y
   aquí es `id`. Se escribe entera para que la prueba recorra el camino
   bueno de verdad —escoger un depósito— y no el de la lista vacía. */
const CON_DEP = () => Object.assign(dia(MOVS), { pagos_libres: [
  { id: DEP, remitente: 'JENNY LISET VERGARA GONZALEZ',
    valor_cop: 125000, saldo_cop: 125000, cuando: '02/09 18:44', dias: 0 },
] });

await p.evaluate(d => window.__e2e.sembrarCaja(d), CON_DEP());
await p.evaluate(() => window.__e2e.tocarConcepto('Mensualidad'));
await p.locator('#modal-caja .medio[data-medio="transferencia"]').click();

enviado.length = 0;
await p.evaluate(() => window.__e2e.guardar());
await p.waitForTimeout(400);

ok('no registra una transferencia sin decir cuál depósito es',
   !enviado.some(x => /\/api\/registrar$/.test(x.url)),
   enviado.map(x => x.url).join(' | '));
m = await p.evaluate(() => window.__e2e.modal());
ok('y la ventana se queda abierta para arreglarlo', m.abierto);
av = await p.evaluate(() => window.__e2e.avisos());
ok('lo dice como pregunta, no como regaño',
   av.length > 0 && /Cuál depósito es/.test(av[0].texto), av[0] && av[0].texto.slice(0, 60));
ok('y enseña las dos salidas que hay',
   av[0] && /Escoge de la lista/.test(av[0].texto) && /No está en la lista/.test(av[0].texto),
   av[0] && av[0].texto.slice(0, 140));
ok('marcando el botón que hay que tocar si de verdad no está',
   await p.locator('#modal-sin-deposito').evaluate(x => x.classList.contains('malo-campo')));

// SALIDA A: decirlo a propósito. Se guarda, y queda marcado.
await p.locator('#modal-sin-deposito').click();
ok('el botón queda encendido al tocarlo',
   await p.locator('#modal-sin-deposito').evaluate(x => x.classList.contains('on')));
ok('y ya no está en rojo',
   !await p.locator('#modal-sin-deposito').evaluate(x => x.classList.contains('malo-campo')));

enviado.length = 0;
await p.evaluate(() => window.__e2e.guardar());
await p.waitForTimeout(400);
let reg2 = enviado.find(x => /\/api\/registrar$/.test(x.url));
ok('dicho a propósito, sí se guarda', !!reg2, enviado.map(x => x.url).join(' | '));
ok('y va sin depósito, que es lo que se dijo',
   !!reg2 && reg2.cuerpo.pago_id === null, reg2 && JSON.stringify(reg2.cuerpo.pago_id));

// SALIDA B: escoger el depósito. Es el camino bueno y no pregunta nada.
await p.evaluate(d => window.__e2e.sembrarCaja(d), CON_DEP());
await p.evaluate(() => window.__e2e.tocarConcepto('Mensualidad'));
await p.locator('#modal-caja .medio[data-medio="transferencia"]').click();
await p.waitForTimeout(150);
await p.locator('#modal-depositos [data-pago]').first().click();

enviado.length = 0;
await p.evaluate(() => window.__e2e.guardar());
await p.waitForTimeout(400);
reg2 = enviado.find(x => /\/api\/registrar$/.test(x.url));
ok('con depósito escogido no pregunta nada', !!reg2, enviado.map(x => x.url).join(' | '));
ok('y lo manda enlazado', !!reg2 && reg2.cuerpo.pago_id === DEP,
   reg2 && String(reg2.cuerpo.pago_id));

/* El "no está en la lista" NO se hereda. Decirlo para un cobro y que
   valiera para el siguiente sería peor que no pedirlo: el segundo
   pasaría sin que nadie lo mirara. */
await p.evaluate(d => window.__e2e.sembrarCaja(d), CON_DEP());
await p.evaluate(() => window.__e2e.tocarConcepto('Mensualidad'));
await p.locator('#modal-caja .medio[data-medio="transferencia"]').click();
enviado.length = 0;
await p.evaluate(() => window.__e2e.guardar());
await p.waitForTimeout(400);
ok('el "no está" del cobro anterior no vale para este',
   !enviado.some(x => /\/api\/registrar$/.test(x.url)),
   enviado.map(x => x.url).join(' | '));

// Y cambiar de transferencia a efectivo lo olvida también: en efectivo
// no hay depósito que escoger y el permiso no tiene sentido.
await p.locator('#modal-sin-deposito').click();
await p.locator('#modal-caja .medio[data-medio="efectivo"]').click();
await p.locator('#modal-caja .medio[data-medio="transferencia"]').click();
enviado.length = 0;
await p.evaluate(() => window.__e2e.guardar());
await p.waitForTimeout(400);
ok('pasar por efectivo y volver también lo olvida',
   !enviado.some(x => /\/api\/registrar$/.test(x.url)),
   enviado.map(x => x.url).join(' | '));

// Un COBRO EN EFECTIVO no pregunta nada: no hay depósito que escoger.
await p.locator('#modal-caja .medio[data-medio="efectivo"]').click();
enviado.length = 0;
await p.evaluate(() => window.__e2e.guardar());
await p.waitForTimeout(400);
ok('en efectivo no se pregunta por ningún depósito',
   enviado.some(x => /\/api\/registrar$/.test(x.url)),
   enviado.map(x => x.url).join(' | '));

// Y un GASTO por transferencia tampoco: sale, no entra.
await p.evaluate(d => window.__e2e.sembrarCaja(d), CON_DEP());
await p.evaluate(() => window.__e2e.tocarConcepto('Profesores'));
await p.locator('#modal-caja .medio[data-medio="transferencia"]').click();
await p.locator('#modal-valor').fill('80000');
enviado.length = 0;
await p.evaluate(() => window.__e2e.guardar());
await p.waitForTimeout(400);
ok('un gasto por transferencia tampoco pregunta',
   enviado.some(x => /\/api\/registrar$/.test(x.url)),
   enviado.map(x => x.url).join(' | '));

ok('sin errores de JS', errs.length === 0, errs.join(' | '));
console.log(fallos ? `\n${fallos} fallo(s)` : '\nTodo bien');
await b.close();
process.exit(fallos ? 1 : 0);
