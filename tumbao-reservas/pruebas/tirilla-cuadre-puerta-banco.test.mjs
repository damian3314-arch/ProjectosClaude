/**
 * HOJA 2 DE 3 — "qué era la plata del día".
 *
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
 * Y lo que pidió el dueño encima: que la hoja diga CON PALABRAS qué de
 * lo que se registró hoy se disfruta hoy y qué son reservas futuras,
 * sin que haya que deducirlo de que una línea diga "Clases de hoy" y
 * la de al lado "Clases futuras".
 *
 * Los tres casos que lo rompen:
 *   · tres amigas que reservan el sábado que viene con UN solo pago son
 *     3 cupos y 1 renglón del extracto. Si el papel dijera solo "3",
 *     habría que buscar tres renglones que no existen.
 *   · un cierre viejo servido por un servidor sin la 0064 no trae
 *     `cuadre`. La hoja tiene que salir igual —en blanco corre la
 *     numeración y quien recoja el fajo contaría dos donde van tres— y
 *     decir por qué no tiene nada dentro.
 *   · la hoja 1 y la hoja 2 dicen las dos "depósitos registrados hoy".
 *     Es a propósito (una es el total y la otra su desglose) pero el
 *     papel tiene que decirlo, o dos cifras con el mismo nombre en el
 *     mismo fajo hacen desconfiar de las tres hojas.
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

/* Un clic pinta las TRES hojas dentro de #tirilla. Esta suite mira la
 * segunda; `fajo` queda a mano para lo poco que se comprueba sobre el
 * papel entero (el orden entre hojas, un rótulo que no puede repetirse).
 *
 * El papel se lee sin espacios: en pantalla la tirilla está oculta y
 * los renglones vienen pegados. */
const pintar = async d => {
  const r = await p.evaluate(x => window.__e2e.tirillas(x), d);
  const h2 = r.hojas[1];
  return { ...h2, junto: h2.texto.replace(/\s/g, ''),
           fajo: r.texto, hojas: r.hojas };
};

const t = await pintar(DIA);

// ── es la hoja 2 y se identifica sola ────────────────────────────
// Se archivan sueltas: sin esto, tres hojas de dos días distintos
// encima del mostrador no se distinguen.
ok('la segunda hoja es la de la plata del día', t.id === 'hoja-plata', t.id);
ok('se identifica arriba', /QUÉ ERA LA PLATA DEL DÍA · HOJA 2 DE 3/.test(t.texto));
ok('y en el pie, con su fecha',
   /Hoja 2 de 3/.test(t.texto) && /29 de ago(\.)? de 2026/.test(t.texto));

// ── quién cruzó la puerta ────────────────────────────────────────
ok('la hoja empieza explicando quién entró', /QUIÉN ENTRÓ HOY/.test(t.texto));
// Antes era "va antes de los renglones que hay que buscar" dentro de un
// mismo papel; ahora los renglones están en la hoja 3, así que lo que
// se comprueba es el orden de las hojas dentro del fajo. Sigue siendo
// lo mismo: primero se entiende, después se busca.
ok('y va antes del punteo, que está en la hoja siguiente',
   t.fajo.indexOf('QUIÉN ENTRÓ HOY') < t.fajo.indexOf('BUSCAR EN EL EXTRACTO'));
ok('entraron 21 personas', /Entraronaclase21personas/.test(t.junto));
ok('16 traían la plata de días antes',
   /yahabíanpagadoantes16/.test(t.junto));
ok('y los 5 que pagaron hoy salen con su plata',
   /pagaronhoy5·\$75\.000/.test(t.junto));
ok('sin depósito no se imprime cuando es cero',
   !/sindepósito/i.test(t.junto));
// Lo que evita la resta a mano en el margen: decir por qué esos 16 no
// se buscan en el extracto de hoy.
ok('dice por qué los de días antes no se buscan hoy',
   /extractodeOTROdía/.test(t.junto));

// ── qué se registró hoy ──────────────────────────────────────────
ok('la segunda mitad dice qué se registró', /QUÉ SE REGISTRÓ HOY/.test(t.texto));
ok('las clases de hoy salen con su cuenta y su plata',
   /Clasesdehoy5·\$75\.000/.test(t.junto));
ok('los conceptos de `otros` salen con el nombre legible',
   /Clasesueltax2\$30\.000/.test(t.junto));
ok('y nunca con el código de la base', !/clase_suelta/.test(t.texto));
ok('el total es lo identificado, que es lo que suman los renglones',
   /=Depósitosregistradoshoy\$105\.000/.test(t.junto));

// ── LO QUE PIDIÓ EL DUEÑO: que lo diga con palabras ──────────────
// "Se debe indicar claramente qué es pagos del día que se disfrutan ese
// día, y qué es pagos de reservas futuras." Los datos ya venían
// partidos; lo que faltaba era que el papel lo dijera.
ok('dice con palabras qué se disfruta hoy',
   /SEPAGÓHOYYSEDISFRUTAHOY/.test(t.junto));
ok('y qué se disfruta otro día',
   /SEPAGÓHOY,SEDISFRUTAOTRODÍA/.test(t.junto));
