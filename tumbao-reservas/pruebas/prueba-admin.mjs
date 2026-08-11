/**
 * Prueba del panel de admin con Chromium.
 * Requiere el espejo corriendo:  node pruebas/espejo-api.mjs
 */
import { chromium } from 'playwright-core';

const BASE = 'http://localhost:8899/admin';
const CHROME = process.env.CHROME_PATH || '/opt/pw-browsers/chromium-1194/chrome-linux/chrome';
const TOKEN = process.env.TOKEN_ADMIN || 'token-de-prueba';
let fallos = 0;
const ok = (n, c, extra = '') => {
  console.log(`${c ? '✓' : '✗'} ${n}${extra ? '  → ' + extra : ''}`);
  if (!c) fallos++;
};

const nav = await chromium.launch({ executablePath: CHROME });
const ctx = await nav.newContext({ viewport: { width: 1280, height: 900 }, locale: 'es-CO' });
const p = await ctx.newPage();
const errores = [];
p.on('console', m => { if (m.type() === 'error') errores.push(m.text()); });
p.on('pageerror', e => errores.push('pageerror: ' + e.message));

const entrar = async tk => {
  await p.fill('#token', tk);
  await p.locator('#btn-entrar').click();
};

// El espejo guarda estado en memoria y esta suite crea clases, reserva
// y marca asistencias. Sin volver al principio, la segunda corrida
// arranca sobre los restos de la primera y falla por cosas que no
// tienen que ver con el codigo.
await fetch('http://localhost:8899/_prueba/reiniciar').catch(() => {});

await p.goto(BASE, { waitUntil: 'networkidle' });

// ───────── entrar ─────────
ok('pide el token', await p.locator('#entrar').isVisible());
ok('el panel esta escondido', await p.locator('#app').isHidden());

await entrar('token-malo');
await p.waitForTimeout(700);
ok('un token malo no entra', await p.locator('#app').isHidden());
ok('y lo dice', !(await p.locator('#err-entrar').isHidden()),
   (await p.locator('#err-entrar').innerText()).slice(0, 60));

await p.fill('#token', '');
await entrar(TOKEN);
await p.waitForSelector('#app:not([hidden])', { timeout: 8000 });
ok('con el token bueno entra', true);
ok('guarda la sesion', await p.evaluate(() => !!localStorage.getItem('tumbao_admin_token')));

// ───────── tablero ─────────
// Es la pestaña en la que cae quien entra: solo lectura, y responde de
// un vistazo si cabe alguien más en la clase de las 7.
console.log('\n── Tablero ──');
ok('entra directo al tablero',
   await p.locator('#p-tablero').evaluate(e => e.classList.contains('on')));

// El espejo siembra las clases desde mañana, así que hoy sale vacío.
// Que el día sin clases no reviente también es parte de la prueba.
await p.waitForTimeout(900);
ok('un dia sin clases lo dice, no se cae',
   /No hay clases/.test(await p.locator('#clases-tab').innerText()),
   (await p.locator('#clases-tab').innerText()).slice(0, 40));

await p.locator('#dia-despues').click();
await p.waitForSelector('.clase-card', { timeout: 8000 });
const tarj = await p.locator('.clase-card').count();
ok('pinta una tarjeta por clase', tarj > 0, `${tarj} clases`);
ok('cinco cifras arriba', await p.locator('#tiles-tab .tile').count() === 5);

// El aviso punteado de los que vencen ese dia. Solo sale donde hay
// alguien venciendo: si saliera en todas, seria ruido.
const conVence = p.locator('.clase-card').filter({ has: p.locator('.vencen') });
ok('avisa cuando hay planes que vencen ese dia', await conVence.count() >= 1,
   `${await conVence.count()} de ${await p.locator('.clase-card').count()} clases`);
