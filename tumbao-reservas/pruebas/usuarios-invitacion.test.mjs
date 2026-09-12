/**
 * La invitación que no llegó — estado de cada usuario y cómo reenviarla.
 *
 * POR QUÉ EXISTE ESTA PRUEBA
 * El 24 de agosto se dieron de alta tres personas. Una entró; las otras
 * dos llevan tres semanas sin poder. Mirado contra producción:
 *
 *   19:14  damian3314@gmail.com   → cuenta creada en Auth, invitación enviada
 *   19:48  bailatumbao@gmail.com  → fila en admin_usuarios, NADA en auth.users
 *   19:49  tanyizgus@hotmail.com  → fila en admin_usuarios, NADA en auth.users
 *
 * GoTrue crea la cuenta y manda el correo en la misma operación: si el
 * envío falla, deshace la creación. O sea que el correo falló y se llevó
 * la cuenta con él.
 *
 * Lo que hizo que nadie se enterara en tres semanas NO fue el fallo del
 * correo: fue que la lista decía lo mismo —«Invitación pendiente»— en
 * tres situaciones que piden cosas distintas. Por eso la mitad de esta
 * prueba es sobre los carteles y no sobre los botones: el cartel es lo
 * que hace que el problema se vea.
 *
 * Y la otra mitad es sobre la salida sin correo. Mientras Supabase mande
 * con su servidor de fábrica —racionado, y rechazado a menudo por
 * Hotmail— depender del correo es depender de lo que ya falló. El enlace
 * para copiar es lo que desatasca esto hoy.
 *
 *   node usuarios-invitacion.test.mjs
 */
import { chromium } from 'playwright-core';
import { rutaDelPanel } from './instrumentar.mjs';
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';

const PANEL = rutaDelPanel();
const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
const p = await b.newPage({ viewport: { width: 430, height: 1000 } });
const errs = []; p.on('pageerror', e => errs.push(String(e)));

let fallos = 0;
const ok = (n, c, extra = '') => { if (!c) fallos++;
  console.log(`${c ? '✓' : 'FALLO'} ${n}${extra ? '  → ' + extra : ''}`); };

const ID = {
  damian: 'aaaaaaaa-0000-4000-8000-00000000a001',
  luisa:  'aaaaaaaa-0000-4000-8000-00000000a002',
  tanya:  'aaaaaaaa-0000-4000-8000-00000000a003',
  lista:  'aaaaaaaa-0000-4000-8000-00000000a004',
  fuera:  'aaaaaaaa-0000-4000-8000-00000000a005',
};

/* Los tres casos reales, más los dos que faltaban para cubrir los cuatro
   estados y el desactivado. */
let usuarios = { ok: true, usuarios: [
  { id: ID.damian, nombre: 'Damián', email: 'damian3314@gmail.com',
    rol: 'propietario', activo: true, tiene_acceso: true, estado: 'activo',
    invitado_at: '2026-08-24T19:14:39Z', ultimo_ingreso: '2026-09-12T13:19:12Z' },
  { id: ID.luisa, nombre: 'Luisa', email: 'bailatumbao@gmail.com',
    rol: 'cajero', activo: true, tiene_acceso: false, estado: 'sin_invitar',
    invitado_at: null, ultimo_ingreso: null },
  { id: ID.tanya, nombre: 'Tanya Santiago', email: 'tanyizgus@hotmail.com',
    rol: 'propietario', activo: true, tiene_acceso: false, estado: 'invitado',
    invitado_at: '2026-08-24T19:49:18Z', ultimo_ingreso: null },
  { id: ID.lista, nombre: 'Marcela', email: 'marcela@ejemplo.com',
    rol: 'administrador', activo: true, tiene_acceso: false, estado: 'listo',
    invitado_at: '2026-09-10T15:00:00Z', ultimo_ingreso: null },
  { id: ID.fuera, nombre: 'Quien se fue', email: 'exempleada@ejemplo.com',
    rol: 'cajero', activo: false, tiene_acceso: false, estado: 'sin_invitar',
    invitado_at: null, ultimo_ingreso: null },
] };

const pedido = { invitar: [], enlace: [] };
let respInvitar = { status: 200, cuerpo: { ok: true,
  mensaje: 'Correo enviado a bailatumbao@gmail.com. El enlace sirve una sola vez.' } };
let respEnlace = { status: 200, cuerpo: { ok: true,
  email: 'bailatumbao@gmail.com', tipo: 'invite',
  enlace: 'https://fobpccreihcylpsullhu.supabase.co/auth/v1/verify' +
          '?token=pkce_abc123&type=invite&redirect_to=https%3A%2F%2Ftumbaobaila.com%2Fadmin',
  mensaje: 'Mándale este enlace por WhatsApp. Sirve una sola vez.' } };

