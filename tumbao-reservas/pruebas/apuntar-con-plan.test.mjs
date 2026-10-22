/**
 * Apuntar «con plan» a mano a quien AdminGym todavía no muestra (0168).
 *
 * Damián (10 oct): la mensualidad de Daniela Jaimes no sale en AdminGym y recepción necesita apuntarla a mano. «Tiene plan»
 * rebotaba con «ese celular no está en la lista de afiliados». Ahora recepción puede confirmar «apúntala con plan igual».
 * Lo que NO se negocia, y esta prueba protege:
 *   1. solo recepción (token de administrador) puede hacerlo: el aviso a tomar_cupo es un ajuste local a la transacción que
 *      solo pone admin_crear_reserva; nada de lo público lo conoce;
 *   2. solo con tipo «miembro»: una clase suelta nunca se salta el cobro con esto;
 *   3. no se apunta sola: la página pide confirmar y la reserva queda marcada «Plan a mano» para revisarla;
 *   4. sin la confirmación, todo sigue rechazando igual que antes.
 *
 *   node apuntar-con-plan.test.mjs
 * La prueba con un navegador de verdad (que el aviso aparece y que confirmar manda lo correcto) está en prueba-apuntar.mjs.
 */
import { readFileSync } from 'node:fs';
let fallos = 0;
const ok = (n, c, extra = '') => { if (!c) fallos++; console.log(`${c ? '✓' : '✗'} ${n}${extra ? '  → ' + extra : ''}`); };
const leer = (r) => readFileSync(new URL(r, import.meta.url), 'utf8');
const raw = leer('../supabase/migrations/0168_apuntar_con_plan_a_mano.sql');
const m = raw.replace(/--.*$/gm, '');
const w = leer('../../tumbao-caja/src/index.js');
const admin = leer('../../docs/admin.html');