if (await conVence.count()) {
  const txtV = await conVence.first().locator('.vencen').innerText();
  ok('dice cuantos son', /\d+\s+con plan vencen?/.test(txtV), txtV.trim());
  // Nunca puede pasarse de los que tienen plan: se estarian ofreciendo
  // puestos que si estan ocupados.
  const cifrasV = await conVence.first().evaluate(e => ({
    conPlan: Number(e.querySelectorAll('.mini .v')[1].textContent),
    vencen: Number(e.querySelector('.vencen b').textContent),
  }));
  ok('nunca dice mas de los que tienen plan',
     cifrasV.vencen <= cifrasV.conPlan,
     `${cifrasV.vencen} de ${cifrasV.conPlan} con plan`);
  // Es informacion, no una venta: el cupo a la venta no lo incluye.
  const venta = await conVence.first().evaluate(e =>
    Number(e.querySelectorAll('.mini .v')[2].textContent));
  const aforoV = await conVence.first().evaluate(e =>
    Number(e.querySelectorAll('.mini .v')[0].textContent));
  ok('y no se suma solo al cupo a la venta',
     venta === aforoV - cifrasV.conPlan,
     `${venta} = ${aforoV} − ${cifrasV.conPlan}`);
}
ok('no ensucia las clases donde no vence nadie',
   await p.locator('.clase-card').count() > await conVence.count(),
   `${await p.locator('.clase-card').count() - await conVence.count()} sin aviso`);

const c1 = p.locator('.clase-card').first();
const txtC1 = await c1.innerText();
ok('la tarjeta trae las cuatro cifras del cupo',
   /aforo/i.test(txtC1) && /con plan/i.test(txtC1) &&
   /a la venta/i.test(txtC1) && /reservadas/i.test(txtC1));
ok('dice cuanta gente entra a la sala', /Entran\s+\d+\s+de\s+\d+/.test(txtC1),
   (txtC1.match(/Entran[^\n]*/) || [''])[0]);
ok('dice cuantos cupos quedan',
   /(\d+ libres?|Sin cupo)/.test(await c1.locator('.quedan').innerText()),
   (await c1.locator('.quedan').innerText()).trim());

// Los números del panel y los de la cuadrícula salen de la misma base:
// si se contradicen, uno de los dos está mintiendo.
const cifras = await c1.evaluate(e => {
  const v = [...e.querySelectorAll('.mini .v')].map(x => Number(x.textContent));
  return { aforo: v[0], conPlan: v[1], venta: v[2], reservadas: v[3] };
});
ok('aforo − con plan = a la venta',
   cifras.aforo - cifras.conPlan === cifras.venta,
   `${cifras.aforo} − ${cifras.conPlan} = ${cifras.venta}`);

// ───────── la lista de la puerta ─────────
// El caso real: son las 5:55, hay cola, y alguien dice "yo reservé".
// ¿Dónde se mira? Aquí, a un toque de la tarjeta de la clase.
console.log('\n── Puerta ──');
// Esa clase todavia no tiene reservas: se le siembra una para que la
// lista tenga los DOS grupos, que es lo que hay que comprobar. Con solo
// gente de plan el caso interesante no aparece.
const idClase = await c1.getAttribute('data-clase');
await fetch('http://localhost:8899/webhook/tumbao/reservar', {
  method: 'POST', headers: { 'content-type': 'application/json' },
  body: JSON.stringify({ clase_id: idClase, nombre: 'Yenny Vergara',
                         telefono: '3102543733', tipo: 'suelta', habeas: true })
});
await p.locator('#recargar-tab').click();
await p.waitForTimeout(700);

await c1.click();
await p.waitForSelector('#vista-puerta:not([hidden])', { timeout: 8000 });
await p.waitForSelector('.fila-puerta', { timeout: 8000 });
ok('la tarjeta de la clase abre su lista', true);
ok('esconde la vista del dia', await p.locator('#vista-dia').isHidden());

const marcador = await p.locator('#puerta-marcador').innerText();
ok('dice cuantos entraron de cuantos', /\d+\s*de\s*\d+\s*entraron/.test(marcador),
   marcador.replace(/\n/g, ' '));

