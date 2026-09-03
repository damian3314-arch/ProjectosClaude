/**
 * La página de mensualidad: docs/mensualidad.html
 *
 * POR QUÉ EXISTE ESTA PÁGINA
 * El embudo llega de Instagram, Facebook y TikTok al WhatsApp, y ahí se
 * parte en dos. Quien quiere CLASE SUELTA se va a la página y el sistema
 * lo lleva de la mano. Quien quiere MENSUALIDAD no se iba a ninguna
 * parte: se le contestaba a mano y a veces se le mandaba el número de
 * cuenta «por error» y pagaba. Esa plata entraba al banco sin nombre,
 * sin hora y sin nadie que supiera de quién era.
 *
 * LO QUE ESTA PRUEBA PROTEGE
 * Tres cosas, y ninguna es que la página sea bonita:
 *
 *   1. QUE NADIE PAGUE SIN CUPO. Con 25 mensualidades por hora, mandar a
 *      pagar a quien no alcanzó es crear el problema que la página vino
 *      a resolver — un depósito sin dueño y una clienta molesta.
 *
 *   2. QUE EL SERVIDOR MANDE SOBRE LA PANTALLA. Entre que la página
 *      pinta «quedan 2» y la persona termina de escribir su cédula, esos
 *      dos cupos pueden haberse ido. Si el servidor responde
 *      `lista_espera`, la página tiene que obedecer aunque acabara de
 *      pintar que había sitio.
 *
 *   3. QUE SE DIGA ANTES, NO DESPUÉS. Llenar un formulario creyendo que
 *      compras y descubrir al final que quedaste en una lista es la peor
 *      forma de enterarse.
 *
 * El API se simula: así se puede probar la hora llena, que con los datos
 * reales de hoy no existe, y la prueba no depende de que el Worker esté
 * arriba ni gasta cupos de verdad.
 *
 *   node mensualidad-pagina.test.mjs
 */
import { chromium } from 'playwright-core';

const PAGINA = 'file:///home/user/ProjectosClaude/docs/mensualidad.html';

const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });

let fallos = 0;
const ok = (n, c, extra = '') => { if (!c) fallos++;
  console.log(`${c ? '✓' : '✗'} ${n}${extra ? '  → ' + extra : ''}`); };

/* Abre la página con el API simulado. `cupos` son las horas que
   devuelve el GET; `solicitar` es lo que contesta el POST, para poder
   forzar que el servidor diga otra cosa que la pantalla. */
async function abrir({ cupos, solicitar, pague } = {}) {
  const p = await b.newPage({ viewport: { width: 420, height: 940 } });
  const errs = [];
  p.on('pageerror', e => errs.push(String(e)));
  await p.addInitScript(([c, s, g]) => {
    window.__llamadas = [];
    window.fetch = async (url, opc) => {
      const cuerpo = opc && opc.body ? JSON.parse(opc.body) : null;
      window.__llamadas.push({ url: String(url), cuerpo });
      let d;
      if (String(url).endsWith('/solicitar')) d = s;
      else if (String(url).endsWith('/pague')) d = g;
      else d = c;
      return { ok: true, json: async () => d };
    };
  }, [
    cupos || { ok: true, tope: 25, valor_cop: 125000, horas: [
      { hora: '07:00', etiqueta: '7:00 am', ocupadas: 20, tope: 25, libres: 5 },
      { hora: '18:00', etiqueta: '6:00 pm', ocupadas: 24, tope: 25, libres: 1 },
      { hora: '19:00', etiqueta: '7:00 pm', ocupadas: 25, tope: 25, libres: 0 },
    ] },
    solicitar || { ok: true, id: '11111111-2222-3333-4444-555555555555',
                   estado: 'esperando_pago', valor_cop: 125000, ya_estaba: false },
    pague || { ok: true, estado: 'pagada', ya_estaba: false },
  ]);
  await p.goto(PAGINA);
  await p.waitForSelector('.hora', { timeout: 10000 });
  return { p, errs };
}

const llenar = async (p, { nombre = 'María Ruiz', celular = '3001234567',
                           habeas = true } = {}) => {
  await p.fill('#nombre', nombre);
  await p.fill('#celular', celular);
  if (habeas) await p.check('#habeas');
};

