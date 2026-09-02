/**
 * LA SEGUNDA HOJA — "el punteo, pago por pago".
 *
 * La hoja que se pone al lado del extracto de Bancolombia para ir
 * tachando renglones. Lo que no puede fallar es que el papel sume lo
 * MISMO que el banco.
 *
 * El caso que lo rompe es real, del 28 de agosto: Isabel Flórez y Lizet
 * Gutiérrez entraron con un solo depósito de $30.000. Si el papel las
 * listara como dos líneas de $30.000, sumaría $60.000 contra un extracto
 * que dice $30.000 y el cuadre no daría nunca.
 *
 * Encima de eso, lo que pidió el dueño y antes había que deducir: que la
 * hoja diga DE ENTRADA cuánto de esa plata se va a encontrar en el
 * extracto y cuánto no se va a encontrar nunca porque está en el cajón.
 * Confundirlos es una noche buscando en el banco un efectivo que jamás
 * estuvo ahí — y ese bloque va arriba del todo, antes del primer
 * renglón, porque es lo que hay que saber antes de empezar a buscar.
 *
 * Las dos hojas salen de un solo clic y se comprueban sobre el texto de
 * ESTA hoja, no sobre el del fajo entero: casi todo lo de aquí es "esto
 * sale en la 2 y no en la 1", y sobre las dos pegadas eso no se puede
 * afirmar. De ahí que se lea `hojas.find(...)` y no `texto`.
 *
 * Fueron tres hojas. La de en medio ("qué era la plata del día") se
 * eliminó, y la primera es ahora el papel que dibujó la dueña —más
 * corto, sin veredictos—; lo comprueba tirilla-de-la-duena. Esta hoja
 * sobrevivió a esa poda porque es la única con la que se puede
 * conciliar contra el extracto del banco.
 *
 * El gancho window.__e2e lo pone instrumentar.mjs sobre una copia
 * temporal de docs/admin.html. Sin argumentos:
 *
 *   node tirilla-cuando-pagaron.test.mjs
 *
 * Admite una ruta suelta para apuntar a otra copia del panel.
 */
import { chromium } from 'playwright-core';
import { rutaDelPanel } from './instrumentar.mjs';
const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
const p = await b.newPage({ viewport: { width: 430, height: 900 } });
const errs = []; p.on('pageerror', e => errs.push(String(e)));
await p.goto('file://' + rutaDelPanel());

// Lo que devuelve caja_del_dia el 28 de agosto, con sus casos reales:
// un depósito compartido, uno de hace dos días, efectivo de puerta y
// alguien que entró sin depósito.
const DIA = {
  dia: '2026-08-28',
  banco: { recibido_cop: 580000 },
  entradas: { personas_n: 5 },
  cierre: {}, resumen_conceptos: [], por_verificar: {},
  conciliacion: {
    banco: [
      { dia: '2026-08-26', dias_antes: 2, hora: '09:10', valor_cop: 15000,
        remitente: 'CAMILA LOPEZ', referencia: 'M11112222',
        para: ['Camila Lopez'], conceptos: [], cobros: 0, es_parte: false },
      // El caso difícil: una mensualidad que llegó en dos transferencias.
      { dia: '2026-08-28', dias_antes: 0, hora: '09:39', valor_cop: 85000,
        remitente: 'GENNY PAOLA GONZALEZ VEGA', referencia: 'M11110000',
        para: [], conceptos: ['mensualidad'], cobros: 0, es_parte: false },
      { dia: '2026-08-28', dias_antes: 0, hora: '11:29', valor_cop: 30000,
        remitente: 'ISABEL FLOREZ MARTINEZ', referencia: 'M07471046',
        para: ['Isabel Florez', 'Lizet Gutierrez'], conceptos: [], cobros: 0,
        es_parte: false },
      { dia: '2026-08-28', dias_antes: 0, hora: '17:45', valor_cop: 40000,
        remitente: 'GENNY PAOLA GONZALEZ VEGA', referencia: 'M11110001',
        para: [], conceptos: ['mensualidad'], cobros: 0, es_parte: true },
      { dia: '2026-08-28', dias_antes: 0, hora: '17:58', valor_cop: 15000,
        remitente: 'JUAN GABRIEL OSPINA BADILLO', referencia: null,
        para: [], conceptos: ['clase_suelta'], cobros: 1, es_parte: false },
    ],
    banco_cop: 185000,
    banco_hoy_cop: 170000,
    efectivo: [{ hora: '18:25', concepto: 'clase_suelta', valor_cop: 15000 },
               { hora: '18:52', concepto: 'mensualidad', valor_cop: 125000 }],
    efectivo_cop: 140000,
    sin_enlazar: [{ hora: '19:10', concepto: 'camiseta', valor_cop: 50000 }],
    sin_enlazar_cop: 50000,
    sin_pago: [{ nombre: 'Julieth Herrera', motivo: 'reprogramada, pago otro dia' }],
  },
};

