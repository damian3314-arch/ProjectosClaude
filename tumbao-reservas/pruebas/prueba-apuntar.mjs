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
let efectivoFalla = false;
let gente = [{ codigo: 'TB-0001', nombre: 'Ana Ruiz', telefono: '3001112233',
               estado: 'confirmada', tipo: 'suelta', asistio: false }];
let loQuePidio = null;       // lo último que el panel mandó a /api/reserva
let respuesta = null;        // qué se le va a contestar

// El panel ya no llama a n8n: el tablero y la lista de la clase van
// al Worker, en /api/admin/<ruta>.
await pagina.route('**/api/admin/**', async (route) => {
  const u = route.request().url();
  let r = { ok: true };
  if (u.endsWith('/semana')) r = { ok: true, dias: [] };
  else if (u.endsWith('/pendientes')) r = { ok: true, reservas: [] };
  else if (u.endsWith('/tablero')) r = {
    ok: true, dia: '2026-08-05',
    clases: [{ clase_id: CLASE, hora: '18:00', aforo: 20, libres: 5, en_sala: 15,
               con_plan: 10, reservadas: gente.length, a_la_venta: 10, vencen: 0,
               ya_paso: false, activa: true }],
    resumen: { libres: 5, en_sala: 15, reservadas: gente.length, confirmadas: gente.length,
               por_validar: 0, ingreso_cop: 0, aforo: 20 },
  };
  else if (u.endsWith('/lista')) r = {
    ok: true,
    clase: { clase_id: CLASE, hora: '18:00', fecha: '2026-08-05' },
    resumen: { entraron: 0, esperados: gente.length, sin_confirmar: 0 },
    reservas: gente, con_plan: [],
  };
  await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(r) });
});

