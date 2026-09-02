/**
 * Prueba de la pestaña Caja, con un navegador de verdad.
 *
 * POR QUÉ EXISTE
 * La caja se desplegó dos veces sin funcionar. Las dos veces mi
 * verificación dijo "sintaxis OK": extraía los <script> del HTML, los
 * concatenaba y los pasaba por node --check. Al concatenarlos quedaban
 * en ámbitos distintos, así que un `const` duplicado —que en el
 * navegador mata el bloque entero— pasaba desapercibido.
 *
 * Esto abre la página real en Chromium, hace clic donde haría clic la
 * cajera, y falla si la consola escupe un solo error. Es la capa que
 * faltaba: la de "el usuario toca y pasa algo".
 *
 * Se sirve desde localhost y se interceptan las llamadas de red, así
 * que no toca ni n8n ni Supabase ni el Worker.
 */
import { chromium } from 'playwright-core';
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { extname, join } from 'node:path';

const RAIZ = new URL('../../docs/', import.meta.url).pathname;
const CHROME = '/opt/pw-browsers/chromium-1194/chrome-linux/chrome';
const PUERTO = 8123;

const TIPOS = { '.html': 'text/html; charset=utf-8', '.png': 'image/png',
                '.json': 'application/json', '.txt': 'text/plain' };

