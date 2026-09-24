/**
 * Comprar una tiquetera desde la página de mensualidad (0098): el mismo
 * mecanismo de pago que una clase suelta, sin arriesgar el embudo de
 * mensualidad que ya trae la plata.
 *
 * POR QUÉ EXISTE
 * Damián: «el pago se confirma automático porque quedaría como cuando
 * compran clase suelta; si no se puede confirmar en automático, pues se
 * activa que nos contacte por WhatsApp». Y aparte: recuperar el código
 * por celular si se pierde.
 *
 * Cuatro cosas que no pueden fallar:
 *
 *   1. Elegir paquete → datos → pago es un flujo aparte del de
 *      mensualidad: no debe tocar ni un pixel de esa pantalla.
 *   2. Cuando el banco confirma sola, se ve el código y cuántas clases
 *      trae, con un enlace para guardarlo en WhatsApp (sin mandar nada
 *      automático: es un wa.me sin número, la persona elige a quién).
 *   3. Cuando NO se confirma a tiempo, se invita a escribir por
 *      WhatsApp -- nunca se le dice "listo" a alguien que no pagó.
 *   4. Buscar el código perdido por celular funciona, y dice claro
 *      cuando no hay nada que encontrar.
 *
 * El API se simula (mismo patrón que mensualidad-pagina.test.mjs) y el
 * tiempo de espera se acorta escribiendo una copia temporal del archivo:
 * 3 minutos de verdad harían la prueba eterna.
 *
 *   node tiquetera-mensualidad.test.mjs
 */
import { chromium } from 'playwright-core';
import { readFileSync, writeFileSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const ORIGINAL = '/home/user/ProjectosClaude/docs/mensualidad.html';
const dir = mkdtempSync(join(tmpdir(), 'tiquetera-mens-'));
const COPIA = join(dir, 'mensualidad.html');
writeFileSync(COPIA,
  readFileSync(ORIGINAL, 'utf8')
    .replace('MINUTOS_ESPERA_TIQ: 3', 'MINUTOS_ESPERA_TIQ: 0.05'));
const PAGINA = 'file://' + COPIA;

const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });

let fallos = 0;
const ok = (n, c, extra = '') => { if (!c) fallos++;
  console.log(`${c ? '✓' : '✗'} ${n}${extra ? '  → ' + extra : ''}`); };
const titulo = t => console.log(`\n-- ${t} ${'-'.repeat(Math.max(0, 54 - t.length))}`);

async function abrir({ estado } = {}) {
  const p = await b.newPage({ viewport: { width: 420, height: 940 } });
  const errs = []; p.on('pageerror', e => errs.push(String(e)));

  await p.addInitScript(([estadoResp]) => {
    window.__llamadas = [];
    window.fetch = async (url, opc) => {
      const cuerpo = opc && opc.body ? JSON.parse(opc.body) : null;
      window.__llamadas.push({ url: String(url), cuerpo });
      const u = String(url);
      let d;
      if (u.endsWith('/paquetes')) {
        d = { ok: true, paquetes: [
          { clave: '4', clases: 4, precio_cop: 52000, vigencia_dias: 45 },
          { clave: '8', clases: 8, precio_cop: 96000, vigencia_dias: 90 },
        ] };
      } else if (u.endsWith('/comprar')) {
        d = { ok: true, id: 1, codigo: 'ABC123', precio_cop: 52000, clases: 4,
              vence_el: '2026-11-08' };
      } else if (u.endsWith('/pague')) {
        d = { ok: true, estado: 'pendiente_pago', ya_estaba: false };
      } else if (u.includes('/estado')) {
        // El Worker de verdad, con vencido=1, contesta pendiente_validacion
        // -- no el mismo estado que antes. El mock imita eso.
        d = u.includes('vencido=1')
          ? { ok: true, estado: 'pendiente_validacion', codigo: 'ABC123' }
          : (estadoResp || { ok: true, estado: 'confirmada', codigo: 'ABC123',
                             clases: 4, tiquetera_saldo: 4 });
      } else if (u.endsWith('/recuperar')) {
        d = { ok: false, error: 'SIN_TIQUETERA',
              mensaje: 'No encontramos una tiquetera activa con ese celular. '
                    + 'Si crees que es un error, escríbenos por WhatsApp.' };
      } else {
        d = { ok: true, valor_cop: 125000, horas: [
          { hora: '07:00', etiqueta: '7:00 am', ocupadas: 20, tope: 25, libres: 5 },
        ] };
      }
      return { ok: true, json: async () => d };
    };
  }, [estado]);
  await p.goto(PAGINA);
  await p.waitForSelector('.hora', { timeout: 10000 });
  return { p, errs };
}

/* ═══════ 1 · el enlace no toca el embudo de mensualidad ═══════ */

titulo('1. Entrar y salir de la tiquetera');
{
  const { p, errs } = await abrir();
  ok('mensualidad arranca visible', await p.locator('#s0').isVisible());
  ok('la tiquetera arranca oculta', await p.locator('#tiquetera-todo').isHidden());

  await p.locator('#link-tiquetera').click();
  ok('ahora se ve la tiquetera', await p.locator('#tiquetera-todo').isVisible());
  ok('y se esconden los pasos de mensualidad', await p.locator('#pasos').isHidden());
  await p.waitForSelector('#tiq-paquetes .hora', { timeout: 8000 });
  ok('trae los dos paquetes', (await p.locator('#tiq-paquetes .hora').count()) === 2);

  await p.locator('#volver-mensualidad-0').click();
  ok('volver deja la tiquetera oculta otra vez', await p.locator('#tiquetera-todo').isHidden());
  ok('y mensualidad vuelve a verse', await p.locator('#s0').isVisible());

  ok('sin errores de JS', errs.length === 0, errs.join(' | '));
  await p.close();
}