/* EN PLAYWRIGHT MANDA LA ÚLTIMA RUTA REGISTRADA, no la más específica. */
await p.route('**/api/**', r => r.fulfill({ status: 200,
  contentType: 'application/json',
  body: JSON.stringify({ ok: true, dias: [], reservas: [], pagos_libres: [],
                         movimientos: [], resumen_conceptos: [] }) }));
await p.route('**/api/admin/usuarios-listar', r => r.fulfill({ status: 200,
  contentType: 'application/json', body: JSON.stringify(usuarios) }));
await p.route('**/api/admin/usuarios-invitar', r => {
  pedido.invitar.push(JSON.parse(r.request().postData() || '{}'));
  return r.fulfill({ status: respInvitar.status, contentType: 'application/json',
    body: JSON.stringify(respInvitar.cuerpo) });
});
await p.route('**/api/admin/usuarios-enlace', r => {
  pedido.enlace.push(JSON.parse(r.request().postData() || '{}'));
  return r.fulfill({ status: respEnlace.status, contentType: 'application/json',
    body: JSON.stringify(respEnlace.cuerpo) });
});

const srv = createServer(async (q, s) => {
  try {
    const cuerpo = await readFile(PANEL);
    s.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' }); s.end(cuerpo);
  } catch (_) { s.writeHead(404); s.end('no'); }
});
await new Promise(r => srv.listen(8132, r));

await p.addInitScript(() => {
  localStorage.setItem('tumbao_admin_token',
    JSON.stringify({ token: 'x', rol: 'propietario', nombre: 'Prueba' }));
});
await p.goto('http://localhost:8132/', { waitUntil: 'load' });
await p.waitForTimeout(500);
await p.click('#tab-usuarios');
await p.waitForTimeout(600);

const txt = () => p.locator('#lista-usuarios').innerText().then(s => s.replace(/\s+/g, ' '));
let t = await txt();

/* ═══════════ 1. los cuatro estados se distinguen ═══════════
   Esto es el corazón de la prueba. Si los cuatro se vieran igual,
   volvería a pasar lo de agosto: nadie sabría a quién insistirle. */

ok('quien nunca tuvo cuenta lo dice así', /Sin invitación/.test(t), t);
ok('y explica qué hacer con ella',
   /Nunca le salió el correo\. Mándale el enlace\./.test(t), t);
ok('quien tiene cuenta sin clave se distingue de la anterior',
   /Sin contraseña/.test(t), t);
ok('y dice que le falta abrir el enlace',
   /Le falta abrir el enlace/.test(t), t);
ok('quien ya puso su clave y no ha entrado también se distingue',
   /Lista para entrar/.test(t), t);
ok('quien ya usa el panel no lleva cartel de nada',
   !/Damián Propietario Sin/.test(t), t);
ok('y de esa se dice cuándo entró, que es lo único interesante',
   /Última entrada/.test(t), t);
// Sin esto, los cuatro carteles serían el mismo que había antes con otro
// nombre: el cartel sirve si dice desde cuándo viene el silencio.
ok('los estados a medias dicen de cuándo es la invitación',
   /Invitada el 24 de ago/.test(t), t);
ok('el cartel viejo de «Invitación pendiente» ya no existe',
   !/Invitación pendiente/.test(t), t);

/* ═══════════ 2. los botones salen donde hay algo que hacer ═══════════ */

ok('hay botón de reenviar en las tres que no han entrado',
   await p.locator('[data-invitar]').count() === 3,
   'sin invitar, sin contraseña y lista para entrar');
ok('y de copiar enlace en las mismas tres',
   await p.locator('[data-enlace]').count() === 3);
ok('quien ya entra no tiene botones: no hay nada que mandarle',
   await p.locator(`[data-invitar="${ID.damian}"]`).count() === 0);
// Invitar a alguien desactivado es mandarle a poner una clave con la que
// después no va a poder entrar. Postgres lo rebota; aquí ni se ofrece.
ok('a quien está desactivado no se le ofrece invitar',
   await p.locator(`[data-invitar="${ID.fuera}"]`).count() === 0,
   'entraría y se le rebotaría por inactivo');

/* ═══════════ 3. reenviar manda el correo y lo cuenta ═══════════ */

await p.click(`[data-invitar="${ID.luisa}"]`);
await p.waitForTimeout(400);
ok('el reenvío manda el id de esa persona y nada más',
   pedido.invitar.length === 1 && pedido.invitar[0].id === ID.luisa,
   JSON.stringify(pedido.invitar));