// Los dos grupos: quien reservó, y quien tiene plan y solo llega. Sin
// el segundo, el portero vería 3 nombres de las 30 personas que entran.
const gruposP = await p.locator('.grupo-puerta > h3').allInnerTexts();
ok('separa a los que reservaron de los que tienen plan',
   gruposP.some(t => /Reservaron/i.test(t)) && gruposP.some(t => /plan/i.test(t)),
   gruposP.join(' | ').replace(/\n/g, ' '));

const fila1 = p.locator('.fila-puerta').first();
const quien = (await fila1.locator('.nom').innerText()).trim();
ok('cada persona trae un boton grande de marcar',
   await fila1.locator('.btn-entro').count() === 1,
   quien);

await fila1.locator('.btn-entro').click();
await p.waitForTimeout(800);
ok('marcar deja la fila en verde',
   (await fila1.getAttribute('class')).includes('entro'));
ok('y el boton dice que entro', /Entró/.test(await fila1.locator('.btn-entro').innerText()),
   (await fila1.locator('.btn-entro').innerText()).trim());
const tras1 = await p.locator('#puerta-marcador .n').innerText();
ok('el contador sube', Number(tras1) >= 1, `${tras1} entraron`);

// Se toca con prisa: marcar dos veces no puede contar dos personas.
await fila1.locator('.btn-entro').click();
await p.waitForTimeout(700);
await fila1.locator('.btn-entro').click();
await p.waitForTimeout(700);
ok('desmarcar y volver a marcar no cuenta doble',
   (await p.locator('#puerta-marcador .n').innerText()) === tras1,
   `${await p.locator('#puerta-marcador .n').innerText()} vs ${tras1}`);

// El buscador es el punto entero de la pantalla.
await p.fill('#buscar-puerta', quien.split(' ')[0].toLowerCase());
await p.waitForTimeout(300);
ok('el buscador filtra la lista', await p.locator('.fila-puerta').count() >= 1,
   `${await p.locator('.fila-puerta').count()} fila(s)`);
await p.fill('#buscar-puerta', 'zzz-nadie');
await p.waitForTimeout(300);
ok('y dice cuando no esta', /Nadie con/.test(await p.locator('#lista-puerta').innerText()),
   (await p.locator('#lista-puerta').innerText()).replace(/\n/g, ' ').slice(0, 50));
await p.locator('#limpiar-puerta').click();
await p.waitForTimeout(300);

// La marca tiene que seguir puesta al volver a abrir.
await p.locator('#puerta-volver').click();
await p.waitForSelector('#vista-dia:not([hidden])', { timeout: 8000 });
ok('volver devuelve a la vista del dia', await p.locator('#vista-puerta').isHidden());
await p.waitForSelector('.clase-card', { timeout: 8000 });
await p.locator('.clase-card').first().click();
await p.waitForSelector('.fila-puerta', { timeout: 8000 });
ok('lo marcado sigue marcado al volver a entrar',
   await p.locator('.fila-puerta.entro').count() >= 1,
   `${await p.locator('.fila-puerta.entro').count()} marcada(s)`);
await p.locator('#puerta-volver').click();
await p.waitForSelector('#vista-dia:not([hidden])', { timeout: 8000 });

await p.locator('#dia-hoy').click();
await p.waitForTimeout(700);
ok('el boton Hoy vuelve al dia de hoy',
   /Hoy/.test(await p.locator('#dia-rango').innerText()),
   await p.locator('#dia-rango').innerText());

// ───────── horario ─────────
console.log('\n── Horario ──');
await p.locator('#tab-horario').click();
await p.waitForSelector('.dia-col', { timeout: 8000 });
ok('pinta los 7 dias', await p.locator('.dia-col').count() === 7,
   `${await p.locator('.dia-col').count()} columnas`);
ok('muestra el rango de la semana', /\w+.*—.*\w+/.test(await p.locator('#sem-rango').innerText()),
   await p.locator('#sem-rango').innerText());