const servidor = createServer(async (req, res) => {
  try {
    const ruta = req.url.split('?')[0];
    const archivo = join(RAIZ, ruta === '/' ? 'index.html' : ruta.replace(/^\//, ''));
    const cuerpo = await readFile(archivo);
    res.writeHead(200, { 'Content-Type': TIPOS[extname(archivo)] || 'application/octet-stream' });
    res.end(cuerpo);
  } catch (_) { res.writeHead(404); res.end('no'); }
});
await new Promise((r) => servidor.listen(PUERTO, r));

let ok = 0, mal = 0;
const bien = (t, d) => { ok++; console.log(`  ✓ ${t}${d ? '  → ' + d : ''}`); };
const falla = (t, d) => { mal++; console.log(`  ✗ ${t}${d ? '  → ' + d : ''}`); };

const navegador = await chromium.launch({ executablePath: CHROME });
const pagina = await navegador.newPage({ viewport: { width: 1280, height: 900 } });

// Lo que de verdad importa: cualquier error de JavaScript es un fallo.
// Los 400 que esta prueba provoca a propósito los apunta el navegador
// en la consola; ese ruido se descarta. Lo que NO se descarta es un
// ReferenceError como "caja is not defined", que es exactamente lo que
// se coló hasta producción por no pulsar el botón de cerrar.
const errores = [];
const ruido = (t) => /Failed to load resource/.test(t);
pagina.on('console', (m) => {
  if (m.type() === 'error' && !ruido(m.text())) errores.push(m.text());
});
pagina.on('pageerror', (e) => errores.push('JS: ' + e.message));

/* Un botón de la caja, buscado por su rótulo EXACTO.
 *
 * POR QUÉ NO `hasText`. `.locator('.caja-btn', { hasText: 'Mensualidad' })`
 * quiere decir "contiene", y "Media mensualidad" también contiene
 * "Mensualidad". Playwright encuentra dos botones y revienta con
 * "strict mode violation" — y como revienta, mata el proceso entero y
 * todo lo que venga después deja de comprobarse. Así estuvo esta prueba
 * desde que la Caja ganó los conceptos de media mensualidad y camiseta
 * (d6dc548): sin red, y sin que se notara.
 *
 * El fallo se repite con cualquier par de botones donde el rótulo de uno
 * esté contenido en el del otro, así que la defensa no puede ser
 * arreglar la línea 537 y ya: tiene que ser cómo se busca CUALQUIER
 * botón.
 *
 * Se descartó `hasText` con expresión regular anclada —`/^Mensualidad$/`
 * sobre el botón— porque el texto del botón no es solo el rótulo: lleva
 * pegado el precio ("Mensualidad $125.000") o "monto libre", así que el
 * ancla `$` obligaría a escribir el precio en la prueba y ésta se caería
 * el día que suba una tarifa, que no es lo que aquí se comprueba.
 *
 * `getByText(rotulo, { exact: true })` empareja contra el <span class="q">,
 * que lleva el rótulo y nada más: exacto sobre lo único que identifica
 * al botón, e indiferente al precio. */
const botonCaja = (rotulo) => pagina.locator('.caja-btn')
  .filter({ has: pagina.getByText(rotulo, { exact: true }) });

// ---- se finge el backend ----
let movimientos = [];
let idSeq = 0;

const dia = () => ({
  ok: true, dia: '2026-08-05',
  movimientos,
  base_cop: apertura ? apertura.contado_cop : 100000,
  ingreso_efectivo: suma('ingreso', 'efectivo'),
  egreso_efectivo: suma('egreso', 'efectivo'),
  esperado_efectivo: (apertura ? apertura.contado_cop : 100000)
    + suma('ingreso', 'efectivo') - suma('egreso', 'efectivo'),
  ingreso_transferencia: suma('ingreso', 'transferencia'),
  egreso_transferencia: suma('egreso', 'transferencia'),
  // Cobradas HOY: por la fecha en que entró la plata, no la de la
  // clase. Antes de la 0038 esto se contaba por el día de la clase y
  // el cierre no se podía cuadrar contra el banco.
  reservas_cop: 15000,
  reservas_n: sinCajaAlDia ? undefined : 1,
  reservas_futuras_cop: futurasCop,
  reservas_futuras_n: futurasN,
  // Lo que valen las clases dictadas hoy. Otro reloj, otra pregunta:
  // va aparte y no suma.
  reservas_dictadas_cop: 45000,
  reservas_dictadas_n: 3,
  // Confirmadas en el mostrador: NO entran en total_ingresos porque su
  // plata ya está en los movimientos de caja. Contarlas dos veces fue el
  // error que iba a inflar el cierre del 10 de agosto en $30.000.
  reservas_a_mano_cop: 30000,
  reservas_a_mano_n: 2,
  // Entradas de clase suelta de hoy (0051). El efectivo sí sale del
  // mismo movimientos que ya simula la caja —el botón genérico y la
  // apuntada a mano pasan igual por ahí—, así que se deriva en vivo,
  // igual que ingreso_efectivo. La transferencia por recepción/página
  // no tiene de dónde salir en este simulacro (no modela `reservas`),
  // así que va fija, como reservas_dictadas_cop.
  entradas: {
    efectivo_cop: suma('ingreso', 'efectivo', 'clase_suelta'),
    efectivo_n: cuenta('ingreso', 'efectivo', 'clase_suelta'),
    recepcion_transferencia_cop: 15000,
    recepcion_transferencia_n: 1,
    pagina_transferencia_cop: 30000,
    pagina_transferencia_n: 2,
    // Apuntados en recepción cuyo cobro no quedó en Caja (0054). Iban
    // en cero porque el simulacro no los mandaba, así que la línea
    // "Reservas manuales" de la tirilla se imprimía siempre con raya y
    // nadie comprobaba nunca que supiera enseñar un número.
    a_mano_cop: 15000,
    a_mano_n: 1,
    // La cuenta de personas la manda el servidor con su propia regla
    // (0059) y NO es la suma de las casillas de dinero: quien entró con
    // una clase reprogramada pagó otro día, y aun así cruzó la puerta.
    // Va a propósito uno POR ENCIMA de la suma (2 + 1 + 4 = 7) para que
    // la prueba distinga las dos cifras. Si el panel volviera a sumar
    // las casillas imprimiría 7, que es exactamente el error del 28 de
    // agosto: el papel decía 10 y por la puerta habían entrado 11.
    personas_n: 8,
  },
  total_ingresos: suma('ingreso', 'efectivo') + suma('ingreso', 'transferencia') + 15000,
  total_egresos: suma('egreso', 'efectivo') + suma('egreso', 'transferencia'),
  contra_admingym: {
    venta_membresias: suma('ingreso', 'efectivo'),
    ingresos_a_banco: suma('ingreso', 'transferencia') + 15000,
    retirar_dinero_de_caja: suma('egreso', 'efectivo'),
    dinero_en_caja: (apertura ? apertura.contado_cop : 100000)
      + suma('ingreso', 'efectivo') - suma('egreso', 'efectivo'),
  },
  banco: banco(),
  pagos_libres: libres,
  resumen_conceptos: resumen(),
  // Lo que necesita la SEGUNDA tirilla ("Imprimir cuándo pagaron"), que
  // hasta ahora esta prueba no pulsaba nunca: sin `cuadre` ni
  // `conciliacion` el papel sale vacío y un error de JS al pintarlo no
  // lo veía nadie. Los números son los del sábado 29 de agosto, que es
  // el día que motivó ese papel: entraron 21 personas pero al banco
  // entraron solo $105.000 porque 16 habían pagado días antes.
  cuadre: {
    quien_entro: { personas: 21, pagaron_antes: 16, pagaron_hoy: 5,
                   pagaron_hoy_cop: 75000, sin_deposito: 0 },
    entro_al_banco: {
      clases_hoy_n: 5, clases_hoy_cop: 75000,
      // Tres amigas que reservan el sábado siguiente con UN solo pago:
      // 3 cupos y 1 renglón del extracto. Si el papel dijera solo "3"
      // habría que buscar tres renglones que no existen.
      futuras_cupos: 3, futuras_depositos: 1, futuras_cop: 45000,
      otros: [{ concepto: 'mensualidad', n: 1, cop: 125000 }],
      otros_cop: 125000,
      identificado_cop: 245000,
      reporto_banco_cop: 245000, sin_identificar_cop: 0,
    },
  },
  conciliacion: {
    banco: [
      { dia: '2026-08-05', dias_antes: 0, hora: '10:12', valor_cop: 30000,
        remitente: 'MARIA CAMILA RUIZ', referencia: 'M22223333',
        para: ['Maria Ruiz', 'Sara Ruiz'], conceptos: [], cobros: 0,
        es_parte: false },
    ],
    banco_cop: 30000, banco_hoy_cop: 30000,
    efectivo: [], efectivo_cop: 0,
    sin_enlazar: [], sin_enlazar_cop: 0,
    sin_pago: [],
  },
  abierta: sinAbrirSoportado ? undefined : apertura !== null,
  apertura: sinAbrirSoportado ? undefined : apertura,
  cerrado: cierre !== null,
  cierre,
});

// Estado de la caja en el simulacro. Arranca sin abrir, que es como
// amanece de verdad.
let apertura = null;
let cierre = null;
// Con esto en true, el simulacro finge ser el servidor de ANTES de la
// migración 0031: no manda `abierta` ni `apertura`.
let sinAbrirSoportado = false;
// Con esto en true, el simulacro finge ser el servidor de ANTES de la
// 0038: cuenta las reservas por la fecha de la CLASE y no manda
// `reservas_n`.
let sinCajaAlDia = false;

// Lo que necesita la tirilla: agrupado por concepto, no movimiento a
// movimiento. Veinte líneas de "Clase suelta $15.000" no dicen más que
// una que diga "x20".
const resumen = () => {
  const m = new Map();
  for (const x of movimientos) {
    const k = `${x.sentido}|${x.concepto}|${x.medio}`;
    const v = m.get(k) || { sentido: x.sentido, concepto: x.concepto,
                            medio: x.medio, n: 0, valor_cop: 0 };
    v.n++; v.valor_cop += x.valor_cop;
    m.set(k, v);
  }
  return [...m.values()];
};

// El inventario del banco: depósitos que llegaron y nadie ha reclamado.
// `hayBanco` en false simula que la migración 0027 todavía no se pegó.
let hayBanco = false;
let libres = [];
let errorCierre = null;   // fuerza un fallo del servidor al cerrar
// Anticipos: lo que se pagó hoy para una clase de otro día. En 0 no
// aparece la fila — es justo lo que probó que el 24 de agosto la plata
// no estaba perdida, solo sin separar.
let futurasCop = 0, futurasN = 0;
const banco = () => {
  if (!hayBanco) return undefined;
  const sinResp = movimientos.filter(
    m => m.sentido === 'ingreso' && m.medio === 'transferencia' && !m.pago_id);
  const deHoy = libres.filter(p => Number(p.dias) === 0);
  const suma = l => l.reduce((a, p) => a + p.valor_cop, 0);
  return {
    recibido_cop: 330000,
    libre_hoy_cop: suma(deHoy),
    libre_hoy_n: deHoy.length,
    libre_cop: suma(libres),
    libre_n: libres.length,
    atras_cop: suma(libres) - suma(deHoy),
    atras_n: libres.length - deHoy.length,
    mes_cop: 4820000,
    sin_respaldo_cop: sinResp.reduce((a, m) => a + m.valor_cop, 0),
    sin_respaldo_n: sinResp.length,
    ventana_dias: 20,
    corte: '19:42',
  };
};
const suma = (s, m, cpt) => movimientos.filter((x) => x.sentido === s && x.medio === m
                                              && (!cpt || x.concepto === cpt))
                                  .reduce((a, b) => a + b.valor_cop, 0);
const cuenta = (s, m, cpt) => movimientos.filter((x) => x.sentido === s && x.medio === m
                                              && (!cpt || x.concepto === cpt)).length;

await pagina.route('**/tumbao-caja.*/api/**', async (route) => {
  const url = route.request().url();
  const b = JSON.parse(route.request().postData() || '{}');
  let r = { ok: true };
  if (url.endsWith('/dia')) r = dia();
  else if (url.endsWith('/registrar')) {
    // Adjudicar un depósito lo saca del inventario, igual que en
    // Postgres. Si no se sacara, la prueba del enlace pasaría sin que la
    // pantalla estuviera mandando el pago_id.
    if (b.pago_id) libres = libres.filter((p) => p.id !== b.pago_id);
    movimientos.unshift({ id: '00000000-0000-4000-8000-' + String(++idSeq).padStart(12, '0'),
      sentido: b.sentido, concepto: b.concepto, valor_cop: +b.valor,
      medio: b.medio, nota: b.nota || null, hora: '10:0' + idSeq, quien: 'prueba',
      pago_id: b.pago_id || null, con_banco: !!b.pago_id });
    r = { ok: true, id: 'x' };
  } else if (url.endsWith('/abrir')) {
    const contado = +String(b.contado).replace(/\D/g, '');
    apertura = { contado_cop: contado, esperado_cop: 100000,
                 diferencia_cop: contado - 100000, nota: b.nota || null,
                 quien: 'prueba', hora: '07:12' };
    r = { ok: true, ...apertura };
  } else if (url.endsWith('/cerrar')) {
    if (errorCierre) {
      await route.fulfill({ status: 400, contentType: 'application/json',
        body: JSON.stringify({ ok: false, error: errorCierre }) });
      return;
    }
    const base = apertura ? apertura.contado_cop : 100000;
    const esp = base + suma('ingreso','efectivo') - suma('egreso','efectivo');
    const contado = +String(b.contado).replace(/\D/g, '');
    const dejado = +String(b.dejado || 0).replace(/\D/g, '');
    cierre = { contado_cop: contado, esperado_cop: esp,
               diferencia_cop: contado - esp, dejado_cop: dejado,
               retirado_cop: contado - dejado, banco_cop: 330000,
               banco_sin_ident_cop: 0, rehecho_n: b.rehacer ? 1 : 0,
               rehecho_motivo: b.motivo || null, quien: 'prueba',
               nota: b.nota || null, hora: '21:03' };
    r = { ok: true, dia: '2026-08-05' };
  } else if (url.endsWith('/anular')) {
    const m = movimientos.find((x) => x.id === b.id);
    movimientos = movimientos.filter((x) => x.id !== b.id);
    r = { ok: true, concepto: m?.concepto, valor_cop: m?.valor_cop };
  }
  await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(r) });
});

// n8n: lo mínimo para que el panel arranque y no estorbe.
// El panel ya no llama a n8n: sus rutas van al Worker, en
// /api/admin/<ruta>. Se interceptan ahí para que la pestaña Caja
// arranque sin tocar nada de verdad.
await pagina.route('**/api/admin/**', async (route) => {
  const u = route.request().url();
  let r = { ok: true };
  if (u.endsWith('/semana')) r = { ok: true, dias: [] };
  else if (u.endsWith('/pendientes')) r = { ok: true, reservas: [] };
  else if (u.endsWith('/tablero')) r = { ok: true, dia: '2026-08-05', clases: [],
    resumen: { libres: 0, en_sala: 0, reservadas: 0, confirmadas: 0, por_validar: 0, ingreso_cop: 0 } };
  await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(r) });
});

