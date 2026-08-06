/**
 * Apuntar a alguien a mano, con un navegador de verdad.
 *
 * POR QUÉ EXISTE
 * Es la pantalla que reemplaza el rodeo de "abrir la página del cliente
 * y fingir que soy ella". Toca plata y toca aforo, así que lo que no
 * puede pasar es que parezca que apuntó y no haya apuntado, o que
 * apunte a alguien en una clase llena.
 *
 * Aquí se comprueba lo segundo de verdad: el servidor falso responde
 * SIN_CUPO y la prueba exige que ese mensaje llegue a la pantalla. Un
 * modal que se cierra en silencio ante SIN_CUPO sería peor que no tener
 * el botón.
 */
import { chromium } from 'playwright-core';
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { extname, join } from 'node:path';

const RAIZ = new URL('../../docs/', import.meta.url).pathname;
const CHROME = '/opt/pw-browsers/chromium-1194/chrome-linux/chrome';
const PUERTO = 8124;

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

// Esta prueba provoca un 400 a propósito (el SIN_CUPO), y el navegador
// apunta todo 4xx en la consola. Ese ruido se descarta; lo que no se
// descarta es un error de JavaScript, que es lo que dejó la caja sin
// abrir dos despliegues seguidos.
const errores = [];
const ruido = (t) => /Failed to load resource/.test(t);
pagina.on('console', (m) => {
  if (m.type() === 'error' && !ruido(m.text())) errores.push(m.text());
});
pagina.on('pageerror', (e) => errores.push('JS: ' + e.message));

const CLASE = '11111111-2222-4333-8444-555555555555';

// La gente que ya está apuntada a esa clase. Crear a mano la hace crecer.
let gente = [{ codigo: 'TB-0001', nombre: 'Ana Ruiz', telefono: '3001112233',
               estado: 'confirmada', tipo: 'suelta', asistio: false }];
let loQuePidio = null;       // lo último que el panel mandó a /api/reserva
let respuesta = null;        // qué se le va a contestar

await pagina.route('**/barragan.app.n8n.cloud/**', async (route) => {
  const u = route.request().url();
  let r = { ok: true };
  if (u.includes('/semana')) r = { ok: true, dias: [] };
  else if (u.includes('/pendientes')) r = { ok: true, reservas: [] };
  else if (u.includes('/tablero')) r = {
    ok: true, dia: '2026-08-05',
    clases: [{ clase_id: CLASE, hora: '18:00', aforo: 20, libres: 5, en_sala: 15,
               con_plan: 10, reservadas: gente.length, a_la_venta: 10, vencen: 0,
               ya_paso: false, activa: true }],
    resumen: { libres: 5, en_sala: 15, reservadas: gente.length, confirmadas: gente.length,
               por_validar: 0, ingreso_cop: 0, aforo: 20 },
  };
  else if (u.includes('/lista')) r = {
    ok: true,
    clase: { clase_id: CLASE, hora: '18:00', fecha: '2026-08-05' },
    resumen: { entraron: 0, esperados: gente.length, sin_confirmar: 0 },
    reservas: gente, con_plan: [],
  };
  await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(r) });
});

await pagina.route('**/tumbao-caja.*/api/**', async (route) => {
  const url = route.request().url();
  const b = JSON.parse(route.request().postData() || '{}');
  if (!url.endsWith('/reserva')) {
    await route.fulfill({ status: 200, contentType: 'application/json',
                          body: JSON.stringify({ ok: true }) });
    return;
  }
  loQuePidio = b;
  if (respuesta) {
    await route.fulfill({ status: 400, contentType: 'application/json',
                          body: JSON.stringify(respuesta) });
    return;
  }
  gente = gente.concat([{ codigo: 'TB-0042', nombre: b.nombre, telefono: b.telefono,
                          estado: 'confirmada', tipo: b.tipo, asistio: false }]);
  await route.fulfill({ status: 200, contentType: 'application/json',
    body: JSON.stringify({ ok: true, codigo: 'TB-0042', nombre: b.nombre,
                           telefono: b.telefono, tipo: b.tipo }) });
});

console.log('\n── Apuntar a mano, en un navegador de verdad ──\n');
await pagina.goto(`http://localhost:${PUERTO}/admin.html`, { waitUntil: 'domcontentloaded' });
await pagina.fill('#token', 'token-de-prueba');
await pagina.click('#btn-entrar');
await pagina.waitForSelector('#app:not([hidden])', { timeout: 8000 })
  .then(() => bien('entra al panel'))
  .catch(() => falla('entra al panel', 'el panel nunca apareció'));

