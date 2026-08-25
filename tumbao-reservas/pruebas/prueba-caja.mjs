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
const suma = (s, m) => movimientos.filter((x) => x.sentido === s && x.medio === m)
                                  .reduce((a, b) => a + b.valor_cop, 0);

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

const nTarjetas = await pagina.locator('.caja-btn').count();
nTarjetas === 9 ? bien('salen las 9 tarjetas') : falla('salen las 9 tarjetas', `salieron ${nTarjetas}`);

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
await pagina.locator('.caja-btn', { hasText: 'Clase suelta' }).click();
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
await pagina.locator('.caja-btn', { hasText: 'Profesores' }).click();
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
await pagina.locator('.caja-btn', { hasText: 'Mensualidad' }).click();
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
await pagina.locator('.caja-btn', { hasText: 'Clase suelta' }).click();
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

// Escogerlo trae el valor del banco: si la cajera teclea otra cosa,
// Postgres rechaza el enlace, así que mejor que aquí ya cuadre.
await pagina.fill('#modal-valor', '99999');
await dep.click();
await pagina.waitForTimeout(200);
(await pagina.inputValue('#modal-valor')) === '15000'
  ? bien('escoger el depósito trae el valor del banco')
  : falla('el valor del depósito', await pagina.inputValue('#modal-valor'));

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
await pagina.locator('.caja-btn', { hasText: 'Mensualidad' }).click();
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
await pagina.locator('.caja-btn', { hasText: 'Clase suelta' }).first().click();
await pagina.waitForTimeout(250);
await pagina.click('#modal-guardar');
await pagina.waitForTimeout(400);
await pagina.locator('.caja-btn', { hasText: 'Cumpleaños' }).first().click();
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

(await pagina.locator('#caja-cierre').innerText()).includes('Imprimir la tirilla')
  ? bien('cerrado, ofrece imprimir la tirilla')
  : falla('el botón de la tirilla', 'no salió');

// LO QUE GARANTIZA EL CIERRE: con el día cerrado no entra nada más. Sin
// esto se podía cerrar a las 9, vender a las 9:05, y el papel impreso
// quedaba mintiendo.
await pagina.locator('.caja-btn', { hasText: 'Clase suelta' }).first().click();
await pagina.waitForTimeout(250);
await pagina.click('#modal-guardar');
await pagina.waitForTimeout(600);
// El simulacro deja pasar el registro, así que lo que se comprueba aquí
// es que la pantalla NO invente movimientos sobre un día cerrado: la
// puerta de verdad es la de Postgres, y esa tiene su prueba en
// humo-abrir-cerrar.sql. Aquí basta con que el cierre siga en pie.
(await pagina.locator('#caja-cierre').innerText()).includes('Imprimir la tirilla')
  ? bien('el cierre sigue en pie después de intentar registrar')
  : falla('el cierre se deshizo');

// ---- la tirilla ----
await pagina.evaluate(() => document.querySelector('#btn-tirilla').click());
await pagina.waitForTimeout(400);

const tirilla = (await pagina.locator('#tirilla').innerText({ timeout: 3000 })
  .catch(() => '')) || await pagina.locator('#tirilla').evaluate(e => e.textContent);
const t = tirilla.replace(/\s+/g, ' ');

/TUMBAO/.test(t) && /CIERRE DE CAJA/.test(t)
  ? bien('la tirilla lleva encabezado')
  : falla('el encabezado de la tirilla', t.slice(0, 80));

// Tiene que decir de QUÉ fue la plata. Una tirilla con solo totales
// obliga a volver a la pantalla, y entonces no reemplaza a la pantalla.
/ENTRÓ/.test(t) && /SALIÓ/.test(t) && /Clase suelta/.test(t)
  ? bien('desglosa por concepto, no solo totales')
  : falla('el desglose', t.slice(0, 220));

// Y agrupa: veinte líneas iguales no caben en un rollo de 80mm.
/Clase suelta x\d/.test(t)
  ? bien('agrupa los repetidos con su cantidad',
         (t.match(/Clase suelta x\d/) || [])[0])
  : falla('no agrupó los repetidos', t.slice(0, 220));

// El signo, delante del peso. "$-5.000" en papel se lee mal.
!/\$-/.test(t)
  ? bien('los negativos salen como −$5.000, no $-5.000')
  : falla('el signo del negativo', (t.match(/\$-[\d.]+/) || [])[0]);

/APERTURA/.test(t) && /95\.000/.test(t)
  ? bien('deja constancia de la apertura y su conteo')
  : falla('la apertura en la tirilla', t.slice(0, 200));

/CONTRA ADMINGYM/.test(t) && /DINERO EN CAJA/.test(t)
  ? bien('trae los cuatro números de AdminGym')
  : falla('AdminGym en la tirilla', t.slice(0, 200));

/Firma/.test(t)
  ? bien('y una línea para firmar') : falla('la firma');

// En pantalla no se ve: solo existe al imprimir.
(await pagina.locator('#tirilla').isHidden())
  ? bien('en pantalla la tirilla no estorba')
  : falla('la tirilla se ve en pantalla');

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