console.log('\n── La caja, en un navegador de verdad ──\n');
await pagina.goto(`http://localhost:${PUERTO}/admin.html`, { waitUntil: 'domcontentloaded' });

// Entrar — con el token, que es el modo avanzado plegado en un <details>.
await pagina.evaluate(() => { document.querySelector('#modo-token').open = true; });
await pagina.fill('#token', 'token-de-prueba');
await pagina.click('#btn-entrar-token');
await pagina.waitForSelector('#app:not([hidden])', { timeout: 8000 })
  .then(() => bien('entra al panel'))
  .catch(() => falla('entra al panel', 'el panel nunca apareció'));

// LO QUE FALLABA
await pagina.click('#tab-caja');
await pagina.waitForTimeout(700);

const visible = await pagina.locator('#p-caja').evaluate((e) => e.classList.contains('on'));
visible ? bien('la pestaña Caja abre') : falla('la pestaña Caja abre', 'el panel no quedó visible');

/* Los botones con los que se registra la plata, uno por concepto.
 *
 * ERAN 9 Y LUEGO 11, Y ESTÁ BIEN: d6dc548 añadió "Media mensualidad"
 * y "Camiseta" a CONCEPTOS a propósito, sin valor sugerido porque
 * todavía no tienen tarifa. No sobra ninguno ni se duplicó nada.
 *
 * Y AHORA SON 10: se fue "Otro ingreso". Era el cajón de sastre donde
 * caían los $15.000 que nadie quiso buscar en la lista, y el cierre no
 * los contaba como clase suelta — así se perdía la cuenta de gente del
 * día sin dejar rastro. Los movimientos viejos que lo tienen guardado
 * se siguen pintando con su nombre; lo que se quitó es poder escogerlo.
 *
 * Se comprueba la LISTA y no el número. Un contador solo dice "son
 * once" y se lo cree igual si un concepto desaparece y otro se
 * duplica — que en una pantalla donde cada botón mueve dinero real es
 * justo el error que hay que ver. Con los rótulos, además, el fallo
 * dice qué cambió en vez de dejar dos números que no explican nada. */
const ROTULOS = ['Clase suelta', 'Media mensualidad', 'Mensualidad',
                 'Cumpleaños', 'Camiseta',
                 'Profesores', 'Cafetería', 'Aseo', 'Papelería', 'Otra salida'];
const rotulos = (await pagina.locator('.caja-btn .q').allInnerTexts()).map(t => t.trim());
rotulos.join('|') === ROTULOS.join('|')
  ? bien(`salen las ${ROTULOS.length} tarjetas, y son las que son`)
  : falla(`salen las ${ROTULOS.length} tarjetas`, `salieron ${rotulos.length}: ${rotulos.join(', ')}`);

// ═══════════════ sin la migración 0031 ═══════════════
// El estado real entre que se despliega la página y se pega el SQL: el
// servidor no devuelve `abierta`. La pantalla NO puede pedir abrir una
// caja que el servidor todavía no sabe abrir — el botón daría 502.
// Este fallo se coló en el despliegue de esta noche y por eso tiene
// prueba propia.
sinAbrirSoportado = true;
await pagina.click('#caja-recargar');
await pagina.waitForTimeout(700);
!/Abrir la caja/.test(await pagina.locator('#caja-cierre').innerText())
  ? bien('sin la migración 0031, no pide abrir la caja')
  : falla('pide abrir sin que el servidor sepa hacerlo');
sinAbrirSoportado = false;
await pagina.click('#caja-recargar');
await pagina.waitForTimeout(700);

// ═══════════════ abrir la caja ═══════════════
// La caja amanece sin abrir. Lo primero que se ve es el conteo, no los
// botones de venta: contar al abrir es lo que parte un descuadre en "lo
// de anoche" y "lo de hoy". Sin eso, un faltante aparece a las nueve
// mezclado con las ventas del día.
const pantallaApertura = await pagina.locator('#caja-cierre').innerText();
/Abrir la caja/.test(pantallaApertura)
  ? bien('sin abrir, lo primero que pide es contar el cajón')
  : falla('la pantalla de apertura', pantallaApertura.slice(0, 90));

/Anoche se dejó/.test(pantallaApertura) && /100\.000/.test(pantallaApertura)
  ? bien('y dice cuánto se dejó anoche, para comparar')
  : falla('lo que se dejó anoche', pantallaApertura.slice(0, 120));

// Sin contar no se abre.
await pagina.click('#btn-abrir-caja');
await pagina.waitForTimeout(400);
(await pagina.locator('#a-contado').evaluate(e => e.classList.contains('malo-campo')))
  ? bien('sin escribir el conteo, señala el campo')
  : falla('el campo de conteo', 'no quedó marcado');

// ── "Cerrar el día sin abrir" ──
// No funcionaba. El enlace ponía la bandera y llamaba a pintarCaja(),
// que volvía a entrar por la pantalla de apertura antes de mirarla y
// redibujaba lo mismo: al hacer clic no pasaba nada. Quien no abrió por
// la mañana se quedaba sin poder cerrar.
await pagina.click('#saltar-apertura');
await pagina.waitForTimeout(400);
(await pagina.locator('#c-contado').count()) === 1
  ? bien('sin abrir, el enlace sí deja llegar al cierre')
  : falla('el enlace de cerrar sin abrir',
          (await pagina.locator('#caja-cierre').innerText()).slice(0, 90));

// Y la salida de vuelta, para quien lo tocó sin querer.
await pagina.click('#volver-apertura');
await pagina.waitForTimeout(400);
(await pagina.locator('#a-contado').count()) === 1
  ? bien('y se puede volver a la apertura sin recargar')
  : falla('la vuelta a la apertura',
          (await pagina.locator('#caja-cierre').innerText()).slice(0, 90));

// Se abre con MENOS de lo que decía el papel: es el caso que hace que
// esto valga la pena.
await pagina.fill('#a-contado', '95.000');
await pagina.fill('#a-nota', 'faltaban 5 mil');
await pagina.click('#btn-abrir-caja');
await pagina.waitForTimeout(800);

const avisoAp = (await pagina.locator('#avisos .nota').first().innerText()).replace(/\s+/g, ' ');
/Faltan \$5\.000/.test(avisoAp)
  ? bien('avisa la diferencia con lo de anoche', avisoAp.trim())
  : falla('el aviso de apertura', avisoAp);

// Y LO IMPORTANTE: el día corre sobre lo contado, no sobre el papel. Si
// arrastrara los 100.000, el faltante de anoche se mezclaría con el
// arqueo de esta noche y ya no se sabría de qué turno fue. Como durante
// el turno no se enseña ninguna cifra, se comprueba donde sí sale: en la
// ventana del cierre.

// DURANTE EL TURNO NO SE ENSEÑA NINGUNA CIFRA.
//
// Dos razones. La del arqueo: ver el total del cajón sumándose todo el
// día le da al cajero la respuesta antes de contar, y contar contra una
// cifra ya sabida no comprueba nada.
//
// Y la que pesa más, dicha por quien lo usa: cuatro recuadros arriba
// estorban. Lo primero que se ve al entrar tiene que ser dónde registrar
// la plata, no números que hay que interpretar en mitad de una venta. Se
// probó enseñar las reservas y las transferencias —que no son plata del
// cajón y no anclan nada— y aun así confundían.
//
// Los totales viven abajo y solo salen al pedir el cierre.
const tiles = async () => await pagina.locator('#caja-tiles .tile').count();

(await tiles()) === 0
  ? bien('durante el turno no se enseña ninguna cifra')
  : falla('quedaron recuadros durante el turno',
          (await pagina.locator('#caja-tiles').innerText()).replace(/\s+/g, ' ').slice(0, 160));

await pagina.locator('#caja-tiles').isHidden()
  ? bien('y el hueco tampoco queda ahí')
  : falla('el contenedor de cifras sigue ocupando sitio');

// El sitio importa: los totales van DESPUÉS de los botones de registrar,
// no antes. Arriba era lo primero que se veía y era justo lo que sobraba.
await pagina.evaluate(() => {
  const t = document.querySelector('#caja-tiles');
  const e = document.querySelector('#sec-entra');
  return !!(t.compareDocumentPosition(e) & Node.DOCUMENT_POSITION_PRECEDING);
})
  ? bien('los totales van debajo de donde se registra la plata')
  : falla('los totales siguen arriba');