// ═══════ los cupos, tal como se pintan ═══════════════════════════
{
  const { p, errs } = await abrir();
  const txt = await p.evaluate(() =>
    [...document.querySelectorAll('.hora')].map(h => h.innerText).join(' ~ '));

  ok('pinta las tres horas', (await p.locator('.hora').count()) === 3);
  ok('la de 5 cupos los dice en plural', /Quedan 5 cupos/.test(txt));
  // "Queda 1 cupo" y no "Quedan 1 cupos": el número exacto mueve mucho
  // más que "hay cupo", y una concordancia rota lo hace parecer roto.
  ok('la de 1 cupo va en singular', /Queda 1 cupo\b/.test(txt) && !/Quedan 1 cupos/.test(txt));
  ok('la llena dice que es lista de espera',
     /Sin cupo/.test(txt) && /lista de espera/.test(txt));
  ok('y se distinguen de un vistazo',
     (await p.locator('.pastilla.libre').count()) === 2 &&
     (await p.locator('.pastilla.lleno').count()) === 1);
  ok('el precio sale del servidor, no del HTML',
     (await p.locator('#precio').textContent()).includes('125.000'));
  ok('sin errores de JS', errs.length === 0, errs.join(' | '));
  await p.close();
}

// ═══════ se dice ANTES de pedir los datos ════════════════════════
{
  const { p } = await abrir();
  await p.click('.hora[data-hora="07:00"]');
  let sub = await p.locator('#sub1').innerText();
  ok('con cupo, avisa que se aparta mientras paga', /apartamos el cupo/.test(sub), sub);
  ok('y el botón lleva al pago',
     (await p.locator('#btn-enviar').textContent()).includes('pago'));

  await p.click('#volver0');
  await p.click('.hora[data-hora="19:00"]');
  sub = await p.locator('#sub1').innerText();
  ok('sin cupo, lo dice ANTES de que llene nada', /está lleno/.test(sub), sub);
  ok('y deja claro que no se paga nada', /No tienes que pagar nada ahora/.test(sub));
  ok('el botón ya no habla de pagar',
     (await p.locator('#btn-enviar').textContent()).includes('lista de espera'));
  await p.close();
}

// ═══════ lo que no se puede mandar ═══════════════════════════════
{
  const { p } = await abrir();
  await p.click('.hora[data-hora="07:00"]');

  await p.click('#btn-enviar');
  ok('sin nombre no manda nada', /Escribe tu nombre/.test(await p.locator('#err1').innerText()));

  await p.fill('#nombre', 'María Ruiz');
  await p.fill('#celular', '300123');
  await p.click('#btn-enviar');
  ok('un celular corto tampoco', /10 dígitos/.test(await p.locator('#err1').innerText()));

  await p.fill('#celular', '3001234567');
  await p.click('#btn-enviar');
  ok('ni sin autorizar los datos',
     /autorizar el uso de tus datos/.test(await p.locator('#err1').innerText()),
     'es un dato personal: sin permiso no se guarda');

  ok('no se llamó al servidor ni una vez',
     (await p.evaluate(() => window.__llamadas.filter(l => l.url.endsWith('/solicitar')).length)) === 0);

  /* La trampa para bots. Se comprueba que esté FUERA DE LA PANTALLA y no
     con `isVisible()`: Playwright cuenta como visible un campo de 1px
     aunque esté a -9999px, y esa es justo la técnica — un `display:none`
     lo detectan los bots y no caen. Lo que importa es que un humano no
     pueda verlo ni tabular hasta él. */
  const trampa = await p.evaluate(() => {
    const e = document.querySelector('#apellido2');
    const r = e.getBoundingClientRect();
    return { x: r.x, ancho: r.width, tab: e.tabIndex, valor: e.value };
  });
  ok('el campo trampa está fuera de la pantalla', trampa.x < -1000,
     `x=${trampa.x}`);
  ok('y no se llega a él tabulando', trampa.tab === -1);
  ok('nace vacío, que es lo que lo delata cuando un bot lo llena',
     trampa.valor === '');
  await p.close();
}

