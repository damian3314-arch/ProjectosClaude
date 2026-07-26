/**
 * Prueba del parser del reporte de afiliados.
 *
 * Existe porque este parser se fue a produccion sin una sola prueba y
 * fallo en la primera corrida real: el nodo "Extract From File" entrega
 * cada fila como { row: [...] }, no como un objeto plano, y el parser
 * hacia Object.values() sobre eso. Resultado: la fila entera se volvia
 * un solo texto y nunca aparecia la cabecera.
 *
 * Los nombres de aqui son inventados. La FORMA (fila de titulo, cabecera
 * en la segunda, "PLAN MENSUALIDAD 7:00AM", fechas "30/jun./2026") es la
 * del archivo real de Drive.
 */
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const RAIZ = join(dirname(fileURLToPath(import.meta.url)), '..');
const CODIGO = readFileSync(join(RAIZ, 'n8n', 'parser-afiliados.js'), 'utf8');

let fallos = 0;
const ok = (n, c, extra = '') => {
  console.log(`${c ? '✓' : '✗'} ${n}${extra ? '  → ' + extra : ''}`);
  if (!c) fallos++;
};

// Corre el codigo del nodo con un $input simulado.
function correr(items) {
  const $input = { all: () => items };
  return new Function('$input', CODIGO + '\n')($input);
}

const enFilas = arr => arr.map(row => ({ json: { row } }));

// La forma real que devuelve "Extract From File" con headerRow:false.
const REPORTE = [
  ['Reporte Afiliados con Membresía Activa', '', '', '', '', '', '', ''],
  ['Afiliado', 'Membresía', '# Documento', 'Celular', 'Correo', 'Dirección',
   'Inicio Membresía', 'Final Membresía'],
  ['ANA MARIA PEREZ', 'PLAN MENSUALIDAD 7:00AM', 1005175642, 3134211992, '', '',
   '30/jun./2026', '29/jul./2026'],
  ['BEATRIZ LONDONO', 'PLAN MENSUALIDAD 7:00PM', 37750158, 3012116124, '', '',
   '17/jul./2026', '16/ago./2026'],
  ['CARLA GIRALDO', 'MEDIA MENSUALIDAD 6:00PM', 43567890, 3001234567, '', '',
   '01/jul./2026', '31/jul./2026'],
];

// ── el caso que rompio en produccion ─────────────────────────
{
  const r = correr(enFilas(REPORTE))[0].json;
  ok('encuentra la cabecera en la forma { row: [...] }', r.ok === true,
     r.ok ? '' : r.mensaje);
  ok('lee los 3 afiliados', r.total === 3, `total=${r.total}`);
  ok('no descarta ninguno', r.descartados === 0,
     r.descartados ? JSON.stringify(r.detalle_descartes) : '');

  const a = r.filas[0];
  ok('saca la hora del texto de la membresia', a.hora === '07:00:00', a.hora);
  ok('convierte la fecha con mes abreviado', a.inicio === '2026-06-30', a.inicio);
  ok('y la de fin', a.fin === '2026-07-29', a.fin);
  ok('el documento sale como texto', a.documento === '1005175642', a.documento);
  ok('el celular tambien', a.celular === '3134211992', a.celular);

  ok('7:00 PM se convierte a 19:00, no a 07:00',
     r.filas[1].hora === '19:00:00', r.filas[1].hora);
  ok('distingue media mensualidad de plan',
     r.filas[2].tipo === 'media' && r.filas[0].tipo === 'plan',
     `${r.filas[2].tipo} / ${r.filas[0].tipo}`);

  // Comparar por contenido, no por JSON.stringify: el orden de las
  // llaves depende del orden de insercion y no significa nada.
  const esperado = { '07:00:00': 1, '18:00:00': 1, '19:00:00': 1 };
  const mismo = Object.keys(esperado).length === Object.keys(r.por_hora).length &&
    Object.entries(esperado).every(([k, v]) => r.por_hora[k] === v);
  ok('cuenta por hora', mismo, JSON.stringify(r.por_hora));
}

// ── la forma de objeto plano tambien tiene que servir ────────
{
  const items = REPORTE.map(row => ({
    json: Object.fromEntries(row.map((c, i) => ['col' + i, c]))
  }));
  const r = correr(items)[0].json;
  ok('tambien lee la forma de objeto plano', r.ok === true && r.total === 3,
     r.ok ? `total=${r.total}` : r.mensaje);
}

// ── cosas que se pueden torcer ───────────────────────────────
{
  // Columnas reordenadas: el parser busca por nombre, no por posicion.
  const revuelto = [
    ['Reporte Afiliados con Membresía Activa', '', '', ''],
    ['Final Membresía', 'Afiliado', 'Inicio Membresía', 'Membresía'],
    ['29/jul./2026', 'ANA MARIA PEREZ', '30/jun./2026', 'PLAN MENSUALIDAD 7:00AM'],
  ];
  const r = correr(enFilas(revuelto))[0].json;
  ok('aguanta que reordenen las columnas',
     r.ok === true && r.total === 1 && r.filas[0].hora === '07:00:00',
     r.ok ? '' : r.mensaje);
}
{
  // Sin cabecera: tiene que decirlo, no inventarse datos.
  const r = correr(enFilas([['algo', 'otra cosa'], ['mas', 'datos']]))[0].json;
  ok('sin cabecera lo dice', r.ok === false && r.error === 'sin_cabecera', r.error);
}
{
  // Archivo vacio.
  const r = correr([])[0].json;
  ok('archivo vacio lo dice', r.ok === false && r.error === 'sin_cabecera', r.error);
}
{
  // Una fila a la que le falta la fecha se descarta, pero las demas entran.
  const cojo = [
    REPORTE[0], REPORTE[1], REPORTE[2],
    ['DIANA RUIZ', 'PLAN MENSUALIDAD 6:00PM', 111, 300, '', '', '', ''],
  ];
  const r = correr(enFilas(cojo))[0].json;
  ok('una fila incompleta no tumba el resto',
     r.ok === true && r.total === 1 && r.descartados === 1,
     `total=${r.total} descartados=${r.descartados}`);
  ok('y dice a quien descarto y por que',
     r.detalle_descartes[0].afiliado === 'DIANA RUIZ' &&
     /inicio/.test(r.detalle_descartes[0].falta),
     JSON.stringify(r.detalle_descartes[0]));
}
{
  // Filas en blanco al final del archivo, que Excel mete siempre.
  const conVacias = [...REPORTE, ['', '', '', '', '', '', '', ''], ['', '']];
  const r = correr(enFilas(conVacias))[0].json;
  ok('salta las filas en blanco del final',
     r.total === 3 && r.descartados === 0, `total=${r.total}`);
}
{
  // 12:00 PM es mediodia, 12:00 AM es medianoche. Es el error clasico.
  const medio = [
    REPORTE[0], REPORTE[1],
    ['ELENA VEGA', 'PLAN MENSUALIDAD 12:00PM', 1, 2, '', '', '01/jul./2026', '31/jul./2026'],
    ['FABIO SOTO', 'PLAN MENSUALIDAD 12:00AM', 3, 4, '', '', '01/jul./2026', '31/jul./2026'],
  ];
  const r = correr(enFilas(medio))[0].json;
  ok('12:00 PM es mediodia', r.filas[0].hora === '12:00:00', r.filas[0].hora);
  ok('12:00 AM es medianoche', r.filas[1].hora === '00:00:00', r.filas[1].hora);
}

console.log(`\n${fallos === 0 ? 'TODO EN VERDE' : fallos + ' FALLOS'}`);
process.exit(fallos ? 1 : 0);
