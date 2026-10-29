// Cálculos puros. Las fechas son SIEMPRE texto 'YYYY-MM-DD' y la aritmética se hace en UTC,
// para que la zona horaria del navegador nunca corra un día una venta.

const MS = 86_400_000;
export const pad = (n) => String(n).padStart(2, '0');
export const ymd = (y, m, d) => `${y}-${pad(m)}-${pad(d)}`;
export const aMs = (s) => {
  const [y, m, d] = s.split('-').map(Number);
  return Date.UTC(y, m - 1, d);
};
export const deMs = (ms) => new Date(ms).toISOString().slice(0, 10);
export const sumarDias = (s, n) => deMs(aMs(s) + n * MS);
export const partes = (s) => {
  const [y, m, d] = s.split('-').map(Number);
  return { y, m, d };
};
export const diasDelMes = (y, m) => new Date(Date.UTC(y, m, 0)).getUTCDate();
export const diasEntre = (a, b) => Math.round((aMs(b) - aMs(a)) / MS); // b - a

export function fechaValida(s) {
  if (typeof s !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(s)) return false;
  return deMs(aMs(s)) === s;
}

// Suma n meses recortando el día al último del mes destino (31 mar - 1 mes = 28 feb).
export function sumarMeses(s, n) {
  const { y, m, d } = partes(s);
  const t = y * 12 + (m - 1) + n;
  const ny = Math.floor(t / 12);
  const nm = (t % 12) + 1;
  return ymd(ny, nm, Math.min(d, diasDelMes(ny, nm)));
}

export const diaSemana = (s) => (new Date(aMs(s)).getUTCDay() + 6) % 7; // 0 = lunes
export const inicioSemana = (s) => sumarDias(s, -diaSemana(s));

export function inicioPeriodo(tipo, s) {
  const { y, m } = partes(s);
  switch (tipo) {
    case 'dia': return s;
    case 'semana': return inicioSemana(s);
    case 'mes': return ymd(y, m, 1);
    case 'trimestre': return ymd(y, Math.floor((m - 1) / 3) * 3 + 1, 1);
    case 'semestre': return ymd(y, m <= 6 ? 1 : 7, 1);
    case 'anio': return ymd(y, 1, 1);
    default: throw new Error('periodo desconocido: ' + tipo);
  }
}

export const rangoAcumulado = (tipo, R) => ({ desde: inicioPeriodo(tipo, R), hasta: R });

const SALTO_MESES = { mes: 1, trimestre: 3, semestre: 6, anio: 12 };

// Rango equivalente en el pasado, "a la misma altura" del periodo.
//  modo 'previo': periodo anterior (día/semana: 7 días atrás; mes/trim/sem: un periodo atrás).
//  modo 'anio'  : un año atrás. Día y semana usan 364 días (52 semanas) para que caiga el mismo día de la semana.
export function rangoComparable(tipo, R, modo) {
  if (tipo === 'dia' || tipo === 'semana') {
    const k = modo === 'previo' ? 7 : 364;
    const h = sumarDias(R, -k);
    return { desde: inicioPeriodo(tipo, h), hasta: h };
  }
  const meses = modo === 'previo' ? SALTO_MESES[tipo] : 12;
  const h = sumarMeses(R, -meses);
  return { desde: inicioPeriodo(tipo, h), hasta: h };
}

// ---------- Serie diaria ----------
// resumen: [{fecha, ventas_contado, creditos_total_ventas, creditos_abonos, ...}]
export function construirDiario(resumen) {
  const m = new Map();
  for (const r of resumen) {
    const contado = r.ventas_contado || 0;
    const credito = r.creditos_total_ventas || 0;
    const abonos = r.creditos_abonos || 0;
    m.set(r.fecha, {
      fecha: r.fecha,
      contado,
      credito,
      abonos,
      facturado: contado + credito, // lo vendido en el día, se haya cobrado o no
      recaudo: contado + abonos, // plata que entró en el día
      saldoCxcMes: r.saldo_cxc_mes ?? null,
    });
  }
  return m;
}

export function datosRango(diario, desde, hasta) {
  const out = { facturado: 0, contado: 0, credito: 0, abonos: 0, recaudo: 0, diasConDatos: 0, dias: 0 };
  for (let f = desde; f <= hasta; f = sumarDias(f, 1)) {
    out.dias++;
    const r = diario.get(f);
    if (!r) continue;
    out.diasConDatos++;
    out.facturado += r.facturado;
    out.contado += r.contado;
    out.credito += r.credito;
    out.abonos += r.abonos;
    out.recaudo += r.recaudo;
  }
  return out;
}