// Registrar una clase suelta
await botonCaja('Clase suelta').click();
await pagina.waitForTimeout(300);
const valorPrecargado = await pagina.inputValue('#modal-valor');
valorPrecargado === '15000'
  ? bien('la ventana precarga $15.000') : falla('la ventana precarga $15.000', valorPrecargado);

await pagina.click('#modal-guardar');
await pagina.waitForTimeout(700);

// LO QUE IMPORTA: registrar una venta no hace aparecer ningún total. Si
// saliera "$115.000 en el cajón" estaría cantándole el resultado al
// cajero mientras atiende, y el arqueo de la noche ya no comprobaría
// nada.
(await tiles()) === 0
  ? bien('al guardar una venta no aparece ningún total')
  : falla('apareció un total al registrar',
          (await pagina.locator('#caja-tiles').innerText()).replace(/\s+/g, ' ').slice(0, 120));

// El listado arranca cerrado: hay que abrirlo. No se quitó del todo
// porque es la única forma de anular algo mal registrado.
const btnMovs = pagina.locator('#caja-ver-movs');
/Ver movimientos de hoy \(1\)/.test(await btnMovs.innerText())
  ? bien('el botón dice cuántos hay sin abrir la lista', (await btnMovs.innerText()).trim())
  : falla('el botón de movimientos', await btnMovs.innerText());

(await pagina.locator('#caja-lista').isHidden())
  ? bien('la lista arranca cerrada')
  : falla('la lista arranca cerrada', 'salió abierta');

await btnMovs.click();
await pagina.waitForTimeout(300);
(await pagina.locator('#caja-lista').isVisible())
  ? bien('y se abre al pedirla') : falla('abrir la lista', 'siguió oculta');

const nMovs = await pagina.locator('.mov').count();
nMovs === 1 ? bien('aparece en la lista') : falla('aparece en la lista', `hay ${nMovs}`);

// Guardar bien tiene que decir que fue bien. Esto se rompió sin que
// nadie lo notara: cerrarModal() ponía cajaElegido en null y la línea
// siguiente leía cajaElegido.n, así que el movimiento SÍ se guardaba
// pero la pantalla decía "No se pudo registrar". La prueba pasaba
// porque solo miraba que el saldo subiera.
const trasGuardar = pagina.locator('#avisos .nota').first();
const txtGuardar = (await trasGuardar.innerText()).replace(/\s+/g, ' ').trim();
(await trasGuardar.evaluate(e => e.classList.contains('bien')))
 && /Clase suelta/.test(txtGuardar)
  ? bien('avisa que se guardó, con qué fue', txtGuardar)
  : falla('el aviso de guardado', txtGuardar);

// Y el aviso va en dos renglones: título y detalle eran spans sin
// display:block, así que salía "Falta cuánto contasteEscribe el…".
const renglones = await trasGuardar.evaluate(e => [
  getComputedStyle(e.querySelector('.tit')).display,
  getComputedStyle(e.querySelector('.det')).display,
]);
renglones.every(d => d === 'block')
  ? bien('el aviso no sale con el texto pegado')
  : falla('título y detalle pegados', renglones.join('/'));

// Un egreso con monto libre
await botonCaja('Profesores').click();
await pagina.waitForTimeout(300);
await pagina.fill('#modal-valor', '80.000');           // con punto, como teclea la cajera
await pagina.click('#modal-guardar');
await pagina.waitForTimeout(700);
(await pagina.locator('.mov').count()) === 2
  ? bien('el egreso entra en la lista y entiende "80.000"')
  : falla('el egreso', `hay ${await pagina.locator('.mov').count()} movimientos`);
(await tiles()) === 0
  ? bien('y sigue sin cantarse ningún total')
  : falla('apareció un total tras el egreso',
          (await pagina.locator('#caja-tiles').innerText()).replace(/\s+/g, ' ').slice(0, 120));

// Anular
await pagina.locator('[data-anular]').first().click();
await pagina.waitForTimeout(700);
(await pagina.locator('.mov').count()) === 1
  ? bien('anular quita el movimiento de la lista')
  : falla('anular', `quedaron ${await pagina.locator('.mov').count()}`);

// El cierre no enseña ni un número hasta que el cajero lo pide. Eso es
// lo que impide que cuadre de cabeza contra un total que ya vio.
const antesDeCerrar = await pagina.locator('#caja-cierre').innerText();
!/\$/.test(antesDeCerrar) && /Cerrar el día/.test(antesDeCerrar)
  ? bien('durante el turno el cierre no enseña ni una cifra')
  : falla('el cierre enseña cifras antes de tiempo',
          antesDeCerrar.replace(/\s+/g, ' ').slice(0, 120));

await pagina.click('#btn-abrir-cierre');
await pagina.waitForTimeout(500);

// Y al pedirlo aparecen también las cuatro tarjetas de arriba.
(await pagina.locator('#caja-tiles .tile').count()) >= 4
  ? bien('al pedir el cierre aparecen los totales')
  : falla('los totales al cerrar',
          `${await pagina.locator('#caja-tiles .tile').count()} tarjetas`);

// Los recuadros se pintaban con <b><span><small>, etiquetas que el CSS
// del panel no conoce: salía "$100.000en el cajónbase + efectivo".
// Pasaba todas las pruebas porque el número sí estaba. Esto mira que
// cifra, título y pista sean tres bloques, no una frase pegada. Se
// comprueba aquí porque es el único momento en que hay recuadros.
const primerTile = pagina.locator('#caja-tiles .tile').first();
const partes = await primerTile.evaluate((e) =>
  ['.n', '.k', '.pista'].map((s) => e.querySelector(s)?.textContent.trim() || null));
partes.every(Boolean)
  ? bien('el recuadro va en tres renglones', partes.join(' / '))
  : falla('el recuadro va en tres renglones', 'texto pegado: ' + (await primerTile.innerText()).trim());

const hayCierre = await pagina.locator('#caja-cierre').innerText();
hayCierre.includes('AdminGym')
  ? bien('el cierre muestra los nombres de AdminGym') : falla('el cierre', 'sin referencia a AdminGym');

// ═══════════════ el control del banco ═══════════════
// Sin la migración 0027 aplicada, `banco` no viene. La tarjeta no debe
// salir y nada más puede romperse: es el estado real de la página entre
// que se despliega y se pega el SQL.
(await pagina.locator('#caja-tiles .tile.banco').count()) === 0
  ? bien('sin la migración 0027, la tarjeta no sale y nada revienta')
  : falla('sin la migración 0027', 'salió la tarjeta igual');

const recargar = async () => {
  await pagina.click('#caja-recargar');
  await pagina.waitForTimeout(700);
};
const tarjeta = pagina.locator('#caja-tiles .tile.banco');
const pista = async () => (await tarjeta.locator('.pista').innerText()).trim();

// El tamaño real: 75 depósitos de arrastre histórico, de antes de que
// existiera este módulo, más uno de hoy sin reclamar. Con datos de
// juguete la pantalla parecía bien; con los de verdad, el arrastre se
// comía la tarjeta y la dejaba en ámbar para siempre.
hayBanco = true;
const arrastre = Array.from({ length: 74 }, (_, i) => ({
  id: 'dddddddd-0000-4000-8000-' + String(i).padStart(12, '0'),
  valor_cop: 40000 + i * 1000, cuando: '20/07 09:00',
  dias: 3 + (i % 15), remitente: 'HISTORICO ' + i,
}));
libres = [
  { id: 'cccccccc-0000-4000-8000-000000000001', valor_cop: 15000,
    cuando: '05/08 14:12', dias: 0, remitente: 'CAMILA ROJAS' },
  ...arrastre,
];
await recargar();

// LO QUE SE ESTABA ROMPIENDO: el titular tiene que hablar de hoy. Con
// el arrastre mandando decía "$3.211.000 sin identificar · 75
// depósitos", un número que no baja nunca y que por tanto no se mira.
/15\.000 de hoy sin identificar · 1 depósito/.test(await pista())
  ? bien('el titular habla solo de hoy', await pista())
  : falla('el titular habla solo de hoy', await pista());

const pieTarjeta = (await tarjeta.locator('.corte').innerText()).replace(/\s+/g, ' ');
/7:42 pm/.test(pieTarjeta) && /en el mes/.test(pieTarjeta) && /días atrás/.test(pieTarjeta)
  ? bien('hora, mes y arrastre van en letra chica', pieTarjeta)
  : falla('la letra chica', pieTarjeta);

