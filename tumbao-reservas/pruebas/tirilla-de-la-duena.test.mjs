/**
 * HOJA 1 — la tirilla del cierre, tal como la dibujó la dueña.
 *
 * Este formato no lo diseñó nadie del lado del código: la dueña lo
 * dibujó a mano en un rollo y lo mandó. Antes de eso el papel llevaba
 * el arqueo con veredicto, el desglose de la plata del banco, el
 * contador de personas, lo que quedaba por revisar y una firma; ella lo
 * leyó y devolvió esta hoja, más corta y sin veredictos.
 *
 * Lo que esta prueba protege NO es que el papel sea bonito, es que
 * SUME. La tirilla se archiva junto al efectivo y es lo único que queda
 * del día sin abrir el sistema: si un renglón se cae del subtotal, o el
 * saldo final no es lo que de verdad se dejó en el cajón, el error se
 * descubre semanas después y ya no hay a quién preguntarle.
 *
 * De ahí que los subtotales se comprueben CONTRA LOS RENGLONES QUE SE
 * IMPRIMEN y no contra un campo del servidor: es la única forma de que
 * un concepto nuevo no pueda entrar en el desglose y quedarse fuera del
 * total, que es exactamente como se pierde plata en un papel.
 *
 * Los casos que lo rompen:
 *   · un concepto que nadie previó (una camiseta, un cumpleaños) tiene
 *     que aparecer solo, con su bloque y dentro del total.
 *   · una reserva apuntada a mano no es efectivo ni es banco —el cobro
 *     no se registró en ninguna parte—, así que no puede sumarse a
 *     ninguno de los dos sin que el papel jure tener una plata
 *     localizable que no lo es.
 *   · un descuadre al contar el cajón no estaba en el dibujo de ella,
 *     pero tiene que salir cuando lo hay: sin eso un faltante no
 *     aparece en ningún sitio del papel.
 *
 * El gancho window.__e2e lo pone instrumentar.mjs sobre una copia
 * temporal de docs/admin.html. Sin argumentos:
 *
 *   node tirilla-de-la-duena.test.mjs
 *
 * Admite una ruta suelta para apuntar a otra copia del panel.
 */
import { chromium } from 'playwright-core';
import { rutaDelPanel } from './instrumentar.mjs';
const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
const p = await b.newPage({ viewport: { width: 430, height: 900 } });
const errs = []; p.on('pageerror', e => errs.push(String(e)));
await p.goto('file://' + rutaDelPanel());

let fallos = 0;
const ok = (n, c, extra = '') => { if (!c) fallos++;
  console.log(`${c ? '✓' : '✗'} ${n}${extra ? '  → ' + extra : ''}`); };

// El texto sale pegado (`innerText` sobre un #tirilla oculto no mete
// saltos), así que se compara sobre la versión sin espacios: "6 cupos"
// y "$90.000" quedan como "6cupos$90.000".
const pintar = async (d) => {
  const fajo = await p.evaluate(x => window.__e2e.tirillas(x), d);
  const h = fajo.hojas.find(x => x.id === 'hoja-cierre') || { texto: '' };
  return { fajo, texto: h.texto, junto: h.texto.replace(/\s/g, '') };
};

/* ── el día real: 1 de septiembre de 2026 ─────────────────────────
   Los mismos números que la dueña escribió en su dibujo, verificados
   contra producción. Si esta prueba pasa, el papel que sale de la
   impresora es el papel que ella pidió. */