// Si la semana que abre por defecto no tiene clases (segun el dia en que
// se corra la prueba), se avanza hasta encontrar una que si.
let filas = await p.locator('.fila-clase').count();
for (let i = 0; i < 3 && filas === 0; i++) {
  await p.locator('#sem-despues').click();
  await p.waitForTimeout(900);
  filas = await p.locator('.fila-clase').count();
}
ok('lista las clases', filas > 0, `${filas} clases`);
ok('cada clase trae interruptor y cupo',
   filas > 0 &&
   await p.locator('.fila-clase .interruptor').count() === filas &&
   await p.locator('.fila-clase .cupo-in').count() === filas);

// El desglose de donde salen los cupos tiene que estar a la vista.
const meta = await p.locator('.fila-clase .meta').first().innerText();
ok('explica de donde sale el cupo', /aforo\s+\d+\s+−\s+\d+\s+con plan/.test(meta),
   meta.replace(/\n/g, ' · '));

// La barra de guardar solo aparece cuando hay algo que guardar.
ok('sin cambios no hay barra de guardar', await p.locator('#barra-guardar').isHidden());

// ───────── cupo manual ─────────
console.log('\n── Cupo manual ──');
const primerCupo = p.locator('.fila-clase .cupo-in').first();
await primerCupo.fill('7');
await primerCupo.dispatchEvent('change');
await p.waitForTimeout(250);
ok('marcar un cupo levanta la barra', !(await p.locator('#barra-guardar').isHidden()));
ok('cuenta el cambio', (await p.locator('#cuenta-cambios').innerText()).includes('1 cambio'),
   await p.locator('#cuenta-cambios').innerText());
ok('el campo se marca como manual',
   (await primerCupo.getAttribute('class')).includes('manual'));

await p.locator('#guardar').click();
await p.waitForTimeout(1200);
const msg1 = await p.locator('#msg-horario').innerText();
ok('guarda y confirma', /guardado/i.test(msg1), msg1.split('\n')[0].slice(0, 70));
ok('la barra se esconde tras guardar', await p.locator('#barra-guardar').isHidden());
const cupoTrasGuardar = await p.locator('.fila-clase .cupo-in').first().inputValue();
ok('el cupo manual quedo puesto', cupoTrasGuardar === '7', `"${cupoTrasGuardar}"`);

// Soltarlo devuelve al automatico.
await primerCupo.fill('');
await primerCupo.dispatchEvent('change');
await p.locator('#guardar').click();
await p.waitForTimeout(1200);
ok('soltar el cupo vuelve al automatico',
   (await p.locator('.fila-clase .cupo-in').first().inputValue()) === '',
   'quedo vacio');

// ───────── abrir una hora nueva ─────────
console.log('\n── Abrir una hora ──');
const antes = await p.locator('.fila-clase').count();
const col = p.locator('.dia-col').nth(1);
await col.locator('.agregar input[type="time"]').fill('16:00');
await col.locator('.agregar button').click();
await p.waitForTimeout(400);
ok('la clase nueva se pinta de una', await p.locator('.fila-clase').count() === antes + 1);
await p.locator('#guardar').click();
await p.waitForTimeout(1200);
const msg2 = await p.locator('#msg-horario').innerText();
ok('la guarda como creada', /1 creada/.test(msg2), msg2.split('\n')[0].slice(0, 70));
ok('sigue ahi tras recargar la semana',
   (await p.locator('.dia-col').nth(1).innerText()).includes('4:00 pm'));

// No deja abrir dos clases a la misma hora.
await col.locator('.agregar input[type="time"]').fill('16:00');
await col.locator('.agregar button').click();
await p.waitForTimeout(300);
ok('no deja duplicar la hora',
   /ya hay una clase/i.test(await p.locator('#msg-horario').innerText()),
   (await p.locator('#msg-horario').innerText()).slice(0, 70));