// Con 75 depósitos la lista es un muro: sin filtro la cajera escoge el
// primero que le cuadre de valor, que es justo lo que hay que evitar.
await botonCaja('Mensualidad').click();
await pagina.waitForTimeout(250);
await pagina.locator('.medio[data-medio="transferencia"]').click();
await pagina.waitForTimeout(250);
(await pagina.inputValue('#modal-dep-buscar')) === '125000'
  ? bien('el filtro arranca con el precio del concepto')
  : falla('el filtro arranca con el precio', await pagina.inputValue('#modal-dep-buscar'));

await pagina.fill('#modal-dep-buscar', 'camila');
await pagina.waitForTimeout(250);
(await pagina.locator('.dep').count()) === 1
  ? bien('buscar por nombre deja un solo candidato de 75')
  : falla('buscar por nombre', `quedaron ${await pagina.locator('.dep').count()}`);

// Escoger el depósito trae el valor del banco cuando el concepto se
// teclea a mano: si la cajera dejó otra cifra, Postgres rechaza el
// enlace, así que mejor que cuadre desde aquí.
//
// Esto se comprueba en Mensualidad y ya no en Clase suelta: desde el
// contador, una clase suelta vale cantidad × $15.000 y su campo está
// bloqueado a propósito. No se pisa nada ahí, y por eso el caso se mira
// donde el valor todavía se escribe.
await pagina.fill('#modal-valor', '99999');
await pagina.locator('.dep').first().click();
await pagina.waitForTimeout(200);
(await pagina.inputValue('#modal-valor')) === '15000'
  ? bien('escoger el depósito trae el valor del banco')
  : falla('el valor del depósito', await pagina.inputValue('#modal-valor'));

// Buscando por valor salen el que cuadra exacto Y unos pocos que
// alcanzan aunque valgan más: desde la 0039 un depósito de $30.000
// puede pagar una clase de $15.000.
//
// Los dos extremos importan. Antes solo salía el exacto, así que un
// depósito de $30.000 no aparecía nunca y parecía que la plata no había
// llegado — fue lo que dejó $30.000 atascados el 15 de agosto. Pero
// mostrarlos todos son 75 y la cajera escoge el primero que le cuadre,
// que es peor que no encontrarlo.
await pagina.fill('#modal-dep-buscar', '15000');
await pagina.waitForTimeout(250);
const cuantosDep = await pagina.locator('.dep').count();
cuantosDep > 1 && cuantosDep <= 4
  ? bien('buscar por valor deja el exacto y unos pocos que alcanzan',
         `${cuantosDep} de 75`)
  : falla('buscar por valor', `quedaron ${cuantosDep}`);

// El que cuadra exacto va de primero: es el que casi siempre es.
(await pagina.locator('.dep .v').first().innerText()).trim() === '$15.000'
  ? bien('y el que cuadra exacto va de primero')
  : falla('el orden del filtro',
          await pagina.locator('.dep .v').first().innerText());

await pagina.fill('#modal-dep-buscar', 'zzzz');
await pagina.waitForTimeout(250);
(await pagina.locator('.dep-vacio').count()) === 1
  ? bien('si no coincide nada lo dice, no deja el hueco en blanco')
  : falla('filtro sin resultados', 'no salió el aviso');

await pagina.click('#modal-cancelar');
await pagina.waitForTimeout(200);

// La lista solo aparece para una transferencia que entra.
await botonCaja('Clase suelta').click();
await pagina.waitForTimeout(250);
!(await pagina.locator('#modal-banco').isVisible())
  ? bien('en efectivo no pide depósito')
  : falla('en efectivo no pide depósito', 'salió la lista igual');

await pagina.locator('.medio[data-medio="transferencia"]').click();
await pagina.waitForTimeout(250);
(await pagina.locator('#modal-banco').isVisible())
  ? bien('al marcar transferencia aparecen los depósitos')
  : falla('al marcar transferencia', 'la lista no salió');

await pagina.fill('#modal-dep-buscar', 'camila');
await pagina.waitForTimeout(250);
const dep = pagina.locator('.dep').first();
const txtDep = (await dep.innerText()).replace(/\s+/g, ' ').trim();
/CAMILA ROJAS/.test(txtDep) && /· hoy/.test(txtDep)
  ? bien('el depósito de hoy dice de quién es', txtDep)
  : falla('el depósito de hoy', txtDep);

// Y uno del arrastre tiene que decir cuántos días lleva esperando: es
// lo que le dice a la cajera si ese depósito puede ser el de esta
// persona o es de otra semana.
await pagina.fill('#modal-dep-buscar', 'historico 7');
await pagina.waitForTimeout(250);
const viejo = (await pagina.locator('.dep').first().innerText()).replace(/\s+/g, ' ');
/hace \d+ días/.test(viejo)
  ? bien('uno viejo dice cuántos días lleva esperando', viejo)
  : falla('los días del depósito viejo', viejo);

await pagina.fill('#modal-dep-buscar', 'camila');
await pagina.waitForTimeout(250);

// En Clase suelta el valor lo manda el contador: una clase son $15.000
// y el campo está bloqueado. Escoger el depósito NO lo pisa —ni hacia
// arriba ni hacia abajo— porque el monto y la cuenta de gente tienen
// que seguir diciendo lo mismo. Que aquí cuadre con el banco es
// coincidencia buscada: una clase suelta vale exactamente lo que llegó.
await dep.click();
await pagina.waitForTimeout(200);
(await pagina.inputValue('#modal-valor')) === '15000'
  ? bien('con el contador, el depósito no pisa el valor calculado')
  : falla('el valor calculado de la clase suelta', await pagina.inputValue('#modal-valor'));

(await pagina.locator('#modal-valor').evaluate(el => el.readOnly))
  ? bien('y ese valor no se puede teclear a mano')
  : falla('el valor de la clase suelta', 'se dejó editar');

await pagina.click('#modal-guardar');
await pagina.waitForTimeout(800);

/todo lo de hoy identificado/.test(await pista())
  ? bien('adjudicado, lo de hoy queda limpio', await pista())
  : falla('tras adjudicar', await pista());

(await pagina.locator('.mov .ok-banco').count()) === 1
  ? bien('el movimiento queda con su visto de respaldado')
  : falla('el visto de respaldado', `hay ${await pagina.locator('.mov .ok-banco').count()}`);

// Registrar sin enlazar: Nequi, otra cuenta, o el aviso que no llegó.
// Se permite, se cuenta aparte, y no se acusa a nadie.
await botonCaja('Mensualidad').click();
await pagina.waitForTimeout(250);
await pagina.locator('.medio[data-medio="transferencia"]').click();
await pagina.waitForTimeout(200);
// Ningún depósito del arrastre vale 125.000, así que el filtro no
// puede ofrecer un candidato: lo peor que podría pasar aquí es que
// mostrara uno cualquiera y la cajera lo diera por bueno.
(await pagina.locator('.dep').count()) === 0
 && (await pagina.locator('.dep-vacio').count()) === 1
  ? bien('si ningún depósito cuadra con el precio, no ofrece ninguno')
  : falla('el filtro ofreció un candidato que no cuadra',
          `${await pagina.locator('.dep').count()} visibles`);

await pagina.click('#modal-guardar');
await pagina.waitForTimeout(800);

// Lo confirmado en el mostrador tiene que verse, y tiene que verse como
// algo que NO suma: es el punto de control de que esa plata se registró
// en Caja. Si no se enseñara, el arreglo del doble conteo sería
// invisible y nadie podría comprobarlo.
// Se busca SU fila, no se cuentan las que haya: contar ataba la prueba
// a cuántas filas de control tiene el cierre, y al añadir el desglose
// del banco se cayó sin que nada estuviera roto.
const ctrl = pagina.locator('#caja-cierre .fila.control')
  .filter({ hasText: 'Confirmadas en el mostrador' });
(await ctrl.count()) === 1
  ? bien('el cierre enseña lo confirmado en el mostrador',
         (await ctrl.innerText()).replace(/\s+/g, ' ').trim())
  : falla('lo confirmado en el mostrador', `${await ctrl.count()} filas`);

/* EL TOTAL LO PONE EL BANCO, NO LA SUMA A MANO.
 *
 * Se armaba sumando las transferencias del mostrador más las reservas
 * cobradas. El 20 de agosto eso dio 490.000 cuando al banco entraron
 * 475.000: los 15.000 de más eran un movimiento apuntado a mano sin
 * depósito detrás, o sea la misma plata dos veces. Y ese número se
 * copia en AdminGym, así que el error viajaba.
 *
 * Se comprueba contra `banco.recibido_cop` —lo que el banco dice— y NO
 * contra la suma, que es justo lo que se dejó de hacer. */
