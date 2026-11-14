/**
 * En los nodos Code de n8n, el modo "Run Once for Each Item"
 * (`runOnceForEachItem`) PROHÍBE `$input.first()`, `$input.all()` y
 * `$input.last()`. Si se usan, el nodo revienta en ejecución con:
 *
 *     Can't use .first() here [line 1, for item 0]
 *
 * Eso mandó a producción una API de reservas donde ninguna reserva
 * funcionaba: tres nodos estaban en modo por-item usando `.first()`.
 * `GET /clases` sí andaba, porque ese nodo estaba en el otro modo — así
 * que la página cargaba los horarios y fallaba justo al apartar el cupo.
 *
 * No lo cazó nada porque el espejo de pruebas (espejo-api.mjs) reimplementa
 * el contrato en Node: prueba la PÁGINA, no el código que corre dentro de
 * n8n. Este chequeo cubre ese hueco por el lado del texto.
 *
 *   node pruebas/modo-code-n8n.mjs
 */
import { readdirSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const RAIZ = join(dirname(fileURLToPath(import.meta.url)), '..');
const DIR = join(RAIZ, 'n8n');

const PROHIBIDOS = ['$input.first(', '$input.all(', '$input.last('];

let fallos = 0;
const hallazgos = [];

for (const archivo of readdirSync(DIR).filter(f => /\.(js|ts)$/.test(f)).sort()) {
  const texto = readFileSync(join(DIR, archivo), 'utf8');

  // Cada nodo Code trae su modo y su jsCode; se buscan juntos porque el
  // problema no es el modo ni el método por separado, sino la pareja.
  const nodos = [...texto.matchAll(
    /mode:\s*'(runOnceForEachItem|runOnceForAllItems)'[\s\S]{0,200}?jsCode:\s*([A-Z_]+|"(?:[^"\\]|\\.)*")/g
  )];

  for (const m of nodos) {
    if (m[1] !== 'runOnceForEachItem') continue;

    // El jsCode puede venir en línea o por el nombre de una constante.
    let codigo = m[2];
    if (!codigo.startsWith('"')) {
      const cte = new RegExp(`const\\s+${codigo}\\s*=\\s*("(?:[^"\\\\]|\\\\.)*")`).exec(texto);
      if (!cte) continue;
      codigo = cte[1];
    }

    for (const malo of PROHIBIDOS) {
      if (codigo.includes(malo)) {
        const linea = texto.slice(0, m.index).split('\n').length;
        hallazgos.push(`${archivo}:${linea}  modo por-item usando ${malo})`);
        fallos++;
      }
    }
  }
}

if (fallos === 0) {
  console.log('✓ ningun nodo Code en modo por-item usa $input.first/all/last');
  console.log('\nTODO EN VERDE');
  process.exit(0);
}

console.log(`✗ ${fallos} nodo(s) Code que van a reventar en ejecucion:\n`);
for (const h of hallazgos) console.log('   ' + h);
console.log('\nArreglo: o pasar el nodo a runOnceForAllItems, o usar $input.item.json.');
console.log(`\n${fallos} FALLOS`);
process.exit(1);
