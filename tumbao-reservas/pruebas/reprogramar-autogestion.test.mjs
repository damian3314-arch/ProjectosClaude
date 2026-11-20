/** Reprogramar la clase suelta pagada desde la página, con el código de la reserva (19 nov, pedido de Damián).
 *  node reprogramar-autogestion.test.mjs */
import { readFileSync } from 'node:fs';
const leer = (r) => readFileSync(new URL(r, import.meta.url), 'utf8');
const mig = leer('../supabase/migrations/0211_reprogramar_por_la_persona.sql');
const sql = mig.replace(/--.*$/gm, '');
const w = leer('../../tumbao-caja/src/index.js');
const pag = leer('../../docs/reprogramar.html');
const idx = leer('../../docs/index.html');
let fallos = 0;
const ok = (n, c) => { if (!c) fallos++; console.log(`${c ? '✓' : '✗'} ${n}`); };
const titulo = t => console.log(`\n-- ${t} ${'-'.repeat(Math.max(0, 54 - t.length))}`);

titulo('1. Quién puede reprogramar');
ok('hace falta el código Y los últimos 4 números del celular, y no dice cuál de los dos falló',
   /right\(regexp_replace\(coalesce\(r\.telefono, ''\), '\\D', '', 'g'\), 4\) <> v_c4/.test(sql) && /NO_ENCONTRADA/.test(sql));
ok('solo clase suelta confirmada y pagada (pago, cobro, comprobante o pago del grupo)',
   /r\.estado <> 'confirmada' then 'NO_CONFIRMADA'/.test(sql) && /r\.tipo = 'tiquetera' then 'ES_TIQUETERA'/.test(sql) && /r\.tipo <> 'suelta' then 'ES_MIEMBRO'/.test(sql)
   && /not v_pago then 'SIN_PAGO'/.test(sql) && /r\.cobro_mov_id is not null or r\.referencia_pago is not null/.test(sql));
ok('las clases con la promo 2 por $24.000 NO se reprograman y el mensaje lo dice',
   /valor_reserva\(r\.id\) < coalesce\(c\.precio_cop, 0\) then 'ES_PROMO'/.test(sql) && /when 'ES_PROMO' then 'Las clases de la promoción[^']*no se pueden reprogramar/.test(sql));
ok('el plazo son 3 días desde el día de la clase', /v_vence := v_dia \+ 3/.test(sql) && /v_hoy > v_vence then 'VENCIDA'/.test(sql));
ok('si ya entró a la clase no se mueve, y solo se mueve una vez',
   /exists \(select 1 from asistencias a where a\.reserva_id = r\.id\) then 'YA_ASISTIO'/.test(sql)
   && /r\.reprogramada_a is not null then 'YA_REPROGRAMADA'/.test(sql) && /r\.origen = 'reprogramada' or r\.viene_de is not null then 'YA_ES_REPROGRAMACION'/.test(sql));

titulo('2. Cómo se mueve');
ok('la clase nueva sale de tomar_cupo (no sobrevende) y nace confirmada, sin pago propio, con viene_de',
   /tomar_cupo\(p_clase_id, v_res\.nombre, v_res\.telefono, v_res\.email, 'reprogramada', 'suelta'\)/.test(sql) && /viene_de = v_res\.id/.test(sql));
ok('si la clase vieja no había pasado, su cupo se libera; si ya pasó queda como crédito (no vino)',
   /cupo_tomado = greatest\(cupo_tomado - 1, 0\) where id = v_res\.clase_id/.test(sql) && /no_vino_at = coalesce\(no_vino_at, now\(\)\)/.test(sql));
ok('bloquea la reserva vieja: dos toques seguidos no la mueven dos veces', /for update;[\s\S]*?v_res\.reprogramada_a is not null/.test(sql));
ok('queda en la auditoría como «Cliente (página)»', /'Cliente \(página\)', 'reprogramar_autogestion'/.test(sql));
ok('solo clases futuras con cupo en los próximos 15 días', /c\.fecha_hora > now\(\) \+ interval '30 minutes'/.test(sql) && /interval '15 days'/.test(sql));
ok('solo el Worker puede llamarlas (service_role)', /to service_role/.test(sql) && /revoke all on function public\.reprogramar_propia/.test(sql));
ok('no borra nada: sin DROP ni DELETE', !/\bdrop\s+(table|function|index|column)|\bdelete\s+from/i.test(sql));

titulo('3. Worker y página');
ok('el Worker tiene la consulta y la acción, limpia los datos y refresca cupos antes de listar',
   /'\/tumbao\/reprogramar\/consulta'/.test(w) && /reprogramar_consulta/.test(w) && /reprogramar_propia/.test(w) && /celular4/.test(w));
ok('la página pide código y 4 números, lista las clases por día y confirma',
   /id="codigo"/.test(pag) && /id="c4"/.test(pag) && /\/reprogramar\/consulta/.test(pag) && /pedir\('\/reprogramar'/.test(pag) && /Tu código nuevo/.test(pag));
ok('dice el plazo de 3 días y que no pierde el pago', /tienes 3 días desde el día de tu clase/.test(pag) && /No pierdes tu pago/.test(pag));
ok('si no se puede, explica por qué y lleva a WhatsApp', /id="wa3"/.test(pag) && /d\.mensaje/.test(pag));
ok('la página de reservas enlaza a reprogramar (arriba y en la pantalla final)', (idx.match(/href="reprogramar\.html"/g) || []).length >= 2);

titulo('3b. Tiquetera: se mueve antes de la clase, no después (0212)');
{
  const m12 = leer('../supabase/migrations/0212_reprogramar_tiquetera_antes_de_la_clase.sql').replace(/--.*$/gm, '');
  ok('una clase de tiquetera que todavía no empieza se puede mover; si ya pasó, se perdió',
     /r\.tipo = 'tiquetera' and c\.fecha_hora <= now\(\) then 'ES_TIQUETERA'/.test(m12) && /r\.tipo not in \('suelta', 'tiquetera'\) then 'ES_MIEMBRO'/.test(m12));
  ok('el saldo de la tiquetera queda igual: se devuelve la clase, tomar_cupo la vuelve a descontar, y si falla se restituye',
     /clases_usadas = greatest\(clases_usadas - 1, 0\)/.test(m12) && /'tiquetera', v_tiq\.codigo/.test(m12) && /clases_usadas = clases_usadas \+ 1/.test(m12));
  ok('la clase vieja queda rechazada y enlazada (reprogramada_a) y su cupo se libera; la nueva cae antes de que venza la tiquetera',
     /estado = 'rechazada', estado_antes = 'confirmada', reprogramada_a = v_id/.test(m12) && /tiquetera_vence/.test(m12));
  ok('la página dice «hasta que empiece tu clase» y que no gasta otra clase', /Puedes cambiarla hasta que empiece tu clase/.test(pag) && /No gastas otra clase de tu tiquetera/.test(pag));
}

titulo('4. Reservas limpia');
ok('la página de reservas no tiene franjas ni tarjetas arriba (la franja del día se quitó)', !/id="franja-dia"/.test(idx) && !/var FRANJAS = \[/.test(idx));

console.log(`\n${fallos ? '✗ ' + fallos + ' con problemas' : '✓ todo bien'}`);
process.exit(fallos ? 1 : 0);