const esperadoBanco = dia().banco.recibido_cop;
// :not(.control) descarta el desglose de abajo ("De la transferencia,
// cruzado en el mostrador" / "...reservas que entraron solas"), y
// .first() se queda con la fila "Transferencia" de la tarjeta "Entró" y no con
// "Apuntado sin respaldo... 1 transferencia" de la tarjeta del banco,
// que también contiene la palabra "transferencia".
const totalBanco = await pagina.locator('#caja-cierre .fila:not(.control)')
  .filter({ hasText: 'Transferencia' }).first().innerText();
const cifraBanco = Number((totalBanco.match(/\$([\d.]+)/) || [])[1]?.replace(/\./g, ''));
cifraBanco === esperadoBanco
  ? bien('el total de transferencias lo pone el banco',
         `$${esperadoBanco.toLocaleString('es-CO')}`)
  : falla('el total de transferencias no es el del banco',
          `el banco dice ${esperadoBanco}, la pantalla dice ${cifraBanco}`);

// Y en concreto: NO puede ser la suma a mano, que es la que se
// equivocaba.
const sumaAMano = dia().contra_admingym.ingresos_a_banco;
cifraBanco !== sumaAMano || sumaAMano === esperadoBanco
  ? bien('y no la suma de los movimientos')
  : falla('sigue enseñando la suma a mano', `${cifraBanco}`);

/* ANTICIPOS: lo que se pagó hoy para una clase de otro día.
 *
 * El 24 de agosto esto fue justo lo que hizo parecer que faltaban
 * $105.000 comparado contra AdminGym: dos personas pagaron ese día por
 * clases del día siguiente. Esa plata sigue sumando al total de
 * arriba —entró de verdad—, pero tiene que poder verse aparte de lo
 * que un cliente disfrutó hoy mismo. */
futurasCop = 45000; futurasN = 1;
await recargar();

const deHoy = pagina.locator('#caja-cierre .fila')
  .filter({ hasText: 'De eso, de clientes de hoy' });
(await deHoy.innerText()).includes((esperadoBanco - 45000).toLocaleString('es-CO'))
  ? bien('separa lo de hoy de los anticipos',
         (await deHoy.innerText()).replace(/\s+/g, ' ').trim())
  : falla('lo de hoy', await deHoy.innerText());

const paraOtroDia = pagina.locator('#caja-cierre .fila.control')
  .filter({ hasText: 'De eso, para clases de otro día' });
(await paraOtroDia.innerText()).includes('45.000') && (await paraOtroDia.innerText()).includes('1 reserva')
  ? bien('y dice cuánto es anticipo y de cuántas reservas',
         (await paraOtroDia.innerText()).replace(/\s+/g, ' ').trim())
  : falla('el anticipo', await paraOtroDia.innerText());

futurasCop = 0; futurasN = 0;
await recargar();

// La cola del banco (lo sin identificar, lo sin respaldo) ya no es una
// tarjeta más con semáforos de color — el cierre solo tiene tres
// tarjetas (Entró, Salió, ¿Cuadra?) y esto es una línea aparte,
// informativa, que ni siquiera es del cierre de hoy.
const cierreTxt = await pagina.locator('#caja-cierre').innerText();
/apuntado sin respaldo del banco/i.test(cierreTxt) && /125\.000/.test(cierreTxt)
  ? bien('lo apuntado sin respaldo sale contado aparte en el cierre')
  : falla('sin respaldo en el cierre', cierreTxt.slice(0, 200));

// Lo que ya no puede pasar: que un desfase de fechas se pinte de rojo.
// Rojo estaba reservado para "comprobante falso" y disparaba solo por
// llegar tarde, que es lo normal.
const cls = await tarjeta.getAttribute('class');
!cls.includes('malo')
  ? bien('nunca se pone en rojo por un desfase de fechas')
  : falla('rojo por desfase', cls);

// ═══════════════ avisos y cerrar el día ═══════════════
// Antes aquí solo se comprobaba que el botón estuviera habilitado. Con
// eso, "caja is not defined" —una llamada a una función renombrada—
// llegó a producción y dejó el cierre roto. Ahora se pulsa de verdad.

// 1. Falta el contado: tiene que avisar Y señalar el campo.
await pagina.fill('#c-contado', '');
await pagina.click('#btn-cerrar-caja');
await pagina.waitForTimeout(300);

const laNota = pagina.locator('#avisos .nota').first();
(await laNota.count()) && /Falta cuánto contaste/.test(await laNota.innerText())
  ? bien('el aviso sale flotando, no enterrado en la página',
         (await laNota.innerText()).replace(/\s+/g, ' ').trim())
  : falla('el aviso flotante', 'no salió');

await pagina.locator('#c-contado').evaluate(e => e.classList.contains('malo-campo'))
  ? bien('y marca en rojo el campo que falta')
  : falla('marcar el campo', '#c-contado no quedó marcado');

// El aviso está fijo arriba a la derecha: se ve aunque estemos mirando
// el final del cierre, que es donde de verdad está la cajera.
const pos = await laNota.evaluate(e => {
  const r = e.getBoundingClientRect();
  return { fijo: getComputedStyle(e.parentElement).position,
           dentro: r.top >= 0 && r.right <= innerWidth + 1 };
});
pos.fijo === 'fixed' && pos.dentro
  ? bien('queda a la vista mires donde mires')
  : falla('la posición del aviso', JSON.stringify(pos));

// Escribir en el campo le quita el rojo: si no, se queda marcado para
// siempre y deja de significar algo.
await pagina.fill('#c-contado', '50000');
await pagina.waitForTimeout(150);
!(await pagina.locator('#c-contado').evaluate(e => e.classList.contains('malo-campo')))
  ? bien('al corregirlo se le quita el rojo')
  : falla('el rojo se queda pegado');

/* 1b. LOS GASTOS SE PREGUNTAN.
 *
 * El 20 de agosto se le pagaron 25.000 al celador y no quedaron en
 * ninguna parte: cero egresos registrados, y el cierre salió "cuadrado"
 * con un gasto real fuera de la cuenta. Nadie se acuerda de ir a otra
 * pestaña justo cuando está cerrando, así que si no hay ninguno hay que
 * decir que de verdad no hubo. */
await pagina.fill('#c-contado', '150000');
await pagina.click('#btn-cerrar-caja');
await pagina.waitForTimeout(300);
const porGastos = (await pagina.locator('#avisos .nota').first().innerText()).replace(/\s+/g, ' ');
/gastos hoy/i.test(porGastos)
  ? bien('sin gastos registrados, no deja cerrar sin confirmarlo', porGastos.trim())
  : falla('el freno de los gastos', porGastos);

await pagina.check('#c-sin-gastos');
(await pagina.locator('#c-sin-gastos').isChecked())
  ? bien('y se confirma de un toque')
  : falla('la casilla de sin gastos', 'no se pudo marcar');

// 2. Dejar más de lo contado: se atrapa antes de salir al servidor y
//    señala el otro campo, no el mismo.
await pagina.fill('#c-dejado', '999999');
await pagina.click('#btn-cerrar-caja');
await pagina.waitForTimeout(300);
(await pagina.locator('#c-dejado').evaluate(e => e.classList.contains('malo-campo')))
  ? bien('señala el campo correcto de los dos')
  : falla('señala el campo correcto', '#c-dejado no quedó marcado');
await pagina.fill('#c-dejado', '100000');

// 3. Un error del servidor llega traducido, no en clave.
//    Se usa DIA_CERRADO y no DEJADO_MAYOR_QUE_CONTADO: ese texto es
//    idéntico al de la validación del navegador, así que la prueba no
//    podría distinguir cuál de las dos respondió — y de hecho antes
//    pasaba por la del navegador sin llegar nunca al servidor.
await pagina.fill('#c-contado', '150000');
await pagina.fill('#c-dejado', '100000');
errorCierre = 'DIA_CERRADO';
await pagina.click('#btn-cerrar-caja');
await pagina.waitForTimeout(500);
const trad = (await pagina.locator('#avisos .nota').first().innerText()).replace(/\s+/g, ' ');
/El día ya está cerrado/.test(trad) && !/DIA_CERRADO/.test(trad)
  ? bien('el error del servidor llega en español, no en clave', trad.trim())
  : falla('la traducción del error', trad);

