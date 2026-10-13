/**
 * La pausa de los avisos de renovación (0177, 13 oct).
 *
 * Damián: «esta semana no envíes mensajes invitando a renovar, porque ya se enviaron desde recepción».
 * La pausa se probó en la base real (el aviso diario responde «pausa_hasta» y el bot no propone mensualidades). Aquí se
 * protege lo que queda escrito en el archivo:
 *   · es por FECHA (se levanta sola el lunes 19), no un interruptor que alguien tenga que acordarse de encender;
 *   · cubre los tres caminos que invitan a renovar: el aviso diario, el bot de ventas y su seguimiento;
 *   · NO toca lo demás: lista de espera, confirmaciones, rescate de tiqueteras, respuestas a quien escribe.
 *
 *   node pausa-renovaciones.test.mjs
 */
import { readFileSync } from 'node:fs';

let fallos = 0;
const ok = (n, c, extra = '') => { if (!c) fallos++; console.log(`${c ? '✓' : '✗'} ${n}${extra ? '  → ' + extra : ''}`); };
const titulo = t => console.log(`\n-- ${t} ${'-'.repeat(Math.max(0, 54 - t.length))}`);

const raw = readFileSync(new URL('../supabase/migrations/0177_pausa_de_renovaciones.sql', import.meta.url), 'utf8');
const m = raw.replace(/--.*$/gm, '');

titulo('1. La pausa es por fecha y se levanta sola');
{
  ok('guarda la fecha en ajustes.renovacion_pausa_hasta (viernes 18 de octubre, inclusive)',
     /'renovacion_pausa_hasta', '2026-10-18'/.test(m));
  ok('vacía o con fecha pasada = sin pausa (el lunes 19 todo vuelve a correr sin tocar nada)',
     (m.match(/coalesce\(nullif\(\(select valor from ajustes where clave = 'renovacion_pausa_hasta'\), ''\)::date, date '2000-01-01'\)/g) || []).length === 3);
  ok('compara con «hoy <= fecha» (la fecha misma sigue en pausa)', (m.match(/hoy <= coalesce\(/g) || []).length === 3);
}

titulo('2. Cubre los tres caminos que invitan a renovar');
{
  ok('el aviso diario de renovación (3 días antes / el día / 2 días después) devuelve «pausa_hasta» y no encola nada',
     /public\.renovacion_automatica\(\)/.test(m) && /'motivo', 'pausa_hasta'/.test(m));
  ok('el bot de ventas no abre chats nuevos de mensualidad de 7 am ni de 6 pm (cupos en 0)',
     /public\.ventas_candidatos\(integer\)/.test(m) && /v_l7 := 0; v_l6 := 0;/.test(m));
  ok('el seguimiento no le escribe a quien tiene un chat abierto de mensualidad',
     /public\.ventas_seguimientos_tomar\(integer\)/.test(m) && /c\.objetivo like 'mensualidad%'/.test(m));
}

titulo('3. No toca nada más');
{
  ok('cada cambio se aplica una sola vez y avisa si ya estaba (se puede correr de nuevo sin romper nada)',
     (m.match(/ya tenía la pausa/g) || []).length === 3);
  ok('si cambió el código de la función y no encuentra dónde poner la pausa, falla en vez de dejarla a medias',
     (m.match(/raise exception '0177: no encontré el ancla/g) || []).length === 3);
  ok('no toca la lista de espera, las reservas, el rescate de tiqueteras ni las plantillas',
     !/mensualidad_avisar_lista_espera|tiquetera_recordar_pago|reserva|cron\.(un)?schedule|cron\.alter_job/.test(m));
  ok('no borra nada ni cancela avisos ya encolados',
     !/\bdelete\b|\bdrop\b|\btruncate\b|update\s+wa_avisos/i.test(m));
}

console.log(`\n${fallos ? '✗ ' + fallos + ' con problemas' : '✓ todo bien'}`);
process.exit(fallos ? 1 : 0);
