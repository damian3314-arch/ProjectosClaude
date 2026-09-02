/**
 * Las pruebas de navegador del panel, todas de un tirón.
 *
 * POR QUÉ
 * Que no existiera es parte de por qué esto se pudrió sin que nadie lo
 * viera: siete archivos sueltos que había que acordarse de correr uno a
 * uno, con una ruta a mano cada vez. Llevaban semanas sin ejecutarse y
 * ninguna arrancaba.
 *
 * QUÉ MIRA PARA DECIDIR SI PASÓ
 * El código de salida Y las marcas ✗ del texto. Las dos cosas, porque no
 * todas las suites se acuerdan de salir con código distinto de cero:
 * deposito-a-caja.test.mjs imprime sus ✗ y termina en 0. Contando las
 * marcas, un fallo suyo se ve aquí igual que el de las demás sin tener
 * que tocarla.
 *
 *   node pruebas/todas.mjs
 */
import { spawnSync } from 'node:child_process';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { panelInstrumentado, PANEL } from './instrumentar.mjs';

const AQUI = dirname(fileURLToPath(import.meta.url));

const SUITES = [
  'confirmar-pide-referencia',
  'deposito-a-caja',
  'juntar-depositos',
  'pulso-ingesta',
  'tarjeta-sabado',
  'tirilla-cuadre-puerta-banco',
  'tirilla-cuando-pagaron',
];

// Se instrumenta una vez aquí para que, si el marcador del panel cambió,
// se sepa de entrada y con el mensaje bueno — y no siete veces seguidas
// enterrado entre la salida de cada suite.
const copia = panelInstrumentado();
console.log(`Panel:  ${PANEL}`);
console.log(`Copia:  ${copia}\n`);

const resultados = [];

for (const nombre of SUITES) {
  console.log(`\n─── ${nombre} ${'─'.repeat(Math.max(0, 56 - nombre.length))}`);
  const r = spawnSync(process.execPath, [join(AQUI, `${nombre}.test.mjs`), copia],
                      { encoding: 'utf8' });
  const salida = (r.stdout || '') + (r.stderr || '');
  process.stdout.write(salida);
  const marcas = (salida.match(/✗/g) || []).length;
  const bien = r.status === 0 && marcas === 0;
  resultados.push({ nombre, bien, marcas, codigo: r.status,
                    checks: (salida.match(/[✓✗]/g) || []).length });
}

console.log(`\n${'═'.repeat(64)}`);
for (const x of resultados) {
  console.log(
    `${x.bien ? '✓' : '✗'} ${x.nombre.padEnd(30)} ` +
    `${String(x.checks).padStart(3)} comprobaciones` +
    (x.bien ? '' : `  → ${x.marcas} fallo(s), salió con ${x.codigo}`));
}

const malas = resultados.filter(x => !x.bien);
console.log(malas.length
  ? `\n${malas.length} de ${resultados.length} suites con fallos.`
  : `\nLas ${resultados.length} suites en verde.`);
process.exit(malas.length ? 1 : 0);
