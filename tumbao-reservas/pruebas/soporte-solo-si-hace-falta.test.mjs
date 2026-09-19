/**
 * El soporte de pago se pide SOLO cuando hace falta.
 *
 * POR QUÉ EXISTE
 * Damián: «se han aumentado los casos de gente enviando mensaje al
 * WhatsApp de que pagó, y al parecer no pasaron validación automática».
 * Al mirarlo, casi ninguno había fallado: en ocho semanas se
 * confirmaron solas 553 reservas y NINGUNA quedó en
 * `pendiente_validacion`. La página le estaba enseñando «Escribirnos por
 * WhatsApp» a las 553.
 *
 * Y cada uno de esos mensajes cuesta dos veces: la persona se queda
 * pendiente de una respuesta que no necesitaba, y alguien tiene que
 * leerlo y contestar «sí, ya nos llegó». El comprobante en el chat sirve
 * cuando el pago NO cruzó solo; cuando sí cruzó, pedirlo es trabajo
 * inventado.
 *
 * La regla que se prueba aquí, con sus palabras: «si la persona pasa
 * validación automática no se le debe invitar a que nos escriba al
 * WhatsApp; es solo cuando no se pudo validar».
 *
 * CÓMO
 * Con el espejo del API, que simula el flujo entero incluido el retardo
 * del correo del banco. Dos corridas, porque el desenlace lo decide el
 * servidor y no la página:
 *
 *   RETARDO_BANCO=1              el pago cruza  → no se ofrece escribir
 *   NUNCA_LLEGA=1 MINUTOS_ESPERA el pago no cruza → se pide el soporte
 *
 * La prueba levanta y baja el espejo ella misma, así que corre sola:
 *
 *   node soporte-solo-si-hace-falta.test.mjs
 */
import { chromium } from 'playwright-core';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const AQUI = dirname(fileURLToPath(import.meta.url));
const BASE = 'http://localhost:8899/';
const CHROME = process.env.CHROME_PATH ||
  '/opt/pw-browsers/chromium-1194/chrome-linux/chrome';

let fallos = 0;
const ok = (n, c, extra = '') => { if (!c) fallos++;
  console.log(`${c ? '✓' : '✗'} ${n}${extra ? '  → ' + extra : ''}`); };
const titulo = t => console.log(`\n-- ${t} ${'-'.repeat(Math.max(0, 54 - t.length))}`);

/* El espejo guarda estado en memoria y escucha siempre en el 8899, así
   que cada escenario necesita el suyo: se levanta, se usa y se baja. */
async function conEspejo(env, fn) {
  const hijo = spawn(process.execPath, [join(AQUI, 'espejo-api.mjs')],
    { env: { ...process.env, ...env }, stdio: 'ignore' });
  try {
    // Esperar a que conteste de verdad; un sleep fijo falla en una
    // máquina cargada y el fallo no se parece a su causa.
    for (let i = 0; i < 100; i++) {
      try { await fetch(BASE); break; }
      catch { await new Promise(r => setTimeout(r, 100)); }
    }
    return await fn();
  } finally {
    hijo.kill('SIGTERM');
    // Dar tiempo a que suelte el puerto antes del siguiente escenario.
    await new Promise(r => setTimeout(r, 300));
  }
}

const nav = await chromium.launch({ executablePath: CHROME });

/* Camina el embudo entero hasta la pantalla final: elegir clase, datos,
   «ya pagué» y la espera del banco. Es el camino de una persona real, no
   un atajo: el botón que se prueba vive al final de todo. */
async function hastaElFinal() {
  const ctx = await nav.newContext({ viewport: { width: 390, height: 844 }, locale: 'es-CO' });
  const p = await ctx.newPage();
  const errores = [];
  p.on('pageerror', e => errores.push('pageerror: ' + e.message));

  await p.goto(BASE, { waitUntil: 'networkidle' });
  await p.locator('.opcion[data-tipo="suelta"]').click();
  await p.waitForSelector('.clase:not(:disabled)', { timeout: 8000 });
  await p.locator('.clase:not(:disabled)').first().click();
  await p.waitForSelector('#s2.on', { timeout: 8000 });
  await p.fill('#nombre', 'Camila Rojas');
  await p.fill('#celular', '3002223344');
  await p.check('#habeas');
  await p.locator('#enviar').click();

  await p.waitForSelector('#s3.on', { timeout: 8000 });
  await p.fill('#hora-transf', '18:42');
  await p.locator('#ya-pague').click();
  await p.waitForSelector('#s5.on', { timeout: 40000 });
  return { p, ctx, errores };
}

/* ═══════ 1 · el pago cruza solo: no hay nada que preguntar ═══════ */

titulo('1. Pago confirmado solo');
await conEspejo({ RETARDO_BANCO: '1' }, async () => {
  const { p, ctx, errores } = await hastaElFinal();

  const t = await p.locator('#t5').innerText();
  ok('dice que el pago quedó confirmado', /confirmado|te esperamos/i.test(t), t);

  // El corazón de la prueba. `hidden` no basta con mirarlo en el
  // atributo: .btn-ghost trae display:block y una regla de autor le gana
  // al [hidden] del navegador si alguien quita el !important.
  ok('NO ofrece escribir por WhatsApp',
     !(await p.locator('#ok-wa').isVisible()),
     'es lo que llenaba el chat de «ya pagué»');

  const cuerpo = await p.locator('#s5').innerText();
  ok('ni se lo insinúa en el texto',
     !/whatsapp/i.test(cuerpo) && !/soporte/i.test(cuerpo),
     cuerpo.replace(/\n/g, ' ').slice(0, 130));
  ok('le dice lo único que tiene que hacer', /recepción/i.test(cuerpo));
  ok('y conserva el código', /^[A-Z0-9]{4,8}$/.test(
     (await p.locator('#ok-codigo').innerText()).trim()));

  /* Que no se ofrezca WhatsApp no puede llevarse por delante la
     invitación a opinar, que es de otra cosa y sí va en este caso. */
  ok('la invitación a contarnos sigue en pie',
     await p.locator('#ok-opina').isVisible());

  ok('sin errores de JS', errores.length === 0, errores.join(' | '));
  await ctx.close();
});

/* ═══════ 2 · el pago NO cruza: ahí sí se pide el soporte ═══════ */

titulo('2. El banco no responde');
await conEspejo({ NUNCA_LLEGA: '1', MINUTOS_ESPERA: '0.15' }, async () => {
  const { p, ctx, errores } = await hastaElFinal();

  const t = await p.locator('#t5').innerText();
  ok('no dice que se confirmó', !/confirmado/i.test(t), t);

  ok('SÍ ofrece escribir, y pidiendo el soporte',
     await p.locator('#ok-wa').isVisible());
  ok('con el botón en primer plano, no de relleno',
     (await p.locator('#ok-wa').getAttribute('class')) === 'btn',
     'aquí la persona tiene algo que hacer');
  ok('y el mensaje ya escrito',
     /soporte/i.test(await p.locator('#ok-wa').innerText()),
     (await p.locator('#ok-wa').innerText()).trim());

  const cuerpo = await p.locator('#s5').innerText();
  ok('sin dejarla creyendo que perdió el cupo',
     /cupo sigue apartado/i.test(cuerpo));

  ok('sin errores de JS', errores.length === 0, errores.join(' | '));
  await ctx.close();
});

await nav.close();
console.log(fallos ? `\n\x1b[31m${fallos} fallo(s)\x1b[0m`
                   : '\n\x1b[32mtodo en verde\x1b[0m');
process.exit(fallos ? 1 : 0);
