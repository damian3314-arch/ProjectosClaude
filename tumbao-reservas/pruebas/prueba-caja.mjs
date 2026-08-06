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

// Lo que de verdad importa: cualquier error de consola es un fallo.
const errores = [];
pagina.on('console', (m) => { if (m.type() === 'error') errores.push(m.text()); });
pagina.on('pageerror', (e) => errores.push('JS: ' + e.message));

// ---- se finge el backend ----
let movimientos = [];
let idSeq = 0;

const dia = () => ({
  ok: true, dia: '2026-08-05',
  movimientos,
  base_cop: 100000,
  ingreso_efectivo: suma('ingreso', 'efectivo'),
  egreso_efectivo: suma('egreso', 'efectivo'),
  esperado_efectivo: 100000 + suma('ingreso', 'efectivo') - suma('egreso', 'efectivo'),
  ingreso_transferencia: suma('ingreso', 'transferencia'),
  egreso_transferencia: suma('egreso', 'transferencia'),
  reservas_cop: 15000,
  total_ingresos: suma('ingreso', 'efectivo') + suma('ingreso', 'transferencia') + 15000,
  total_egresos: suma('egreso', 'efectivo') + suma('egreso', 'transferencia'),
  contra_admingym: {
    venta_membresias: suma('ingreso', 'efectivo'),
    ingresos_a_banco: suma('ingreso', 'transferencia') + 15000,
    retirar_dinero_de_caja: suma('egreso', 'efectivo'),
    dinero_en_caja: 100000 + suma('ingreso', 'efectivo') - suma('egreso', 'efectivo'),
  },
  banco: banco(),
  pagos_libres: libres,
  cerrado: false, cierre: null,
});

// El inventario del banco: depósitos que llegaron y nadie ha reclamado.
// `hayBanco` en false simula que la migración 0027 todavía no se pegó.
let hayBanco = false;
let libres = [];
const banco = () => {
  if (!hayBanco) return undefined;
  const sinResp = movimientos.filter(
    m => m.sentido === 'ingreso' && m.medio === 'transferencia' && !m.pago_id);
  return {
    recibido_cop: 15000,
    libre_cop: libres.reduce((a, p) => a + p.valor_cop, 0),
    libre_n: libres.length,
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
  } else if (url.endsWith('/anular')) {
    const m = movimientos.find((x) => x.id === b.id);
    movimientos = movimientos.filter((x) => x.id !== b.id);
    r = { ok: true, concepto: m?.concepto, valor_cop: m?.valor_cop };
  }
  await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(r) });
});

// n8n: lo mínimo para que el panel arranque y no estorbe.
await pagina.route('**/barragan.app.n8n.cloud/**', async (route) => {
  const u = route.request().url();
  let r = { ok: true };
  if (u.includes('/semana')) r = { ok: true, dias: [] };
  else if (u.includes('/pendientes')) r = { ok: true, reservas: [] };
  else if (u.includes('/tablero')) r = { ok: true, dia: '2026-08-05', clases: [],
    resumen: { libres: 0, en_sala: 0, reservadas: 0, confirmadas: 0, por_validar: 0, ingreso_cop: 0 } };
  await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(r) });
});

console.log('\n── La caja, en un navegador de verdad ──\n');
await pagina.goto(`http://localhost:${PUERTO}/admin.html`, { waitUntil: 'domcontentloaded' });

// Entrar
await pagina.fill('#token', 'token-de-prueba');
await pagina.click('#btn-entrar');
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

const enCajon = async () => (await pagina.locator('#caja-tiles .tile .n').first().innerText()).trim();
(await enCajon()) === '$100.000'
  ? bien('arranca en $100.000') : falla('arranca en $100.000', await enCajon());

// Los recuadros se pintaban con <b><span><small>, etiquetas que el CSS
// del panel no conoce: salía "$100.000en el cajónbase + efectivo".
// Pasaba todas las pruebas porque el número sí estaba. Esto mira que
// cifra, título y pista sean tres bloques, no una frase pegada.
const primerTile = pagina.locator('#caja-tiles .tile').first();
const partes = await primerTile.evaluate((e) =>
  ['.n', '.k', '.pista'].map((s) => e.querySelector(s)?.textContent.trim() || null));
partes.every(Boolean)
  ? bien('el recuadro va en tres renglones', partes.join(' / '))
  : falla('el recuadro va en tres renglones', 'texto pegado: ' + (await primerTile.innerText()).trim());

// Registrar una clase suelta
await pagina.locator('.caja-btn', { hasText: 'Clase suelta' }).click();
await pagina.waitForTimeout(300);
const valorPrecargado = await pagina.inputValue('#modal-valor');
valorPrecargado === '15000'
  ? bien('la ventana precarga $15.000') : falla('la ventana precarga $15.000', valorPrecargado);

await pagina.click('#modal-guardar');
await pagina.waitForTimeout(700);
(await enCajon()) === '$115.000'
  ? bien('al guardar sube a $115.000') : falla('al guardar sube a $115.000', await enCajon());

