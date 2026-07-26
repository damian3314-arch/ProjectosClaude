/**
 * Supabase carga la extensión `safeupdate` en las conexiones de PostgREST.
 * Ahí, un DELETE o un UPDATE sin WHERE revienta con
 *     DELETE requires a WHERE clause
 * y lo hace también dentro de funciones SECURITY DEFINER, y también sobre
 * tablas temporales.
 *
 * Postgres a secas no trae esa extensión, así que las pruebas locales
 * pasan y el error solo aparece contra Supabase de verdad. Por eso esto
 * es un chequeo de texto y no una prueba de ejecución.
 *
 *   node pruebas/sin-delete-sin-where.mjs
 */
import { readdirSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const RAIZ = join(dirname(fileURLToPath(import.meta.url)), '..');
const DIR = join(RAIZ, 'supabase', 'migrations');

let fallos = 0;
const hallazgos = [];

for (const archivo of readdirSync(DIR).filter(f => f.endsWith('.sql')).sort()) {
  const texto = readFileSync(join(DIR, archivo), 'utf8');
  const lineas = texto.split('\n');

  for (let i = 0; i < lineas.length; i++) {
    const linea = lineas[i];
    // Se quitan los comentarios de línea antes de mirar.
    const codigo = linea.replace(/--.*$/, '');
    const m = /\b(delete\s+from|update)\s+([a-z_][a-z0-9_."]*)/i.exec(codigo);
    if (!m) continue;

    // "select ... for update", "for update skip locked" y "for update of r"
    // son bloqueo de fila, no sentencias UPDATE. No llevan WHERE propio.
    if (/\bfor\s*$/i.test(codigo.slice(0, m.index))) continue;

    // Un DELETE/UPDATE puede llevar el WHERE varias líneas más abajo. Se
    // mira desde aquí hasta el punto y coma que cierra la sentencia.
    let sentencia = codigo.slice(m.index);
    let j = i;
    while (!sentencia.includes(';') && j < lineas.length - 1) {
      j++;
      sentencia += ' ' + lineas[j].replace(/--.*$/, '');
    }
    sentencia = sentencia.split(';')[0];

    // "update ... set ... from x where" y "delete from x using y where"
    // también cuentan: lo único que importa es que haya WHERE.
    if (/\bwhere\b/i.test(sentencia)) continue;

    hallazgos.push(`${archivo}:${i + 1}  ${linea.trim()}`);
    fallos++;
  }
}

if (fallos === 0) {
  console.log('✓ ningun DELETE ni UPDATE sin WHERE en las migraciones');
  console.log('\nTODO EN VERDE');
  process.exit(0);
}

console.log(`✗ ${fallos} sentencia(s) sin WHERE — safeupdate de Supabase las va a rechazar:\n`);
for (const h of hallazgos) console.log('   ' + h);
console.log('\nSi de verdad hay que borrar/actualizar toda la tabla, pon "where true".');
console.log(`\n${fallos} FALLOS`);
process.exit(1);