const REAL = {
  dia: '2026-09-01',
  cerrado: true,
  base_cop: 100000,
  egreso_efectivo: 0,
  cierre: { hora: '19:43', quien: 'Tania', retirado_cop: 140000,
            dejado_cop: 100000, contado_cop: 240000, diferencia_cop: 0 },
  entradas: {
    pagina_transferencia_n: 6, pagina_transferencia_cop: 90000,
    a_mano_n: 0, a_mano_cop: 0,
    efectivo_n: 1, efectivo_cop: 15000,
    recepcion_transferencia_n: 4, recepcion_transferencia_cop: 60000,
  },
  resumen_conceptos: [
    { concepto: 'mensualidad', medio: 'transferencia', sentido: 'ingreso',
      n: 4, valor_cop: 500000 },
    { concepto: 'mensualidad', medio: 'efectivo', sentido: 'ingreso',
      n: 1, valor_cop: 125000 },
    { concepto: 'clase_suelta', medio: 'transferencia', sentido: 'ingreso',
      n: 4, valor_cop: 60000 },
    { concepto: 'clase_suelta', medio: 'efectivo', sentido: 'ingreso',
      n: 1, valor_cop: 15000 },
  ],
  banco: { recibido_cop: 715000 },
  // El desglose de lo que trajo el banco (0064), tal como estaba ese día:
  // $465.000 se supieron nombrar y $250.000 quedaron sin dueño.
  cuadre: {
    quien_entro: { personas: 7, pagaron_antes: 1, pagaron_hoy: 5,
                   pagaron_hoy_cop: 75000, sin_deposito: 1 },
    entro_al_banco: {
      clases_hoy_n: 5, clases_hoy_cop: 75000,
      futuras_cupos: 0, futuras_depositos: 0, futuras_cop: 0,
      otros: [{ concepto: 'mensualidad', n: 3, cop: 375000 },
              { concepto: 'clase_suelta', n: 1, cop: 15000 }],
      otros_cop: 390000,
      identificado_cop: 465000,
      reporto_banco_cop: 715000,
      sin_identificar_cop: 250000 },
  },
  conciliacion: { banco: [], banco_cop: 0, banco_hoy_cop: 465000,
                  efectivo: [], efectivo_cop: 0,
                  sin_enlazar: [], sin_enlazar_cop: 0, sin_pago: [] },
};

let { fajo, texto: t, junto: j } = await pintar(REAL);

// ── la cabecera que ella dibujó ──────────────────────────────────
ok('se titula TUMBAO · CIERRE DE CAJA',
   /TUMBAO/.test(t) && /CIERRE DE CAJA/.test(t));
ok('la fecha va con guiones y el día delante', /01-09-2026/.test(t),
   'así la escribió ella, no 2026-09-01 ni 01/09/2026');
ok('la hoja del cierre no se numera', !/HOJA 1 DE/i.test(t),
   'su dibujo no lleva numeración');
ok('y termina dando las gracias', /Gracias/.test(t));

// ── los cupos, por la puerta por la que entraron ─────────────────
ok('reservas por página, con sus cupos', /Reservasporpágina6cupos\$90\.000/.test(j));
ok('reservas manuales salen aunque sean cero',
   /Reservasmanuales0cupos\$0/.test(j),
   'un renglón ausente se lee como "se me olvidó", no como "no hubo"');
ok('los cupos de caja, partidos en efectivo y bancos',
   /Cuposencaja/.test(j) && /Efectivo:1cupo\$15\.000/.test(j) &&
   /Bancos:4cupos\$60\.000/.test(j));

// ── lo que no es un cupo ─────────────────────────────────────────
ok('las mensualidades llevan su propio bloque', /Mensualidades/.test(t));
ok('partidas también en efectivo y bancos',
   /Efectivo:1mensualidad\$125\.000/.test(j) &&
   /Bancos:4mensualidades\$500\.000/.test(j),
   'y en plural cuando son varias');

// ── el resumen: lo que de verdad protege esta prueba ─────────────
ok('los ingresos en efectivo suman los renglones de efectivo',
   /Ingresosenefectivo\$140\.000/.test(j), '15.000 del cupo + 125.000 de la mensualidad');
ok('los de bancos suman los de bancos',
   /Ingresosporbancos\$650\.000/.test(j), '90.000 página + 60.000 caja + 500.000 mensualidades');
ok('y el TOTAL es la suma de los dos',
   /TOTALINGRESOS\$790\.000/.test(j), '140.000 + 650.000');

// ── el cajón ─────────────────────────────────────────────────────
ok('el movimiento de caja arranca en la base',
   /Baseinicial\$100\.000/.test(j));
ok('mete solo el efectivo, no lo del banco',
   /Entradasenefectivo\$140\.000/.test(j),
   'la transferencia no pasa por el cajón');
ok('gastos y retiros van juntos, como en su dibujo',
   /Gastos\/retiros\$140\.000/.test(j), '0 de gastos + 140.000 que se llevó al cerrar');
