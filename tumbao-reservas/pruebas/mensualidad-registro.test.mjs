/**
 * Mensualidad por la página: primera vez (registro completo) y renovación (directo al pago), 29 oct.
 *
 * LO QUE PIDIÓ DAMIÁN
 *   · Quien paga la mensualidad por primera vez deja nombre completo, correo, celular y fecha de nacimiento (sin eso el
 *     sistema de accesos no la crea), acepta el tratamiento de datos y contesta unas preguntas de salud. Si marca algo,
 *     la página le recuerda seguir lo que diga su médico. Al terminar se le dice que llegue 10 o 15 minutos antes de su
 *     primera clase al registro biométrico (la huella).
 *   · Quien ya es alumna y renueva entra por una opción clara: solo nombre y celular, sin salud ni autorizaciones, y pasa
 *     al pago. El bot manda a las alumnas con ?renovar=1.
 *
 * El API se simula, igual que en mensualidad-pagina.test.mjs.
 *
 *   node mensualidad-registro.test.mjs
 */
import { chromium } from 'playwright-core';

const PAGINA = 'file:///home/user/ProjectosClaude/docs/mensualidad.html';
const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });

let fallos = 0;
const ok = (n, c, extra = '') => { if (!c) fallos++; console.log(`${c ? '✓' : '✗'} ${n}${extra ? '  → ' + extra : ''}`); };
const titulo = t => console.log(`\n-- ${t} ${'-'.repeat(Math.max(0, 54 - t.length))}`);

const CUPOS = { ok: true, tope: 25, valor_cop: 125000, horas: [
  { hora: '07:00', etiqueta: '7:00 am', ocupadas: 20, tope: 35, libres: 15 },
  { hora: '18:00', etiqueta: '6:00 pm', ocupadas: 25, tope: 25, libres: 0 },
  { hora: '19:00', etiqueta: '7:00 pm', ocupadas: 15, tope: 25, libres: 10 },
] };
const OK_PAGO = { ok: true, id: '11111111-2222-3333-4444-555555555555', estado: 'esperando_pago', valor_cop: 125000, ya_estaba: false };

/* `respuestas` es la lista de lo que contesta el POST /solicitar, una por llamada (la última se repite). */
async function abrir({ respuestas = [OK_PAGO], url = PAGINA, entrar = true } = {}) {
  const p = await b.newPage({ viewport: { width: 420, height: 940 } });
  const errs = [];
  p.on('pageerror', e => errs.push(String(e)));
  await p.addInitScript(([c, rs]) => {
    window.__llamadas = []; let n = 0;
    window.fetch = async (u, o) => {
      const cuerpo = o && o.body ? JSON.parse(o.body) : null;
      window.__llamadas.push({ url: String(u), cuerpo });
      let d;
      if (String(u).endsWith('/solicitar')) d = rs[Math.min(n++, rs.length - 1)];
      else if (String(u).endsWith('/pague')) d = { ok: true, estado: 'pagada' };
      else d = c;
      return { ok: true, json: async () => d };
    };
  }, [CUPOS, respuestas]);
  await p.goto(url);
  if (entrar) {
    await p.waitForSelector('[data-elegir="mensualidad"]', { timeout: 10000 });
    await p.click('[data-elegir="mensualidad"]');
    await p.waitForSelector('.hora', { timeout: 10000 });
  }
  return { p, errs };
}
const solicitudes = p => p.evaluate(() => window.__llamadas.filter(l => l.url.endsWith('/solicitar')).map(l => l.cuerpo));
const visible = (p, s) => p.locator(s).isVisible();
const SALUD = ['corazon', 'pecho', 'lesion', 'embarazo', 'otra'];

