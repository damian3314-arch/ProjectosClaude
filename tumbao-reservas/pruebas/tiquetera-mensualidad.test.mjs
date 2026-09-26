/**
 * Comprar una tiquetera desde la página de mensualidad (0098 + rediseño
 * de tarjetas): el mismo mecanismo de pago que una clase suelta, sin
 * arriesgar el embudo de mensualidad que ya trae la plata.
 *
 * POR QUÉ EXISTE
 * Damián: «el pago se confirma automático porque quedaría como cuando
 * compran clase suelta; si no se puede confirmar en automático, pues se
 * activa que nos contacte por WhatsApp». Y después pidió que la entrada
 * fuera de tarjetas -- una para mensualidad, una para cada tiquetera --
 * y que en ellas mismas, sin tener que buscarlo, quedara clarísimo que
 * hay que reservar cada clase y que la tiquetera vence al mes.
 *
 * Cinco cosas que no pueden fallar:
 *
 *   1. Lo primero que se ve es la elección de tres tarjetas, no el
 *      embudo de mensualidad empujando por delante.
 *   2. Las tarjetas de tiquetera dicen, en su propio texto, que hay que
 *      reservar y la vigencia -- y el ahorro real contra clase suelta.
 *   3. Elegir una tiquetera por su tarjeta salta directo a pedir los
 *      datos: el paquete ya está decidido, no hay que volver a elegirlo.
 *   4. Cuando el banco confirma sola, se ve el código y cuántas clases
 *      trae, con un enlace para guardarlo en WhatsApp (sin mandar nada
 *      automático: es un wa.me sin número, la persona elige a quién).
 *      Cuando NO se confirma a tiempo, se invita a escribir por
 *      WhatsApp -- nunca se le dice "listo" a alguien que no pagó.
 *   5. Buscar el código perdido por celular funciona desde la elección,
 *      y volver regresa ahí, no a mensualidad.
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
          { clave: '4', clases: 4, precio_cop: 52000, vigencia_dias: 30 },
          { clave: '8', clases: 8, precio_cop: 96000, vigencia_dias: 30 },
        ] };
      } else if (u.endsWith('/comprar')) {
        d = { ok: true, id: 1, codigo: 'ABC123', precio_cop: 52000, clases: 4,
              vence_el: '2026-10-26' };
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
        d = cuerpo && cuerpo.celular === '3009998877'
          ? { ok: true, tiqueteras: [
              { codigo: 'XYZ999', clases_restantes: 2, vence_el: '2026-10-10' } ] }
          : { ok: false, error: 'SIN_TIQUETERA',
              mensaje: 'No encontramos una tiquetera activa con ese celular. '
                    + 'Si crees que es un error, escríbenos por WhatsApp.' };
      } else {
        d = { ok: true, valor_cop: 125000, horas: [
          { hora: '07:00', etiqueta: '7:00 am', libres: 5 },
        ] };
      }
      return { ok: true, json: async () => d };
    };
  }, [estado]);
  await p.goto(PAGINA);
  await p.waitForSelector('#tarjetas-eleccion .tarjeta', { timeout: 10000 });
  return { p, errs };
}

/* ═══════ 1 · lo primero es la elección, con lo clave a la vista ═══ */

titulo('1. Las tres tarjetas de entrada');
{
  const { p, errs } = await abrir();
  ok('la elección arranca visible', await p.locator('#eleccion').isVisible());
  ok('mensualidad arranca oculta detrás', await p.locator('#s0').isHidden());

  const tarjetas = p.locator('#tarjetas-eleccion .tarjeta');
  ok('hay tres tarjetas (mensualidad + 2 tiqueteras)',
     await tarjetas.count() === 3, String(await tarjetas.count()));

  const t4 = p.locator('[data-elegir="tq"][data-clave="4"]');
  const texto4 = await t4.innerText();
  ok('la tarjeta de 4 clases dice que hay que reservar',
     /reservas cada clase/i.test(texto4), texto4.replace(/\n/g, ' '));
  ok('y dice los 30 días, sin tener que buscarlo',
     /30 días/i.test(texto4), texto4.replace(/\n/g, ' '));
  ok('trae el ahorro real contra clase suelta',
     /ahorras \$8\.000/i.test(texto4), texto4.replace(/\n/g, ' '));

  const t8 = p.locator('[data-elegir="tq"][data-clave="8"]');
  ok('la de 8 también avisa la vigencia', /30 días/i.test(await t8.innerText()));
  ok('la de 8 se marca como mejor precio', /mejor precio/i.test(await t8.innerText()));

  ok('sin errores de JS', errs.length === 0, errs.join(' | '));
  await p.close();
}