ok('y el saldo final es lo que de verdad se dejó',
   /SALDOFINALENCAJA\$100\.000/.test(j),
   '100.000 + 140.000 − 140.000, que es el dejado_cop real');

// ── un día limpio no enseña veredictos ───────────────────────────
ok('sin descuadre no aparece ningún renglón de descuadre',
   !/Descuadre/.test(t));
ok('ni el arqueo viejo con su SÍ CUADRA',
   !/SÍ CUADRA|NO CUADRA|CAJA 1|Se abrió con|Debía haber/.test(t));
ok('ni las secciones que ella quitó',
   !/INGRESOS DEL DÍA|POR REVISAR|DE ESO|Firma/.test(t));

/* ── un concepto que nadie previó ─────────────────────────────────
   Se vende una camiseta. Tiene que salir con su bloque y, sobre todo,
   entrar en los dos subtotales: un concepto nuevo que aparezca en el
   desglose pero no en el total es plata perdida en el papel. */
({ texto: t, junto: j } = await pintar({ ...REAL,
  resumen_conceptos: [...REAL.resumen_conceptos,
    { concepto: 'camiseta', medio: 'efectivo', sentido: 'ingreso',
      n: 2, valor_cop: 50000 }] }));
ok('un concepto nuevo se imprime solo, sin tocar el código',
   /Camisetas/.test(t) && /Efectivo:2camisetas\$50\.000/.test(j));
ok('y entra en el subtotal de efectivo',
   /Ingresosenefectivo\$190\.000/.test(j), '140.000 + 50.000');
ok('y en el TOTAL', /TOTALINGRESOS\$840\.000/.test(j), '790.000 + 50.000');
ok('y también en el cajón, que es donde están esos billetes',
   /Entradasenefectivo\$190\.000/.test(j) &&
   /SALDOFINALENCAJA\$150\.000/.test(j));

/* ── una reserva apuntada a mano ──────────────────────────────────
   El cobro no quedó registrado en ninguna parte: ni en el cajón ni en
   el banco. Sumarla a cualquiera de los dos haría que el papel jurara
   tener una plata que nadie puede ir a buscar. */
({ texto: t, junto: j } = await pintar({ ...REAL,
  entradas: { ...REAL.entradas, a_mano_n: 1, a_mano_cop: 15000 } }));
ok('la apuntada a mano sale con su cupo', /Reservasmanuales1cupo\$15\.000/.test(j));
ok('no se cuela en el efectivo', /Ingresosenefectivo\$140\.000/.test(j));
ok('ni en los bancos', /Ingresosporbancos\$650\.000/.test(j));
ok('va en su propio renglón, dicho con todas las letras',
   /Sinregistrarelcobro\$15\.000/.test(j));
ok('pero SÍ suma en el total', /TOTALINGRESOS\$805\.000/.test(j),
   '790.000 + 15.000: el papel no puede perderla');
ok('y no toca el cajón, que solo cuenta billetes',
   /SALDOFINALENCAJA\$100\.000/.test(j));

/* ── el cajón no cuadró ───────────────────────────────────────────
   Esto no estaba en el dibujo. Sale solo cuando lo hay: en un día
   normal la hoja queda tal cual ella la pidió, y el día que falta
   plata es lo último que se lee antes de firmar. */
({ texto: t, junto: j } = await pintar({ ...REAL,
  cierre: { ...REAL.cierre, contado_cop: 235000, diferencia_cop: -5000 } }));
ok('un faltante sí aparece', /Descuadre al contar/.test(t));
ok('con el signo delante del peso, que en papel se lee bien',
   /−\$5\.000/.test(t) && !/\$-5\.000/.test(t));

/* ── un día todavía sin cerrar ────────────────────────────────────
   Sin cierre no hay retiro ni conteo: la hoja se imprime igual (se usa
   para mirar cómo va el día) y no puede inventarse un descuadre. */
({ texto: t, junto: j } = await pintar({ ...REAL,
  cerrado: false, cierre: {} }));
ok('sin cerrar el día la hoja sale igual', /TOTALINGRESOS\$790\.000/.test(j));
ok('sin retiro, el cajón guarda todo lo que entró',
   /SALDOFINALENCAJA\$240\.000/.test(j), '100.000 de base + 140.000');