ok('cada rótulo va justo encima de su línea',
   t.junto.indexOf('SEPAGÓHOYYSEDISFRUTAHOY') < t.junto.indexOf('Clasesdehoy')
   && t.junto.indexOf('Clasesdehoy') < t.junto.indexOf('SEPAGÓHOY,SEDISFRUTAOTRODÍA')
   && t.junto.indexOf('SEPAGÓHOY,SEDISFRUTAOTRODÍA') < t.junto.indexOf('Clasesfuturas'));

// ── efectivo y transferencia, que atraviesa las tres hojas ───────
// `entro_al_banco` son depósitos: transferencia toda. Decirlo evita
// buscar en el cajón lo que está en el extracto.
ok('avisa de que todo lo de esta sección es transferencia',
   /PORTRANSFERENCIA/.test(t.junto) && /estáenelextracto/.test(t.junto));
ok('y manda el efectivo a la hoja 3',
   /Elefectivodeldíavaenlahoja3/.test(t.junto));

// ── lo que se decidió NO imprimir ────────────────────────────────
// `reporto_banco_cop` no es lo que reportó Bancolombia sino lo que el
// sistema ingirió, así que la resta da cero casi siempre y un renglón
// que siempre dice $0 enseña a ignorar el papel.
ok('no se imprime lo que quedó sin identificar',
   !/sin identificar/i.test(t.texto));

// ── el amarre con la hoja 1 ──────────────────────────────────────
// Las dos hojas dicen "depósitos registrados hoy". Es el mismo número
// visto entero y visto por dentro, pero si el papel no lo dijera serían
// dos cifras con el mismo nombre en el mismo fajo.
ok('dice que es el total de la hoja 1 desglosado',
   /EseltotaldelahojaÊ?1desglosado|Eseltotaldelahoja1desglosado/.test(t.junto));
ok('y qué significa que no coincidan',
   /depósitosqueelsistemanosupodequéeran/.test(t.junto));

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
ok('un día en ceros sigue imprimiendo las dos secciones',
   /QUIÉN ENTRÓ HOY/.test(cero.texto) && /QUÉ SE REGISTRÓ HOY/.test(cero.texto));
ok('con cero personas y las líneas en raya',
   /Entraronaclase0personas/.test(cero.junto) && /Clasesdehoy—/.test(cero.junto));
ok('y el total en cero', /=Depósitosregistradoshoy\$0/.test(cero.junto));
// Un subtítulo sobre nada es ruido: sin conceptos de `otros` no hay
// "NO ES UNA CLASE" que encabezar.
ok('sin conceptos sueltos no se encabeza una lista vacía',
   !/NOESUNACLASE/.test(cero.junto));

/* ── un cierre viejo, sin la 0064 detrás ──────────────────────────
 * CAMBIÓ LO QUE SE ESPERA. Antes el bloque del cuadre vivía dentro de
 * la tirilla de pagos y sin `cuadre` sencillamente no se pintaba: la
 * tirilla salía más corta y ya. Ahora es una hoja entera de tres, y
 * desaparecerla dejaría un fajo de dos hojas numeradas 1 y 3. Así que
 * la hoja sale igual y dice por qué está vacía. */
const viejo = await pintar(como(c => { delete c.cuadre; }));
ok('sin `cuadre` la hoja 2 se imprime igual', viejo.hojas.length === 3,
   `${viejo.hojas.length} hojas`);
ok('y sigue siendo la hoja 2 de 3', /HOJA 2 DE 3/.test(viejo.texto));
ok('pero no finge tener datos', !/QUIÉN ENTRÓ HOY/.test(viejo.texto));
ok('dice por qué está vacía, en recuadro',
   viejo.recuadros >= 1 && /todavía no partía la plata del día/.test(viejo.texto),
   String(viejo.recuadros));
ok('y avisa de que las otras dos sí salen completas',
   /hojas 1 y 3 salen completas/.test(viejo.texto));
ok('el resto del fajo sale igual que siempre',
   /BUSCAR EN EL EXTRACTO/.test(viejo.fajo) && /\$75\.000/.test(viejo.fajo));

// ── el rótulo que mentía ─────────────────────────────────────────
// `banco.recibido_cop` es la suma de los depósitos que el sistema
// alcanzó a registrar, no lo que dice el extracto de Bancolombia.
ok('el fajo ya no dice que el banco recibió',
   !/El banco recibió hoy/.test(t.fajo));
// Dos rótulos iguales con cifras distintas es lo que hace desconfiar
// del papel. "Depósitos registrados hoy" en minúsculas solo puede
// aparecer una vez en las tres hojas: es el total de la hoja 2. El de
// la hoja 1 es un título en mayúsculas y su renglón se llama distinto.
ok('y el rótulo del total no se repite en las tres hojas',
   (t.fajo.match(/Depósitos registrados hoy/g) || []).length === 1,
   String((t.fajo.match(/Depósitos registrados hoy/g) || []).length));

ok('sin errores de JS', errs.length === 0, errs.join(' | '));
console.log(fallos ? `\n${fallos} fallo(s)` : '\nTodo bien');
await b.close();
process.exit(fallos ? 1 : 0);
