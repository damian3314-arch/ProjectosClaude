/**
 * El puente entre las dos cifras que nunca se parecen.
 *
 * La tirilla del sábado 29 de agosto decía "Entradas del día $360.000"
 * y debajo "Bancolombia reportó hoy $195.000". Ninguna de las dos
 * estaba mal: de las 21 personas que entraron ese día, 16 habían pagado
 * días antes y su plata está en el extracto de OTRO día. Restarlas da
 * una diferencia que no significa nada, y la dueña lo resolvía a mano
 * en el margen del papel.
 *
 * Lo que se comprueba aquí es que el papel diga esa explicación solo,
 * con los números del 29 de agosto tal como los devuelve la 0064.
 *
 * Los dos casos que lo rompen:
 *   · tres amigas que reservan el sábado que viene con UN solo pago son
 *     3 cupos y 1 renglón del extracto. Si el papel dijera solo "3",
 *     habría que buscar tres renglones que no existen.
 *   · un cierre viejo servido por un servidor sin la 0064 no trae
 *     `cuadre`. El papel tiene que salir igual que siempre, no en
 *     blanco.
 *
 *   node tirilla-cuadre-puerta-banco.test.mjs <ruta a admin.html con __e2e>
 */
import { chromium } from 'playwright-core';
const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
const p = await b.newPage({ viewport: { width: 430, height: 900 } });
const errs = []; p.on('pageerror', e => errs.push(String(e)));
await p.goto('file://' + process.argv[2]);

// El 29 de agosto de verdad, verificado contra producción: 21 entraron,
// 16 traían la plata de días antes, y al banco entraron $105.000 que
// son cinco clases de hoy más dos clases sueltas cobradas en la puerta.
const DIA = {
  dia: '2026-08-29',
  banco: { recibido_cop: 105000 },
  entradas: { personas_n: 21 },
  cierre: {}, resumen_conceptos: [], por_verificar: {},
  cuadre: {
    quien_entro: { personas: 21, pagaron_antes: 16, pagaron_hoy: 5,
                   pagaron_hoy_cop: 75000, sin_deposito: 0 },
    entro_al_banco: {
      clases_hoy_n: 5, clases_hoy_cop: 75000,
      futuras_cupos: 0, futuras_depositos: 0, futuras_cop: 0,
      otros: [{ concepto: 'clase_suelta', n: 2, cop: 30000 }],
      otros_cop: 30000,
      identificado_cop: 105000,
      reporto_banco_cop: 105000,
      sin_identificar_cop: 0 },
  },
  conciliacion: {
    banco: [
      { dia: '2026-08-29', dias_antes: 0, hora: '10:12', valor_cop: 75000,
        remitente: 'MARIA CAMILA RUIZ', referencia: 'M22223333',
        para: ['Maria Ruiz', 'Sara Ruiz'], conceptos: [], cobros: 0,
        es_parte: false },
      { dia: '2026-08-29', dias_antes: 0, hora: '18:40', valor_cop: 30000,
        remitente: 'JUAN OSPINA', referencia: null,
        para: [], conceptos: ['clase_suelta'], cobros: 2, es_parte: false },
    ],
    banco_cop: 105000, banco_hoy_cop: 105000,
    efectivo: [], efectivo_cop: 0,
    sin_enlazar: [], sin_enlazar_cop: 0, sin_pago: [],
  },
};

// Copia con los cambios que se le pidan, sin tocar el día real.
const como = cambios => {
  const c = JSON.parse(JSON.stringify(DIA));
  cambios(c);
  return c;
};

let fallos = 0;
const ok = (n, c, extra = '') => { if (!c) fallos++;
  console.log(`${c ? '✓' : '✗'} ${n}${extra ? '  → ' + extra : ''}`); };

// El papel se lee sin espacios: en pantalla la tirilla está oculta y
// los renglones vienen pegados, igual que en la prueba de al lado.
const pintar = async d => {
  const t = await p.evaluate(x => window.__e2e.tirillaPagos(x), d);
  return { ...t, junto: t.texto.replace(/\s/g, '') };
};

const t = await pintar(DIA);

// ── quién cruzó la puerta ────────────────────────────────────────
ok('el papel empieza explicando quién entró', /QUIÉN ENTRÓ HOY/.test(t.texto));
ok('y va antes de los renglones que hay que buscar',
   t.texto.indexOf('QUIÉN ENTRÓ HOY') < t.texto.indexOf('BUSCAR EN EL EXTRACTO'));
ok('entraron 21 personas', /Entraronaclase21personas/.test(t.junto));
ok('16 traían la plata de días antes',
   /yahabíanpagadoantes16/.test(t.junto));
ok('y los 5 que pagaron hoy salen con su plata',
   /pagaronhoy5·\$75\.000/.test(t.junto));
ok('sin depósito no se imprime cuando es cero',
   !/sindepósito/i.test(t.junto));

// ── qué se registró hoy ──────────────────────────────────────────
ok('la segunda mitad dice qué se registró', /QUÉ SE REGISTRÓ HOY/.test(t.texto));
ok('las clases de hoy salen con su cuenta y su plata',
   /Clasesdehoy5·\$75\.000/.test(t.junto));
