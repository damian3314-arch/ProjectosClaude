/**
 * HOJA 1, BLOQUE "DE ESO" — de lo que entró hoy, qué era cada peso.
 *
 * Esto fue una hoja entera ("qué era la plata del día", hoja 2 de 3) y
 * la dueña la eliminó en cuanto la vio impresa: una página para un
 * desglose de seis renglones, que además obligaba a pasar el papel
 * adelante y atrás porque el total que desglosaba estaba en la hoja
 * anterior. Ahora va pegado a ese total, dentro de la hoja 1, y esta
 * prueba se mudó con él.
 *
 * Lo que el bloque tiene que dejar dicho, en el orden que pidió el
 * dueño: entró tanto; de eso, tanto son clases de hoy, tanto clases
 * futuras, tanto mensualidades y demás, y tanto quedó sin identificar.
 *
 * Los tres casos que lo rompen:
 *   · tres amigas que reservan el sábado que viene con UN solo pago son
 *     3 cupos y 1 renglón del extracto. Si el papel dijera solo "3",
 *     habría que buscar tres renglones que no existen.
 *   · un cierre viejo servido por un servidor sin la 0064 no trae
 *     `cuadre`. La hoja 1 tiene que salir completa igual —el arqueo del
 *     cajón no depende de esto— y decir que no hay desglose, en vez de
 *     imprimir un bloque de ceros que parecerían reales.
 *   · `sin_identificar_cop` SE IMPRIME. Antes se ocultaba a propósito
 *     "porque casi siempre da $0", y con datos reales resultó falso: el
 *     1 de septiembre eran $250.000. Es la cifra que dice cuánto trabajo
 *     queda.
 *
 * El gancho window.__e2e lo pone instrumentar.mjs sobre una copia
 * temporal de docs/admin.html. Sin argumentos:
 *
 *   node tirilla-cuadre-puerta-banco.test.mjs
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

const pintar = async (d) => {
  const fajo = await p.evaluate(x => window.__e2e.tirillas(x), d);
  const h = fajo.hojas.find(x => x.id === 'hoja-cierre') || { texto: '' };
  return { fajo, texto: h.texto };
};

/* ── el día real: 1 de septiembre de 2026 ─────────────────────────
   Verificado contra producción. Entraron $715.000 al banco y solo
   $465.000 se supieron nombrar: los $250.000 que faltan son dos
   mensualidades que llegaron y nadie cobró en la Caja. Ese hueco es
   justo lo que el bloque existe para enseñar. */