// Curva acumulada día a día de un mes. Después de `corte` queda null (no se dibuja).
export function curvaMes(diario, y, m, campo, corte) {
  const n = diasDelMes(y, m);
  const curva = [];
  let acum = 0;
  for (let d = 1; d <= n; d++) {
    const f = ymd(y, m, d);
    if (corte && f > corte) { curva.push(null); continue; }
    acum += diario.get(f)?.[campo] || 0;
    curva.push(acum);
  }
  return curva;
}

// ---------- Movimientos (detalle por cuenta) ----------
export function porCuenta(movs, desde, hasta) {
  const g = new Map();
  let total = 0;
  for (const x of movs) {
    if (x.fecha < desde || x.fecha > hasta) continue;
    let c = g.get(x.cuentaClave);
    if (!c) { c = { clave: x.cuentaClave, nombre: x.cuenta, venta: 0, abono: 0, otro: 0, total: 0, n: 0 }; g.set(x.cuentaClave, c); }
    if (x.tipo === 'VENTA') c.venta += x.valor;
    else if (x.tipo === 'ABONO') c.abono += x.valor;
    else c.otro += x.valor;
    c.total += x.valor;
    c.n++;
    total += x.valor;
  }
  return [...g.values()].map((c) => ({ ...c, pct: total ? c.total / total : 0 })).sort((a, b) => b.total - a.total);
}

export function topClientes(movs, desde, hasta, n = 5) {
  const g = new Map();
  let total = 0;
  for (const x of movs) {
    if (x.fecha < desde || x.fecha > hasta) continue;
    g.set(x.cliente, (g.get(x.cliente) || 0) + x.valor);
    total += x.valor;
  }
  const lista = [...g.entries()].map(([cliente, valor]) => ({ cliente, valor, pct: total ? valor / total : 0 })).sort((a, b) => b.valor - a.valor);
  return { lista: lista.slice(0, n), total, clientes: lista.length };
}

export function primerMovimientoPorCuenta(movs) {
  const m = new Map();
  for (const x of movs) {
    const p = m.get(x.cuentaClave);
    if (!p || x.fecha < p) m.set(x.cuentaClave, x.fecha);
  }
  return m;
}

// Promedio de `campo` por día de la semana en los últimos `nDias`, sólo con días que tienen registro.
export function perfilSemana(diario, hasta, nDias = 91, campo = 'facturado') {
  const suma = Array(7).fill(0);
  const cnt = Array(7).fill(0);
  for (let i = 0; i < nDias; i++) {
    const f = sumarDias(hasta, -i);
    const r = diario.get(f);
    if (!r) continue;
    const w = diaSemana(f);
    suma[w] += r[campo];
    cnt[w]++;
  }
  return suma.map((s, i) => ({ dia: i, promedio: cnt[i] ? s / cnt[i] : null, n: cnt[i] }));
}

// Días sin registro entre `desde` y `hasta`, agrupados en rangos consecutivos.
export function huecos(diario, desde, hasta, diasCerrados = []) {
  const faltan = [];
  for (let f = desde; f <= hasta; f = sumarDias(f, 1)) {
    if (diasCerrados.includes(diaSemana(f))) continue;
    if (!diario.has(f)) faltan.push(f);
  }
  const rangos = [];
  for (const f of faltan) {
    const ult = rangos[rangos.length - 1];
    if (ult && sumarDias(ult.hasta, 1) === f) ult.hasta = f;
    else rangos.push({ desde: f, hasta: f });
  }
  return { dias: faltan, rangos };
}

// Cuadre: Σ movimientos del día contra (ventas contado + abonos) del resumen.
export function cuadre(movs, diario, tolerancia = 1) {
  const sumaMov = new Map();
  for (const x of movs) sumaMov.set(x.fecha, (sumaMov.get(x.fecha) || 0) + x.valor);
  const difs = [];
  const fechas = new Set([...sumaMov.keys(), ...diario.keys()]);
  for (const f of [...fechas].sort()) {
    const r = diario.get(f);
    const a = sumaMov.get(f) || 0;
    const b = r ? r.recaudo : null;
    if (b == null) { difs.push({ fecha: f, movimientos: a, resumen: null, dif: null, motivo: 'sin resumen' }); continue; }
    if (Math.abs(a - b) > tolerancia) difs.push({ fecha: f, movimientos: a, resumen: b, dif: a - b, motivo: 'no cuadra' });
  }
  return difs;
}