titulo('1. La entrada para quien ya es alumna');
{
  const { p, errs } = await abrir({ entrar: false });
  await p.waitForSelector('#btn-renovar', { timeout: 10000 });
  ok('arriba de los pases hay una opción clara para renovar', await visible(p, '#renovar-caja') && /Renovar mi mensualidad/.test(await p.locator('#btn-renovar').innerText()));
  ok('y dice «¿Ya eres alumna de Tumbao?»', /Ya eres alumna de Tumbao/.test(await p.locator('#renovar-caja').innerText()));

  await p.click('#btn-renovar');
  await p.waitForSelector('.hora', { timeout: 5000 });
  ok('al tocarla se entra a la renovación (no a la tienda)', !(await visible(p, '#eleccion')) && /Renueva tu mensualidad/.test(await p.locator('#s0-titulo').innerText()));
  const filas = await p.locator('.hora').allInnerTexts();
  ok('todas las horas dicen «Renovar», incluso la que está llena para gente nueva', filas.length === 3 && filas.every(f => /Renovar/.test(f)), filas.join(' ~ '));
  ok('ninguna fila habla de lista de espera', !filas.some(f => /Lista de espera|Apuntarme/.test(f)));

  // Datos de quien renueva: solo nombre y celular.
  await p.click('.hora[data-hora="18:00"]');
  ok('el título dice que renueva', /Renueva tu mensualidad/.test(await p.locator('#t1').innerText()));
  ok('el resumen habla de renovación con el precio', /Renovación · 6:00 pm/.test(await p.locator('#resumen').innerText()) && /125\.000/.test(await p.locator('#resumen').innerText()));
  for (const [n, s] of [['fecha de nacimiento', '#nacimiento'], ['correo', '#correo'], ['documento', '#documento'], ['preguntas de salud', '#bloque-salud'],
                        ['declaración de salud', '#salud-ok'], ['autorización de datos', '#habeas'], ['novedades', '#novedades']]) {
    ok(`no pide ${n}`, !(await visible(p, s)));
  }
  ok('sí pide nombre y celular', await visible(p, '#nombre') && await visible(p, '#celular'));
  ok('el botón lleva al pago', /Continuar al pago/.test(await p.locator('#btn-enviar').innerText()));

  await p.fill('#nombre', 'Laura Gómez');
  await p.fill('#celular', '3001112233');
  await p.click('#btn-enviar');
  await p.waitForSelector('#s2:not([hidden])', { timeout: 5000 });
  const [env] = await solicitudes(p);
  ok('manda modo renovación, sin autorización de datos ni salud',
     env.modo === 'renovacion' && env.habeas === undefined && env.salud === undefined && env.nacimiento === undefined, JSON.stringify(env));
  ok('y pasa directo al pago', await visible(p, '#s2'));
  ok('sin errores de JS', errs.length === 0, errs.join(' | '));
  await p.close();
}

titulo('2. El bot manda a las alumnas con ?renovar=1');
{
  const { p } = await abrir({ url: PAGINA + '?renovar=1', entrar: false });
  await p.waitForSelector('.hora', { timeout: 10000 });
  ok('cae directo en la renovación', /Renueva tu mensualidad/.test(await p.locator('#s0-titulo').innerText()) && !(await visible(p, '#eleccion')));
  await p.close();
}

titulo('3. Renueva pero no la encontramos');
{
  const { p } = await abrir({ entrar: false, respuestas: [
    { ok: false, error: 'NO_ENCONTRADA', mensaje: 'No te encontramos como alumna con ese celular. Si es tu primera vez, completa tus datos.' }] });
  await p.waitForSelector('#btn-renovar', { timeout: 10000 });
  await p.click('#btn-renovar');
  await p.waitForSelector('.hora', { timeout: 5000 });
  await p.click('.hora[data-hora="07:00"]');
  await p.fill('#nombre', 'Camila Torres Ríos');
  await p.fill('#celular', '3009998877');
  await p.click('#btn-enviar');
  await p.waitForSelector('#nacimiento', { state: 'visible', timeout: 5000 });
  ok('no queda en un callejón: se abre el formulario de primera vez', await visible(p, '#bloque-salud') && await visible(p, '#habeas'));
  ok('lo explica', /No te encontramos como alumna/.test(await p.locator('#sub1').innerText()));
  ok('y conserva lo que ya escribió', (await p.inputValue('#nombre')) === 'Camila Torres Ríos' && (await p.inputValue('#celular')) === '3009998877');
  await p.close();
}

