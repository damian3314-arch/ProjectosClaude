/**
 * La pausa de los avisos de renovación (0177 + 0178, 13 oct).
 *
 * Damián: «esta semana no envíes mensajes invitando a renovar, porque ya se enviaron desde recepción». Y después aclaró:
 * «lo único que pedí pausar son los avisos a los clientes a quienes se les venció la mensualidad. Solamente esos».
 * 0177 pausó de más; 0178 lo deja en lo que pidió. La pausa se probó en la base real; aquí se protege lo que queda escrito:
 *   · es por FECHA (se levanta sola el lunes 19), no un interruptor que alguien tenga que acordarse de encender;
 *   · solo se salta el aviso de «ya venció» (fin entre hoy-2 y hoy);
 *   · el aviso de «te vence en 3 días», el bot de ventas y su seguimiento quedan como siempre.
 *
 *   node pausa-renovaciones.test.mjs
 */
import { readFileSync } from 'node:fs';

let fallos = 0;
const ok = (n, c, extra = '') => { if (!c) fallos++; console.log(`${c ? '✓' : '✗'} ${n}${extra ? '  → ' + extra : ''}`); };
const titulo = t => console.log(`\n-- ${t} ${'-'.repeat(Math.max(0, 54 - t.length))}`);

const leer = (n) => readFileSync(new URL(`../supabase/migrations/${n}`, import.meta.url), 'utf8').replace(/--.*$/gm, '');
const m77 = leer('0177_pausa_de_renovaciones.sql');
const m78 = leer('0178_pausa_solo_avisos_de_ya_vencio.sql');

titulo('1. La pausa es por fecha y se levanta sola');
{
  ok('la fecha vive en ajustes.renovacion_pausa_hasta (domingo 18 de octubre, inclusive)',
     /'renovacion_pausa_hasta', '2026-10-18'/.test(m77));
  ok('vacía o con fecha pasada = sin pausa (el lunes 19 todo vuelve sin tocar nada)',
     /coalesce\(nullif\(\(select valor from ajustes where clave = 'renovacion_pausa_hasta'\), ''\)::date, date '2000-01-01'\)/.test(m78));
  ok('compara con «hoy <= fecha» (la fecha misma sigue en pausa)', /en_pausa boolean := hoy <= coalesce\(/.test(m78));
}

titulo('2. Solo se pausa el aviso de «ya se le venció»');
{
  ok('el aviso diario ya no corta todo: se quita el «return» de 0177',
     /renovacion_automatica\(\)/.test(m78) && /'motivo', 'pausa_hasta'/.test(m78) && /\$a\$, ''\);/.test(m78));
  ok('solo se salta la parte de «ya venció» (fin entre hoy-2 y hoy)',
     /where e\.fin between hoy - 2 and hoy and not en_pausa/.test(m78));
  ok('el aviso de «te vence en 1 a 3 días» no se toca', !/hoy \+ 1|hoy \+ 3/.test(m78));
}

titulo('3. Lo demás queda como siempre');
{
  ok('el bot de ventas vuelve a proponer mensualidades de 7 am y 6 pm (se quita el bloque de 0177)',
     /ventas_candidatos\(integer\)/.test(m78) && /v_l7 := 0; v_l6 := 0;/.test(m78) && /no encontré el bloque de pausa en ventas_candidatos/.test(m78));
  ok('el seguimiento vuelve a escribirle a los chats de mensualidad',
     /ventas_seguimientos_tomar\(integer\)/.test(m78) && /c\.objetivo like 'mensualidad%'/.test(m78));
  ok('no toca la lista de espera, las reservas, el rescate de tiqueteras ni los horarios del cron',
     !/mensualidad_avisar_lista_espera|tiquetera_recordar_pago|reserva|cron\.(un)?schedule|cron\.alter_job/.test(m78));
  ok('se puede correr de nuevo sin romper nada, y falla en vez de dejar algo a medias',
     (m78.match(/ya estaba (acotada|normal)/g) || []).length === 3 && (m78.match(/raise exception '0178: no encontré/g) || []).length >= 5);
  ok('no borra nada ni cancela avisos ya encolados', !/\bdelete\b|\bdrop\b|\btruncate\b|update\s+wa_avisos/i.test(m78));
}

console.log(`\n${fallos ? '✗ ' + fallos + ' con problemas' : '✓ todo bien'}`);
process.exit(fallos ? 1 : 0);