let fallos = 0;
const ok = (n, c, extra='') => { if (!c) fallos++;
  console.log(`${c ? '✓' : '✗'} ${n}${extra ? '  → ' + extra : ''}`); };

const fajo = await p.evaluate(d => window.__e2e.tirillas(d), DIA);
const hoja = fajo.hojas.find(h => h.id === 'hoja-punteo') || { texto: '', recuadros: 0 };
const t = hoja.texto;
// La 1, para comprobar que lo de allí no se repite aquí.
const cierre = (fajo.hojas.find(h => h.id === 'hoja-cierre') || { texto: '' }).texto;

// ── sale, y sale la segunda ──────────────────────────────────────
ok('el punteo es una de las dos hojas del fajo',
   fajo.n === 2 && fajo.hojas.length === 2,
   fajo.hojas.map(h => h.id).join(' '));
ok('y es la última', fajo.hojas[1].id === 'hoja-punteo');
ok('la hoja del medio ya no se imprime',
   !fajo.hojas.some(h => h.id === 'hoja-plata'));
// Ya no se numera "HOJA 2 DE 2": la hoja 1 es el dibujo de la dueña y
// no lleva número, así que anunciar una numeración que la otra no
// tiene hace buscar un número que no existe. Lo que sí hace falta es
// que esta hoja diga QUÉ es: sale de la misma impresora, detrás del
// cierre, y sin rótulo se confunde con él.
ok('dice qué papel es, arriba', /EL PUNTEO, PAGO POR PAGO/.test(t));
ok('y lo repite en el pie, que es lo que asoma en la carpeta',
   (t.match(/EL PUNTEO, PAGO POR PAGO/g) || []).length >= 2);
ok('sin numerarse, porque la hoja 1 tampoco se numera',
   !/HOJA \d DE \d/i.test(t));

// ── efectivo contra transferencia, antes de buscar nada ──────────
// Lo que pidió el dueño: que el papel PRECISE qué es efectivo y qué
// transferencia. Va antes del primer renglón porque es lo que hay que
// saber antes de sentarse con el extracto.
ok('lo primero de la hoja es efectivo o transferencia',
   /EFECTIVO O TRANSFERENCIA/.test(t));
ok('y va antes de la lista de movimientos',
   t.indexOf('EFECTIVO O TRANSFERENCIA') < t.indexOf('BUSCAR EN EL EXTRACTO'));
ok('lo de transferencia incluye lo que aún no tiene renglón',
   /235\.000/.test(t), '185.000 del extracto + 50.000 sin depósito escogido');
ok('el efectivo se dice aparte', /140\.000/.test(t));
// LA DISTINCIÓN LA CARGAN LOS TÍTULOS, NO UNA GLOSA. Debajo de cada
// una de estas dos cifras había una frase ("se busca en el extracto",
// "está en el cajón") que repetía el encabezado de su sección. Se
// quitaron por petición del dueño —la hoja tenía demasiada letra— y lo
// que no puede perderse es que el papel siga diciendo cuál de las dos
// se busca en el banco y cuál no.
ok('los títulos siguen diciendo dónde se busca cada una',
   /POR TRANSFERENCIA · BUSCAR EN EL EXTRACTO/.test(t) &&
   /EN EFECTIVO · NO ESTÁ EN EL EXTRACTO/.test(t));
ok('y ya no repiten esa explicación debajo de la cifra',
   !/se busca en el extracto, renglón por renglón/.test(t) &&
   !/está en el cajón/.test(t));
ok('los dos no se suman en una sola cifra',
   !/375\.000/.test(t), '235.000 + 140.000 no debe aparecer como total');

// ── lo que no puede fallar ───────────────────────────────────────
ok('el total a buscar es el del banco', /185\.000/.test(t));
ok('el depósito compartido aparece UNA sola vez',
   (t.match(/30\.000/g) || []).length === 1,
   `${(t.match(/30\.000/g) || []).length} veces`);
