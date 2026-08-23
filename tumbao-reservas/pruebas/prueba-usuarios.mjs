/**
 * Login con correo y contraseña, y los tres roles — con un navegador de
 * verdad.
 *
 * POR QUÉ EXISTE
 * humo-usuarios-con-rol.sql ya prueba que Postgres reparte los permisos
 * bien. Esto prueba la otra mitad: que el panel MUESTRA lo que cada rol
 * puede hacer y esconde lo que no, y que el login de verdad (no el
 * token pegado) es el camino de entrada normal.
 *
 * Requiere el espejo corriendo:  node pruebas/espejo-api.mjs
 */
import { chromium } from 'playwright-core';

const BASE = 'http://localhost:8899/admin';
const CHROME = process.env.CHROME_PATH || '/opt/pw-browsers/chromium-1194/chrome-linux/chrome';
let fallos = 0;
const ok = (n, c, extra = '') => {
  console.log(`${c ? '✓' : '✗'} ${n}${extra ? '  → ' + extra : ''}`);
  if (!c) fallos++;
};

await fetch('http://localhost:8899/_prueba/reiniciar').catch(() => {});

const nav = await chromium.launch({ executablePath: CHROME });
const ctx = await nav.newContext({ viewport: { width: 1280, height: 900 }, locale: 'es-CO' });
const p = await ctx.newPage();
const errores = [];
p.on('console', m => { if (m.type() === 'error') errores.push(m.text()); });
p.on('pageerror', e => errores.push('pageerror: ' + e.message));
p.on('dialog', d => d.accept());   // el confirm() de "desactivar"

const entrarConCorreo = async (correo, clave) => {
  await p.fill('#correo', correo);
  await p.fill('#clave', clave);
  await p.locator('#btn-entrar').click();
};

console.log('\n── La pantalla de entrada ──\n');
await p.goto(BASE, { waitUntil: 'networkidle' });
ok('pide correo y contraseña, no un token', await p.locator('#correo').isVisible());
ok('el token queda plegado, no a la vista', await p.locator('#token').isHidden());

await entrarConCorreo('nadie@tumbaobaila.com', 'lo-que-sea');
await p.waitForTimeout(500);
ok('un correo que no existe no entra', await p.locator('#app').isHidden());
ok('y lo dice', !(await p.locator('#err-entrar').isHidden()),
   (await p.locator('#err-entrar').innerText()).slice(0, 60));

console.log('\n── Cajero: solo caja ──\n');
await entrarConCorreo('cajero@tumbaobaila.com', 'clave1234');
await p.waitForSelector('#app:not([hidden])', { timeout: 8000 })
  .then(() => ok('entra con correo y contraseña', true))
  .catch(() => ok('entra con correo y contraseña', false));
ok('no ve Horario', await p.locator('#tab-horario').isHidden());
ok('no ve Por disfrutar', await p.locator('#tab-disfrutar').isHidden());
ok('no ve Usuarios', await p.locator('#tab-usuarios').isHidden());
ok('sí ve Caja', await p.locator('#tab-caja').isVisible());
ok('sí ve Por validar', await p.locator('#tab-pendientes').isVisible());

console.log('\n── Administrador: el día a día ──\n');
await p.locator('#salir').click();
await p.waitForSelector('#entrar:not([hidden])', { timeout: 8000 });
await entrarConCorreo('admin@tumbaobaila.com', 'clave1234');
await p.waitForSelector('#app:not([hidden])', { timeout: 8000 });
ok('sí ve Horario', await p.locator('#tab-horario').isVisible());
ok('sí ve Por disfrutar', await p.locator('#tab-disfrutar').isVisible());
ok('no ve Usuarios', await p.locator('#tab-usuarios').isHidden());