ok('los conceptos de `otros` salen con el nombre legible',
   /Clasesueltax2\$30\.000/.test(t.junto));
ok('y nunca con el código de la base', !/clase_suelta/.test(t.texto));
ok('el total es lo identificado, que es lo que suman los renglones',
   /=Depósitosregistradoshoy\$105\.000/.test(t.junto));

// ── lo que se decidió NO imprimir ────────────────────────────────
// `reporto_banco_cop` no es lo que reportó Bancolombia sino lo que el
// sistema ingirió, así que la resta da cero casi siempre y un renglón
// que siempre dice $0 enseña a ignorar el papel.
ok('no se imprime lo que quedó sin identificar',
   !/sin identificar/i.test(t.texto));

// ── clases futuras: cupos Y depósitos ────────────────────────────
const f = await pintar(como(c => {
  c.cuadre.entro_al_banco.futuras_cupos = 3;
  c.cuadre.entro_al_banco.futuras_depositos = 1;
  c.cuadre.entro_al_banco.futuras_cop = 45000;
  c.cuadre.entro_al_banco.identificado_cop = 150000;
}));
ok('tres amigas con un solo pago son 3 cupos y 1 depósito',
   /Clasesfuturas3cupos·1depósito·\$45\.000/.test(f.junto),
   'sin el depósito habría que buscar tres renglones que no existen');
ok('y el total sube con ellas', /=Depósitosregistradoshoy\$150\.000/.test(f.junto));

const uno = await pintar(como(c => {
  c.cuadre.entro_al_banco.futuras_cupos = 1;
  c.cuadre.entro_al_banco.futuras_depositos = 1;
  c.cuadre.entro_al_banco.futuras_cop = 15000;
}));
ok('un solo cupo se dice en singular',
   /Clasesfuturas1cupo·1depósito·\$15\.000/.test(uno.junto));

ok('sin nadie pagando por adelantado la línea sale igual, con raya',
   /Clasesfuturas—/.test(t.junto),
   'que ese día nadie pagara por adelantado también es información');

// ── el singular del resto ────────────────────────────────────────
const sola = await pintar(como(c => {
  c.cuadre.quien_entro = { personas: 1, pagaron_antes: 0, pagaron_hoy: 1,
                           pagaron_hoy_cop: 15000, sin_deposito: 0 };
}));
ok('una sola persona no entra "1 personas"',
   /Entraronaclase1persona[^s]/.test(sola.junto));

// ── quien entró sin haber pagado nunca ───────────────────────────
const sinDep = await pintar(como(c => { c.cuadre.quien_entro.sin_deposito = 2; }));
ok('cuando alguien entró sin depósito, ahí sí se nombra',
   /sindepósito2/.test(sinDep.junto));

// ── un día en ceros ──────────────────────────────────────────────
// Sábado sin clase: la 0064 devuelve la misma estructura con ceros y
// `otros` vacío. Tiene que salir un papel, no una excepción.
const cero = await pintar(como(c => {
  c.cuadre = {
    quien_entro: { personas: 0, pagaron_antes: 0, pagaron_hoy: 0,
                   pagaron_hoy_cop: 0, sin_deposito: 0 },
    entro_al_banco: {
      clases_hoy_n: 0, clases_hoy_cop: 0,
      futuras_cupos: 0, futuras_depositos: 0, futuras_cop: 0,
      otros: [], otros_cop: 0, identificado_cop: 0,
      reporto_banco_cop: 0, sin_identificar_cop: 0 },
  };
}));
ok('un día en ceros sigue imprimiendo el bloque',
   /QUIÉN ENTRÓ HOY/.test(cero.texto) && /QUÉ SE REGISTRÓ HOY/.test(cero.texto));
ok('con cero personas y las líneas en raya',
   /Entraronaclase0personas/.test(cero.junto) && /Clasesdehoy—/.test(cero.junto));
ok('y el total en cero', /=Depósitosregistradoshoy\$0/.test(cero.junto));

// ── un cierre viejo, sin la 0064 detrás ──────────────────────────
const viejo = await pintar(como(c => { delete c.cuadre; }));
ok('sin `cuadre` no se pinta el bloque', !/QUIÉN ENTRÓ HOY/.test(viejo.texto));
ok('pero el resto del papel sale igual que siempre',
   /BUSCAR EN EL EXTRACTO/.test(viejo.texto) && /\$75\.000/.test(viejo.texto));

// ── el rótulo que mentía ─────────────────────────────────────────
// `banco.recibido_cop` es la suma de los depósitos que el sistema
// alcanzó a registrar, no lo que dice el extracto de Bancolombia.
ok('el papel ya no dice que el banco recibió',
   !/El banco recibió hoy/.test(t.texto));
ok('lo llama por lo que es', /Totalregistradohoy\$105\.000/.test(t.junto));
// Dos rótulos iguales con cifras distintas en el mismo papel es lo que
// hace desconfiar de él: el total de arriba es lo identificado.
ok('y no repite el rótulo del total de arriba',
   (t.texto.match(/Depósitos registrados hoy/g) || []).length === 1);

ok('sin errores de JS', errs.length === 0, errs.join(' | '));
console.log(fallos ? `\n${fallos} fallo(s)` : '\nTodo bien');
await b.close();
process.exit(fallos ? 1 : 0);