// 4. Y el camino bueno: cerrar el día de verdad. Esto es lo que estaba
//    roto en producción y ninguna prueba tocaba.
errorCierre = null;
await pagina.click('#btn-cerrar-caja');
await pagina.waitForTimeout(700);
const okCierre = (await pagina.locator('#avisos .nota').first().innerText()).replace(/\s+/g, ' ');
/Día cerrado/.test(okCierre)
  ? bien('CERRAR EL DÍA funciona', okCierre.trim())
  : falla('cerrar el día', okCierre);

// Los avisos buenos se van solos; los malos se quedan hasta que alguien
// los lea. Un error que desaparece a los 4 segundos no se leyó.
await pagina.waitForTimeout(4500);
const quedan = await pagina.locator('#avisos .nota').allInnerTexts();
!quedan.some(t => /Día cerrado/.test(t)) && quedan.some(t => /ya está cerrado/.test(t))
  ? bien('lo bueno se va solo, lo malo se queda')
  : falla('la caducidad de los avisos', JSON.stringify(quedan));

// En celular la pila de avisos tapaba la cabecera y las tarjetas. Se
// comprueba en 414px de ancho, que es donde se atiende el mostrador.
await pagina.setViewportSize({ width: 414, height: 900 });
await pagina.waitForTimeout(200);
for (let i = 0; i < 4; i++) {
  await pagina.evaluate(() => document.querySelector('#caja-recargar').click());
  await pagina.waitForTimeout(120);
}
await botonCaja('Clase suelta').click();
await pagina.waitForTimeout(250);
await pagina.click('#modal-guardar');
await pagina.waitForTimeout(400);
await botonCaja('Cumpleaños').click();
await pagina.waitForTimeout(250);
await pagina.click('#modal-guardar');
await pagina.waitForTimeout(500);

const apilados = await pagina.locator('#avisos .nota').count();
apilados <= 2
  ? bien('en celular no se apilan más de dos avisos', `${apilados}`)
  : falla('los avisos tapan la pantalla en celular', `${apilados} apilados`);

// Y la cabecera tiene que seguir viéndose por debajo de ellos.
const tapada = await pagina.locator('#avisos').evaluate((e) => {
  const a = e.getBoundingClientRect();
  return a.height > window.innerHeight * 0.4;
});
!tapada
  ? bien('y no se comen media pantalla')
  : falla('los avisos ocupan más del 40% del alto en celular');

await pagina.setViewportSize({ width: 1280, height: 900 });

// ═══════════════ la tirilla ═══════════════
// El día ya quedó cerrado unas líneas más arriba.
await pagina.click('#caja-recargar');
await pagina.waitForTimeout(700);

// UN SOLO BOTÓN, TRES HOJAS. Antes eran dos botones que escribían los
// dos en el mismo `#tirilla`: había que imprimir, volver y volver a
// imprimir, y quien se olvidaba del segundo clic se quedaba sin con qué
// puntear el extracto.
(await pagina.locator('#caja-cierre').innerText()).includes('Imprimir el cierre')
  ? bien('cerrado, ofrece imprimir el cierre entero')
  : falla('el botón del cierre', 'no salió');

// LO QUE GARANTIZA EL CIERRE: con el día cerrado no entra nada más. Sin
// esto se podía cerrar a las 9, vender a las 9:05, y el papel impreso
// quedaba mintiendo.
await botonCaja('Clase suelta').click();
await pagina.waitForTimeout(250);
await pagina.click('#modal-guardar');
await pagina.waitForTimeout(600);
// El simulacro deja pasar el registro, así que lo que se comprueba aquí
// es que la pantalla NO invente movimientos sobre un día cerrado: la
// puerta de verdad es la de Postgres, y esa tiene su prueba en
// humo-abrir-cerrar.sql. Aquí basta con que el cierre siga en pie.
(await pagina.locator('#caja-cierre').innerText()).includes('Imprimir el cierre')
  ? bien('el cierre sigue en pie después de intentar registrar')
  : falla('el cierre se deshizo');

// ---- el cierre entero: un clic, tres hojas ----
await pagina.evaluate(() => document.querySelector('#btn-tirillas').click());
await pagina.waitForTimeout(400);

// Las tres hojas se leen POR SEPARADO y no como un solo texto pegado.
// Buena parte de lo que hay que comprobar es "esto sale en la hoja 3 y
// NO en la 1" —el arqueo del cajón en la hoja del punteo serían dos
// cajones distintos en la misma impresión—, y sobre las tres juntas eso
// no se puede afirmar.
const hojas = await pagina.evaluate(() =>
  Array.from(document.querySelectorAll('#tirilla .hoja'))
    .map(h => ({ id: h.id, texto: h.textContent })));
const hojaTexto = id => ((hojas.find(h => h.id === id) || {}).texto || '')
  .replace(/\s+/g, ' ');

hojas.length === 3
 && hojas.map(h => h.id).join(' ') === 'hoja-cierre hoja-plata hoja-punteo'
  ? bien('un clic saca las tres hojas, y en su orden',
         hojas.map(h => h.id).join(' '))
  : falla('las tres hojas del cierre', hojas.map(h => h.id).join(' ') || 'ninguna');

// Todo lo que sigue es la HOJA 1. Las otras dos tienen sus propias
// pruebas (tirilla-cuadre-puerta-banco y tirilla-cuando-pagaron).
const t = hojaTexto('hoja-cierre');

/TUMBAO/.test(t) && /CIERRE DE CAJA/.test(t)
  ? bien('la tirilla lleva encabezado')
  : falla('el encabezado de la tirilla', t.slice(0, 80));

// Se archivan sueltas: sin el número de hoja, tres papeles de dos días
// distintos encima del mostrador no se distinguen.
/HOJA 1 DE 3/.test(t) && /Hoja 1 de 3/.test(t)
  ? bien('la hoja dice cuál es, arriba y en el pie')
  : falla('la numeración de la hoja 1', t.slice(0, 120));

/* Tiene que responder lo que la dueña cruza contra su cuaderno de la
 * puerta: cuánta gente de clase suelta entró hoy y por cuál de las tres
 * puertas — no solo un total de entradas y salidas.
 *
 * LOS RÓTULOS CAMBIARON (eac3860, 507046b). Antes las tres puertas se
 * llamaban "Efectivo", "Transferencia, recepción" y "Transferencia,
 * página": nombraban el MEDIO de pago, que a quien cuadra el papel no
 * le dice nada. Ahora se llaman por de dónde vino la persona
 * —"Reservas página", "Reservas manuales", "Pagos en caja"—, y las dos
 * de mostrador van juntas en una sola línea porque en el mostrador se
 * cobra igual en efectivo que por transferencia.
 *
 * Se comprueban los tres rótulos y no uno: si volvieran a partirse por
 * medio de pago, o desapareciera una de las tres puertas, el papel
 * seguiría cuadrando y estaría escondiendo gente. */
/INGRESOS DEL DÍA/.test(t) && /Reservas página/.test(t)
 && /Reservas manuales/.test(t) && /Pagos en caja/.test(t)
 && /= Entradas/.test(t) && /SALIDAS/.test(t) && /= Salidas/.test(t)
  ? bien('desglosa las tres puertas por las que entró alguien, no solo un total')
  : falla('el desglose de entradas', t.slice(0, 300));

// Cada puerta con su cantidad de gente y su plata. El texto sale pegado
// (`#tirilla` está oculto, así que se lee textContent y no hay saltos de
// línea), de ahí el "manuales1" sin espacio.
/Reservas página2 · \$30\.000/.test(t) && /Reservas manuales1 · \$15\.000/.test(t)
 && /Pagos en caja4 · \$60\.000/.test(t)
  ? bien('cada puerta dice cuánta gente y cuánta plata',
         (t.match(/Reservas página[^C]*/) || [])[0])
  : falla('las cifras de cada puerta', t.slice(0, 300));

/* LA CUENTA DE PERSONAS LA MANDA EL SERVIDOR, NO LA SUMA DEL PAPEL.
 *
 * El simulacro manda personas_n = 8 con unas casillas que suman 7: es
 * el caso de la 0059 —quien entró con una clase reprogramada pagó otro
 * día y no está en ninguna casilla de dinero de hoy—. Si el panel
 * volviera a sumar las casillas imprimiría 7, que es el error del 28 de
 * agosto: el papel decía 10 y por la puerta habían entrado 11. */