// ═══════ el camino bueno: hay cupo y paga ════════════════════════
{
  const { p, errs } = await abrir();
  await p.click('.hora[data-hora="07:00"]');
  await llenar(p);
  await p.fill('#documento', '1098765432');
  await p.fill('#correo', 'maria@correo.com');
  await p.click('#btn-enviar');
  await p.waitForSelector('#s2:not([hidden])', { timeout: 5000 });

  const env = await p.evaluate(() =>
    window.__llamadas.find(l => l.url.endsWith('/solicitar')).cuerpo);
  ok('manda la hora elegida', env.hora === '07:00');
  ok('y el celular limpio', env.celular === '3001234567');
  ok('con el documento y el correo', env.documento === '1098765432' && env.correo === 'maria@correo.com');
  ok('y la autorización de datos', env.habeas === true);

  const pago = await p.locator('#s2').innerText();
  ok('la pantalla de pago dice el valor', /125\.000/.test(pago));
  ok('trae la llave, la cuenta y el titular',
     /1096803067/.test(pago) && /91289724619/.test(pago) && /Luz Alejandra/.test(pago));
  // El QR es estático: no lleva el monto dentro. Sin decirlo, la gente
  // escanea y transfiere cualquier valor.
  ok('avisa de que el QR no trae el valor', /El QR no trae el valor/.test(pago));
  ok('dice cuánto le dura el cupo apartado', /24 horas/.test(pago));

  await p.fill('#referencia', 'M12621896');
  await p.click('#btn-pague');
  await p.waitForSelector('#s3:not([hidden])', { timeout: 5000 });
  const av = await p.evaluate(() =>
    window.__llamadas.find(l => l.url.endsWith('/pague')).cuerpo);
  ok('el aviso de pago lleva la referencia', av.referencia === 'M12621896',
     'es lo que amarra el cobro con el renglón del extracto');
  ok('y va con el id de la solicitud, no con el celular',
     av.id === '11111111-2222-3333-4444-555555555555');

  const fin = await p.locator('#s3').innerText();
  ok('el final no promete que ya quedó confirmada',
     /Estamos confirmando/.test(fin) && !/confirmad[oa]\b(?!.*Estamos)/i.test(fin.replace('Estamos confirmando','')),
     'lo confirma el banco, no este botón');
  ok('sin errores de JS', errs.length === 0, errs.join(' | '));
  await p.close();
}

// ═══════ lista de espera: no se le enseña la cuenta ══════════════
{
  const { p } = await abrir({
    solicitar: { ok: true, id: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
                 estado: 'lista_espera', valor_cop: 125000, ya_estaba: false },
  });
  await p.click('.hora[data-hora="19:00"]');
  await llenar(p);
  await p.click('#btn-enviar');
  await p.waitForSelector('#s3:not([hidden])', { timeout: 5000 });

  ok('la pantalla de pago NUNCA se abre', await p.locator('#s2').isHidden(),
     'quien no tiene cupo no puede ver la cuenta');
  const fin = await p.locator('#s3').innerText();
  ok('le dice que quedó en la lista', /Quedaste en la lista/.test(fin));
  ok('y que no pague nada', /No pagues nada todavía/.test(fin));
  ok('con su horario, para que sepa de cuál habla', /7:00 pm/.test(fin));
  await p.close();
}

/* ═══════ EL CASO QUE DE VERDAD IMPORTA ═══════════════════════════
   La página pintó «quedan 5» en las 7am y la persona se demoró
   escribiendo. Para cuando manda, el último cupo ya se fue y el
   servidor responde `lista_espera`. La página tiene que obedecer al
   servidor, no a lo que ella misma pintó hace un minuto: si la mandara
   a pagar, esa plata entraría al banco sin cupo que darle. */
{
  const { p } = await abrir({
    solicitar: { ok: true, id: 'ffffffff-1111-2222-3333-444444444444',
                 estado: 'lista_espera', valor_cop: 125000, ya_estaba: false },
  });
  await p.click('.hora[data-hora="07:00"]');   // la pantalla decía 5 libres
  await llenar(p);
  await p.click('#btn-enviar');
  await p.waitForSelector('#s3:not([hidden])', { timeout: 5000 });

  ok('si el cupo se fue mientras escribía, NO la manda a pagar',
     await p.locator('#s2').isHidden(),
     'manda el servidor, no lo que la pantalla pintó antes');
  ok('y cae en la lista de espera',
     /Quedaste en la lista/.test(await p.locator('#s3').innerText()));
  await p.close();
}

// ═══════ cuando el servidor no contesta ══════════════════════════
{
  const p = await b.newPage({ viewport: { width: 420, height: 940 } });
  const errs = []; p.on('pageerror', e => errs.push(String(e)));
  await p.addInitScript(() => { window.fetch = async () => { throw new Error('caído'); }; });
  await p.goto(PAGINA);
  await p.waitForSelector('#err0 .aviso', { timeout: 10000 });
  const t = await p.locator('#err0').innerText();
  ok('si no puede leer los cupos, lo dice', /No pudimos leer los cupos/.test(t));
  // Y sobre todo: manda a WhatsApp en vez de dejarla mirando una página
  // muerta. El negocio no se cae porque se caiga esto.
  ok('y deja una salida por WhatsApp',
     (await p.locator('#err0 a').count()) === 1);
  ok('sin reventar con un error de JS', errs.length === 0, errs.join(' | '));
  await p.close();
}

console.log(fallos ? `\n${fallos} fallo(s)` : '\nTodo bien');
await b.close();
process.exit(fallos ? 1 : 0);