console.log('\n-- La migración 0168 ------------------------------------');
ok('parchea las dos funciones sobre su definición viva y se detiene si falta una ancla (sin tocar nada)',
   /pg_get_functiondef\(v_firma_tomar\)/.test(m) && /pg_get_functiondef\(v_firma_admin\)/.test(m) && (m.match(/raise exception '0168: falta el ancla/g) || []).length === 8);
ok('es idempotente: si ya está parchada no hace nada', /position\('tumbao\.plan_manual' in d\) = 0/.test(m) && /position\('plan_manual' in d\) = 0/.test(m));
ok('tomar_cupo: sin mensualidad Y con el aviso local, deja pasar; sin el aviso rechaza igual que antes',
   /if not found and coalesce\(current_setting\('tumbao\.plan_manual', true\), ''\) = '1' then\s+v_manual := true;\s+elsif not found then\s+return jsonb_build_object\('ok', false, 'error', 'MEMBRESIA_NO_ENCONTRADA'/.test(m));
ok('tomar_cupo: sin saber la hora de su plan no aplica «ya te cubre» ni el cambio de horario', /if not v_es_sabado and not v_manual then/.test(m));
ok('tomar_cupo conserva firma y permisos (solo CREATE OR REPLACE; no crea otra función ni toca grants)', !/create (or replace )?function/i.test(m.replace(/\$a\$[\s\S]*?\$a\$/g, '')) && !/\bgrant\b|\brevoke\b/i.test(m));
ok('el aviso es LOCAL a la transacción (set_config … true) y se limpia apenas vuelve tomar_cupo',
   /set_config\('tumbao\.plan_manual', '1', true\)/.test(m) && /set_config\('tumbao\.plan_manual', '', true\)/.test(m));
ok('admin_crear_reserva: «plan_manual» solo con tipo miembro; con suelta devuelve MEDIO_INVALIDO',
   /if v_medio = 'plan_manual' then\s+if p_tipo <> 'miembro' then\s+return jsonb_build_object\('ok', false, 'error', 'MEDIO_INVALIDO'/.test(m));
ok('queda marcada para revisarla («Plan a mano (no estaba en AdminGym)» + la nota)', /Plan a mano \(no estaba en AdminGym\)/.test(m) && /pagador_nombre = left\(/.test(m));
ok('lo dice en la respuesta (plan_manual) y no registra caja: el efectivo y «al llegar» siguen siendo solo de clase suelta', /'plan_manual', coalesce\(v_medio = 'plan_manual', false\)/.test(m));
ok('el ajuste solo lo pone admin_crear_reserva (la 0168 no lo pone en ningún otro lado)',
   (m.match(/set_config\('tumbao\.plan_manual', '1'/g) || []).length === 1);
ok('sin DROP ni DELETE', !/\bdrop\b/i.test(raw) && !/\bdelete\b/i.test(raw));

console.log('\n-- Lo público no puede activarlo ------------------------');
const publico = ['../../docs/index.html', '../../docs/mensualidad.html'].map(leer).join('\n');
ok('las páginas públicas no mencionan «plan_manual»', !/plan_manual/.test(publico));
const rutaPublica = w.split("ruta === '/tumbao/reservar'")[1].split("ruta === '/tumbao/")[0];
ok('la ruta pública /tumbao/reservar no pasa ningún medio ni «plan_manual»', !/plan_manual|p_medio/.test(rutaPublica));
ok('el Worker solo lo deja pasar con tipo «miembro» (y Postgres lo vuelve a exigir)',
   /String\(b\.medio \|\| ''\)\.toLowerCase\(\) === 'plan_manual' && b\.tipo === 'miembro'\) \? 'plan_manual' : null/.test(w));
ok('esa es la ruta del administrador (/api/reserva → admin_crear_reserva con token)',
   /ruta === '\/api\/reserva'[\s\S]{0,1800}rpc\(env, 'admin_crear_reserva', \{\s+p_token: token/.test(w));

console.log('\n-- La página de recepción -------------------------------');
ok('el aviso nace oculto y dentro de la ventana de apuntar', /id="ap-plan-manual" hidden/.test(admin) && admin.indexOf('id="ap-plan-manual"') > admin.indexOf('id="modal-apuntar"') && admin.indexOf('id="ap-plan-manual"') < admin.indexOf('id="ap-cancelar"'));
ok('dice que no está en AdminGym, que queda sin cobro y marcada «plan a mano»', /Ese celular no está en la lista de AdminGym/.test(admin) && /sin cobro/.test(admin) && /plan a mano/.test(admin));
ok('apuntar() recibe forzarPlan y el botón de guardar NO le pasa el evento (sería «verdadero»)', /async function apuntar\(forzarPlan = false\)/.test(admin) && /\$\('#ap-guardar'\)\.addEventListener\('click', \(\) => apuntar\(\)\)/.test(admin));
ok('solo ofrece apuntar igual cuando es «Tiene plan», AdminGym no la trae y todavía no lo había confirmado',
   /e\.clave === 'MEMBRESIA_NO_ENCONTRADA' && apTipo === 'miembro' && !forzarPlan/.test(admin));
ok('solo el botón de confirmar manda «plan_manual»', /\$\('#ap-plan-igual'\)\.addEventListener\('click', \(\) => apuntar\(true\)\)/.test(admin) && /medio: apTipo === 'miembro' \? \(forzarPlan \? 'plan_manual' : null\) : apMedio/.test(admin));
ok('cambiar de tipo, nombre o celular esconde el aviso', (admin.match(/\$\('#ap-plan-manual'\)\.hidden = true/g) || []).length >= 4);
ok('al apuntar, recepción lee que quedó «plan puesto a mano»', /Quedó con plan puesto a mano/.test(admin));
ok('los otros usos del error siguen igual (el texto traducido de MEMBRESIA_NO_ENCONTRADA no se tocó)', /MEMBRESIA_NO_ENCONTRADA: \['No aparece con plan'/.test(admin));

console.log(fallos ? `\n${fallos} fallo(s)` : '\nTodo bien');
process.exit(fallos ? 1 : 0);
