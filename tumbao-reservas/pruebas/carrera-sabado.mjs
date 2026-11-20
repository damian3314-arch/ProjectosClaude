/**
 * ¿El reparto del sábado aguanta a varias personas a la vez?
 *
 * El tope por tipo no se guarda en un contador: se cuentan las reservas
 * vivas en el momento de decidir. Eso es correcto solo si esa cuenta
 * pasa DENTRO del `select ... for update` de la clase — si no, dos
 * afiliadas leen "hay 14" al mismo tiempo y entran las dos.
 *
 * Aquí se abren conexiones de verdad y se lanzan juntas: 20 afiliadas y
 * 20 sueltas contra 15 y 15.
 *
 * Lo que se comprueba es lo que costaría dinero si fallara:
 *   · entran exactamente 15 de cada lado, ni una más
 *   · los dos lados llegan a 15 (si se estorbaran, se vendería menos)
 *   · el total es 30 y no se pasa del aforo
 *
 *   PGDATABASE=tumbao node pruebas/carrera-sabado.mjs
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

// Cada llamada abre su propia conexión: dentro de una sola sesión los
// bloqueos no se notan y la prueba no probaría nada.
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

const TOPE = 15;
const CORREDORES = 20;

// Un sábado limpio, con 30 afiliadas que puedan reservar ese día.
await sql(`
  delete from asistencias where true;
  delete from reservas where true;
  delete from pagos where true;
  delete from membresias where true;
  delete from clases where true;
  select generar_horario(current_date, current_date + 13);
  select importar_membresias((
    select jsonb_agg(f) from (
      select jsonb_build_object(
        'afiliado', 'Socia ' || g, 'membresia', 'PLAN MENSUALIDAD 6:00PM',
        'hora', '18:00:00', 'tipo', 'plan',
        'documento', (700000 + g)::text, 'celular', '300' || lpad(g::text, 7, '0'),
        'correo', null,
        'inicio', (current_date - 3)::text, 'fin', (current_date + 25)::text) as f
      from generate_series(1, ${CORREDORES}) g) s));
`);

const claseId = await sql(`
  select id from clases
   where extract(dow from fecha_hora at time zone 'America/Bogota') = 6
     and fecha_hora > now()
   order by fecha_hora limit 1;`);

const [tm, ts] = (await sql(
  `select cupo_miembros, cupo_sueltas from clases where id = '${claseId}'::uuid;`)).split('|');
console.log(`sábado con ${tm} de afiliados y ${ts} de sueltas · ` +
            `${CORREDORES} de cada tipo dándole al botón a la vez\n`);

// Los 40 salen disparados juntos, mezclados.
const intentos = await Promise.all([
  ...Array.from({ length: CORREDORES }, (_, i) =>
    sql(`select tomar_cupo('${claseId}'::uuid, 'Socia ${i + 1}',
          '300${String(i + 1).padStart(7, '0')}', null, 'carrera', 'miembro') ->> 'ok';`)
      .then(r => ({ tipo: 'miembro', ok: r === 'true' }))
      .catch(e => { console.log('   error:', e.message.split('\n')[0]); return null; })),
  ...Array.from({ length: CORREDORES }, (_, i) =>
    sql(`select tomar_cupo('${claseId}'::uuid, 'Suelta ${i + 1}',
          '311${String(i + 1).padStart(7, '0')}', null, 'carrera', 'suelta') ->> 'ok';`)
      .then(r => ({ tipo: 'suelta', ok: r === 'true' }))
      .catch(e => { console.log('   error:', e.message.split('\n')[0]); return null; })),
]);

const cuenta = (t, v) => intentos.filter(x => x && x.tipo === t && x.ok === v).length;
const rotos = intentos.filter(x => x === null).length;

ok(`entraron exactamente ${TOPE} afiliadas`, cuenta('miembro', true) === TOPE,
   `${cuenta('miembro', true)} entraron`);
ok(`entraron exactamente ${TOPE} sueltas`, cuenta('suelta', true) === TOPE,
   `${cuenta('suelta', true)} entraron`);
ok('el resto rebotó limpio',
   cuenta('miembro', false) === CORREDORES - TOPE &&
   cuenta('suelta', false) === CORREDORES - TOPE,
   `${cuenta('miembro', false)} + ${cuenta('suelta', false)} rebotaron`);
ok('ninguna conexión reventó', rotos === 0, `${rotos} con error`);

// Y en la base tiene que verse lo mismo: si los dos lados se hubieran
// estorbado, aquí saldría menos de 30 y se habría vendido de menos.
const [tomado, total, nm, ns] = (await sql(`
  select c.cupo_tomado, c.cupo_total,
         (select count(*) from reservas r where r.clase_id = c.id and r.tipo = 'miembro'),
         (select count(*) from reservas r where r.clase_id = c.id and r.tipo = 'suelta')
    from clases c where c.id = '${claseId}'::uuid;`)).split('|');

ok('la base tiene 15 y 15', Number(nm) === TOPE && Number(ns) === TOPE,
   `${nm} afiliadas, ${ns} sueltas`);
ok('el total no se pasó del aforo', Number(tomado) <= Number(total),
   `${tomado} de ${total}`);
ok('y se vendió el sábado completo', Number(tomado) === TOPE * 2,
   `${tomado} de ${TOPE * 2}`);

console.log(`\n${fallos === 0 ? 'TODO EN VERDE' : fallos + ' FALLOS'}`);
process.exit(fallos ? 1 : 0);
