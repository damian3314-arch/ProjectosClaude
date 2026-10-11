/**
 * Cupos de mensualidad (0164): tope de 23, gracia de 5 días completa y cupos a la vista.
 *
 * Damián (9 oct): «máximo 23 cupos; si se le vence a alguien, se le espera 5 días y se cuenta ese cupo; que la página
 * muestre los cupos disponibles en todos los horarios y ya es tiempo de vender». Esta prueba protege que:
 *   1. el tope de 23 se respete en 6 pm y 7 pm (y 7 am conserve el suyo);
 *   2. la gracia sea de 5 días de verdad: el reporte de AdminGym saca a la gente a los 3 días y el import la conserva;
 *   3. quien renovó no se conserve, y lo importado siga siendo un espejo del reporte;
 *   4. la página muestre el número exacto de cupos por horario desde la primera pantalla.
 *
 *   node cupos-gracia.test.mjs
 */
import { readFileSync } from 'node:fs';
let fallos = 0;
const ok = (n, c, extra = '') => { if (!c) fallos++; console.log(`${c ? '✓' : '✗'} ${n}${extra ? '  → ' + extra : ''}`); };
const titulo = t => console.log(`\n-- ${t} ${'-'.repeat(Math.max(0, 54 - t.length))}`);
const m = readFileSync(new URL('../supabase/migrations/0164_gracia_de_5_dias_completa_y_tope_23.sql', import.meta.url), 'utf8').replace(/--.*$/gm, '');
const men = readFileSync(new URL('../../docs/mensualidad.html', import.meta.url), 'utf8');

titulo('1. Tope de 23');
{
  const topes = /set valor = '([^']+)'[^;]*where clave = 'mensualidad_topes'/.exec(m);
  ok('la página vende hasta 23 en 6 pm y 7 pm', topes && /18:00=23/.test(topes[1]) && /19:00=23/.test(topes[1]), topes && topes[1]);
  ok('7 am conserva su tope público de 35', topes && /07:00=35/.test(topes[1]));
  ok('el tope máximo real sigue siendo 23 (premium_topes no se toca)', !/premium_topes/.test(m));
}

titulo('2. La gracia de 5 días se cumple completa');
{
  ok('lee los días de gracia del ajuste (no un 3 ni un 5 fijo)', /mensualidad_gracia_dias/.test(m) && !/fin \+ 3\b/.test(m) && !/fin \+ 5\b/.test(m));
  ok('antes de reemplazar la tabla guarda a quien venció hace v_gracia días o menos', /m\.fin < v_hoy and m\.fin \+ v_gracia >= v_hoy/.test(m));
  ok('lo vuelve a poner si el reporte nuevo ya no lo trae', /from jsonb_array_elements\(v_vencidas\) r\s+where not exists/.test(m));
  ok('no conserva a quien renovó (el reporte trae una membresía suya que termina después)', /n\.fin > \(r->>'fin'\)::date/.test(m));
  ok('la persona se reconoce por celular, documento o nombre', /create or replace function public\.membresia_persona/.test(m) && /right\(regexp_replace/.test(m));
  ok('conserva el contrato: archivo vacío no toca nada y recalcula cupos', /archivo_vacio/.test(m) && /recalcular_cupos\(\)/.test(m));
  ok('sigue siendo solo del Worker (service_role)', /grant\s+execute on function public\.importar_membresias\(jsonb\)\s+to service_role/.test(m));
}

titulo('3. La página muestra los cupos');
{
  ok('la tarjeta de entrada dice «Hay cupo a las 7:00 am (9 cupos)…» con el número exacto de cada horario',
     /conCupos = \(h\) => `\$\{h\.etiqueta\} \(\$\{Number\(h\.libres\) === 1 \? '1 cupo'/.test(men) && /Hay cupo a las <b>/.test(men));
  ok('los horarios sin cupo siguen invitando a la lista de espera (gratis)', /apúntate a la lista de espera, es gratis/.test(men));
  ok('la pastilla de cada horario sigue mostrando «N cupos» y se pone dorada con 3 o menos', /n <= 3 \? 'pocos'/.test(men));
}

console.log(fallos ? `\n${fallos} fallo(s)` : '\nTodo bien');
process.exit(fallos ? 1 : 0);