const REAL = {
  dia: '2026-09-01',
  banco: { recibido_cop: 715000 },
  entradas: { personas_n: 12 },
  cierre: {}, resumen_conceptos: [], por_verificar: {},
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

let { fajo, texto: t } = await pintar(REAL);

// ── el fajo son DOS hojas, no tres ───────────────────────────────
ok('el cierre son dos hojas', fajo.n === 2 && fajo.hojas.length === 2,
   fajo.hojas.map(h => h.id).join(' '));
ok('y la del medio ya no existe',
   !fajo.hojas.some(h => h.id === 'hoja-plata'));
ok('la hoja 1 lo dice de sí misma', /HOJA 1 DE 2/.test(t));

// ── el bloque vive pegado al total que desglosa ──────────────────
ok('el desglose va bajo los depósitos registrados',
   /DEPÓSITOS REGISTRADOS HOY/.test(t) && /DE ESO/.test(t));
ok('y después del total, no antes',
   t.indexOf('Total registrado') < t.indexOf('DE ESO'));
// Ojo con el .replace: quita TODOS los espacios, también el de "Total
// registrado", así que el patrón va sin él.
ok('el total es lo que entró hoy',
   /Totalregistrado\$715\.000/.test(t.replace(/\s/g, '')),
   'el mismo número que la hoja 2 compara contra el extracto');

// ── los cuatro renglones, en el orden que pidió el dueño ─────────
const orden = ['DE ESO', 'Clases de hoy', 'Clases futuras',
               'Mensualidad', 'Sin identificar'];
ok('los renglones salen en su orden',
   orden.every((x, i) => i === 0 ||
     t.indexOf(x) > t.indexOf(orden[i - 1])),
   orden.join(' → '));

ok('lo que se disfruta hoy, con su gente y su plata',
   /Clases de hoy5 · \$75\.000/.test(t.replace(/\s+/g, '')) ||
   /Clases de hoy\s*5 · \$75\.000/.test(t));
ok('sin clases futuras se imprime la raya, no se esconde el renglón',
   /Clases futuras\s*—/.test(t), 'que nadie pagara por adelantado también es un dato');
ok('lo que no es una clase va con su cantidad',
   /Mensualidad x3/.test(t) && /375\.000/.test(t));
ok('y el concepto suelto sin "x1" delante',
   /Clase suelta/.test(t) && !/Clase suelta x1/.test(t));

// ── lo que faltaba y antes se escondía ───────────────────────────
ok('SIN IDENTIFICAR SE IMPRIME', /Sin identificar/.test(t));
ok('con la cifra real, no un cero de adorno', /250\.000/.test(t),
   '715.000 registrados − 465.000 nombrados');

// ── lo que el bloque no puede romper ─────────────────────────────
ok('el arqueo del cajón sigue intacto',
   /CAJA 1/.test(t) && /Se abrió con/.test(t) && /Se contó/.test(t));
ok('y el desglose no se cuela dentro del arqueo',
   t.indexOf('CAJA 1') < t.indexOf('DE ESO'));
ok('la hoja 1 manda a la 2 para el pago por pago', /en la hoja 2/.test(t));
ok('y ya no habla de una hoja 3', !/hoja 3/i.test(t));

/* ── tres amigas, un solo depósito ────────────────────────────────
   3 cupos del sábado que viene y UN renglón del extracto. Los dos
   números o no se puede puntear. */
({ texto: t } = await pintar({ ...REAL,
  cuadre: { ...REAL.cuadre,
    entro_al_banco: { ...REAL.cuadre.entro_al_banco,
      futuras_cupos: 3, futuras_depositos: 1, futuras_cop: 45000 } } }));
ok('lo pagado por adelantado dice cupos Y depósitos',
   /3 cupos · 1 depósito · \$45\.000/.test(t.replace(/\s+/g, ' ')),
   'tres sillas, un renglón que buscar');

/* ── un día sin hueco ─────────────────────────────────────────────
   Cuando todo se supo nombrar, el papel lo dice en positivo en vez de
   imprimir "Sin identificar $0", que se lee como un renglón roto. */
({ texto: t } = await pintar({ ...REAL,
  cuadre: { ...REAL.cuadre,
    entro_al_banco: { ...REAL.cuadre.entro_al_banco,
      identificado_cop: 715000, sin_identificar_cop: 0 } } }));
ok('sin hueco lo dice en positivo y no imprime un cero',
   /Sin identificar: nada ✓/.test(t) && !/Sin identificar\s*\$0/.test(t));

/* ── un cierre viejo, sin `cuadre` ────────────────────────────────
   El arqueo del cajón no depende de la 0064: la hoja tiene que salir
   entera y decir por qué le falta el desglose. */
const viejo = { ...REAL };
delete viejo.cuadre;
({ fajo, texto: t } = await pintar(viejo));
ok('sin `cuadre` la hoja 1 se imprime igual', fajo.n === 2);
ok('pero no finge un desglose', !/DE ESO/.test(t));
ok('dice por qué no lo trae', /no hay desglose/.test(t));
ok('y el arqueo y el total siguen ahí',
   /CAJA 1/.test(t) && /Total registrado/.test(t));

/* ── un desglose que se pasa del total ────────────────────────────
   No debería ocurrir, pero un "−$5.000 sin identificar" en el papel
   solo confunde a quien cuadra: se enseña como nada. */
({ texto: t } = await pintar({ ...REAL,
  cuadre: { ...REAL.cuadre,
    entro_al_banco: { ...REAL.cuadre.entro_al_banco,
      sin_identificar_cop: -5000 } } }));
ok('un sin identificar negativo no sale en el papel',
   !/-\$?5\.000/.test(t) && !/−\$?5\.000/.test(t));

ok('sin errores de JS', errs.length === 0, errs.join(' | '));
console.log(fallos ? `\n${fallos} fallo(s)` : '\nTodo bien');
await b.close();
process.exit(fallos ? 1 : 0);
