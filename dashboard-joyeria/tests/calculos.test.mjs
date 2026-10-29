import test from 'node:test';
import assert from 'node:assert/strict';
import * as M from '../js/metrics.js';
import { parseCOP, parseFecha, normalizar } from '../js/data.js';
import { progresoMes, planRecuperacion } from '../js/goals.js';
import { senalOro, primaMercado, gramoCOP } from '../js/gold.js';
import { CONFIG } from '../js/config.js';

const serie = (pares) => M.construirDiario(pares.map(([fecha, c, cr = 0, ab = 0]) => ({ fecha, ventas_contado: c, creditos_total_ventas: cr, creditos_abonos: ab })));

test('fechas: suma de meses recorta al último día', () => {
  assert.equal(M.sumarMeses('2026-03-31', -1), '2026-02-28');
  assert.equal(M.sumarMeses('2024-02-29', -12), '2023-02-28');
  assert.equal(M.sumarMeses('2026-01-15', -2), '2025-11-15');
  assert.equal(M.sumarMeses('2026-11-30', 3), '2027-02-28');
});

test('fechas: semana empieza el lunes y no hay corrimiento por zona horaria', () => {
  assert.equal(M.diaSemana('2026-10-29'), 3); // jueves
  assert.equal(M.inicioSemana('2026-10-29'), '2026-10-26');
  assert.equal(M.inicioSemana('2026-11-01'), '2026-10-26'); // domingo
  assert.equal(M.fechaValida('2026-02-30'), false);
  assert.equal(M.fechaValida('2026-02-28'), true);
});

test('rangos acumulados y comparables', () => {
  const R = '2026-10-22';
  assert.deepEqual(M.rangoAcumulado('mes', R), { desde: '2026-10-01', hasta: R });
  assert.deepEqual(M.rangoAcumulado('trimestre', R), { desde: '2026-10-01', hasta: R });
  assert.deepEqual(M.rangoAcumulado('semestre', R), { desde: '2026-07-01', hasta: R });
  assert.deepEqual(M.rangoAcumulado('anio', R), { desde: '2026-01-01', hasta: R });
  assert.deepEqual(M.rangoComparable('mes', R, 'previo'), { desde: '2026-09-01', hasta: '2026-09-22' });
  assert.deepEqual(M.rangoComparable('mes', R, 'anio'), { desde: '2025-10-01', hasta: '2025-10-22' });
  assert.deepEqual(M.rangoComparable('trimestre', R, 'previo'), { desde: '2026-07-01', hasta: '2026-07-22' });
  assert.deepEqual(M.rangoComparable('semestre', R, 'previo'), { desde: '2026-01-01', hasta: '2026-04-22' });
  assert.deepEqual(M.rangoComparable('anio', R, 'anio'), { desde: '2025-01-01', hasta: '2025-10-22' });
  // día y semana: 364 días = mismo día de la semana
  assert.equal(M.diaSemana(M.rangoComparable('dia', R, 'anio').hasta), M.diaSemana(R));
  assert.deepEqual(M.rangoComparable('semana', '2026-10-29', 'previo'), { desde: '2026-10-19', hasta: '2026-10-22' });
});

test('datosRango suma facturado y recaudo sin mezclar conceptos', () => {
  const d = serie([['2026-10-01', 100, 50, 20], ['2026-10-02', 200, 0, 30]]);
  const r = M.datosRango(d, '2026-10-01', '2026-10-03');
  assert.equal(r.facturado, 350); // contado + crédito
  assert.equal(r.recaudo, 350); // contado + abonos
  assert.equal(r.diasConDatos, 2);
  assert.equal(r.dias, 3);
});

test('parseCOP entiende formatos de la hoja y rechaza lo ambiguo', () => {
  assert.equal(parseCOP('1.234.567'), 1234567);
  assert.equal(parseCOP('$ 1.234.567'), 1234567);
  assert.equal(parseCOP('1,234,567'), 1234567);
  assert.equal(parseCOP('1234567'), 1234567);
  assert.equal(parseCOP(1234567), 1234567);
  assert.equal(parseCOP('(1.000)'), -1000);
  assert.equal(parseCOP('-2.500'), -2500);
  assert.equal(parseCOP(''), null);
  assert.equal(parseCOP('abc'), null);
  assert.equal(parseCOP('12.34.5'), null);
});