console.log('\n── Propietario: todo, incluidos los usuarios ──\n');
await p.locator('#salir').click();
await p.waitForSelector('#entrar:not([hidden])', { timeout: 8000 });
await entrarConCorreo('duena@tumbaobaila.com', 'clave1234');
await p.waitForSelector('#app:not([hidden])', { timeout: 8000 });
ok('sí ve Usuarios', await p.locator('#tab-usuarios').isVisible());

await p.locator('#tab-usuarios').click();
await p.waitForSelector('.usuario-fila', { timeout: 8000 });
ok('lista a los tres', await p.locator('.usuario-fila').count() === 3,
   String(await p.locator('.usuario-fila').count()));

// Dar de alta a alguien nuevo
await p.locator('#usuarios-nuevo').click();
await p.fill('#us-nombre', 'Nueva Cajera');
await p.fill('#us-email', 'nueva@tumbaobaila.com');
await p.selectOption('#us-rol', 'cajero');
await p.locator('#us-guardar').click();
await p.locator('#modal-usuario').waitFor({ state: 'hidden', timeout: 8000 })
  .then(() => ok('dar de alta cierra el modal', true))
  .catch(() => ok('dar de alta cierra el modal', false));
await p.waitForTimeout(500);
ok('la nueva persona aparece en la lista', await p.locator('.usuario-fila').count() === 4,
   String(await p.locator('.usuario-fila').count()));

// Un correo repetido se rechaza sin cerrar el modal
await p.locator('#usuarios-nuevo').click();
await p.fill('#us-nombre', 'Otra Vez');
await p.fill('#us-email', 'admin@tumbaobaila.com');
await p.locator('#us-guardar').click();
await p.waitForTimeout(400);
ok('un correo repetido se rechaza', !(await p.locator('#us-error').isHidden()),
   (await p.locator('#us-error').innerText()).slice(0, 60));
await p.locator('#us-cancelar').click();

// Desactivar a alguien le cae el botón a "Reactivar"
const filaAdmin = p.locator('.usuario-fila', { hasText: 'admin@tumbaobaila.com' });
await filaAdmin.locator('[data-alternar]').click();
await p.waitForTimeout(500);
ok('desactivar cambia el botón a Reactivar',
   (await filaAdmin.locator('[data-alternar]').innerText()).trim() === 'Reactivar');
ok('y se ve marcado como desactivado', await filaAdmin.locator('.rol-pill.mal').isVisible());

console.log('\n── Olvidé mi contraseña ──\n');
await p.locator('#salir').click();
await p.waitForSelector('#entrar:not([hidden])', { timeout: 8000 });
await p.locator('#link-olvide').click();
ok('cambia a la pantalla de recuperar', await p.locator('#olvide').isVisible());
await p.fill('#olvide-correo', 'cualquiera@tumbaobaila.com');
await p.locator('#btn-olvide').click();
await p.waitForTimeout(400);
ok('responde igual exista o no el correo', !(await p.locator('#msg-olvide').isHidden()),
   (await p.locator('#msg-olvide').innerText()).slice(0, 70));

console.log('\n── La sesión sobrevive a recargar la página ──\n');
await p.locator('#btn-olvide-volver').click();
await entrarConCorreo('duena@tumbaobaila.com', 'clave1234');
await p.waitForSelector('#app:not([hidden])', { timeout: 8000 });
await p.reload({ waitUntil: 'networkidle' });
await p.waitForSelector('#app:not([hidden])', { timeout: 8000 })
  .then(() => ok('sigue adentro después de recargar', true))
  .catch(() => ok('sigue adentro después de recargar', false));
ok('y sigue viendo Usuarios (guardó el rol)', await p.locator('#tab-usuarios').isVisible());

const inesperados = errores.filter(e => !/40[0-9]|Unauthorized/.test(e));
ok('sin errores de JavaScript inesperados', inesperados.length === 0, inesperados.join(' | ') || 'ninguno');

await nav.close();
console.log(`\n${fallos === 0 ? 'TODO EN VERDE' : fallos + ' FALLOS'}`);
process.exit(fallos ? 1 : 0);