/* ═══════ 2 · comprar y que el banco confirme solo ═══════ */

titulo('2. El banco confirma automático, como una suelta');
{
  const { p, errs } = await abrir({
    estado: { ok: true, estado: 'confirmada', codigo: 'ABC123', clases: 4, tiquetera_saldo: 4 },
  });
  await p.locator('#link-tiquetera').click();
  await p.waitForSelector('#tiq-paquetes .hora', { timeout: 8000 });
  await p.locator('#tiq-paquetes .hora').first().click();

  ok('pasa a pedir los datos', await p.locator('#st1').isVisible());
  await p.fill('#tiq-nombre', 'Camila Rojas');
  await p.fill('#tiq-celular', '3001234567');
  await p.check('#tiq-habeas');
  await p.locator('#tiq-btn-enviar').click();

  await p.waitForSelector('#st2', { state: 'visible', timeout: 8000 });
  ok('pide el pago con el monto del paquete', (await p.locator('#tiq-monto').textContent()).includes('52.000'));

  await p.locator('#tiq-btn-pague').click();
  await p.waitForSelector('#tiq-final:not([hidden])', { timeout: 8000 });

  const cuerpo = await p.locator('#tiq-final').innerText();
  ok('dice que quedó activa, sin decir "pago confirmado" a secas',
     /activa/i.test(cuerpo), cuerpo.replace(/\n/g, ' '));
  ok('muestra el código', /ABC123/.test(cuerpo));
  ok('dice cuántas clases trae', /4.*clases/i.test(cuerpo));
  ok('sin ofrecer WhatsApp de soporte (salió bien)', await p.locator('#tiq-wa').isHidden());

  // El "guardar en WhatsApp" es un wa.me SIN número: nunca manda nada
  // solo, la persona elige a quién. Si tuviera número, seria un envío
  // automático que Damián explícitamente no tiene armado todavía.
  const href = await p.getByRole('link', { name: 'Guardar el código en WhatsApp' }).getAttribute('href');
  ok('el enlace de guardar no tiene número de destino',
     /^https:\/\/wa\.me\/\?text=/.test(href), href);
  ok('y lleva el código adentro', decodeURIComponent(href).includes('ABC123'));

  ok('sin errores de JS', errs.length === 0, errs.join(' | '));
  await p.close();
}

/* ═══════ 3 · el banco NO confirma: invita a WhatsApp ═══════ */

titulo('3. Sin confirmación a tiempo, invita a escribir');
{
  const { p, errs } = await abrir({
    estado: { ok: true, estado: 'pendiente_pago', codigo: 'ABC123' },
  });
  await p.locator('#link-tiquetera').click();
  await p.waitForSelector('#tiq-paquetes .hora', { timeout: 8000 });
  await p.locator('#tiq-paquetes .hora').first().click();
  await p.fill('#tiq-nombre', 'Camila Rojas');
  await p.fill('#tiq-celular', '3001234567');
  await p.check('#tiq-habeas');
  await p.locator('#tiq-btn-enviar').click();
  await p.waitForSelector('#st2', { state: 'visible', timeout: 8000 });
  await p.locator('#tiq-btn-pague').click();

  // Con MINUTOS_ESPERA_TIQ en 0.05 (3 segundos), el primer intervalo de
  // 5s ya la manda a vencida. Se espera un poco más que eso, sin
  // esperar los 3 minutos de verdad.
  await p.waitForSelector('#tiq-final:not([hidden])', { timeout: 12000 });

  const cuerpo = await p.locator('#tiq-final').innerText();
  ok('no dice que quedó activa', !/está activa/i.test(cuerpo), cuerpo.replace(/\n/g, ' '));
  ok('SÍ ofrece escribir por WhatsApp', await p.locator('#tiq-wa').isVisible());
  ok('con el código en el mensaje',
     decodeURIComponent(await p.locator('#tiq-wa').getAttribute('href')).includes('ABC123'));

  ok('sin errores de JS', errs.length === 0, errs.join(' | '));
  await p.close();
}

/* ═══════ 4 · recuperar el código perdido ═══════ */

titulo('4. Recuperar código por celular');
{
  const { p, errs } = await abrir();
  await p.locator('#link-recuperar').click();
  ok('se ve el formulario de recuperar', await p.locator('#recuperar-todo').isVisible());

  await p.fill('#rec-celular', '3001234567');
  await p.locator('#rec-btn').click();
  await p.waitForSelector('#err-r0 .aviso', { timeout: 8000 });
  ok('sin tiquetera activa, lo dice claro',
     /no encontramos/i.test(await p.locator('#err-r0').innerText()));

  await p.locator('#rec-volver').click();
  ok('volver regresa a mensualidad', await p.locator('#s0').isVisible());

  ok('sin errores de JS', errs.length === 0, errs.join(' | '));
  await p.close();
}

await b.close();
console.log(fallos ? `\n\x1b[31m${fallos} fallo(s)\x1b[0m`
                   : '\n\x1b[32mtodo en verde\x1b[0m');
process.exit(fallos ? 1 : 0);