/8 personas a clase suelta/.test(t) && !/7 personas a clase suelta/.test(t)
  ? bien('la gente que entró la cuenta el servidor, no la suma de las casillas')
  : falla('la cuenta de personas', t.slice(0, 300));

// El signo, delante del peso. "$-5.000" en papel se lee mal.
!/\$-/.test(t)
  ? bien('los negativos salen como −$5.000, no $-5.000')
  : falla('el signo del negativo', (t.match(/\$-[\d.]+/) || [])[0]);

/* El arqueo del efectivo, que antes se titulaba "AL ABRIR" y ahora es
 * la sección "CAJA 1". Se dejó de comprobar solo el conteo de la
 * apertura y se comprueban los tres números que hacen falta para que el
 * veredicto de abajo signifique algo: con cuánto se abrió, cuánto
 * debería haber y cuánto se contó. Sin "Debía haber" el "NO CUADRA" es
 * una palabra sin nada contra qué comprobarla. */
// "Se abrió con" y no "Base al abrir": la dueña tachó el rótulo viejo
// en el margen del papel del 29 de agosto. "Base" es palabra de
// contador; quien abre la caja a las nueve la abre con algo.
/CAJA 1/.test(t) && /Se abrió con\$95\.000/.test(t)
 && /Debía haber/.test(t) && /Se contó/.test(t)
  ? bien('el arqueo trae con cuánto se abrió, cuánto debía haber y cuánto se contó',
         (t.match(/CAJA 1.*?Se contó\$[\d.]+/) || [])[0])
  : falla('el arqueo en la tirilla', t.slice(0, 300));

/* SE BORRÓ: "trae los cuatro números de AdminGym".
 *
 * Comprobaba "COMPARAR CON ADMINGYM" y "DINERO EN CAJA" en la tirilla.
 * Esa sección ya no existe en `pintarTirilla`: se quitó a propósito
 * —el comentario del código lo dice, "cada seccion extra era una cifra
 * mas que interpretar en el unico momento del dia en que hay prisa"— y
 * los cuatro números de AdminGym viven ahora solo en la pantalla del
 * cierre, que es donde se copian. No se relajó la aserción: se borró,
 * porque lo que comprobaba ya no debe estar. Lo que sí sigue
 * comprobándose, unas líneas más arriba, es que la PANTALLA del cierre
 * siga nombrando AdminGym ("el cierre muestra los nombres de AdminGym").
 *
 * En su lugar va lo que sí ocupa ese sitio en el papel de hoy, y con el
 * rótulo importa cuál: el código lleva un aviso en mayúsculas de no
 * devolver "BANCOLOMBIA REPORTÓ HOY", porque esa cifra no es lo que
 * dice el extracto sino lo que el sistema alcanzó a registrar, y con el
 * nombre viejo el papel juraba que el banco había reportado de menos.
 * Por eso se comprueba también que el rótulo viejo NO esté. */
/DEPÓSITOS REGISTRADOS HOY/.test(t) && /Total registrado\$330\.000/.test(t)
 && !/BANCOLOMBIA REPORTÓ/i.test(t) && !/Entró al banco/i.test(t)
  ? bien('los depósitos del día se llaman registrados, no reportados por el banco')
  : falla('los depósitos registrados en la tirilla', t.slice(0, 300));

// La razón de ser del cierre: lo que hay que buscar en el extracto a
// mano. Sin depósitos por verificar tiene que decirlo, no dejar el
// hueco en blanco — un espacio vacío se lee como "se me olvidó".
/POR REVISAR/.test(t) && /NADA POR REVISAR/.test(t)
  ? bien('si no hay nada que revisar, lo dice')
  : falla('la sección de por revisar', t.slice(0, 300));

// El veredicto tiene que verse solo, sin tener que restar nada.
/SÍ CUADRA|NO CUADRA/.test(t)
  ? bien('dice si cuadra o no, en una palabra',
         (t.match(/SÍ CUADRA[^—]*|NO CUADRA[^—]*—[^A-Z]*/) || [])[0])
  : falla('el veredicto de cuadre', t.slice(0, 300));

/Firma/.test(t)
  ? bien('y una línea para firmar') : falla('la firma');

// En pantalla no se ve: solo existe al imprimir.
(await pagina.locator('#tirilla').isHidden())
  ? bien('en pantalla la tirilla no estorba')
  : falla('la tirilla se ve en pantalla');

/* ---- las hojas 2 y 3, del MISMO clic ----
 * Antes esto pulsaba un segundo botón. Ya no existe: el cierre son tres
 * hojas y salen las tres o no sale ninguna. Lo que se comprueba aquí es
 * que la 2 y la 3 salieran de verdad en la misma impresión y que cada
 * una siga siendo su propio papel — si el arqueo del cajón se colara en
 * la del punteo, habría dos cajones distintos en el mismo fajo.
 *
 * La hoja 3 se lleva al lado del extracto y contesta "¿de la gente que
 * entró hoy, qué renglón del banco es cada una?"; la 1 se archiva con
 * el efectivo y contesta "¿cuadró el día?". */
const p2 = hojaTexto('hoja-plata');
const p3 = hojaTexto('hoja-punteo');

/EL PUNTEO, PAGO POR PAGO/.test(p3) && !/CIERRE DE CAJA/.test(p3)
 && !/CAJA 1/.test(p3)
  ? bien('la hoja del punteo es su propio papel, no el del cierre')
  : falla('la hoja del punteo', p3.slice(0, 200));

/* LO QUE PIDIÓ EL DUEÑO: que el papel PRECISE qué es efectivo y qué
 * transferencia, y de entrada, no al final. Confundirlos es una noche
 * buscando en el extracto una plata que estaba en el cajón. */
/EFECTIVO O TRANSFERENCIA/.test(p3) && /se busca en el extracto/.test(p3)
 && /NO aparece en el extracto/.test(p3)
  ? bien('el punteo separa lo que se busca en el banco de lo que está en el cajón')
  : falla('efectivo contra transferencia', p3.slice(0, 300));

/* EL PUENTE ENTRE LAS DOS CIFRAS QUE NUNCA SE PARECEN (0064).
 *
 * El papel del 29 de agosto decía "Entradas del día $360.000" y debajo
 * una cifra del banco mucho menor, y la dueña restaba a mano en el
 * margen. Las dos estaban bien: de las 21 que entraron, 16 habían
 * pagado días antes y su plata está en el extracto de otro día. Estas
 * dos secciones son la explicación, y por eso van arriba del todo. */
/QUIÉN ENTRÓ HOY/.test(p2) && /Entraron a clase21 personas/.test(p2)
 && /ya habían pagado antes16/.test(p2) && /pagaron hoy5 · \$75\.000/.test(p2)
  ? bien('separa a quien entró hoy de quien ya había pagado antes')
  : falla('quién entró hoy', p2.slice(0, 300));

// Cupos Y depósitos, en ese orden: tres amigas con un solo pago son 3
// cupos y 1 renglón del extracto. Si dijera solo "3" habría que buscar
// tres renglones que no existen.
/QUÉ SE REGISTRÓ HOY/.test(p2) && /Clases futuras3 cupos · 1 depósito · \$45\.000/.test(p2)
 && /= Depósitos registrados hoy\$245\.000/.test(p2)
  ? bien('lo pagado por adelantado va en cupos Y en renglones del extracto')
  : falla('qué se registró hoy', p2.slice(0, 400));

// El ancho es de rollo, no de folio: a 210mm la impresora del mostrador
// la parte en dos. Se lee el texto del <style>, no el CSSOM: las reglas
// @page dentro de @media no se serializan igual en todos los motores y
// la prueba diría que falta algo que sí está.
const hayRollo = await pagina.evaluate(() =>
  [...document.querySelectorAll('style')].some(e => /@page\s*\{[^}]*80mm/.test(e.textContent)));
hayRollo
  ? bien('el papel es de 80mm, no de carta')
  : falla('el tamaño de página', 'no encontré @page con 80mm');

errores.length === 0
  ? bien('sin errores de consola', 'ninguno')
  : falla('sin errores de consola', errores.slice(0, 3).join(' | '));

await navegador.close();
servidor.close();
console.log(`\n${mal ? mal + ' FALLOS' : 'todo en verde'}  (${ok} comprobaciones)\n`);
process.exit(mal ? 1 : 0);
