/**
 * La segunda tirilla: con qué movimiento del banco entró cada quien.
 *
 * Se imprime al lado del extracto de Bancolombia, así que lo que no
 * puede fallar es que el papel sume lo MISMO que el banco.
 *
 * El caso que lo rompe es real, del 28 de agosto: Isabel Flórez y Lizet
 * Gutiérrez entraron con un solo depósito de $30.000. Si el papel las
 * listara como dos líneas de $30.000, sumaría $60.000 contra un extracto
 * que dice $30.000 y el cuadre no daría nunca.
 *
 * Se comprueba sobre el HTML que de verdad va al rollo, no sobre los
 * datos: el error de duplicar aparecería justo al pintar.
 *
 *   node tirilla-cuando-pagaron.test.mjs <ruta a admin.html con __e2e>
 */
import { chromium } from 'playwright-core';
const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
const p = await b.newPage({ viewport: { width: 430, height: 900 } });
const errs = []; p.on('pageerror', e => errs.push(String(e)));
await p.goto('file://' + process.argv[2]);

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
        remitente: 'CAMILA LOPEZ', referencia: 'M11112222', para: ['Camila Lopez'] },
      { dia: '2026-08-28', dias_antes: 0, hora: '11:29', valor_cop: 30000,
        remitente: 'ISABEL FLOREZ MARTINEZ', referencia: 'M07471046',
        para: ['Isabel Florez', 'Lizet Gutierrez'] },
      { dia: '2026-08-28', dias_antes: 0, hora: '17:58', valor_cop: 15000,
        remitente: 'JUAN GABRIEL OSPINA BADILLO', referencia: null, para: [] },
    ],
    banco_cop: 60000,
    efectivo: [{ hora: '18:25', valor_cop: 15000 }],
    efectivo_cop: 15000,
    sin_pago: [{ nombre: 'Julieth Herrera', motivo: 'reprogramada, pago otro dia' }],
  },
};

let fallos = 0;
const ok = (n, c, extra='') => { if (!c) fallos++;
  console.log(`${c ? '✓' : '✗'} ${n}${extra ? '  → ' + extra : ''}`); };

const t = await p.evaluate(d => window.__e2e.tirillaPagos(d), DIA);

// ── lo que no puede fallar ───────────────────────────────────────
ok('el total a buscar es el del banco, no el de las personas',
   /60\.000/.test(t.texto) && !/\$60\.000[\s\S]*\$60\.000/.test(t.texto.replace(/Buscar en el banco[\s\S]*/, '')),
   'suma 60.000');
ok('el depósito compartido aparece UNA sola vez',
   (t.texto.match(/30\.000/g) || []).length === 1,
   `${(t.texto.match(/30\.000/g) || []).length} veces`);
ok('y nombra a las dos personas debajo',
   /Isabel Florez, Lizet Gutierrez/.test(t.texto));

// ── agrupado por día, que es como está el extracto ───────────────
ok('el pago de hace dos días se agrupa aparte', /HACE 2 DÍAS/.test(t.texto));
ok('y los de hoy dicen HOY', /HOY/.test(t.texto));
ok('el de hace dos días va primero, como en el extracto',
   t.texto.indexOf('HACE 2 DÍAS') < t.texto.indexOf('11:29'));

// ── el efectivo no se busca en el banco ──────────────────────────
ok('el efectivo va en su propia sección', /no va al banco/.test(t.texto));
ok('y no se suma al total del banco', !/=\s*Buscar en el banco[^$]*75\.000/.test(t.texto));

// ── lo que hay que averiguar ─────────────────────────────────────
ok('quien entró sin depósito sale en recuadro', t.recuadros >= 1, String(t.recuadros));
ok('con su nombre y el motivo',
   /Julieth Herrera/.test(t.texto) && /reprogramada/.test(t.texto));

// ── el cobro en la puerta no finge tener dueño ───────────────────
ok('el cobrado en la puerta lo dice', /cobrado en la puerta/.test(t.texto));

// ── que se entienda contra qué se compara ────────────────────────
ok('avisa que el banco reportó más, por las mensualidades',
   /580\.000/.test(t.texto) && /mensualidades/.test(t.texto));

// ── y que sea una tirilla, no la del cierre ──────────────────────
ok('se titula CUÁNDO PAGARON', /CUÁNDO PAGARON/.test(t.texto));
ok('no trae el arqueo del cajón', !/EL CAJÓN/.test(t.texto));
ok('no trae el veredicto de si cuadró', !/SÍ CUADRA|NO CUADRA/.test(t.texto));

ok('sin errores de JS', errs.length === 0, errs.join(' | '));
console.log(fallos ? `\n${fallos} fallo(s)` : '\nTodo bien');
await b.close();
process.exit(fallos ? 1 : 0);