titulo('4. Primera vez: el registro completo');
{
  const { p, errs } = await abrir({ respuestas: [{ ...OK_PAGO, primera_vez: true, es_renovacion: false }] });
  await p.click('.hora[data-hora="07:00"]');
  ok('pide fecha de nacimiento, correo y las preguntas de salud', await visible(p, '#nacimiento') && await visible(p, '#correo') && await visible(p, '#bloque-salud'));
  ok('hay cinco preguntas de salud', (await p.locator('.pregunta').count()) === 5);
  ok('el correo ya no es opcional', !/opcional/i.test(await p.locator('#l-correo').innerText()));
  ok('la autorización habla de la huella', /huella/i.test(await p.locator('#l-habeas').innerText()));
  ok('el nombre pide apellido', /Nombre completo/.test(await p.locator('#l-nombre').innerText()));

  await p.fill('#nombre', 'María');
  await p.fill('#celular', '3001234567');
  await p.click('#btn-enviar');
  ok('un solo nombre no pasa', /nombre completo, con apellido/.test(await p.locator('#err1').innerText()));
  await p.fill('#nombre', 'María Fernanda Ruiz');

  await p.click('#btn-enviar');
  ok('sin fecha de nacimiento no pasa', /fecha de nacimiento/.test(await p.locator('#err1').innerText()));
  await p.fill('#nacimiento', '1990-05-14');

  await p.fill('#correo', 'sin-arroba');
  await p.click('#btn-enviar');
  ok('un correo malo no pasa', /correo válido/.test(await p.locator('#err1').innerText()));
  await p.fill('#correo', 'maria@correo.com');

  await p.click('#btn-enviar');
  ok('sin contestar la salud no pasa', /cinco preguntas de salud/.test(await p.locator('#err1').innerText()));
  ok('y marca cuáles faltan', (await p.locator('.pregunta.mal').count()) === 5);

  for (const k of SALUD) await p.check(`input[name="s-${k}"][value="0"]`);
  ok('con todo «No» no sale el aviso médico', !(await visible(p, '#aviso-salud')));
  await p.click('#btn-enviar');
  ok('sin la declaración de salud no pasa', /declaración de salud/.test(await p.locator('#err1').innerText()));
  await p.check('#salud-ok');

  await p.click('#btn-enviar');
  ok('sin autorizar los datos no pasa', /autorizar el uso de tus datos/.test(await p.locator('#err1').innerText()));
  ok('hasta aquí no se llamó al servidor', (await solicitudes(p)).length === 0);

  // Marca «Sí» en una: sale la recomendación de seguir al médico.
  await p.check('input[name="s-lesion"][value="1"]');
  ok('si marca «Sí», la página recomienda seguir lo que diga su médico',
     await visible(p, '#aviso-salud') && /recomendaciones médicas/.test(await p.locator('#aviso-salud').innerText()));
  ok('y le deja contar cuál', await visible(p, '#salud-detalle'));
  await p.fill('#salud-detalle', 'Operación de rodilla hace dos años');

  await p.check('#habeas');
  await p.click('#btn-enviar');
  await p.waitForSelector('#s2:not([hidden])', { timeout: 5000 });
  const [env] = await solicitudes(p);
  ok('manda todo el registro al servidor',
     env.modo === 'nueva' && env.nombre === 'María Fernanda Ruiz' && env.nacimiento === '1990-05-14' && env.correo === 'maria@correo.com'
     && env.habeas === true && env.salud_ok === true && env.salud.lesion === true && env.salud.corazon === false
     && /rodilla/.test(env.salud.detalle), JSON.stringify(env));

  await p.click('#btn-pague');
  await p.waitForSelector('#s3:not([hidden])', { timeout: 5000 });
  const final = await p.locator('#final').innerText();
  ok('al terminar le pide llegar 10 o 15 minutos antes', /10 o 15 minutos antes/.test(final), final);
  ok('al registro biométrico: la huella', /registro biométrico/.test(final) && /huella/.test(final));
  ok('sin errores de JS', errs.length === 0, errs.join(' | '));
  await p.close();
}

