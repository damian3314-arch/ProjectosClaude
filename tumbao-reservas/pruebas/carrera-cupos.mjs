/**
 * ¿Pueden dos personas llevarse el mismo cupo al mismo tiempo?
 *
 * Esta es la promesa entera del sistema: "si la página dice 3, vendemos
 * 3 y ni uno más". Todo lo demás —la resta del aforo, el descuento por
 * reserva— es aritmética que se ve a simple vista. Esto no: solo aparece
 * cuando varias personas dan al botón en el mismo segundo, que es justo
 * lo que pasa cuando quedan pocos cupos y la clase está por llenarse.
 *
 * La protección es el `select ... for update` de tomar_cupo, que hace
 * que las sesiones hagan fila sobre la fila de la clase. Aquí se abren
 * N conexiones de verdad y se lanzan todas a la vez.
 *
 *   PGDATABASE=tumbao node pruebas/carrera-cupos.mjs
 */
import { spawn } from 'node:child_process';

const PSQL = {
  host: process.env.PGHOST || '/var/lib/postgresql',
  port: process.env.PGPORT || '5599',
  user: process.env.PGUSER || 'postgres',
  db:   process.env.PGDATABASE || 't7',
};

let fallos = 0;
const ok = (n, c, extra = '') => {
  console.log(`${c ? '✓' : '✗'} ${n}${extra ? '  → ' + extra : ''}`);
  if (!c) fallos++;
};

// Cada llamada abre su propia conexión: es la única forma de que peleen
// de verdad. Dentro de una sola sesión los bloqueos no se notan.
const sql = consulta => new Promise((res, rej) => {
  const p = spawn('psql', ['-h', PSQL.host, '-p', PSQL.port, '-U', PSQL.user,
                           '-d', PSQL.db, '-tAq', '-v', 'ON_ERROR_STOP=1'],
                  { stdio: ['pipe', 'pipe', 'pipe'] });
  let out = '', err = '';
  p.stdout.on('data', d => out += d);
  p.stderr.on('data', d => err += d);
  p.on('close', c => c === 0 ? res(out.trim()) : rej(new Error(err.trim() || `psql salio ${c}`)));
  p.stdin.end(consulta);
});

const CUPOS = 4;
const CORREDORES = 12;

// Una clase limpia con exactamente CUPOS libres.
await sql(`
  delete from reservas where true;
  delete from pagos where true;
  delete from membresias where true;
  delete from clases where true;
  select generar_horario(current_date, current_date + 13);
  update clases set cupo_total = ${CUPOS}, cupo_tomado = 0, aforo = 30, activos_plan = 30 - ${CUPOS}
   where fecha_hora > now();
`);

const claseId = await sql(`
  select id from clases where fecha_hora > now() order by fecha_hora limit 1;`);

console.log(`clase con ${CUPOS} cupos · ${CORREDORES} personas dándole al botón a la vez\n`);

// Todas las conexiones salen disparadas juntas.
const intentos = await Promise.all(
  Array.from({ length: CORREDORES }, (_, i) =>
    sql(`select tomar_cupo('${claseId}'::uuid, 'Corredor ${i}', '30000000${String(i).padStart(2,'0')}',
                            null, 'carrera', 'suelta') ->> 'ok';`)
      .then(r => r === 'true')
      .catch(e => { console.log('   error en una conexión:', e.message.split('\n')[0]); return null; })
  ));

const ganaron = intentos.filter(x => x === true).length;
const perdieron = intentos.filter(x => x === false).length;
const rotos = intentos.filter(x => x === null).length;

ok(`entraron exactamente ${CUPOS}`, ganaron === CUPOS, `${ganaron} entraron`);
ok('el resto rebotó limpio', perdieron === CORREDORES - CUPOS, `${perdieron} rebotaron`);
ok('ninguna conexión reventó', rotos === 0, `${rotos} con error`);

const [tomado, total, reservas] = (await sql(`
  select c.cupo_tomado, c.cupo_total,
         (select count(*) from reservas r where r.clase_id = c.id)
    from clases c where c.id = '${claseId}'::uuid;`)).split('|');

ok('cupo_tomado no se pasó del total', Number(tomado) <= Number(total),
   `${tomado} de ${total}`);
ok('hay tantas reservas como cupos gastados', Number(reservas) === Number(tomado),
   `${reservas} reservas, ${tomado} cupos`);

// Y ningún código repetido: el generador aguanta la concurrencia.
const repetidos = await sql(`
  select count(*) from (
    select codigo from reservas group by codigo having count(*) > 1) x;`);
ok('ningún código de reserva repetido', Number(repetidos) === 0, `${repetidos} repetidos`);

console.log(`\n${fallos === 0 ? 'TODO EN VERDE' : fallos + ' FALLOS'}`);
process.exit(fallos ? 1 : 0);
