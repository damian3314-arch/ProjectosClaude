/**
 * El recordatorio del mismo día de la clase (0137).
 *
 * Nace de medir quién reserva y no llega (2 oct): en las últimas 4 semanas,
 * 10,9 % de las reservas sueltas no llegaron (más del 10 % fijado como umbral).
 *
 * Protege lo que no se puede romper sin quemar el número de WhatsApp:
 *   1. nace APAGADO y solo lo prende alguien, cuando Meta apruebe la plantilla;
 *   2. un aviso por persona y clase (clave única), nunca por reserva;
 *   3. no le escribe a quien pidió SALIR ni a los dueños, ni a quien acaba de
 *      recibir su confirmación, ni antes de las 6:30 am;
 *   4. la plantilla es de servicio (UTILITY), sin «código» junto a una variable;
 *   5. no llama a ninguna ruta que envíe: solo encola.
 *
 *   node pruebas/recordatorio-clase.test.mjs
 */
import { readFileSync } from 'node:fs';

let fallos = 0;
const ok = (n, c, extra = '') => { if (!c) fallos++;
  console.log(`${c ? '✓' : 'FALLO'} ${n}${extra ? '  → ' + extra : ''}`); };
const titulo = t => console.log(`\n-- ${t} ${'-'.repeat(Math.max(0, 54 - t.length))}`);
const leer = r => readFileSync(new URL(r, import.meta.url), 'utf8');

const M = leer('../supabase/migrations/0137_recordatorio_el_mismo_dia_de_la_clase.sql');
const CODIGO = M.replace(/--.*$/gm, '');
const WORKER = leer('../../tumbao-caja/src/index.js');

titulo('1. Nace apagado');
ok('el interruptor nace «apagado»', /'wa_recordatorio_clase', 'apagado'/.test(M));
ok('apagado no hace nada', /<> 'encendido' then\s+return jsonb_build_object\('ok', true, 'activo', false\)/.test(CODIGO));

titulo('2. Un aviso por persona y clase');
ok('la clave es clase + celular', /'recordatorio:' \|\| b\.clase_id \|\| ':' \|\| b\.tel/.test(CODIGO));
ok('si la clave existe, no repite', /on conflict \(clave\) do nothing/.test(CODIGO));
ok('un solo aviso por celular aunque reserve varios cupos', /select distinct on \(v\.tel\)/.test(CODIGO));

titulo('3. A quién NO');
ok('no a quien pidió SALIR', /wa_bajas/.test(CODIGO));
ok('no a los dueños', /not wa_es_dueno\(b\.tel\)/.test(CODIGO));
ok('no a quien confirmó hace menos de 2 horas', /confirmada_at < now\(\) - interval '2 hours'/.test(CODIGO));
ok('solo reservas confirmadas', /r\.estado = 'confirmada'/.test(CODIGO));
ok('nunca antes de las 6:30 am de Bogotá', /6 hours 30 minutes/.test(CODIGO) && /greatest\(/.test(CODIGO));
ok('3 horas antes de la clase', /interval '3 hours'/.test(CODIGO));
ok('el aviso vence antes de que empiece la clase', /fecha_hora - interval '20 minutes'/.test(CODIGO));
ok('solo celulares de Colombia', /\^3\[0-9\]\{9\}\$/.test(CODIGO));

titulo('4. La plantilla');
{
  const i = WORKER.indexOf("name: 'recordatorio_clase'");
  const bloque = WORKER.slice(i, i + 900);
  ok('existe en el Worker', i > 0);
  ok('es de servicio (UTILITY)', /category: 'UTILITY'/.test(bloque));
  ok('no usa la palabra «código» (Meta la confunde con autenticación)', !/c[óo]digo/i.test(bloque));
  ok('pide avisar si no puede venir, para liberar el cupo', /liberar tu cupo/.test(bloque));
  ok('lleva tres variables: nombre, hora y clase', /\{\{1\}\}/.test(bloque) && /\{\{2\}\}/.test(bloque) && /\{\{3\}\}/.test(bloque));
  ok('sin promoción ni enlaces', !/BUTTONS|MARKETING/.test(bloque));
}

titulo('5. Solo encola');
ok('no llama a ninguna ruta que envíe', !/net\.http_post|despachar|wa_notas|nota_asistente/.test(CODIGO));
ok('corre cada hora, en el minuto 5', /'5 \* \* \* \*'/.test(CODIGO));

titulo('6. Nada de personas en el repositorio (es público)');
ok('sin celulares', (M.match(/\b3\d{9}\b/g) || []).length === 0);

console.log(fallos ? `\n${fallos} fallo(s)` : '\ntodo en verde');
process.exit(fallos ? 1 : 0);
