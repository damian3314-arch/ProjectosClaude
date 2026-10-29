// Genera data/demo.json con datos SINTÉTICOS (no son ventas reales) para ver el tablero funcionando.
// Determinista: misma semilla, mismo archivo.
import { writeFileSync } from 'node:fs';
import { sumarDias, diaSemana, partes } from '../js/metrics.js';

function mulberry32(a) {
  return () => {
    a |= 0; a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const rnd = mulberry32(20261029);
const pick = (arr, w) => { let r = rnd() * w.reduce((a, b) => a + b, 0); for (let i = 0; i < arr.length; i++) { r -= w[i]; if (r <= 0) return arr[i]; } return arr.at(-1); };
const redondeo = (n) => Math.round(n / 1000) * 1000;

const DESDE = '2025-01-01';
const HASTA = '2026-10-22'; // el demo termina antes de "hoy" para mostrar cómo se ve un atraso de carga
const estacion = { 2: 1.15, 5: 1.35, 9: 1.1, 10: 0.95, 11: 1.45, 12: 1.9 };
const semana = [0.9, 0.95, 1.0, 1.05, 1.25, 1.35, 0.35];

const CUENTAS = [
  { n: 'Bancolombia', w: 4 },
  { n: 'Davivienda', w: 2.5 },
  { n: 'Nequi', w: 2 },
  { n: 'Datáfono', w: 3 },
  { n: 'Efectivo caja', w: 1.5 },
  { n: 'Camila', w: 2, desde: '2026-10-05' },
];
const clientes = Array.from({ length: 140 }, (_, i) => `Cliente ${String(i + 1).padStart(3, '0')}`);

const resumen = [];
const movimientos = [];
let saldoCxc = 0;

for (let f = DESDE; f <= HASTA; f = sumarDias(f, 1)) {
  const { m, d } = partes(f);
  const w = diaSemana(f);
  let k = (estacion[m] || 1) * semana[w] * (0.75 + rnd() * 0.5);
  if (f === `${partes(f).y}-11-28` || f === `${partes(f).y}-11-29`) k *= 2.2; // viernes negro aprox.
  if (d === 15 || d === 30 || d === 28) k *= 1.2; // quincena
  const base = 3_300_000 * k; // ~100 M al mes con k promedio 1
  const nPagos = Math.max(1, Math.round(3 + rnd() * 9 * k));
  const cuentasOk = CUENTAS.filter((c) => !c.desde || f >= c.desde);
  let contado = 0, abonos = 0;
  for (let i = 0; i < nPagos; i++) {
    const tipo = rnd() < 0.72 ? 'VENTA' : 'ABONO';
    const valor = redondeo((base / nPagos) * (0.4 + rnd() * 1.4));
    if (valor <= 0) continue;
    const cuenta = pick(cuentasOk.map((c) => c.n), cuentasOk.map((c) => c.w));
    movimientos.push({ fecha: f, cliente: clientes[Math.floor(rnd() * rnd() * clientes.length)], valor, cuenta, tipo });
    if (tipo === 'VENTA') contado += valor; else abonos += valor;
  }
  const credito = rnd() < 0.55 ? redondeo(base * (0.1 + rnd() * 0.5)) : 0;
  saldoCxc = Math.max(0, saldoCxc + credito - abonos);
  resumen.push({ fecha: f, ventas_contado: contado, creditos_total_ventas: credito, creditos_abonos: abonos, saldo_cxc_mes: saldoCxc });
}

// Un descuadre deliberado para que se vea el control de calidad.
const idx = resumen.findIndex((r) => r.fecha === '2026-09-14');
if (idx >= 0) resumen[idx].ventas_contado += 150_000;

writeFileSync(new URL('../data/demo.json', import.meta.url), JSON.stringify({
  meta: { demo: true, fuente: 'Datos sintéticos de demostración. NO son ventas reales.', generado: new Date().toISOString() },
  resumen,
  movimientos,
}));
console.log(`demo.json: ${resumen.length} días, ${movimientos.length} movimientos.`);