titulo('5. Quien renueva no ve lo de la huella');
{
  const { p } = await abrir({ entrar: false, respuestas: [{ ...OK_PAGO, primera_vez: false, es_renovacion: true }] });
  await p.waitForSelector('#btn-renovar', { timeout: 10000 });
  await p.click('#btn-renovar');
  await p.waitForSelector('.hora', { timeout: 5000 });
  await p.click('.hora[data-hora="19:00"]');
  await p.fill('#nombre', 'Laura Gómez');
  await p.fill('#celular', '3001112233');
  await p.click('#btn-enviar');
  await p.waitForSelector('#s2:not([hidden])', { timeout: 5000 });
  ok('el pago dice que la encontró', /Te encontramos/.test(await p.locator('#sub2').innerText()));
  await p.click('#btn-pague');
  await p.waitForSelector('#s3:not([hidden])', { timeout: 5000 });
  const final = await p.locator('#final').innerText();
  ok('el final no habla de registro biométrico', !/registro biométrico|10 o 15 minutos/.test(final), final);
  ok('y le confirma que sigue entrando con su huella', /Sigues entrando con tu huella/.test(final));
  await p.close();
}

titulo('6. Lista de espera: sin preguntas de salud hasta que haya cupo');
{
  const { p } = await abrir({ respuestas: [
    { ok: false, error: 'DATOS_INCOMPLETOS', campo: 'nacimiento', mensaje: 'Falta tu fecha de nacimiento.' },
    OK_PAGO] });
  await p.click('.hora[data-hora="18:00"]');
  ok('en un horario lleno no se pide fecha de nacimiento ni salud', !(await visible(p, '#nacimiento')) && !(await visible(p, '#bloque-salud')));
  ok('sí se pide la autorización de datos', await visible(p, '#habeas'));
  ok('la lista de espera ofrece «Renueva aquí»', (await p.locator('#sub1 [data-renovar]').count()) === 1);
  await p.fill('#nombre', 'Paola Díaz');
  await p.fill('#celular', '3015556677');
  await p.check('#habeas');
  await p.click('#btn-enviar');
  // El servidor dice que mientras tanto se liberó un cupo: ahora sí hay compra y faltan los datos.
  await p.waitForSelector('#nacimiento', { state: 'visible', timeout: 5000 });
  ok('si se libera un cupo, la página pide los datos que faltan en vez de fallar', /Hay cupo/.test(await p.locator('#sub1').innerText()) && await visible(p, '#bloque-salud'));
  await p.close();
}

titulo('7. Los cupos reales debajo del botón de comprar');
{
  const { p } = await abrir({ entrar: false });
  await p.waitForSelector('#cupos-vivos:not([hidden])', { timeout: 10000 });
  const t = await p.locator('#cupos-vivos').innerText();
  ok('dice cuántos cupos hay en cada horario, con los números del servidor', /7:00 am · 15 cupos/.test(t) && /7:00 pm · 10 cupos/.test(t), t);
  ok('el horario lleno se dice como lista de espera', /6:00 pm · lista de espera/.test(t), t);
  ok('sin descuentos, regalos ni «últimas horas»', !/descuento|regalo|gratis|promo|últimas horas/i.test(t));
  await p.close();
}

await b.close();
console.log(`\n${fallos ? '✗ ' + fallos + ' con problemas' : '✓ todo bien'}`);
process.exit(fallos ? 1 : 0);