await pagina.route('**/tumbao-caja.*/api/**', async (route) => {
  const url = route.request().url();
  // Playwright resuelve la ruta registrada MÁS TARDE primero, y este
  // patrón también casa con /api/admin/*. Sin este fallback se tragaba
  // el tablero y la lista de la clase, y la prueba fallaba diciendo que
  // no había clases cuando el problema era el orden de los simulacros.
  if (url.includes('/api/admin/')) return route.fallback();
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
  // Se imita lo que devuelve admin_crear_reserva desde la 0042: si el
  // pago fue en efectivo, la propia llamada registra el movimiento de
  // caja y lo dice. `efectivoFalla` permite probar el caso feo —el día
  // ya cerrado— sin tener que cerrar una caja de verdad.
  const enEfectivo = b.medio === 'efectivo';
  await route.fulfill({ status: 200, contentType: 'application/json',
    body: JSON.stringify({ ok: true, codigo: 'TB-0042', nombre: b.nombre,
                           telefono: b.telefono, tipo: b.tipo,
                           precio_cop: 15000, medio: b.medio ?? null,
                           cobra_en_puerta: b.medio === 'en_puerta',
                           efectivo_registrado: enEfectivo ? !efectivoFalla : null,
                           aviso_efectivo: (enEfectivo && efectivoFalla)
                             ? 'El día ya está cerrado. Este movimiento va mañana. '
                               + 'La reserva SÍ quedó: apunta esos 15.000 en la caja a mano.'
                             : null }) });
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
// Ya no hay medio por defecto: sin elegirlo, no deja mandar. Arrancaba
// en efectivo y eso cobró una vez plata que no existía.
await pagina.fill('#ap-nombre', 'Carla Prieto');
await pagina.fill('#ap-tel', '300 445 6677');

// Sin escoger cómo pagó no sale del navegador: de eso depende que el
// arqueo cuadre, así que no se adivina.
loQuePidio = null;
await pagina.click('#ap-guardar');
await pagina.waitForTimeout(400);
// El aviso va dentro de la ventana, pegado a los botones: el aviso
// flotante sale por encima del modal y tapaba justo lo que pedía pulsar.
const faltaMedio = (await pagina.locator('#ap-medio-pista').innerText()).replace(/\s+/g, ' ');
(loQuePidio === null && /ya pagó/i.test(faltaMedio))
  ? bien('sin decir cómo pagó, no deja apuntar', faltaMedio.trim())
  : falla('sin decir cómo pagó, no deja apuntar', faltaMedio || '(no avisó)');
(await pagina.locator('#ap-medio-pista.malo-campo').count()) === 1
  ? bien('y el aviso queda junto a los botones, sin taparlos')
  : falla('y el aviso queda junto a los botones, sin taparlos', 'no se marcó');

await pagina.locator('#modal-apuntar [data-apmedio="efectivo"]').click();
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

/* ─────────────────────────────────────────────────────────────
   Cómo pagó — lo que decide si el arqueo cuadra

   El 19 de agosto se apuntaron dos personas en efectivo en la puerta y
   solo una de las dos apareció en el cierre: la ventana no preguntaba
   el medio, así que esa plata solo llegaba a la caja si alguien se
   acordaba de registrarla aparte, en otra pestaña.
   ───────────────────────────────────────────────────────────── */
console.log('\n── Cómo pagó ──\n');

// Por defecto va en efectivo: es lo que más pasa en la puerta, y quien
// ya transfirió normalmente reservó solo desde la página.
loQuePidio && loQuePidio.medio === 'efectivo'
  ? bien('manda el medio que se eligió', loQuePidio.medio)
  : falla('manda el medio que se eligió',
          (loQuePidio && String(loQuePidio.medio)) || '(no mandó nada)');

// Que el efectivo entró tiene que decirse: es la confirmación de que
// esos 15.000 van a estar en el arqueo de esta noche.
/efectivo/i.test(okMsg) && /15\.000/.test(okMsg)
  ? bien('avisa que el efectivo entró a la caja', okMsg)
  : falla('avisa que el efectivo entró a la caja', okMsg);

// ── por transferencia ──
await pagina.click('#puerta-apuntar');
await pagina.waitForTimeout(300);
await pagina.fill('#ap-nombre', 'Elena Pardo');
await pagina.fill('#ap-tel', '3007778899');
await pagina.locator('#modal-apuntar [data-apmedio="transferencia"]').click();
await pagina.waitForTimeout(150);

// La pista tiene que decir la CONSECUENCIA, no el nombre del medio: lo
// que hay que saber es si esa plata va a aparecer en el cajón.
const pistaTr = (await pagina.locator('#ap-medio-pista').innerText()).trim();
/banco/i.test(pistaTr) && /no entra al caj/i.test(pistaTr)
  ? bien('con transferencia avisa que no entra al cajón', pistaTr)
  : falla('con transferencia avisa que no entra al cajón', pistaTr);

await pagina.click('#ap-guardar');
await pagina.waitForTimeout(600);
loQuePidio && loQuePidio.medio === 'transferencia'
  ? bien('manda transferencia cuando se elige', loQuePidio.medio)
  : falla('manda transferencia cuando se elige', loQuePidio && loQuePidio.medio);

const msgTr = (await pagina.locator('#msg-puerta').innerText()).trim();
!/efectivo/i.test(msgTr)
  ? bien('y no habla de efectivo que no existe', msgTr)
  : falla('y no habla de efectivo que no existe', msgTr);

// ── paga al llegar: lo que motivó todo ──
// Si esa plata entrara al apuntar, el cajón esperaría un dinero que
// todavía no está — y si la persona no aparece, no está nunca.
await pagina.click('#puerta-apuntar');
await pagina.waitForTimeout(300);
await pagina.fill('#ap-nombre', 'Hugo Llega');
await pagina.fill('#ap-tel', '3006665544');
await pagina.locator('#modal-apuntar [data-apmedio="en_puerta"]').click();
await pagina.waitForTimeout(150);

const pistaP = (await pagina.locator('#ap-medio-pista').innerText()).trim();
/no entra todav/i.test(pistaP) && /si no viene/i.test(pistaP)
  ? bien('avisa que no entra hasta que llegue', pistaP)
  : falla('avisa que no entra hasta que llegue', pistaP);

await pagina.click('#ap-guardar');
await pagina.waitForTimeout(600);
loQuePidio && loQuePidio.medio === 'en_puerta'
  ? bien('manda en_puerta cuando se elige', loQuePidio.medio)
  : falla('manda en_puerta cuando se elige', loQuePidio && loQuePidio.medio);

// Recepción tiene que saber que le queda algo por cobrar, o se cobra en
// la puerta y nadie lo apunta.
const msgP = (await pagina.locator('#msg-puerta').innerText()).trim();
/cóbrale \$15\.000 al llegar/i.test(msgP)
  ? bien('le recuerda que tiene que cobrarle al llegar', msgP.slice(0, 80))
  : falla('le recuerda que tiene que cobrarle al llegar', msgP);
!/entraron/i.test(msgP)
  ? bien('y no dice que entró plata que no entró')
  : falla('y no dice que entró plata que no entró', msgP);

// ── con plan no se pregunta nada ──
await pagina.click('#puerta-apuntar');
await pagina.waitForTimeout(300);
await pagina.locator('#modal-apuntar [data-tipo="miembro"]').click();
await pagina.waitForTimeout(150);
(await pagina.locator('#ap-caja-medio').isHidden())
  ? bien('con plan no se pregunta cómo pagó')
  : falla('con plan no se pregunta cómo pagó', 'la pregunta sigue ahí');

await pagina.fill('#ap-nombre', 'Fabio Miembro');
await pagina.fill('#ap-tel', '3008889900');
await pagina.click('#ap-guardar');
await pagina.waitForTimeout(600);
loQuePidio && loQuePidio.medio === null
  ? bien('y no manda ningún medio', 'null')
  : falla('y no manda ningún medio', loQuePidio && String(loQuePidio.medio));

// ── el caso feo: la reserva queda pero el efectivo NO entra ──
// Pasa con el día ya cerrado. Es plata que está en el cajón y que el
// sistema no sabe que existe: callarlo aquí sería el mismo fallo de
// antes, pero con otra cara.
efectivoFalla = true;
await pagina.click('#puerta-apuntar');
await pagina.waitForTimeout(300);
await pagina.fill('#ap-nombre', 'Gaby Cerrada');
await pagina.fill('#ap-tel', '3009990011');
await pagina.locator('#modal-apuntar [data-apmedio="efectivo"]').click();
await pagina.click('#ap-guardar');
await pagina.waitForTimeout(600);
efectivoFalla = false;

const msgMal = (await pagina.locator('#msg-puerta').innerText()).trim();
/NO entró a la caja/i.test(msgMal)
  ? bien('si el efectivo no entra, lo grita', msgMal.slice(0, 90))
  : falla('si el efectivo no entra, lo grita', msgMal);
// El valor va con el formato de aquí, no con el separador de miles de
// Postgres: "15,000" en Colombia se lee como decimales.
/apunta esos \$15\.000/i.test(msgMal)
  ? bien('y dice qué hacer con esa plata, en pesos de aquí')
  : falla('y dice qué hacer con esa plata, en pesos de aquí', msgMal);
(await pagina.locator('#msg-puerta.mal').count()) === 1
  ? bien('y sale en rojo, no como un aviso más')
  : falla('y sale en rojo, no como un aviso más', 'no tiene la clase .mal');

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
