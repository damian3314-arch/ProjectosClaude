// Convierte las dos pestañas de la hoja, exportadas como CSV, al JSON que lee el tablero.
//   node scripts/sheet-to-json.mjs Resumen_Diario.csv movimientos_detallados.csv > data/real.json
// En Google Sheets: Archivo > Descargar > Valores separados por comas (.csv), una vez por pestaña.
import { readFileSync } from 'node:fs';

function parseCSV(texto) {
  const filas = [];
  let fila = [], campo = '', q = false;
  const t = texto.replace(/^﻿/, '');
  for (let i = 0; i < t.length; i++) {
    const c = t[i];
    if (q) {
      if (c === '"' && t[i + 1] === '"') { campo += '"'; i++; }
      else if (c === '"') q = false;
      else campo += c;
    } else if (c === '"') q = true;
    else if (c === ',') { fila.push(campo); campo = ''; }
    else if (c === '\n' || c === '\r') {
      if (c === '\r' && t[i + 1] === '\n') i++;
      fila.push(campo); campo = '';
      if (fila.some((x) => x !== '')) filas.push(fila);
      fila = [];
    } else campo += c;
  }
  fila.push(campo);
  if (fila.some((x) => x !== '')) filas.push(fila);
  return filas;
}

function aObjetos(ruta) {
  const [enc, ...filas] = parseCSV(readFileSync(ruta, 'utf8'));
  const cab = enc.map((h) => h.trim());
  return filas.map((f) => Object.fromEntries(cab.map((h, i) => [h, f[i] ?? ''])));
}

const [rutaResumen, rutaMov] = process.argv.slice(2);
if (!rutaResumen || !rutaMov) {
  console.error('Uso: node scripts/sheet-to-json.mjs <Resumen_Diario.csv> <movimientos_detallados.csv> > data/real.json');
  process.exit(1);
}

const resumen = aObjetos(rutaResumen).map((r) => ({
  fecha: r.fecha,
  ventas_contado: r.ventas_contado,
  creditos_total_ventas: r.creditos_total_ventas,
  creditos_abonos: r.creditos_abonos,
  saldo_cxc_mes: r.saldo_cxc_mes,
}));
const movimientos = aObjetos(rutaMov).map((r) => ({
  fecha: r.Fecha, cliente: r.Cliente, valor: r.Valor, cuenta: r.Cuenta_Destino, tipo: r.Tipo,
}));

// Los valores van tal cual vienen de la hoja: js/data.js los valida y avisa de lo ilegible.
process.stdout.write(JSON.stringify({ meta: { demo: false, fuente: 'Export CSV de Google Sheets', generado: new Date().toISOString() }, resumen, movimientos }));