ok('y se dice que salió, con el correo al que fue',
   /Correo enviado a bailatumbao@gmail\.com/
     .test((await p.locator('#msg-usuarios').innerText()).replace(/\s+/g, ' ')));

/* ═══════════ 4. cuando el correo falla, se dice POR QUÉ ═══════════
   Esto es lo que faltó en agosto. «No se pudo mandar» no le sirve a
   nadie: con el motivo delante se sabe que insistir no va a servir y que
   el camino es el enlace. */

respInvitar = { status: 502, cuerpo: { ok: false, error: 'CORREO_RACIONADO',
  mensaje: 'Supabase solo deja mandar unos pocos correos por hora y ya se ' +
           'agotaron. Usa "Copiar enlace" y mándalo por WhatsApp.',
  detalle: 'email rate limit exceeded' } };
await p.click(`[data-invitar="${ID.tanya}"]`);
await p.waitForTimeout(400);
const msg = (await p.locator('#msg-usuarios').innerText()).replace(/\s+/g, ' ');

ok('el fallo dice el motivo en español', /unos pocos correos por hora/.test(msg), msg);
ok('y qué hacer en su lugar', /Copiar enlace/.test(msg), msg);
ok('con el motivo crudo de Supabase a la vista, para poder diagnosticar',
   /email rate limit exceeded/.test(msg), msg);
ok('y el botón vuelve a estar pulsable, no se queda muerto',
   await p.isEnabled(`[data-invitar="${ID.tanya}"]`));

/* ═══════════ 5. el enlace, que es la salida de verdad ═══════════ */

await p.click(`[data-enlace="${ID.luisa}"]`);
await p.waitForTimeout(400);
ok('pedir el enlace manda el id', pedido.enlace.length === 1 && pedido.enlace[0].id === ID.luisa);
ok('el enlace se enseña entero, no solo un botón de copiar',
   (await p.locator('.enlace-caja textarea').inputValue()).includes('token=pkce_abc123'),
   'si el portapapeles falla, lo único que queda es leerlo');
const caja = (await p.locator('.enlace-caja').innerText()).replace(/\s+/g, ' ');
ok('dice de quién es', /bailatumbao@gmail\.com/.test(caja), caja);
ok('y que sirve una sola vez', /una sola vez/.test(caja), caja);
ok('con el botón de copiar al lado', await p.locator('[data-copiar]').count() === 1);

// Pedirlo dos veces no apila dos cajas: la segunda reemplaza a la
// primera. Con dos a la vista no se sabría cuál es el enlace bueno, y el
// de antes ya no sirve.
await p.click(`[data-enlace="${ID.luisa}"]`);
await p.waitForTimeout(400);
ok('pedirlo otra vez reemplaza el anterior, no lo apila',
   await p.locator('.enlace-caja').count() === 1,
   'dos enlaces a la vista y no se sabe cuál vale');

await p.click('[data-cerrar-enlace]');
await p.waitForTimeout(200);
ok('y se puede ocultar cuando ya se mandó',
   await p.locator('.enlace-caja').count() === 0);

/* ═══════════ 6. un panel viejo en caché no se rompe ═══════════
   Los navegadores del mostrador tardan en soltar la copia vieja. Sin
   `estado` la lista tiene que seguir funcionando con lo que ya traía. */

usuarios = { ok: true, usuarios: [
  { id: ID.damian, nombre: 'Damián', email: 'damian3314@gmail.com',
    rol: 'propietario', activo: true, tiene_acceso: true },
  { id: ID.luisa, nombre: 'Luisa', email: 'bailatumbao@gmail.com',
    rol: 'cajero', activo: true, tiene_acceso: false },
] };
await p.click('#usuarios-recargar');
await p.waitForTimeout(500);
t = await txt();

ok('sin `estado` la lista sigue pintándose', /Luisa/.test(t) && /Damián/.test(t), t);
ok('y quien no tiene acceso sigue saliendo marcado',
   /Sin invitación/.test(t), t);
ok('sin dejar de ofrecerle el reenvío',
   await p.locator(`[data-invitar="${ID.luisa}"]`).count() === 1);
// Y sin ofrecérselo a quien ya entra: reenviarle una invitación a quien
// ya tiene cuenta y contraseña es ruido que invita a equivocarse.
ok('y sin ofrecérselo a quien ya tiene acceso',
   await p.locator(`[data-invitar="${ID.damian}"]`).count() === 0,
   'con `tiene_acceso` basta para saberlo');

ok('sin errores de JS', errs.length === 0, errs.join(' | '));
console.log(fallos ? `\n${fallos} fallo(s)` : '\nTodo bien');
await b.close(); srv.close();
process.exit(fallos ? 1 : 0);