test('parseFecha: ISO y día/mes/año colombiano', () => {
  assert.equal(parseFecha('2026-10-22'), '2026-10-22');
  assert.equal(parseFecha('2026-10-22T00:00:00.000Z'), '2026-10-22');
  assert.equal(parseFecha('1/09/2026'), '2026-09-01');
  assert.equal(parseFecha('31/02/2026'), null);
  assert.equal(parseFecha('basura'), null);
});

test('normalizar: no descarta en silencio, agrupa cuentas por nombre equivalente', () => {
  const r = normalizar([{
    resumen: [{ fecha: '2026-10-01', ventas_contado: '1.000', creditos_total_ventas: 'xx', creditos_abonos: 0 }, { fecha: 'mal' }],
    movimientos: [
      { fecha: '2026-10-01', cliente: 'Ana', valor: '500', cuenta: 'Camila', tipo: 'venta' },
      { fecha: '2026-10-01', cliente: 'Ana', valor: '500', cuenta: ' CAMILA ', tipo: 'VENTA' },
      { fecha: '2026-10-01', cliente: 'Luis', valor: '700', cuenta: '', tipo: 'otro' },
      { fecha: '2026-10-01', cliente: 'Zoe', valor: 'n/a', cuenta: 'X', tipo: 'VENTA' },
    ],
  }]);
  assert.equal(r.resumen.length, 1);
  assert.equal(r.movimientos.length, 3); // el de valor ilegible se ignora CON aviso
  assert.equal(new Set(r.movimientos.map((m) => m.cuentaClave)).size, 2); // CAMILA y SIN CUENTA
  const textos = r.avisos.map((a) => a.texto).join('\n');
  assert.match(textos, /fecha ilegible/);
  assert.match(textos, /creditos_total_ventas/);
  assert.match(textos, /valor ilegible/);
  assert.match(textos, /sin cuenta/);
  assert.match(textos, /idénticos/);
});

test('porCuenta separa ventas y abonos y los porcentajes suman 1', () => {
  const movs = [
    { fecha: '2026-10-01', cliente: 'a', valor: 300, cuenta: 'A', cuentaClave: 'A', tipo: 'VENTA' },
    { fecha: '2026-10-02', cliente: 'b', valor: 100, cuenta: 'A', cuentaClave: 'A', tipo: 'ABONO' },
    { fecha: '2026-10-02', cliente: 'c', valor: 600, cuenta: 'B', cuentaClave: 'B', tipo: 'VENTA' },
    { fecha: '2026-09-30', cliente: 'd', valor: 999, cuenta: 'B', cuentaClave: 'B', tipo: 'VENTA' },
  ];
  const r = M.porCuenta(movs, '2026-10-01', '2026-10-31');
  assert.equal(r[0].nombre, 'B');
  assert.equal(r[0].total, 600);
  assert.equal(r[1].venta, 300);
  assert.equal(r[1].abono, 100);
  assert.ok(Math.abs(r.reduce((s, c) => s + c.pct, 0) - 1) < 1e-12);
});

test('huecos agrupa días consecutivos y respeta días cerrados', () => {
  const d = serie([['2026-10-20', 1], ['2026-10-24', 1]]);
  const h = M.huecos(d, '2026-10-20', '2026-10-26');
  assert.deepEqual(h.rangos, [{ desde: '2026-10-21', hasta: '2026-10-23' }, { desde: '2026-10-25', hasta: '2026-10-26' }]);
  const h2 = M.huecos(d, '2026-10-20', '2026-10-26', [6]); // domingo (25/oct) cerrado
  assert.deepEqual(h2.rangos.at(-1), { desde: '2026-10-26', hasta: '2026-10-26' });
});

test('cuadre detecta diferencias y días sin resumen', () => {
  const d = serie([['2026-10-01', 100, 0, 50], ['2026-10-02', 10, 0, 0]]);
  const movs = [
    { fecha: '2026-10-01', valor: 150 },
    { fecha: '2026-10-02', valor: 11 },
    { fecha: '2026-10-03', valor: 5 },
  ];
  const r = M.cuadre(movs, d, 0);
  assert.equal(r.length, 2);
  assert.equal(r[0].dif, 1);
  assert.equal(r[1].motivo, 'sin resumen');
});

