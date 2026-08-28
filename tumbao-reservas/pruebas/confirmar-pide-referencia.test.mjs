/**
 * "Confirmar igual" no se enciende sin la referencia del comprobante.
 *
 * La regla que pidió la dueña es que la cajera no pueda confirmar sin
 * tener el comprobante delante. El freno vive en el panel, así que hay
 * que probarlo en el panel: que el botón nace apagado, que sigue apagado
 * con cualquier cosa tecleada, que enciende con una referencia de
 * verdad, y que esa referencia llega al servidor. Lo último es lo que
 * importa: un botón que enciende pero manda el campo vacío deja el
 * agujero igual de abierto.
 *
 * Se comprueba también que el recuadro de escribir se vea —tiene su CSS
 * propio—, porque un input sin estilo dentro de una fila flex se
 * encoge hasta desaparecer y nadie lo encuentra.
 *
 * Necesita Chromium:
 *   node confirmar-pide-referencia.test.mjs <ruta a admin.html con __e2e>
 */
import { chromium } from 'playwright-core';
const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
const p = await b.newPage({ viewport: { width: 430, height: 900 } });

const enviado = [];
await p.route('**/api/**', async r => {
  enviado.push({ url: r.request().url(), cuerpo: JSON.parse(r.request().postData() || '{}') });
  await r.fulfill({ status: 200, contentType: 'application/json',
    body: JSON.stringify({ ok: true, mensaje: 'confirmada' }) });
});
const errs = []; p.on('pageerror', e => errs.push(String(e)));
await p.goto('file://' + process.argv[2]);

// Una reserva en la cola, sin depósito cerca: el caso en que la única
// salida es "Confirmar igual", que es justo el que se quiere frenar.
// LA FORMA REAL, copiada de lo que arma admin_pendientes. Inventarla es
// justo lo que dejó pasar el fallo de `p.id` contra `pago_id`.
const COLA = [{
  codigo: 'BE3R2U', nombre: 'Yuri Vargas', telefono: '3001234567',
  estado: 'pendiente_validacion', sin_aviso: false, vencida: false,
  cupo_libre: true, tipo: 'clase_suelta',
  creada_at: '2026-08-28T15:12:00+00:00', pagado_en: '2026-08-28T15:20:00+00:00',
  pagador: 'Yuri Vargas', referencia: null,
  clase_id: '99999999-8888-4777-8666-555555555555',
  clase: 'Salsa principiantes', fecha_hora: '2026-08-29T14:00:00+00:00',
  precio_cop: 15000, cupos: 1, acompanantes: [],
  // Sin depósito cerca: el caso en que la única salida es "Confirmar
  // igual", que es el que se quiere frenar.
  pagos_sueltos: [],
}];
await p.evaluate(l => window.__e2e.sembrarPendientes(l), COLA);

let fallos = 0;
const ok = (n, c, extra='') => { if (!c) fallos++;
  console.log(`${c ? '✓' : '✗'} ${n}${extra ? '  → ' + extra : ''}`); };

// 1) El recuadro existe y se ve.
ok('hay dónde escribir la referencia', await p.evaluate(() => window.__e2e.hayCaja()));
const caja = await p.evaluate(() => window.__e2e.anchoRef());
ok('el recuadro no está encogido', caja && caja.ancho > 150, caja && `${Math.round(caja.ancho)}px`);
ok('y tiene alto usable', caja && caja.alto >= 30, caja && `${Math.round(caja.alto)}px`);
ok('el CSS le llegó (tiene borde)', caja && parseFloat(caja.borde) > 0, caja && caja.borde);

// 2) El botón nace apagado.
let bt = await p.evaluate(() => window.__e2e.boton());
ok('el botón de confirmar existe', bt.existe);
ok('nace apagado', bt.apagado);

// 3) Sigue apagado mientras no haya una referencia de verdad.
for (const basura of ['', '  ', 'ab', '12 ']) {
  await p.evaluate(t => window.__e2e.teclear(t), basura);
  bt = await p.evaluate(() => window.__e2e.boton());
  ok(`sigue apagado con ${JSON.stringify(basura)}`, bt.apagado);
}

// 4) Enciende con una referencia real.
await p.evaluate(() => window.__e2e.teclear('M4X7K92C'));
bt = await p.evaluate(() => window.__e2e.boton());
ok('enciende con una referencia', !bt.apagado);

// 5) Y si la borran, se vuelve a apagar: no se queda encendido.
await p.evaluate(() => window.__e2e.teclear('x'));
bt = await p.evaluate(() => window.__e2e.boton());
ok('se vuelve a apagar si la borran', bt.apagado);

// 6) La referencia llega al servidor.
await p.evaluate(() => window.__e2e.teclear('  M4X7K92C  '));
await p.evaluate(() => window.__e2e.clic());
await p.waitForTimeout(300);
const conf = enviado.find(x => /confirmar/.test(x.url));
ok('se llamó a confirmar', !!conf, conf && conf.url);
ok('con la referencia tecleada', conf && conf.cuerpo.referencia === 'M4X7K92C',
   conf && JSON.stringify(conf.cuerpo.referencia));
ok('y con el código de la reserva', conf && conf.cuerpo.codigo === 'BE3R2U',
   conf && String(conf.cuerpo.codigo));

// 7) "Es este" no pide nada. Enlaza un depósito REAL del banco, que
// prueba más que cualquier referencia tecleada; si este camino
// empezara a exigirla, cruzar desde la cola quedaría roto.
const DEPO = '77777777-6666-4555-8444-333333333333';
await p.evaluate(([c, d]) => window.__e2e.sembrarPendientes([{ ...c[0],
  pagos_sueltos: [{ pago_id: d, valor_cop: 15000, fecha: '2026-08-28T15:22:00+00:00',
                    cuadra: true, parecido: 0.95, remitente: 'YURI VARGAS', minutos: 2 }] }]),
  [COLA, DEPO]);
enviado.length = 0;
ok('el botón "Es este" está', await p.evaluate(() => window.__e2e.clicEsEste()));
await p.waitForTimeout(300);
const cruce = enviado.find(x => /confirmar/.test(x.url));
ok('cruzar con "Es este" sigue funcionando sin escribir nada', !!cruce);
ok('y manda el depósito', cruce && cruce.cuerpo.pago_id === DEPO,
   cruce && String(cruce.cuerpo.pago_id));
ok('sin referencia inventada', cruce && !cruce.cuerpo.referencia,
   cruce && JSON.stringify(cruce.cuerpo.referencia));

ok('sin errores de JS', errs.length === 0, errs.join(' | '));
console.log(fallos ? `\n${fallos} fallo(s)` : '\nTodo bien');
await b.close();
process.exit(fallos ? 1 : 0);