const nMovs = await pagina.locator('.mov').count();
nMovs === 1 ? bien('aparece en la lista') : falla('aparece en la lista', `hay ${nMovs}`);

// Un egreso con monto libre
await pagina.locator('.caja-btn', { hasText: 'Profesores' }).click();
await pagina.waitForTimeout(300);
await pagina.fill('#modal-valor', '80.000');           // con punto, como teclea la cajera
await pagina.click('#modal-guardar');
await pagina.waitForTimeout(700);
(await enCajon()) === '$35.000'
  ? bien('el egreso resta y entiende "80.000"') : falla('el egreso resta', await enCajon());

// Anular
await pagina.locator('[data-anular]').first().click();
await pagina.waitForTimeout(700);
const tras = await enCajon();
tras === '$115.000' ? bien('anular devuelve el cupo de plata') : falla('anular', tras);

// El cierre está a la vista
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

// EL CASO QUE MANDA: transfirió hace dos días, llega hoy. Es lo que
// rompía el diseño anterior, que restaba el banco de hoy contra la caja
// de hoy y daba un negativo que acusaba a un cliente honesto.
hayBanco = true;
libres = [{ id: 'cccccccc-0000-4000-8000-000000000001', valor_cop: 15000,
            cuando: '03/08 14:12', dias: 2, remitente: 'CAMILA ROJAS' }];
await recargar();

/15\.000 sin identificar · 1 depósito/.test(await pista())
  ? bien('el depósito de hace dos días sigue contado', await pista())
  : falla('el depósito de hace dos días', await pista());

(await tarjeta.locator('.corte').innerText()).includes('7:42 pm')
  ? bien('dice hasta qué hora es la cifra', 'Bancolombia, hasta las 7:42 pm')
  : falla('la hora de corte', await tarjeta.locator('.corte').innerText());

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

const dep = pagina.locator('.dep').first();
const txtDep = (await dep.innerText()).replace(/\s+/g, ' ').trim();
/CAMILA ROJAS/.test(txtDep) && /hace 2 días/.test(txtDep)
  ? bien('el depósito dice de quién es y de cuándo', txtDep)
  : falla('el depósito dice de quién es', txtDep);

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

/todo identificado/.test(await pista())
  ? bien('adjudicado, el inventario queda limpio', await pista())
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
(await pagina.locator('.dep-vacio').count()) === 1
  ? bien('sin depósitos libres lo dice claro, no deja el hueco en blanco')
  : falla('sin depósitos libres', 'no salió el aviso');

await pagina.click('#modal-guardar');
await pagina.waitForTimeout(800);

const cierreTxt = await pagina.locator('#caja-cierre').innerText();
/Apuntado sin respaldo del banco/.test(cierreTxt) && /125\.000/.test(cierreTxt)
  ? bien('lo apuntado sin respaldo sale contado aparte en el cierre')
  : falla('sin respaldo en el cierre', cierreTxt.slice(0, 160));

// Lo que ya no puede pasar: que un desfase de fechas se pinte de rojo.
// Rojo estaba reservado para "comprobante falso" y disparaba solo por
// llegar tarde, que es lo normal.
const cls = await tarjeta.getAttribute('class');
!cls.includes('malo')
  ? bien('nunca se pone en rojo por un desfase de fechas')
  : falla('rojo por desfase', cls);

// El color se comprueba computado y no por la clase: la fila del banco
// es una `.fila.total` y su cifra es el último hijo, así que el oro del
// total le ganaba por especificidad y el semáforo no se veía.
const difs = pagina.locator('#caja-cierre .grupo.banco .dif');
const color = i => difs.nth(i).evaluate(e => getComputedStyle(e).color);

// Fila 1: sin identificar. Está en cero, así que verde.
(await color(0)) === 'rgb(74, 222, 128)'
  ? bien('el inventario en cero se pinta verde')
  : falla('el color del inventario', await color(0));

// Fila 2: apuntado sin respaldo. Hay 125.000, así que ámbar — nunca
// rojo, porque la pantalla no puede saber si fue Nequi o un engaño.
(await color(1)) === 'rgb(255, 193, 77)'
  ? bien('lo que falta por respaldar se pinta ámbar, no del oro del total')
  : falla('el color del sin respaldo', await color(1));

// Lo que no puede pasar: que un descuadre del banco impida cerrar. El
// cierre lo manda el efectivo, que es lo único que se cuenta a mano.
await pagina.locator('#btn-cerrar-caja').isEnabled()
  ? bien('el descuadre del banco NO bloquea el cierre')
  : falla('el descuadre del banco NO bloquea el cierre', 'el botón quedó deshabilitado');

errores.length === 0
  ? bien('sin errores de consola', 'ninguno')
  : falla('sin errores de consola', errores.slice(0, 3).join(' | '));

await navegador.close();
servidor.close();
console.log(`\n${mal ? mal + ' FALLOS' : 'todo en verde'}  (${ok} comprobaciones)\n`);
process.exit(mal ? 1 : 0);