/* ═══════ 2 · mensualidad sigue siendo la de siempre ═══════════════ */

titulo('2. Mensualidad, sin tocarle ni un pixel');
{
  const { p, errs } = await abrir();
  await p.locator('[data-elegir="mensualidad"]').click();
  ok('entra al paso de horario de mensualidad', await p.locator('#s0').isVisible());
  ok('la barra de pasos reaparece', await p.locator('#pasos').isVisible());
  await p.waitForSelector('.clase.hora', { timeout: 8000 });
  ok('los horarios de mensualidad se pintan', (await p.locator('.clase.hora').count()) > 0);

  await p.locator('#volver-eleccion-mens').click();
  ok('"cambiar de opción" regresa a la elección', await p.locator('#eleccion').isVisible());
  ok('y esconde la barra de pasos', await p.locator('#pasos').isHidden());

  ok('sin errores de JS', errs.length === 0, errs.join(' | '));
  await p.close();
}

/* ═══════ 3 · elegir la tarjeta salta directo a los datos ═══════ */

titulo('3. La tarjeta ya decide el paquete');
{
  const { p, errs } = await abrir();
  await p.locator('[data-elegir="tq"][data-clave="4"]').click();
  ok('va directo a pedir los datos (sin pasar por la lista)',
     await p.locator('#st1').isVisible());
  ok('el resumen trae el paquete elegido',
     /4 clases/i.test(await p.locator('#tiq-resumen').innerText()));
  ok('sin errores de JS', errs.length === 0, errs.join(' | '));
  await p.close();
}

/* ═══════ 4 · comprar y que el banco confirme solo ═══════ */

titulo('4. El banco confirma automático, como una suelta');
{
  const { p, errs } = await abrir({
    estado: { ok: true, estado: 'confirmada', codigo: 'ABC123', clases: 4, tiquetera_saldo: 4 },
  });
  await p.locator('[data-elegir="tq"][data-clave="4"]').click();
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

/* ═══════ 5 · el banco NO confirma: invita a WhatsApp ═══════ */

titulo('5. Sin confirmación a tiempo, invita a escribir');
{
  const { p, errs } = await abrir({
    estado: { ok: true, estado: 'pendiente_pago', codigo: 'ABC123' },
  });
  await p.locator('[data-elegir="tq"][data-clave="4"]').click();
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

/* ═══════ 6 · recuperar el código perdido, desde la elección ═══════ */

titulo('6. Recuperar código por celular');
{
  const { p, errs } = await abrir();
  await p.locator('#link-recuperar-2').click();
  ok('se ve el formulario de recuperar', await p.locator('#recuperar-todo').isVisible());

  await p.fill('#rec-celular', '3001234567');
  await p.locator('#rec-btn').click();
  await p.waitForSelector('#err-r0 .aviso', { timeout: 8000 });
  ok('sin tiquetera activa, lo dice claro',
     /no encontramos/i.test(await p.locator('#err-r0').innerText()));

  await p.fill('#rec-celular', '3009998877');
  await p.locator('#rec-btn').click();
  await p.waitForSelector('#rec-resultado b', { timeout: 8000 });
  ok('con tiquetera activa, muestra el código',
     /XYZ999/.test(await p.locator('#rec-resultado').innerText()));

  await p.locator('#rec-volver').click();
  ok('volver regresa a la elección, no a mensualidad', await p.locator('#eleccion').isVisible());

  ok('sin errores de JS', errs.length === 0, errs.join(' | '));
  await p.close();
}

await b.close();
console.log(fallos ? `\n\x1b[31m${fallos} fallo(s)\x1b[0m`
                   : '\n\x1b[32mtodo en verde\x1b[0m');
process.exit(fallos ? 1 : 0);
