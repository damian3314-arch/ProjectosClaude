/**
 * La campaña del 14 de octubre, 9:00 am (0182).
 *
 * Damián (13 oct): «envíalo mañana a las 9 am, con el copy nuevo que armamos, y a las que apliquen a mensualidad,
 * invitarlas a mensualidad. A la gente que le viste alguna intención o reacción, escríbele si se puede».
 *
 * La lógica de quién entra se probó en la base real en modo «solo contar» (retoma 9, mensualidad 10, tiquetera 13). Aquí se
 * protege lo que queda escrito en el archivo:
 *
 *   node campana-14-oct.test.mjs
 */
import { readFileSync } from 'node:fs';

let fallos = 0;
const ok = (n, c, extra = '') => { if (!c) fallos++; console.log(`${c ? '✓' : '✗'} ${n}${extra ? '  → ' + extra : ''}`); };
const titulo = t => console.log(`\n-- ${t} ${'-'.repeat(Math.max(0, 54 - t.length))}`);

const m = readFileSync(new URL('../supabase/migrations/0182_campana_frecuentes_14_oct.sql', import.meta.url), 'utf8').replace(/^\s*--.*$/gm, '');

titulo('1. Sale una sola vez, a las 9:00 am, y solo en horario permitido');
{
  ok('un cron de una sola vez: 14 de octubre, 14:00 UTC = 9:00 am de Bogotá',
     /cron\.schedule\('tumbao-campana-14oct', '0 14 14 10 \*'/.test(m));
  ok('el mismo cron se desprograma al terminar',
     /campana_frecuentes_14oct\(true\); select cron\.unschedule\('tumbao-campana-14oct'\)/.test(m));
  ok('todo se encola como campaña (tipo «campana»): el despachador la retiene fuera del horario de mercadeo (Ley 2300)',
     (m.match(/'campana', /g) || []).length >= 3 && !/'renovacion'|'tiquetera_activa'/.test(m));
  ok('p_ejecutar = false solo cuenta: ninguna inserción ni actualización corre sin él',
     (m.match(/p_ejecutar and/g) || []).length === 3 && /where p_ejecutar and c\.id = r\.chat_id/.test(m));
}

titulo('2. A quién: los mismos filtros de siempre');
{
  ok('no escribe a quien pidió SALIR, a las dueñas ni a celulares inválidos',
     (m.match(/wa_bajas/g) || []).length >= 2 && (m.match(/not wa_es_dueno/g) || []).length >= 2 && (m.match(/\^3\[0-9\]\{9\}\$/g) || []).length >= 2);
  ok('no escribe a quien ya tiene plan vigente (con la gracia) ni tiquetera vigente',
     (m.match(/not in \(select tel from vig\)/g) || []).length >= 2 && (m.match(/t\.vence_el >= hoy/g) || []).length >= 2);
  ok('frecuentes: 2 o más clases sueltas en 30 días; sin oferta de tiquetera en 14 días; máximo 2 campañas en 14 días y ninguna en 3',
     /r\.v30 >= 2/.test(m) && /coalesce\(a\.enviado_at, a\.creado_at\) > now\(\) - interval '14 days'/.test(m) &&
     /< 2/.test(m) && /a\.creado_at > now\(\) - interval '3 days'/.test(m));
  ok('respeta el «no me interesa» de los últimos 45 días y a quien ya pagó una solicitud de mensualidad',
     /c\.cerrada_at > now\(\) - interval '45 days'/.test(m) && /m\.estado in \('esperando_pago', 'pagada'\)/.test(m));
  ok('una sola vez por persona: la clave de la tiquetera es única, la de retoma lleva la fecha y los frecuentes no repiten a los de retoma',
     /'tiqconst:' \|\| a\.tel/.test(m) && /':retoma:'/.test(m) && /r\.tel not in \(select tel from ret\)/.test(m));
}

titulo('3. Qué recibe cada uno');
{
  ok('retoma: pidieron la mensualidad de 6 o 7 pm; se les reabre la conversación y reciben la apertura con «ya hay cupo disponible»',
     /resumen ~\* '7\(:00\)\?/.test(m) && /resumen ~\* '6\(:00\)\?/.test(m) && /estado = 'abierta'/.test(m) && /ya hay cupo disponible/.test(m));
  ok('retoma y mensualidad son hasta el número de cupos libres de cada horario (no se oferta más de lo que hay)',
     /rq\.rn <= coalesce\(\(cupos ->> rq\.hora_r\)::int, 0\)/.test(m) && /c\.rn <= coalesce\(\(select libres from resto where h = c\.hp\), 0\)/.test(m));
  ok('a los frecuentes con cupo en su horario se les invita a la mensualidad de ese horario (quien baila de mañana, a la de 7 am)',
     /case when b\.hh < '12:00' then '07:00' else b\.hh end hp/.test(m) && /'mensualidad_7am'/.test(m) && /'mensualidad_6pm'/.test(m) && /'mensualidad_7pm'/.test(m));
  ok('los demás frecuentes reciben el copy nuevo de constancia (tiquetera_constancia) con su nombre y las veces que bailaron',
     /'tiquetera_constancia'/.test(m) && /a\.v30::text/.test(m));
  ok('el saludo usa el nombre que más se repite en ese celular, no el de la última reserva',
     /mode\(\) within group \(order by initcap\(split_part\(btrim\(x\.nombre\), ' ', 1\)\)\) n/.test(m));
  ok('sin descuentos, sin promesas y sin «últimos cupos» en los textos que escribe esta migración',
     !/descuento|gratis|promo|últimos cupos|oferta limitada/i.test(m));
}

titulo('4. El seguimiento gratis llega más lejos');
{
  ok('el seguimiento de 24 h pasa de 20 a 22 horas después del último mensaje de Timba, una sola vez y dentro de la ventana',
     /interval ''22 hours'' and ahora - interval ''3 hours''/.test(m) && /ventas_seguimientos_tomar\(integer\)/.test(m));
  ok('no borra nada', !/\bdelete\b|\bdrop\b|\btruncate\b/i.test(m));
}

console.log(`\n${fallos ? '✗ ' + fallos + ' con problemas' : '✓ todo bien'}`);
process.exit(fallos ? 1 : 0);