test('progresoMes: acumulado, faltante, ritmo requerido y proyección lineal', () => {
  const filas = [];
  for (let d = 1; d <= 10; d++) filas.push([`2026-10-${String(d).padStart(2, '0')}`, 1_000_000]);
  const p = progresoMes(serie(filas), '2026-10-10', CONFIG);
  assert.equal(p.acumulado, 10_000_000);
  assert.equal(p.faltaMeta, 110_000_000);
  assert.equal(p.restantes, 21);
  assert.ok(Math.abs(p.reqDiarioMeta - 110_000_000 / 21) < 1e-6);
  assert.equal(p.proyLineal, 31_000_000);
  assert.equal(p.proyEstacional, null); // sin año anterior no se inventa
});

test('progresoMes: proyección estacional con año anterior completo', () => {
  const filas = [];
  for (let d = 1; d <= 31; d++) filas.push([`2025-10-${String(d).padStart(2, '0')}`, 1_000_000]); // lineal
  for (let d = 1; d <= 10; d++) filas.push([`2026-10-${String(d).padStart(2, '0')}`, 2_000_000]);
  const p = progresoMes(serie(filas), '2026-10-10', CONFIG);
  assert.ok(Math.abs(p.shareAnioAnterior - 10 / 31) < 1e-12);
  assert.ok(Math.abs(p.proyEstacional - 62_000_000) < 1);
});

test('planRecuperacion: lo necesario se reparte completo y respeta el corte', () => {
  const filas = [];
  const ini = new Date(Date.UTC(2025, 0, 1));
  for (let i = 0; i < 365; i++) filas.push([new Date(ini.getTime() + i * 86400000).toISOString().slice(0, 10), 3_000_000]);
  for (let m = 1; m <= 9; m++) for (let d = 1; d <= M.diasDelMes(2026, m); d++) filas.push([M.ymd(2026, m, d), 2_000_000]);
  for (let d = 1; d <= 22; d++) filas.push([M.ymd(2026, 10, d), 2_000_000]);
  const diario = serie(filas);
  const plan = planRecuperacion(diario, '2026-10-22', CONFIG);
  const ytd = M.datosRango(diario, '2026-01-01', '2026-10-22').facturado;
  assert.equal(plan.ytd, ytd);
  assert.equal(plan.meta.necesario, CONFIG.metaMensual * 12 - ytd);
  assert.equal(plan.usaAnioAnterior, true);
  const sumaMeses = plan.meses.reduce((s, x) => s + x.meta, 0);
  assert.ok(Math.abs(sumaMeses - plan.meta.necesario) < 1, 'los meses deben sumar lo necesario');
  assert.equal(plan.desdeRestante, '2026-10-23');
  assert.ok(plan.ventanas.every((v) => v.hasta > '2026-10-22'));
});

test('planRecuperacion sin año anterior usa multiplicadores y sigue sumando exacto', () => {
  const diario = serie([['2026-10-22', 1_000_000]]);
  const plan = planRecuperacion(diario, '2026-10-22', CONFIG);
  assert.equal(plan.usaAnioAnterior, false);
  const sumaVentanas = plan.ventanas.reduce((s, v) => s + v.meta, 0);
  assert.ok(sumaVentanas < plan.meta.necesario); // las ventanas son sólo una parte
  const sumaMeses = plan.meses.reduce((s, x) => s + x.meta, 0);
  assert.ok(Math.abs(sumaMeses - plan.meta.necesario) < 1);
});

test('oro: conversión a gramo, señal y prima', () => {
  // 1 oz troy = 31.1034768 g
  assert.ok(Math.abs(gramoCOP(31.1034768, 3000) - 3000) < 1e-9);
  const cfg = { umbral: 0.02, minLecturas: 3 };
  assert.equal(senalOro({ '2026-10-01': 100 }, '2026-10-02', 100, cfg).estado, 'sin-datos');
  const h = { '2026-10-01': 100, '2026-10-02': 100, '2026-10-03': 100 };
  assert.equal(senalOro(h, '2026-10-04', 103, cfg).estado, 'alto');
  assert.equal(senalOro(h, '2026-10-04', 97, cfg).estado, 'bajo');
  assert.equal(senalOro(h, '2026-10-04', 101, cfg).estado, 'neutral');
  assert.ok(Math.abs(primaMercado(90, 100) + 0.1) < 1e-12);
  assert.equal(primaMercado(0, 100), null);
});