ok('y no se inventa un descuadre', !/Descuadre/.test(t));

// ── el fajo sigue siendo dos hojas ───────────────────────────────
({ fajo } = await pintar(REAL));
ok('el cierre son dos hojas', fajo.n === 2,
   fajo.hojas.map(h => h.id).join(' '));
ok('la primera es la de ella', fajo.hojas[0].id === 'hoja-cierre');
ok('y la segunda el punteo', fajo.hojas[1].id === 'hoja-punteo');

/* ── LA FECHA ────────────────────────────────────────────────────
   Tania reportó que "no salía la fecha del día". Iba con los puntos
   guía de las demás filas, que empujan el valor al borde derecho, y en
   un rollo de 72mm esa fila de puntos se lee como un separador y no
   como un dato. Ahora va pegada a su rótulo, como en su dibujo. */
({ texto: t, junto: j } = await pintar(REAL));
ok('la fecha sale pegada a su rótulo, sin puntos guía',
   /Fecha: 01-09-2026/.test(t), 'como en el dibujo de ella');
ok('y no es una fila de puntos como los totales',
   !/Fecha:\s*\.{3}/.test(t));

// Un papel sin fecha no se puede archivar. Si el servidor no la mandara
// —no debería pasar nunca— se pone la del navegador antes que un hueco.
({ texto: t } = await pintar({ ...REAL, dia: null }));
ok('sin fecha del servidor no queda el hueco',
   /Fecha: \d{2}-\d{2}-\d{4}/.test(t), (t.match(/Fecha: [^\n]*/) || [])[0]);

/* ── EL TOTALIZADOR POR CONCEPTO ─────────────────────────────────
   Lo pidió Tania al revisar el cierre: poder decir «vendimos diez
   clases sueltas y tres mensualidades». Las sueltas entran por cuatro
   puertas y salen en cuatro renglones, así que esa pregunta no la
   contestaba ni el detalle de arriba ni el resumen por medio de pago. */
({ texto: t, junto: j } = await pintar(REAL));
ok('hay un bloque de totales del día', /Totales del día/.test(t));
ok('las clases sueltas se suman de las cuatro puertas',
   /Clasessueltas11·\$165\.000/.test(j),
   '6 página + 0 manuales + 1 efectivo + 4 bancos = 11');
ok('y las mensualidades de sus dos mitades',
   /Mensualidades5·\$625\.000/.test(j), '1 efectivo + 4 bancos = 5');
ok('el totalizador va antes del resumen por medio de pago',
   t.indexOf('Totales del día') < t.indexOf('Resumen de ingresos'));

/* ── LA PLATA FUTURA SE FUE DEL PAPEL (0071) ─────────────────────
   Aquí iba «El banco hoy»: reportó / del día / reservas futuras / sin
   identificar. Cuatro renglones que obligaban a cuadrar dos días a la
   vez —el de hoy y el del sábado que viene— y que eran justo lo que
   hacía que las cifras del cierre parecieran contradecirse.

   Damián: «quitarle lo que diga de la plata futura, porque eso es lo
   que está causando el conflicto». El anticipo se cuadra el día en que
   la persona entra, que es cuando se sabe si vino.

   Se comprueba con el cierre que MÁS lo tentaba: $715.000 reportados,
   siete reservas futuras y $250.000 sin dueño. Ninguno de esos cuatro
   números puede asomar. */
({ texto: t, junto: j } = await pintar({ ...REAL,
  cuadre: { ...REAL.cuadre, entro_al_banco: { ...REAL.cuadre.entro_al_banco,
    futuras_cupos: 7, futuras_depositos: 5, futuras_cop: 105000 } } }));
ok('el bloque del banco ya no se imprime', !/El banco hoy/.test(t));
ok('no se dice cuánto reportó el banco', !/Reportó/.test(t));
ok('las reservas futuras no salen en el papel', !/Reservas futuras/.test(t),
   'se cuadran el día que la persona entra, no hoy');
ok('ni lo que sigue sin identificar', !/Sin identificar/.test(t),
   'eso se persigue en el panel, no en el papel');
