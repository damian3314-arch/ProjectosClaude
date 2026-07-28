/**
 * Prueba del selector del reporte de afiliados.
 *
 * Los nombres de aquí son los REALES de la carpeta de Drive, leídos con
 * el explorador. Importa porque en esa carpeta conviven los cierres de
 * caja (25-07-2026.xlsx) con el reporte de afiliados (Afiliados activos
 * 2026-07-27.xlsx), y confundirlos sería leer un archivo de caja como si
 * fuera el listado de gente con plan.
 */
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const RAIZ = join(dirname(fileURLToPath(import.meta.url)), '..');
const CODIGO = readFileSync(join(RAIZ, 'n8n', 'elegir-reporte-afiliados.js'), 'utf8');

let fallos = 0;
const ok = (n, c, extra = '') => {
  console.log(`${c ? '✓' : '✗'} ${n}${extra ? '  → ' + extra : ''}`);
  if (!c) fallos++;
};

const correr = nombres => {
  const items = nombres.map((name, i) => ({ json: { id: 'id-' + i, name } }));
  const $input = { all: () => items };
  return new Function('$input', CODIGO + '\n')($input)[0].json;
};

// Los 21 archivos que hay hoy en la carpeta, tal cual.
const CIERRES = [
  '25-07-2026.xlsx', '24-07-2026.xlsx', '23-07-2026.xlsx', '22-07-2026.xlsx',
  '21-07-2026.xlsx', '18-07-2026.xlsx', '17-07-2026.xlsx', '16-07-2026.xlsx',
  '15-07-2026.xlsx', '14-07-2026.xlsx', '13-07-2026.xlsx', '11-07-2026.xlsx',
  '10-07-2026.xlsx', '09-07-2026.xlsx', '08-07-2026.xlsx', '06-07-2026.xlsx',
  '04-07-2026.xlsx', '03-07-2026.xlsx', '02-07-2026.xlsx', '01-07-2026.xlsx',
];

const hoyISO = new Intl.DateTimeFormat('en-CA', {
  timeZone: 'America/Bogota', year: 'numeric', month: '2-digit', day: '2-digit',
}).format(new Date());
const desplazar = n => {
  const [a, m, d] = hoyISO.split('-').map(Number);
  const f = new Date(Date.UTC(a, m - 1, d));
  f.setUTCDate(f.getUTCDate() + n);
  return f.toISOString().slice(0, 10);
};

// ── el caso real ─────────────────────────────────────────────
{
  const r = correr([...CIERRES, `Afiliados activos ${desplazar(-1)}.xlsx`]);
  ok('elige el de afiliados, no un cierre de caja',
     r.ok === true && /Afiliados/.test(r.file_name), r.file_name);
  ok('ignora los 20 cierres', r.candidatos === 1, `${r.candidatos} candidato(s)`);
  ok('el de ayer cuenta como 1 dia de atraso', r.dias_de_atraso === 1,
     String(r.dias_de_atraso));
  ok('no avisa por 1 dia, que es lo normal', r.aviso === null, String(r.aviso));
}

// ── varios días de afiliados en la carpeta ───────────────────
{
  const r = correr([
    ...CIERRES,
    `Afiliados activos ${desplazar(-3)}.xlsx`,
    `Afiliados activos ${desplazar(-1)}.xlsx`,
    `Afiliados activos ${desplazar(-2)}.xlsx`,
  ]);
  ok('se queda con el más nuevo',
     r.file_name === `Afiliados activos ${desplazar(-1)}.xlsx`, r.file_name);
  ok('cuenta bien los candidatos', r.candidatos === 3, String(r.candidatos));
}

// ── el que se quedó sin guardar varios días ──────────────────
{
  const r = correr([...CIERRES, `Afiliados activos ${desplazar(-4)}.xlsx`]);
  ok('a los 4 días importa pero avisa',
     r.ok === true && /4 dias de atraso/.test(r.aviso || ''), r.aviso);
}
{
  const r = correr([...CIERRES, `Afiliados activos ${desplazar(-9)}.xlsx`]);
  ok('a los 9 días se niega a importar',
     r.ok === false && r.error === 'archivo_viejo', r.mensaje);
  ok('y dice cuántos días lleva', r.dias_de_atraso === 9, String(r.dias_de_atraso));
}

// ── nombres torcidos ─────────────────────────────────────────
{
  const r = correr([...CIERRES, `Afiliados activos ${desplazar(2)}.xlsx`]);
  ok('una fecha futura se rechaza en vez de usarse',
     r.ok === false && r.error === 'fecha_futura', r.mensaje);
}
{
  const r = correr(CIERRES);
  ok('si no hay archivo de afiliados lo dice claro',
     r.ok === false && r.error === 'sin_archivo', r.mensaje);
}
{
  const r = correr([]);
  ok('carpeta vacía también', r.ok === false && r.error === 'sin_archivo');
}

// ── la transición: archivos viejos sin fecha ─────────────────
{
  const r = correr([
    ...CIERRES,
    'Reporte Afiliados con Membresía Activa.xlsx',
    'Reporte Afiliados con Membresía Activa (5).xlsx',
    'Reporte Afiliados con Membresía Activa (10).xlsx',
    'Reporte Afiliados con Membresía Activa (9).xlsx',
  ]);
  ok('sin fecha, usa el sufijo y toma el (10), no el (9)',
     r.ok === true && /\(10\)/.test(r.file_name), r.file_name);
  ok('y avisa que no sabe de qué día es',
     r.dias_de_atraso === null && /no se puede saber/i.test(r.aviso || ''), r.aviso);
}
{
  // Si hay uno con fecha y otros sin ella, manda el que tiene fecha.
  const r = correr([
    ...CIERRES,
    'Reporte Afiliados con Membresía Activa (10).xlsx',
    `Afiliados activos ${desplazar(-1)}.xlsx`,
  ]);
  ok('el que tiene fecha le gana al del sufijo',
     /Afiliados activos/.test(r.file_name), r.file_name);
}

// ── el nombre de hoy mismo ───────────────────────────────────
{
  const r = correr([...CIERRES, `Afiliados activos ${hoyISO}.xlsx`]);
  ok('el de hoy es 0 días de atraso', r.dias_de_atraso === 0, String(r.dias_de_atraso));
}

console.log(`\n${fallos === 0 ? 'TODO EN VERDE' : fallos + ' FALLOS'}`);
process.exit(fallos ? 1 : 0);