// Abrir la clase: el botón vive donde ya está parada la recepcionista.
await pagina.locator('.clase-card[data-clase]').first().click();
await pagina.waitForTimeout(500);
(await pagina.locator('#puerta-apuntar').isVisible())
  ? bien('el botón está en la lista de la clase')
  : falla('el botón está en la lista de la clase', 'no se ve');

await pagina.click('#puerta-apuntar');
await pagina.waitForTimeout(300);
(await pagina.locator('#modal-apuntar').isVisible())
  ? bien('la ventana abre') : falla('la ventana abre', 'sigue oculta');

const cabecera = (await pagina.locator('#ap-clase').innerText()).trim();
/6:00 pm/.test(cabecera)
  ? bien('dice a qué clase se está apuntando', cabecera)
  : falla('dice a qué clase se está apuntando', cabecera);

// ---- lo que no se puede tragar: SIN_CUPO ----
respuesta = { ok: false, error: 'SIN_CUPO', mensaje: 'Esa clase se llenó.' };
await pagina.fill('#ap-nombre', 'Carla Prieto');
await pagina.fill('#ap-tel', '300 445 6677');
await pagina.click('#ap-guardar');
await pagina.waitForTimeout(600);

(await pagina.locator('#modal-apuntar').isVisible())
  ? bien('con SIN_CUPO la ventana NO se cierra')
  : falla('con SIN_CUPO la ventana NO se cierra', 'se cerró como si hubiera apuntado');

// El motivo sale en el aviso flotante, encima de la ventana: si
// quedara dentro de la ventana y ésta estuviera a media pantalla en un
// portátil pequeño, el mensaje no se vería.
const err = (await pagina.locator('#avisos .nota').first().innerText()).replace(/\s+/g, ' ');
/Esa clase está llena/.test(err)
  ? bien('y el motivo se lee en pantalla, traducido', err.trim())
  : falla('el motivo del rechazo', err || '(vacío)');

// ---- el camino bueno ----
respuesta = null;
await pagina.click('#ap-guardar');
await pagina.waitForTimeout(900);

!(await pagina.locator('#modal-apuntar').isVisible())
  ? bien('al apuntar bien, la ventana se cierra')
  : falla('al apuntar bien, la ventana se cierra', 'quedó abierta');

// El celular tiene que viajar en dígitos: si va "300 445 6677", el
// mismo cliente termina con dos celulares distintos según por dónde
// entró, y buscarlo en la puerta deja de funcionar.
loQuePidio && loQuePidio.telefono === '3004456677'
  ? bien('el celular va limpio de espacios', loQuePidio.telefono)
  : falla('el celular va limpio de espacios', loQuePidio && loQuePidio.telefono);

loQuePidio && loQuePidio.clase_id === CLASE
  ? bien('manda la clase que estaba abierta')
  : falla('manda la clase que estaba abierta', loQuePidio && loQuePidio.clase_id);

const lista = await pagina.locator('#lista-puerta').innerText();
/Carla Prieto/.test(lista)
  ? bien('aparece ya en la lista de la puerta')
  : falla('aparece ya en la lista de la puerta', 'no está');

const okMsg = (await pagina.locator('#msg-puerta').innerText()).trim();
/TB-0042/.test(okMsg)
  ? bien('le dice el código a la recepcionista', okMsg)
  : falla('le dice el código a la recepcionista', okMsg || '(vacío)');

// ---- lo que se rechaza sin molestar al servidor ----
await pagina.click('#puerta-apuntar');
await pagina.waitForTimeout(300);
loQuePidio = null;
await pagina.fill('#ap-nombre', 'Luis');
await pagina.fill('#ap-tel', '30044');
await pagina.click('#ap-guardar');
await pagina.waitForTimeout(400);
const corto = (await pagina.locator('#avisos .nota').first().innerText()).replace(/\s+/g, ' ');
(loQuePidio === null && /10 dígitos/.test(corto))
  ? bien('un celular corto ni sale del navegador')
  : falla('un celular corto ni sale del navegador', corto);

// Y señala el campo, no solo avisa: en una ventana con nombre, celular
// y nota, "el celular no sirve" no dice dónde hay que ir.
(await pagina.locator('#ap-tel').evaluate(e => e.classList.contains('malo-campo')))
  ? bien('y marca en rojo el celular')
  : falla('marcar el celular', 'no quedó marcado');

errores.length === 0
  ? bien('sin errores de consola', 'ninguno')
  : falla('sin errores de consola', errores.slice(0, 3).join(' | '));

await navegador.close();
servidor.close();
console.log(`\n${mal ? mal + ' FALLOS' : 'todo en verde'}  (${ok} comprobaciones)\n`);
process.exit(mal ? 1 : 0);
