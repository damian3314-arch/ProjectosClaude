import { fechaValida, ymd } from './metrics.js';

// Convierte lo que venga de Sheets/CSV a pesos enteros. Devuelve null si no es un número claro:
// preferimos avisar a adivinar.
export function parseCOP(v) {
  if (typeof v === 'number') return Number.isFinite(v) ? v : null;
  if (v == null) return null;
  let s = String(v).trim().replace(/[$\s]/g, '');
  if (s === '') return null;
  let neg = false;
  if (/^\(.*\)$/.test(s)) { neg = true; s = s.slice(1, -1); }
  if (s.startsWith('-')) { neg = !neg; s = s.slice(1); }
  let n;
  if (/^\d+$/.test(s)) n = Number(s);
  else if (/^\d{1,3}(\.\d{3})+(,\d+)?$/.test(s)) n = Number(s.replace(/\./g, '').replace(',', '.'));
  else if (/^\d{1,3}(,\d{3})+(\.\d+)?$/.test(s)) n = Number(s.replace(/,/g, ''));
  else if (/^\d+[.,]\d{1,2}$/.test(s)) n = Number(s.replace(',', '.'));
  else return null;
  return neg ? -n : n;
}

// Acepta 'YYYY-MM-DD', 'YYYY-MM-DDTHH:...' y 'D/M/YYYY' (formato colombiano, día primero).
export function parseFecha(v) {
  if (v == null) return null;
  const s = String(v).trim();
  let m = s.match(/^(\d{4})-(\d{2})-(\d{2})/);
  if (m) { const f = `${m[1]}-${m[2]}-${m[3]}`; return fechaValida(f) ? f : null; }
  m = s.match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})$/);
  if (m) { const f = ymd(Number(m[3]), Number(m[2]), Number(m[1])); return fechaValida(f) ? f : null; }
  return null;
}

export const claveCuenta = (s) =>
  String(s ?? '').normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/\s+/g, ' ').trim().toUpperCase();

const TIPOS = new Set(['VENTA', 'ABONO']);

// Une, limpia y valida. Nada se descarta en silencio: todo lo raro queda en `avisos`.
export function normalizar(fuentes) {
  const avisos = [];
  const aviso = (nivel, texto) => avisos.push({ nivel, texto });

  const resumenPorFecha = new Map();
  const movimientos = [];
  const vistos = new Map();
  let demo = false;

  for (const raw of fuentes) {
    if (raw?.meta?.demo) demo = true;

    for (const r of raw.resumen || []) {
      const fecha = parseFecha(r.fecha);
      if (!fecha) { aviso('error', `Resumen con fecha ilegible: "${r.fecha}" (fila ignorada).`); continue; }
      const fila = { fecha };
      for (const k of ['ventas_contado', 'creditos_total_ventas', 'creditos_abonos', 'saldo_cxc_mes']) {
        const n = parseCOP(r[k]);
        if (r[k] != null && r[k] !== '' && n === null) aviso('error', `Resumen ${fecha}: "${k}" no es un monto válido ("${r[k]}"). Se tomó como 0.`);
        fila[k] = n ?? 0;
      }
      if (resumenPorFecha.has(fecha)) aviso('aviso', `Resumen repetido para ${fecha}; se usó la última fila.`);
      resumenPorFecha.set(fecha, fila);
    }

    for (const x of raw.movimientos || []) {
      const fecha = parseFecha(x.fecha);
      const valor = parseCOP(x.valor);
      if (!fecha) { aviso('error', `Movimiento con fecha ilegible: "${x.fecha}" (${x.cliente ?? '?'}). Ignorado.`); continue; }
      if (valor === null) { aviso('error', `Movimiento ${fecha} ${x.cliente ?? '?'}: valor ilegible ("${x.valor}"). Ignorado.`); continue; }
      let tipo = String(x.tipo ?? '').trim().toUpperCase();
      if (!TIPOS.has(tipo)) { aviso('aviso', `Movimiento ${fecha} ${x.cliente ?? '?'}: tipo "${x.tipo}" no es VENTA ni ABONO.`); tipo = 'OTRO'; }
      let cuenta = String(x.cuenta ?? '').replace(/\s+/g, ' ').trim();
      if (!cuenta) { aviso('aviso', `Movimiento ${fecha} ${x.cliente ?? '?'}: sin cuenta destino.`); cuenta = 'SIN CUENTA'; }
      if (valor <= 0) aviso('aviso', `Movimiento ${fecha} ${x.cliente ?? '?'}: valor ${valor} (cero o negativo).`);
      const mov = {
        fecha,
        cliente: String(x.cliente ?? '').replace(/\s+/g, ' ').trim() || '(sin nombre)',
        valor,
        cuenta,
        cuentaClave: claveCuenta(cuenta),
        tipo,
      };
      const huella = `${mov.fecha}|${mov.cliente}|${mov.valor}|${mov.cuentaClave}|${mov.tipo}`;
      vistos.set(huella, (vistos.get(huella) || 0) + 1);
      movimientos.push(mov);
    }
  }

  const repetidos = [...vistos.entries()].filter(([, n]) => n > 1);
  if (repetidos.length) {
    aviso('aviso', `${repetidos.length} movimientos idénticos aparecen más de una vez (mismo día, cliente, valor, cuenta y tipo). Pueden ser pagos reales iguales o una carga duplicada: revisar.`);
  }

  // Nombre visible de cada cuenta: la primera escritura vista.
  const nombres = new Map();
  for (const m of movimientos) if (!nombres.has(m.cuentaClave)) nombres.set(m.cuentaClave, m.cuenta);
  for (const m of movimientos) m.cuenta = nombres.get(m.cuentaClave);

  movimientos.sort((a, b) => (a.fecha < b.fecha ? -1 : a.fecha > b.fecha ? 1 : 0));
  const resumen = [...resumenPorFecha.values()].sort((a, b) => (a.fecha < b.fecha ? -1 : 1));
  return { resumen, movimientos, avisos, demo };
}

export async function cargarFuentes(urls) {
  const out = [];
  for (const u of urls) {
    const r = await fetch(u, { cache: 'no-store' });
    if (!r.ok) throw new Error(`No pude leer ${u} (HTTP ${r.status}).`);
    out.push(await r.json());
  }
  return out;
}
