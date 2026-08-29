/**
 * La tarjeta del sábado tiene que poder leerse sin equivocarse.
 *
 * El caso: el sábado la clase va partida —15 puestos de afiliados y 20
 * de clase suelta— pero la tarjeta enseñaba un solo "N libres" que
 * mezclaba los dos lados. Llegó a decir "22 libres" mientras del lado
 * de sueltas quedaban 7. Quien lee el número grande y le abre la puerta
 * a alguien más está vendiendo un puesto que no existe.
 *
 * Se comprueba con los números REALES del sábado 29 de agosto.
 *
 *   node tarjeta-sabado.test.mjs <ruta a admin.html con __e2e>
 */
import { chromium } from 'playwright-core';
const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
const p = await b.newPage({ viewport: { width: 430, height: 900 } });
const errs = []; p.on('pageerror', e => errs.push(String(e)));
await p.goto('file://' + process.argv[2]);

// Sábado 29/08 tal como está en la base: 13 tomados de 35, con el
// reparto 6 afiliados de 15 y 7 sueltas de 20.
const SABADO = {
  clase_id: '11111111-2222-4333-8444-555555555555', nombre: 'Clase 9:00 am',
  hora: '09:00', activa: true, ya_paso: false,
  aforo: 35, con_plan: 0, a_la_venta: 35, cupo_manual: 35,
  reservadas: 13, por_soltar: 0, libres: 22, vencen: 0,
  confirmadas: 13, confirmadas_suelta: 7, confirmadas_miembro: 6,
  por_validar: 0, esperando: 0, en_sala: 13, ingreso_cop: 105000,
  reparto: { miembros_tope: 15, miembros_tomados: 6, miembros_libres: 9,
             sueltas_tope: 20, sueltas_tomadas: 7, sueltas_libres: 13 },
};
// Y un día entre semana, que NO debe cambiar en nada.
const MARTES = {
  clase_id: '99999999-8888-4777-8666-555555555555', nombre: 'Clase 6:00 pm',
  hora: '18:00', activa: true, ya_paso: false,
  aforo: 30, con_plan: 27, a_la_venta: 3, cupo_manual: null,
  reservadas: 1, por_soltar: 0, libres: 2, vencen: 0,
  confirmadas: 1, confirmadas_suelta: 1, confirmadas_miembro: 0,
  por_validar: 0, esperando: 0, en_sala: 28, ingreso_cop: 15000,
  reparto: null,
};

let fallos = 0;
const ok = (n, c, extra='') => { if (!c) fallos++;
  console.log(`${c ? '✓' : '✗'} ${n}${extra ? '  → ' + extra : ''}`); };

const n = await p.evaluate(l => window.__e2e.pintarSabado(l), [SABADO, MARTES]);
ok('se pintan las dos tarjetas', n === 2, String(n));

const sab = await p.evaluate(() => window.__e2e.leerTarjeta(0));
const mar = await p.evaluate(() => window.__e2e.leerTarjeta(1));

// ── el sábado ────────────────────────────────────────────────────
ok('el número grande del sábado es el que se puede vender',
   /13/.test(sab.badge) && /suelta/i.test(sab.badge), sab.badge);
ok('y NO enseña el 22 que mezcla los dos lados',
   !/22/.test(sab.badge), sab.badge);
ok('la fila de cifras es la partida', sab.partido);
ok('primero las sueltas libres',
   sab.mini[0].v === '13' && /sueltas libres/.test(sab.mini[0].e),
   `${sab.mini[0].v} ${sab.mini[0].e}`);
ok('después los afiliados libres',
   sab.mini[1].v === '9' && /afiliados libres/.test(sab.mini[1].e),
   `${sab.mini[1].v} ${sab.mini[1].e}`);
ok('no dice "con plan 0", que el sábado engaña',
   !sab.mini.some(x => /con plan/.test(x.e)),
   sab.mini.map(x => x.e).join(' | '));
ok('la línea de la sala cuenta los dos lados', /Entran\s*13\s*de\s*35/.test(sab.sala), sab.sala);
ok('el sábado no se marca como "cupo a mano"', !/cupo a mano/.test(sab.texto));
ok('el reparto queda como detalle de cuántos entraron',
   /Afiliados/.test(sab.reparto) && /6 de 15/.test(sab.reparto)
   && /7 de 20/.test(sab.reparto), sab.reparto);
ok('y ya no repite los "quedan" del encabezado',
   !/quedan/i.test(sab.reparto || ''), sab.reparto);

// ── entre semana, intacto ────────────────────────────────────────
ok('entre semana sigue diciendo "libres"', /2 libres/.test(mar.badge), mar.badge);
ok('entre semana la fila NO es partida', !mar.partido);
ok('entre semana sigue el aforo y el con plan',
   mar.mini[0].e === 'aforo' && /con plan/.test(mar.mini[1].e),
   mar.mini.map(x => x.e).join(' | '));
ok('entre semana "Entran 28 de 30"', /Entran\s*28\s*de\s*30/.test(mar.sala), mar.sala);
ok('entre semana no hay reparto', mar.reparto === null);

ok('sin errores de JS', errs.length === 0, errs.join(' | '));
console.log(fallos ? `\n${fallos} fallo(s)` : '\nTodo bien');
await b.close();
process.exit(fallos ? 1 : 0);
