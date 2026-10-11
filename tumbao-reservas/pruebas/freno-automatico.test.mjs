/**
 * Freno automático de las ventas por WhatsApp y latido del reloj de Cloudflare (0163).
 *
 * Damián (9 oct): «que yo no tenga que dar tanto permiso, que sea automático». Esta prueba protege que:
 *   1. el freno use los límites que ya tenía la rutina diaria (calidad ≠ GREEN, bajas > 8 %, fallos > 25 %, error 131042)
 *      y solo APAGUE: nunca enciende nada ni borra;
 *   2. corra por dos caminos: el centinela (cada hora, pg_cron) y el cron del Worker (cada 10 minutos);
 *   3. el cron del Worker deje un latido para saber si Cloudflare ya dispara los cron en esta cuenta;
 *   4. nada de esto toque renovaciones, reservas, informes ni el dinero.
 *
 *   node freno-automatico.test.mjs
 */
import { readFileSync } from 'node:fs';

let fallos = 0;
const ok = (n, c, extra = '') => { if (!c) fallos++; console.log(`${c ? '✓' : '✗'} ${n}${extra ? '  → ' + extra : ''}`); };
const titulo = t => console.log(`\n-- ${t} ${'-'.repeat(Math.max(0, 54 - t.length))}`);

const w = readFileSync(new URL('../../tumbao-caja/src/index.js', import.meta.url), 'utf8');
const cfg = readFileSync(new URL('../../tumbao-caja/wrangler.jsonc', import.meta.url), 'utf8');
const m = readFileSync(new URL('../supabase/migrations/0163_freno_automatico_de_ventas_y_latido_de_cron.sql', import.meta.url), 'utf8').replace(/--.*$/gm, '');

titulo('1. La función de freno (SQL)');
{
  ok('apaga solo si wa_ventas está encendido y solo escribe «apagado» (nunca «encendido»)',
     /<> 'encendido'/.test(m) && /set valor = 'apagado'/.test(m) && !/set valor = 'encendido'/.test(m));
  ok('calidad distinta de GREEN → apaga', /coalesce\(p_calidad, 'GREEN'\) <> 'GREEN'/.test(m));
  ok('error 131042 de Meta (pago pendiente) → apaga', /like '131042%'/.test(m));
  ok('bajas: más del 8 % de las aperturas del día, con al menos 10', /v_aperturas >= 10 and v_bajas \* 100\.0 \/ v_aperturas > 8/.test(m));
  ok('fallos: más del 25 % de las entregas, con al menos 20', /v_aperturas >= 20 and v_fallos \* 100\.0 \/ v_aperturas > 25/.test(m));
  ok('cuenta las tres plantillas de ventas (apertura, horario y encuesta) del día de Bogotá',
     /'ventas_apertura', 'ventas_horario', 'encuesta_regreso'/.test(m) && /America\/Bogota/.test(m));
  ok('deja el motivo y las cifras en ajustes.ventas_freno_ultimo', /ventas_freno_ultimo/.test(m) && /v_cifras::text/.test(m));
  ok('solo el Worker (service_role) la ejecuta', /revoke all on function public\.ventas_freno_revisar\(text\) from public, anon, authenticated/.test(m)
     && /grant execute on function public\.ventas_freno_revisar\(text\) to service_role/.test(m));
  ok('no toca renovaciones, reservas, informes ni dinero', !/membresias|reservas|wa_informes|pagos|tiqueteras|caja_movimientos/.test(m.replace(/ajustes/g, '')));
  ok('sin DROP ni DELETE', !/\bdrop\b/i.test(m) && !/\bdelete\b/i.test(m));
}

titulo('2. El Worker');
{
  ok('el centinela (cada hora) corre el freno y le avisa a Damián una vez al día', /frenoAutomatico\(env\)[\s\S]{0,200}f\.accion === 'apagado'[\s\S]{0,200}alerta\(`freno:\$\{hoy\}`/.test(w));
  ok('el cron del Worker anota el latido y corre el freno antes de liberar cupos',
     /async scheduled\(evento, env, ctx\)[\s\S]{0,700}'cron_latido'[\s\S]{0,300}frenoAutomatico\(env\)[\s\S]{0,300}liberar_cupos_expirados/.test(w));
  ok('si el latido o el freno fallan, liberar cupos sigue corriendo (cada uno con su catch)',
     /'cron_latido'[^\n]*\.catch\(/.test(w) && /frenoAutomatico\(env\)\.catch\(/.test(w));
  ok('lee la calidad del número a Meta y manda null si no puede (el freno no se dispara por un fallo de red)',
     /async function calidadDelNumero[\s\S]{0,400}fields=quality_rating/.test(w) && /calidadDelNumero\(env\)\.catch\(\(\) => null\)/.test(w));
  ok('cron cada 10 minutos agregado sin quitar los de siempre', /"crons": \["0 11-23 \* \* \*", "0 0-3 \* \* \*", "\*\/10 \* \* \* \*"\]/.test(cfg));
}

titulo('3. El latido');
{
  ok('anota la hora y cuenta los disparos', /cf_cron_ultimo/.test(m) && /cf_cron_total/.test(m) && /\+ 1\)::text/.test(m));
  ok('solo el Worker (service_role) lo ejecuta', /grant execute on function public\.cron_latido\(text\) to service_role/.test(m));
}

console.log(fallos ? `\n${fallos} fallo(s)` : '\nTodo bien');
process.exit(fallos ? 1 : 0);
