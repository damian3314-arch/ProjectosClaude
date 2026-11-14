// Arma los carruseles de Tumbao (HTML 1080×1350) y saca cada lámina en PNG.
//   node generar.mjs            → todos
//   node generar.mjs tips       → solo uno
// Los PNG quedan en salida/<carrusel>/NN.png (no van al repo: se regeneran con este archivo).
import { writeFileSync, mkdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { chromium } from '/opt/node22/lib/node_modules/playwright/index.mjs';

const AQUI = dirname(fileURLToPath(import.meta.url));

const puntos = (i, n) => `<div class="puntos">${Array.from({ length: n }, (_, k) => `<i class="${k === i ? 'on' : ''}"></i>`).join('')}</div>`;
const marco = (i, n, contenido, { desliza = false, sinLogo = false } = {}) => `
  <section class="slide">
    <div class="led a"></div><div class="led b"></div>
    <div class="top">${sinLogo ? '<span></span>' : '<img src="assets/logo.svg" alt="Tumbao">'}<span class="pag">${i + 1}/${n}</span></div>
    ${contenido}
    ${puntos(i, n)}
    ${desliza ? '<div class="desliza">Desliza →</div>' : ''}
  </section>`;

// ── 1 · Educativo: 5 tips ─────────────────────────────────────────────────────────────────────────────────
const TIPS = [
  ['Llega 10 minutos antes', 'Calientas, escoges tu lugar y arrancas sin afán. <b>Los primeros minutos marcan la clase.</b>'],
  ['Hidrátate antes, durante y después', 'Lleva tu termo: en 45 minutos de rumba <b>se suda en serio.</b>'],
  ['Tenis cómodos y ropa que respire', 'Buen agarre, suela que gire y ropa con la que te muevas sin pensar en ella.'],
  ['No te compares: baila a tu ritmo', 'Si hoy no te sale el paso, la próxima sí. <b>Lo importante es moverte.</b>'],
  ['Constancia antes que intensidad', 'Dos o tres clases por semana hacen más por ti que una clase a full cada mes.'],
];
function tips() {
  const n = TIPS.length + 2;
  const s = [];
  s.push(marco(0, n, `<div class="cuerpo">
      <span class="ceja">Tips Tumbao</span>
      <div class="anton titulo">5 tips para<br><span class="neon">sacarle el jugo</span><br>a tu clase</div>
      <p class="txt">Guárdalo para tu próxima rumba 💃</p>
    </div>`, { desliza: true }));
  TIPS.forEach(([t, d], k) => s.push(marco(k + 1, n, `<div class="cuerpo">
      <div class="num">0${k + 1}</div>
      <div class="anton titulo" style="font-size:104px">${t}</div>
      <p class="txt">${d}</p>
    </div>`)));
  s.push(marco(n - 1, n, `<div class="cuerpo centro">
      <img class="logo-grande" src="assets/logo.svg" alt="Tumbao">
      <div class="anton titulo" style="font-size:96px">¿Nos vemos en tu<br><span class="neon">próxima clase?</span></div>
      <span class="pildora">Reserva en tumbaobaila.com</span>
    </div>`, { sinLogo: true }));
  return s;
}

// ── 2 · Venta suave: haz la cuenta (precios reales de la página: suelta $15.000; tiquetera 4 = $52.000, 8 = $96.000,
//      vigencia 30 días; mensualidad $125.000 ≈ $5.000 la clase si vienes a todas) ───────────────────────────────────
function cuenta() {
  const n = 6;
  return [
    marco(0, n, `<div class="cuerpo">
      <span class="ceja">Haz la cuenta</span>
      <div class="anton titulo">¿Clase suelta,<br>tiquetera o<br><span class="neon">mensualidad?</span></div>
      <p class="txt">Depende de cuántas veces vienes. Te mostramos la cuenta 👇</p>
    </div>`, { desliza: true }),
    marco(1, n, `<div class="cuerpo">
      <span class="ceja">Clase suelta</span>
      <div class="precio">$15.000</div>
      <p class="txt">Ideal para <b>probar</b> o si vienes de vez en cuando. La reservas en un minuto en la página.</p>
    </div>`),
    marco(2, n, `<div class="cuerpo">
      <span class="ceja">Tiquetera de 4 y de 8</span>
      <div class="fila"><div class="k">4 clases<small>$52.000</small></div><div class="v">$13.000</div></div>
      <div class="fila mejor"><div class="k">8 clases<small>$96.000 · ahorras $24.000</small></div><div class="v neon">$12.000</div></div>
      <p class="txt" style="margin-top:20px">El precio es <b>por clase</b>. Las usas cuando quieras durante <b>30 días.</b></p>
    </div>`),
    marco(3, n, `<div class="cuerpo">
      <span class="ceja">Mensualidad</span>
      <div class="precio">$125.000</div>
      <span class="pildora">≈ $5.000 la clase</span>
      <p class="txt">Tu <b>horario fijo</b> de lunes a sábado, si vienes a todas. <b>Cupos limitados</b> por horario.</p>
    </div>`),
    marco(4, n, `<div class="cuerpo">
      <span class="ceja">Si vienes 8 veces al mes</span>
      <div class="fila"><div class="k">8 clases sueltas</div><div class="v">$120.000</div></div>
      <div class="fila"><div class="k">Tiquetera de 8</div><div class="v">$96.000</div></div>
      <div class="fila mejor"><div class="k">Mensualidad<small>todas las clases del mes</small></div><div class="v neon">$125.000</div></div>
      <p class="txt" style="margin-top:20px">Por <b>$5.000 más</b> que 8 sueltas, la mensualidad te da <b>todo el mes.</b></p>
    </div>`),
    marco(5, n, `<div class="cuerpo centro">
      <img class="logo-grande" src="assets/logo.svg" alt="Tumbao">
      <div class="anton titulo" style="font-size:96px">Elige el tuyo y<br><span class="neon">no te detengas</span></div>
      <span class="pildora">tumbaobaila.com/mensualidad</span>
    </div>`, { sinLogo: true }),
  ];
}

const CARRUSELES = { tips, cuenta };

const html = (laminas) => `<!doctype html><html lang="es"><head><meta charset="utf-8">
<link rel="stylesheet" href="estilo.css"></head><body>${laminas.join('\n')}</body></html>`;

const pedidos = process.argv.slice(2).length ? process.argv.slice(2) : Object.keys(CARRUSELES);
const nav = await chromium.launch();
for (const nombre of pedidos) {
  const archivo = join(AQUI, `${nombre}.html`);
  writeFileSync(archivo, html(CARRUSELES[nombre]()));
  const dir = join(AQUI, 'salida', nombre);
  mkdirSync(dir, { recursive: true });
  const p = await nav.newPage({ viewport: { width: 1080, height: 1350 } });
  await p.goto('file://' + archivo);
  await p.evaluate(() => document.fonts.ready);
  await p.waitForTimeout(300);
  const laminas = await p.locator('.slide').all();
  for (let k = 0; k < laminas.length; k++) {
    await laminas[k].screenshot({ path: join(dir, `${String(k + 1).padStart(2, '0')}.png`) });
  }
  console.log(nombre, laminas.length, 'láminas →', dir);
  await p.close();
}
await nav.close();