// ───────── una clase con gente no se apaga ─────────
console.log('\n── Apagar ──');
// Se reserva desde la pagina publica para que la clase tenga alguien.
const p2 = await ctx.newPage();
await p2.goto('http://localhost:8899/', { waitUntil: 'networkidle' });
await p2.locator('.opcion[data-tipo="suelta"]').click();
await p2.waitForSelector('.clase:not(:disabled)', { timeout: 8000 });
await p2.locator('.clase:not(:disabled)').first().click();
await p2.waitForSelector('#s2.on', { timeout: 8000 });
await p2.fill('#nombre', 'Camila Rojas');
await p2.fill('#celular', '3002223344');
await p2.check('#habeas');
await p2.locator('#enviar').click();
await p2.waitForSelector('#s3.on', { timeout: 8000 });
await p2.fill('#hora-transf', '18:42');
await p2.locator('#ya-pague').click();
await p2.waitForSelector('#s4.on', { timeout: 8000 });

await p.locator('#sem-hoy').click();
await p.waitForTimeout(900);
// Tiene que ser una clase con gente DE VERDAD y que no haya pasado:
// toda fila dice "reservadas", incluso con cero, y las que ya pasaron
// traen el interruptor deshabilitado. Filtrar solo por la palabra
// agarraba la primera fila de la cuadricula y la prueba se caia o no
// segun la hora a la que se corriera.
const conGente = p.locator('.fila-clase:not(.paso)')
  .filter({ hasText: /[1-9]\d* reservad/ }).first();
ok('se ve cual clase tiene gente', await conGente.count() > 0,
   (await conGente.count()) ? (await conGente.innerText()).replace(/\n/g, ' · ') : 'ninguna');
await conGente.locator('.interruptor').click();
await p.waitForTimeout(200);
await p.locator('#guardar').click();
await p.waitForTimeout(1200);
const msg3 = await p.locator('#msg-horario').innerText();
ok('no apaga una clase con reservas', /no se apago/.test(msg3), msg3.replace(/\n/g, ' | ').slice(0, 100));

// ───────── pendientes ─────────
console.log('\n── Por validar ──');
await p.locator('#tab-pendientes').click();
await p.waitForTimeout(1200);
ok('cambia de pestaña', await p.locator('#p-pendientes').evaluate(e => e.classList.contains('on')));
const tarjetas = await p.locator('.pend-card').count();
ok('lista lo que espera validacion', tarjetas > 0, `${tarjetas} en cola`);
ok('el contador de la pestaña coincide',
   (await p.locator('#globo-pend').innerText()).trim() === String(tarjetas),
   await p.locator('#globo-pend').innerText());

// Agrupadas por clase: sin esto, diez tarjetas seguidas no dicen quien
// viene a las 6 y quien a las 7.
const grupos = await p.locator('.grupo').count();
ok('agrupa la cola por horario', grupos > 0, `${grupos} horario(s)`);
const cab = await p.locator('.grupo .grupo-cab').first().innerText();
ok('cada grupo dice hora, dia y cuantos',
   /\d{1,2}:\d{2}\s*(am|pm)/i.test(cab) && /persona/.test(cab),
   cab.replace(/\n/g, ' · '));

// ── el botón "Es este" ──
// Nunca funcionó, y ninguna prueba lo pulsaba. Los argumentos iban
// corridos —resolver(el, 'confirmar', r.codigo, pagoId) contra la firma
// resolver(tarjeta, r, accion, pagoId)— así que pedía
// POST /tumbao/admin/<codigo-de-reserva> y devolvía 404 siempre: cruzar
// a mano un pago sin dueño era imposible desde el panel.
//
// Se mira la RUTA que sale, no que el clic no reviente. Con los
// argumentos corridos el clic tampoco revienta: falla en silencio, que
// es justo por lo que duró tanto sin verse.
const btnEste = p.locator('.pago button', { hasText: 'Es este' }).first();
ok('el pago sin dueño trae su botón "Es este"', await btnEste.count() > 0);