ok('y nombra a las dos personas debajo',
   /Isabel Florez, Lizet Gutierrez/.test(t));

// ── lo que se registra a mano en la Caja ─────────────────────────
ok('las mensualidades salen', /Mensualidad/i.test(t));
ok('el pago en dos transferencias sale como dos renglones',
   /85\.000/.test(t) && /40\.000/.test(t));
ok('y el segundo se marca como parte del mismo pago',
   /segunda parte del mismo pago/.test(t));
ok('la camiseta sin depósito escogido se nombra aparte',
   /SIN DEPÓSITO ESCOGIDO/.test(t) && /Camiseta/i.test(t));
ok('y dice que hay que buscarla por el valor',
   /[Bb]uscarla en el extracto por el valor/.test(t));
ok('el efectivo dice de qué fue cada uno',
   /18:25 · Clase suelta/.test(t) && /18:52 · Mensualidad/.test(t));

// ── agrupado por día, que es como está el extracto ───────────────
ok('el pago de hace dos días se agrupa aparte', /HACE 2 DÍAS/.test(t));
ok('y los de hoy dicen HOY', /HOY · 28 de ago/.test(t));
ok('el de hace dos días va primero, como en el extracto',
   t.indexOf('HACE 2 DÍAS') < t.indexOf('11:29'));

// ── el efectivo no se busca en el banco ──────────────────────────
ok('el efectivo va en su propia sección',
   /EN EFECTIVO · NO ESTÁ EN EL EXTRACTO/.test(t));
ok('y no se suma al total del banco',
   !/=Buscarenelbanco\$?325\.000/.test(t.replace(/\s/g, '')));

// ── el cuadre contra el extracto de hoy ──────────────────────────
ok('dice cuánto se registró hoy', /580\.000/.test(t));
ok('y cuánto de eso queda identificado', /170\.000/.test(t));
ok('y nombra la diferencia como lo que falta por reclamar',
   /410\.000/.test(t) && /sin dueño/i.test(t),
   'el hueco es 580.000 − 170.000');
ok('ya no dice que solo trae clase suelta',
   !/solo está lo de clase suelta/.test(t));

// ── lo que hay que averiguar ─────────────────────────────────────
ok('quien entró sin depósito sale en recuadro', hoja.recuadros >= 1,
   String(hoja.recuadros));
ok('con su nombre y el motivo',
   /Julieth Herrera/.test(t) && /reprogramada/.test(t));

// ── el cobro en la puerta no finge tener dueño ───────────────────
// Es la diferencia entre "esta plata tiene dueño en el sistema" y "se
// cobró en la puerta y no hay a quién buscar".
ok('el cobrado en la puerta lo dice', /en la puerta/.test(t));
ok('y lo distingue de la mensualidad cobrada en recepción',
   /en recepción/.test(t));

// ── y que siga siendo el punteo, no el cierre ────────────────────
// Ahora las tres salen del mismo clic, así que lo que antes garantizaba
// ser otro papel hay que comprobarlo dentro del mismo fajo: si el
// arqueo se colara aquí, habría dos cajones distintos en una impresión.
ok('no trae el arqueo del cajón', !/CAJA 1/.test(t));
ok('y la hoja 1 tampoco: la dueña quitó ese arqueo',
   !/CAJA 1/.test(cierre));
ok('no trae el veredicto de si cuadró el cajón',
   !/SÍ CUADRA|NO CUADRA/.test(t));
ok('ni en la hoja 1, que ahora cierra en su saldo',
   !/SÍ CUADRA/.test(cierre) && /SALDO FINAL EN CAJA/.test(cierre));

// ── un cierre viejo no se lleva por delante el punteo ────────────
// Este fixture no trae `cuadre` (la 0064), así que la hoja 1 sale sin
// su bloque de desglose. Da igual: el punteo no depende de ese dato
// —sale de `conciliacion`— y es la hoja que de verdad se tacha contra
// el extracto. Tiene que salir entera aunque a la otra le falte algo.
ok('sin `cuadre`, el punteo sale completo igual',
   /BUSCAR EN EL EXTRACTO/.test(t) && /185\.000/.test(t));
ok('y la hoja 1 sale igual, que no depende de ese dato',
   /TOTAL INGRESOS/.test(cierre) && !/DE ESO/.test(cierre));

ok('sin errores de JS', errs.length === 0, errs.join(' | '));
console.log(fallos ? `\n${fallos} fallo(s)` : '\nTodo bien');
await b.close();
process.exit(fallos ? 1 : 0);