ok('ninguna de esas cifras se cuela', !/715\.000/.test(j) && !/105\.000/.test(j),
   'ni el total del banco ni el de las futuras');
ok('pero el resto de la hoja sale entero', /TOTAL INGRESOS/.test(t));

/* ── Y NO SE PUSO NADA EN SU SITIO ───────────────────────────────
   Se quitó A SECAS. Llegué a poner ahí un bloque «Para conciliar» con
   los cobros registrados sin escoger depósito, y Damián lo paró en el
   momento: «no vayas a cambiar la visual actual, es solo quitar esos
   campos». Esa lista ya está en la hoja 2, que es la que se usa con el
   extracto al lado; la hoja 1 es el papel que se archiva con el
   efectivo y tiene que quedar como la dibujó la dueña.

   Esta comprobación es contra mí mismo: se pinta un día CON cobros sin
   depósito —el caso que más tienta a nombrarlos aquí— y la hoja tiene
   que seguir terminando en el saldo. */
({ texto: t, junto: j } = await pintar({ ...REAL,
  conciliacion: { ...REAL.conciliacion,
    sin_enlazar: [{ hora: '08:00', concepto: 'clase_suelta', valor_cop: 15000 },
                  { hora: '09:40', concepto: 'clase_suelta', valor_cop: 15000 }],
    sin_enlazar_cop: 30000 } }));
ok('nada ocupa el sitio del bloque del banco',
   !/Para conciliar/.test(t) && !/Buscar en el extracto/i.test(t),
   'esa lista va en la hoja 2, no aquí');
ok('ni siquiera con cobros sin depósito el papel crece',
   !/30\.000/.test(j), 'la hoja 1 no nombra esa plata');
ok('la hoja termina en el saldo y las gracias',
   t.indexOf('SALDO FINAL EN CAJA') < t.indexOf('Gracias'));
ok('y no queda ningún bloque después del saldo',
   /SALDOFINALENCAJA\$100\.000Gracias/.test(j), j.slice(-60));

// Un cierre viejo sin `cuadre` no puede tumbar la hoja: ya no se lee
// ese dato para nada, pero la prueba se queda como red.
const sinCuadre = { ...REAL }; delete sinCuadre.cuadre;
({ texto: t } = await pintar(sinCuadre));
ok('sin `cuadre` la hoja sale igual', /TOTAL INGRESOS/.test(t));
ok('y sigue cerrando en el saldo', /SALDO FINAL EN CAJA/.test(t));

/* ── CAJA MENOR Y CAJA MAYOR (0069) ──────────────────────────────
   No todos los gastos salen del cajón del mostrador. Lo que pagó la
   empresa se reporta, pero NO puede bajar el saldo de este cajón: eso
   era un faltante inventado cada vez que Tania pagaba algo con la
   cuenta. */
({ texto: t, junto: j } = await pintar({ ...REAL,
  egreso_efectivo: 20000,
  egreso_caja_mayor_efectivo: 500000,
  egreso_transferencia: 300000 }));
ok('el gasto del cajón sí baja el saldo',
   /Gastos\/retiros\$160\.000/.test(j), '20.000 del cajón + 140.000 retirados');
ok('y el saldo queda descontándolo',
   /SALDOFINALENCAJA\$80\.000/.test(j), '100.000 + 140.000 − 160.000');
ok('lo pagado con caja mayor se reporta aparte',
   /Pagadoconcajamayor\$800\.000/.test(j), '500.000 en efectivo + 300.000 por transferencia');
ok('y se dice que no salió de este cajón', /no sale de este cajón/.test(t));
ok('va debajo del saldo, fuera de la resta',
   t.indexOf('SALDO FINAL EN CAJA') < t.indexOf('Pagado con caja mayor'));

// Sin gastos de la empresa el renglón no aparece: uno que casi siempre
// diría $0 enseña a no leer el papel.
({ texto: t } = await pintar(REAL));
ok('sin caja mayor, ese renglón no se imprime', !/Pagado con caja mayor/.test(t));

ok('sin errores de JS', errs.length === 0, errs.join(' | '));
console.log(fallos ? `\n${fallos} fallo(s)` : '\nTodo bien');
await b.close();
process.exit(fallos ? 1 : 0);