if (await btnEste.count() > 0) {
  // Se corta la llamada en vez de dejarla pasar: si se dejara, esta
  // comprobación confirmaría una reserva de verdad y dejaría la cola
  // distinta para los pasos que vienen. Lo que se mide es la ruta, y eso
  // ya se sabe antes de que la petición salga.
  const rutas = [];
  await p.route('**/api/admin/**', async (route) => {
    rutas.push(new URL(route.request().url()).pathname.split('/').pop());
    await route.abort();
  });
  await btnEste.click();
  await p.waitForTimeout(900);
  await p.unroute('**/api/admin/**');

  ok('"Es este" llama a /confirmar, no al código de la reserva',
     rutas.includes('confirmar'), rutas.join(', ') || '(no pidió nada)');

  // Repintar desde el espejo, que no cambió, para dejar la cola como estaba.
  await p.locator('#tab-tablero').click();
  await p.waitForTimeout(400);
  await p.locator('#tab-pendientes').click();
  await p.waitForTimeout(1000);
}

const t1 = p.locator('.pend-card').first();
ok('muestra el codigo', /^[A-Z0-9]{4,8}$/.test((await t1.locator('.cod').innerText()).trim()),
   (await t1.locator('.cod').innerText()).trim());
ok('el telefono es un link de WhatsApp',
   (await t1.locator('.det a').getAttribute('href')).startsWith('https://wa.me/'));
ok('ofrece confirmar y rechazar',
   (await t1.locator('.acciones .btn.ok').count()) === 1 &&
   (await t1.locator('.acciones .btn.mal').count()) === 1);

// ───────── buscador ─────────
// El caso de verdad: llega alguien al mostrador y hay que encontrarlo
// sin leer la lista entera.
console.log('\n── Buscador ──');
const nombre1 = (await t1.locator('.nom').innerText()).trim();
const cod1    = (await t1.locator('.cod').innerText()).trim();

await p.fill('#buscar-pend', cod1);
await p.waitForTimeout(300);
ok('busca por codigo', await p.locator('.pend-card').count() === 1,
   `${await p.locator('.pend-card').count()} tarjeta(s)`);

// Sin tildes y en minusculas: en el mostrador nadie escribe "Velásquez".
await p.fill('#buscar-pend', nombre1.split(' ')[0].toLowerCase()
  .normalize('NFD').replace(/[̀-ͯ]/g, ''));
await p.waitForTimeout(300);
ok('busca por nombre sin tildes ni mayusculas',
   await p.locator('.pend-card').count() >= 1,
   `${await p.locator('.pend-card').count()} tarjeta(s)`);

await p.fill('#buscar-pend', 'zzz-nadie-se-llama-asi');
await p.waitForTimeout(300);
ok('si no hay nadie lo dice', /Nadie con/.test(await p.locator('#lista-pend').innerText()),
   (await p.locator('#lista-pend').innerText()).replace(/\n/g, ' ').slice(0, 45));
ok('el globo no se mueve al filtrar',
   (await p.locator('#globo-pend').innerText()).trim() === String(tarjetas),
   await p.locator('#globo-pend').innerText());

await p.locator('#limpiar-busq').click();
await p.waitForTimeout(300);
ok('el boton de limpiar devuelve la lista entera',
   await p.locator('.pend-card').count() === tarjetas,
   `${await p.locator('.pend-card').count()} de ${tarjetas}`);

// ───────── confirmar ─────────
console.log('\n── Confirmar ──');
const t1b = p.locator('.pend-card').first();
await t1b.locator('.acciones .btn.ok').click();
await p.waitForTimeout(1000);
const trasCheck = await p.locator('.pend-card').first().innerText();
ok('el check confirma', /confirmada/i.test(trasCheck), trasCheck.replace(/\n/g, ' · ').slice(0, 80));
ok('y deja el link para avisarle por WhatsApp',
   (await p.locator('.pend-card').first().locator('a').count()) > 0 &&
   (await p.locator('.pend-card').first().locator('a').last().getAttribute('href')).includes('wa.me'));

