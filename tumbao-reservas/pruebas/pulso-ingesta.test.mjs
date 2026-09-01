/**
 * El aviso de "la conciliación puede estar caída".
 *
 * Lo que protege: que la ingesta de pagos se muera sin que nadie se
 * entere. Si Gmail deja de reenviar o se cae el Worker, no falla nada
 * visible —la página sigue tomando reservas y la gente sigue pagando—,
 * simplemente nadie se confirma. Eso hoy solo se descubre cuando alguien
 * reclama en la puerta, que fue justo lo que pasó el 31 de agosto.
 *
 * Lo que NO puede hacer es gritar en falso. Una alarma que salta sin
 * motivo se aprende a ignorar, y entonces no sirve el día que importa.
 * Por eso el umbral sale de los datos y no de una corazonada:
 *
 *   · de reserva a confirmación, 21 días reales: mediana 3 min, p90 24
 *   · entre pagos del banco: mediana 32 min, pero p90 3 HORAS y p99 25
 *
 * De ahí que se mida lo primero (alguien esperando) y no lo segundo
 * (silencio del banco), que era la idea inicial y habría saltado casi a
 * diario.
 *
 *   node pulso-ingesta.test.mjs <ruta a admin.html con __e2e>
 */
import { chromium } from 'playwright-core';
const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
const p = await b.newPage({ viewport: { width: 430, height: 900 } });
const errs = []; p.on('pageerror', e => errs.push(String(e)));
await p.goto('file://' + process.argv[2]);

let fallos = 0;
const ok = (n, c, extra = '') => { if (!c) fallos++;
  console.log(`${c ? '✓' : '✗'} ${n}${extra ? '  → ' + extra : ''}`); };

// Las fechas se calculan DENTRO del navegador para que "ahora" sea el
// suyo. Pasarlas ya formadas desde node mete el desfase entre los dos
// relojes justo en lo único que esta prueba mide.
await p.evaluate(() => {
  window.haceMin_ = (m) => new Date(Date.now() - m * 60000).toISOString();
});

// ── el caso normal: nadie lleva esperando ────────────────────────
let r = await p.evaluate(() => window.__e2e.pulso([
  { codigo: 'A1', nombre: 'Ana',  pagado_en: window.haceMin_(2) },
  { codigo: 'A2', nombre: 'Beto', pagado_en: window.haceMin_(11) },
]));
ok('con esperas normales no avisa nada', r.visible === false, r.texto.slice(0, 60));

r = await p.evaluate(() => window.__e2e.pulso([
  { codigo: 'A1', nombre: 'Ana',  pagado_en: window.haceMin_(2) },
  { codigo: 'A2', nombre: 'Beto', pagado_en: window.haceMin_(24) },
]));
ok('24 minutos todavía no es alarma (es el p90)', r.visible === false, r.texto.slice(0, 60));

// ── alguien varado ───────────────────────────────────────────────
r = await p.evaluate(() => window.__e2e.pulso([
  { codigo: 'A1', nombre: 'Ana', pagado_en: window.haceMin_(47) },
]));
ok('una persona esperando 47 min sí avisa', r.visible === true);
ok('dice cuántas son', /Una persona lleva/.test(r.texto), r.texto.slice(0, 70));
ok('y cuánto lleva la que más', /47/.test(r.texto));
ok('recuerda cuánto es lo normal', /Lo normal son 3/.test(r.texto));
ok('y dice qué hacer', /a mano/.test(r.texto) && /no se va a arreglar sola/.test(r.texto));

// ── varias ───────────────────────────────────────────────────────
r = await p.evaluate(() => window.__e2e.pulso([
  { codigo: 'A1', nombre: 'Ana',  pagado_en: window.haceMin_(35) },
  { codigo: 'A2', nombre: 'Beto', pagado_en: window.haceMin_(90) },
  { codigo: 'A3', nombre: 'Cris', pagado_en: window.haceMin_(5) },
]));
ok('cuenta solo las varadas, no toda la cola', /2 personas llevan/.test(r.texto), r.texto.slice(0, 70));
ok('y toma la más vieja de las varadas', /90/.test(r.texto));

// ── lo que NO debe disparar la alarma ────────────────────────────
r = await p.evaluate(() => window.__e2e.pulso([
  // Sin pagado_en: no ha dicho que pagó, así que no está esperando nada.
  { codigo: 'B1', nombre: 'Sin aviso', pagado_en: null },
  { codigo: 'B2', nombre: 'Tampoco' },
]));
ok('quien no ha dicho que pagó no cuenta', r.visible === false, r.texto.slice(0, 60));

r = await p.evaluate(() => window.__e2e.pulso([
  { codigo: 'C1', nombre: 'Ya resuelta', pagado_en: window.haceMin_(200), _resuelto: true },
]));
ok('lo ya resuelto en pantalla no cuenta', r.visible === false);

r = await p.evaluate(() => window.__e2e.pulso([
  { codigo: 'D1', nombre: 'Fecha rota', pagado_en: 'no es una fecha' },
]));
ok('una fecha ilegible no dispara la alarma ni revienta', r.visible === false);

r = await p.evaluate(() => window.__e2e.pulso([]));
ok('la cola vacía no avisa', r.visible === false);

// ── y que se apague sola cuando se resuelve ──────────────────────
await p.evaluate(() => window.__e2e.pulso([
  { codigo: 'E1', nombre: 'Varada', pagado_en: window.haceMin_(60) },
]));
r = await p.evaluate(() => window.__e2e.pulso([
  { codigo: 'E1', nombre: 'Varada', pagado_en: window.haceMin_(60), _resuelto: true },
]));
ok('al resolverla el aviso desaparece', r.visible === false);

ok('sin errores de JS', errs.length === 0, errs.join(' | '));
console.log(fallos ? `\n${fallos} fallo(s)` : '\nTODO EN VERDE');
await b.close();
process.exit(fallos ? 1 : 0);