// El resultado vive en la reserva, no en el DOM: filtrar y volver no
// puede borrar de la pantalla el enlace que el cajero acaba de sacar.
await p.fill('#buscar-pend', cod1);
await p.waitForTimeout(300);
const trasFiltro = await p.locator('#lista-pend').innerText();
ok('la confirmacion sobrevive al buscador', /confirmada/i.test(trasFiltro),
   trasFiltro.replace(/\n/g, ' · ').slice(0, 70));
await p.locator('#limpiar-busq').click();
await p.waitForTimeout(300);

// ───────── deshacer ─────────
// La duda llega medio segundo despues del clic: "¿era este el que habia
// pagado?". Sin esto la unica salida es tocar la base a mano.
console.log('\n── Deshacer ──');
const resuelta = p.locator('.pend-card.resuelta').first();
ok('la tarjeta resuelta ofrece deshacer',
   await resuelta.locator('.btn.deshacer').count() === 1);
const restante = (await resuelta.locator('.btn.deshacer').innerText()).trim();
ok('y dice cuanto plazo queda', /\d+\s*(min|s)\b/.test(restante), restante);

await resuelta.locator('.btn.deshacer').click();
await p.waitForTimeout(1000);
ok('lo dice cuando lo deshace',
   /vuelve a estar por validar/i.test(await p.locator('#msg-pend').innerText()),
   (await p.locator('#msg-pend').innerText()).slice(0, 55));

// Lo que hace que deshacer sirva de algo: la tarjeta vuelve con sus dos
// botones, no como un aviso muerto.
const devuelta = p.locator('.pend-card').filter({ hasText: cod1 }).first();
ok('vuelve a la cola con sus botones',
   (await devuelta.locator('.acciones .btn.ok').count()) === 1 &&
   (await devuelta.locator('.acciones .btn.mal').count()) === 1);
ok('y ya no se ve como resuelta',
   await p.locator('.pend-card.resuelta').count() === 0);
ok('el contador vuelve a subir',
   (await p.locator('#globo-pend').innerText()).trim() === String(tarjetas),
   await p.locator('#globo-pend').innerText());

// ───────── salir ─────────
console.log('\n── Sesión ──');
await p.locator('#salir').click();
await p.waitForTimeout(300);
ok('salir esconde el panel', await p.locator('#app').isHidden());
ok('y borra el token guardado',
   await p.evaluate(() => !localStorage.getItem('tumbao_admin_token')));

// ───────── consola ─────────
console.log('');
// Se descartan los 4xx que las propias pruebas provocan (token malo) y el
// ERR_FAILED de la llamada que se corta a proposito al probar "Es este".
// Lo que NO se descarta es un error de JavaScript: un ReferenceError o un
// "Cannot read properties of null" tienen que seguir tumbando la prueba.
const inesperados = errores.filter(e =>
  !/40[0-9]|Unauthorized|Bad Request|net::ERR_FAILED/.test(e));
ok('sin errores de JavaScript inesperados', inesperados.length === 0, inesperados.join(' | ') || 'ninguno');

// capturas
const dir = process.env.CAPTURAS || '/tmp';
await p.goto(BASE, { waitUntil: 'networkidle' });
await p.screenshot({ path: `${dir}/a0-entrar.png` });
await p.fill('#token', TOKEN);
await p.locator('#btn-entrar').click();
await p.waitForSelector('#p-tablero.on', { timeout: 8000 });
await p.locator('#dia-despues').click();
await p.waitForSelector('.clase-card', { timeout: 8000 });
await p.waitForTimeout(400);
await p.screenshot({ path: `${dir}/a1-tablero.png`, fullPage: true });
await p.locator('#tab-horario').click();
await p.waitForSelector('.dia-col', { timeout: 8000 });
await p.waitForTimeout(400);
await p.screenshot({ path: `${dir}/a2-horario.png`, fullPage: true });
await p.locator('#tab-pendientes').click();
await p.waitForTimeout(1000);
await p.screenshot({ path: `${dir}/a3-validar.png`, fullPage: true });

await nav.close();
console.log(`\n${fallos === 0 ? 'TODO EN VERDE' : fallos + ' FALLOS'}`);
process.exit(fallos ? 1 : 0);
