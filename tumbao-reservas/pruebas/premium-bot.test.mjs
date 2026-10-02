/**
 * La mensualidad en el asistente interno (el WhatsApp nuevo).
 *
 * Damián (30 sep): la mensualidad de $125.000 es inviable; queda para quien
 * cumpla unos requisitos, con 20 a 25 personas por horario (7 am, 6 pm y
 * 7 pm). «Yo no soy aprobador: la aprobación es que la persona cumpla los
 * requisitos». Y: nombres repetidos o incompletos no sirven para vender; hace
 * falta celular o cédula.
 *
 * Esta prueba protege tres cosas:
 *   1. que el asistente conteste «aplica / no aplica» y no espere una
 *      aprobación de nadie (ni la pida);
 *   2. que identifique bien a la persona antes de contestar;
 *   3. que solo lea (nada de escribir en la base) y que ningún dato de
 *      personas viaje al repositorio, que es público.
 *
 *   node pruebas/premium-bot.test.mjs
 */
import { readFileSync } from 'node:fs';
import { INSTRUCCIONES_PREMIUM } from '../../tumbao-caja/src/premium.js';
import * as modulo from '../../tumbao-caja/src/premium.js';

let fallos = 0;
const ok = (n, c, extra = '') => { if (!c) fallos++;
  console.log(`${c ? '✓' : 'FALLO'} ${n}${extra ? '  → ' + extra : ''}`); };
const titulo = t => console.log(`\n-- ${t} ${'-'.repeat(Math.max(0, 54 - t.length))}`);
const leer = ruta => readFileSync(new URL(ruta, import.meta.url), 'utf8');

const INDEX = leer('../../tumbao-caja/src/index.js');
const PREMIUM = leer('../../tumbao-caja/src/premium.js');
const M129 = leer('../supabase/migrations/0129_premium_cumplir_es_aprobar.sql');
const M132 = leer('../supabase/migrations/0132_aviso_de_pago_dice_si_aplica.sql');
const M128 = leer('../supabase/migrations/0128_premium_por_horario.sql');
const M133 = leer('../supabase/migrations/0133_mensualidad_cerrada_deja_pagar_a_quien_aplica.sql');
const M134 = leer('../supabase/migrations/0134_premium_3_meses_y_tope_23_en_6_y_7_pm.sql');
const M135 = leer('../supabase/migrations/0135_gracia_de_3_dias_y_tarea_de_cupo_liberado.sql');
const M136 = leer('../supabase/migrations/0136_cupos_para_los_mas_fieles.sql');
const M127 = leer('../supabase/migrations/0127_grupo_premium.sql');
const ESTE = readFileSync(new URL(import.meta.url), 'utf8');
const t = INSTRUCCIONES_PREMIUM;

titulo('1. Cumplir los requisitos ES la aprobación');
{
  ok('dice que cumplir los requisitos es la aprobación', /CUMPLIR LOS REQUISITOS ES LA APROBACIÓN/.test(t));
  ok('dice que no hay que pedirle permiso a nadie', /No hay que pedirle permiso a Damián ni a nadie/.test(t));
  ok('y que él no aprueba ni descarta a nadie', /tú no apruebas ni descartas a nadie/.test(t));
  ok('no le manda decir «lo aprueba Damián»', !/lo aprueba Damián|falta que Damián|solo Damián aprueba|Damián decide/i.test(t));
  ok('si aplica, recepción la recibe y la registra en el horario que escoja',
     /recepción puede recibirla y registrarla en AdminGym/.test(t) && /horario que escoja/.test(t));
  ok('si no aplica, no se le vende mensualidad', /no se le vende mensualidad/i.test(t));
  ok('conoce los veredictos nuevos', ['aplica', 'no_aplica', 'sin_historial'].every(v => t.includes(v)));
  ok('ya no existen los veredictos de aprobación', !/cabe_por_cupo|ya_es_premium|descartada|candidatas/.test(t));
}

titulo('2. Conoce el negocio');
{
  ok('tope de 23 en 6 pm y 7 pm, y 7 am abierto',
     /máximo 23 personas cada uno/.test(t) && /6:00 pm y 7:00 pm/.test(t) && /7:00 am entran todos los que lleguen/.test(t));
  ok('la fecha es el 30 de diciembre de 2026', /30 de diciembre de 2026/.test(t));
  ok('los dos requisitos (plan 4 meses seguidos, o 90 días en clase suelta)',
     /3 meses seguidos/.test(t) && !/4 meses seguidos/.test(t) && /más de 90 días/.test(t) && /8 visitas/.test(t));
  ok('quien no cumple sigue con suelta o tiquetera', /clase suelta o tiquetera/.test(t));
  ok('le enseña todas las funciones de lectura',
     ['premium_evaluar', 'premium_vigentes', 'premium_estado', 'renovaciones_proximas', 'mensualidad_cupos'].every(f => t.includes(f)));
  ok('no menciona pases de regalo (es interno)', !/regalo|constancia|pase gratis/i.test(t));
}

titulo('3. Identificar bien a la persona');
{
  ok('lo primero es identificar bien', /IDENTIFICAR BIEN A LA PERSONA es lo primero/.test(t));
  ok('dice que hay nombres repetidos e incompletos', /nombres repetidos y nombres incompletos/.test(t));
  ok('prefiere celular o cédula', /celular o la cédula/.test(t) && /lo más seguro/.test(t));
  ok('con varias coincidencias no adivina y pide el dato completo',
     /NO adivines ni respondas "aplica"/.test(t) && /últimos 4 del celular/.test(t) && /celular o la cédula completa/.test(t));
  ok('si es una sola por nombre, pide confirmar que es ella', /confirmar_identidad = true/.test(t) && /confirmar que es ella/.test(t));
  ok('si no aparece, pide el otro dato', /pruebe con el otro dato/.test(t));
  ok('la función acepta nombre, celular o cédula', /nombre, celular o cédula/.test(t));
}

titulo('4. Solo lee: nada de escribir');
{
  ok('dice que solo consulta y que recepción registra', /Tú solo consultas/.test(t) && /Eso lo hace recepción/.test(t));
  ok('cualquier cambio se pide en Claude Code', /pídelo|lo pidan en Claude Code/.test(t) || /lo pidan en Claude Code/.test(t));
  ok('el módulo ya no exporta herramientas de escritura',
     !('HERRAMIENTA_PREMIUM' in modulo) && !('premiumDecidir' in modulo) && Object.keys(modulo).join() === 'INSTRUCCIONES_PREMIUM');
  ok('el Worker no expone premium_decidir', !/premium_decidir|premiumDecidir|HERRAMIENTA_PREMIUM/.test(INDEX));
  ok('el Worker sigue con sus dos herramientas de lectura',
     /name: 'consultar'/.test(INDEX) && /name: 'ver_tablas'/.test(INDEX));
  ok('no le pasa «quién escribe» a las herramientas', !/ejecutarHerramienta\(env, c\.name, c\.arguments, quien\)/.test(INDEX));
  ok('las instrucciones van dentro de las del agente', /\$\{INSTRUCCIONES_PREMIUM\}/.test(INDEX) && /from '\.\/premium\.js'/.test(INDEX));
  ok('la regla de «no puedes cambiar nada» quedó sin excepciones',
     /No puedes cambiar nada ni escribirle a clientes\. Si te piden hacerlo, di que eso todavía no está habilitado y que lo pidan en Claude Code\.\n/.test(INDEX));
}

titulo('5. La base (migración 0129)');
{
  ok('identifica por celular, cédula y nombre', /'celular'::text por/.test(M129) && /'documento'::text por/.test(M129) && /'nombre'::text por/.test(M129));
  ok('avisa cuándo hay que confirmar la identidad', /'confirmar_identidad'/.test(M129));
  ok('el veredicto es aplica / no_aplica / sin_historial', /'aplica'/.test(M129) && /'no_aplica'/.test(M129) && /'sin_historial'/.test(M129));
  ok('no hay veredictos de aprobación', !/cabe_por_cupo|ya_es_premium|'descartada'/.test(M129));
  ok('los cupos salen de los planes vigentes hoy', /ocupados_hoy/.test(M129) && /from membresias m where m\.fin >= c\.hoy/.test(M129));
  ok('lista quiénes tienen plan y si cumplirían al renovar', /premium_vigentes/.test(M129) && /'cumple'/.test(M129));
  ok('todas son de solo lectura (STABLE)',
     ['premium_identificar', 'premium_evaluar', 'premium_vigentes', 'premium_estado', 'premium_cupos_horario']
       .every(f => new RegExp(`function public\\.${f}\\([\\s\\S]*?\\n(language sql|language plpgsql)\\n\\s*stable`).test(M129)));
  ok('nada se abre a público ni a anon', /revoke all on function[\s\S]*from public, anon, authenticated/.test(M129));
  ok('la cédula se carga aparte, no en el repositorio', /add column if not exists documento/.test(M129) && !/update afiliados_historial/i.test(M129));
}

titulo('5b. El aviso de pagos dice si quien pagó aplica (0132)');
{
  ok('dice «Aplica» con su razón y que se puede registrar', /✅ Aplica a mensualidad/.test(M132) && /Se puede registrar/.test(M132));
  ok('dice «NO aplica» y que no se registre', /⛔ NO aplica a mensualidad/.test(M132) && /No la registres/.test(M132));
  ok('si no la encuentra o hay varias, pide celular o cédula', /No la encuentro en el historial/.test(M132) && /personas con ese nombre/.test(M132));
  ok('solo pagos del tamaño de una mensualidad (60.000 o más)', /p_valor < 60000/.test(M132));
  ok('avisa cuando la identificó solo por el nombre del banco', (M132.match(/nombre del banco/g) || []).length >= 2);
  ok('lo pega en los pagos sin dueño y en las mensualidades pagadas por la página',
     /premium_frase\(r\.remitente, r\.saldo\)/.test(M132) && /premium_frase\(r\.celular, 125000\)/.test(M132));
  ok('el cierre del bloque ya no manda registrar cualquier mensualidad', /Si dice «aplica», regístrala/.test(M132));
}

titulo('5c. Horario cerrado: quien cumple puede pagar (0133)');
{
  ok('se identifica por celular o cédula, nunca solo por nombre',
     /'celular', 'documento'/.test(M133) && !/'nombre'\)/.test(M133));
  ok('exige una sola coincidencia y veredicto «aplica»', /'encontradas'\)::int = 1/.test(M133) && /'veredicto' = 'aplica'/.test(M133));
  ok('respeta el tope del premium y la vigencia', /premium_cupos_horario/.test(M133) || /premium_cupo_max/.test(M133)); ok('la vigencia también', /premium_vigente_hasta/.test(M133));
  ok('solo lectura (STABLE) y cerrada a público', /stable\s+security definer/.test(M133.replace(/\n/g, ' ')) && /revoke all on function public\.premium_puede_pagar/.test(M133));
  ok('promueve al apuntarse y al volver a apuntarse',
     (M133.match(/premium_puede_pagar\(p_celular, p_documento, v_hora\)/g) || []).length === 2);
  ok('la respuesta dice «por_requisitos»', (M133.match(/por_requisitos/g) || []).length >= 3);
  ok('no cambia el cupo público (no toca mensualidad_topes)', !/mensualidad_topes/.test(M133.replace(/--.*$/gm, '')));
}

titulo('5d. 3 meses y tope de 23 en 6 pm y 7 pm (0134)');
{
  ok('baja el mínimo de meses a 3', /set valor = '3' where clave = 'premium_min_meses'/.test(M134));
  ok('tope 23 en 6 pm y 7 pm, 7 am sin tope práctico', /07:00=99,18:00=23,19:00=23/.test(M134));
  ok('el tope sale de cada horario en premium_cupos_horario y en premium_puede_pagar',
     /premium_topes/.test(M134) && /premium_cupos_horario\(\) -> to_char\(p_hora/.test(M134));
  ok('no toca el cupo público (mensualidad_topes)', !/mensualidad_topes/.test(M134.replace(/--.*$/gm, '')));
}

titulo('5e. Gracia de 3 días (0135)');
{
  ok('la gracia es de 3 días y está en ajustes', /'mensualidad_gracia_dias', '3'/.test(M135));
  ok('el cupo se cuenta hasta fin + gracia, por persona (no por fila)',
     /m\.fin \+ v_gracia/.test(M135) && /count\(distinct coalesce\(nullif\(right\(regexp_replace/.test(M135));
  ok('corre 8:20 am Bogotá, lunes a sábado', /'20 13 \* \* 1-6'/.test(M135));
}

titulo('5f. Los cupos son para los más fieles y recepción recibe UNA instrucción (0136)');
{
  const sinComentarios = M136.replace(/--.*$/gm, '');
  ok('la fila se ordena por fidelidad: cumple, meses seguidos, meses totales, visitas, llegada',
     /order by g\.ap desc, g\.r desc, g\.m desc, g\.v desc, g\.creado_at/.test(M136));
  ok('quien no cumple no recibe cupo de la fila (va a tiquetera)', /x\.aplica and x\.orden <= v_libres/.test(M136) && /not \(x\.aplica and x\.orden <= v_libres\)/.test(M136));
  ok('nadie se cuela: quien se apunta solo paga si le toca por fidelidad', /mensualidad_fila\(p_hora\)/.test(M136) && /coalesce\(v_rank, 1\) <= v_libres/.test(M136));
  ok('a los primeros les dice que ya hay cupo y paguen su mensualidad', /Avísales que ya hay cupo y que paguen su mensualidad/.test(M136));
  ok('la tiquetera es para quienes siguen en cola', /Ofréceles tiquetera/.test(M136));
  ok('no lista a quienes no renovaron', !/no renovaron/i.test(sinComentarios));
  ok('todos los horarios van en UNA sola nota', /mensualidad_cupo_liberado_mensaje\(\)/.test(M136) && (sinComentarios.match(/nota_recepcion\(/g) || []).length === 1);
  ok('no repite la misma instrucción (como mucho una vez por semana)', /md5\(v_texto\)/.test(M136) && /IYYY-IW/.test(M136));
  ok('solo manda si hay algo que hacer', /if v_texto is null then return 0/.test(M136));
  ok('no escribe a ningún cliente', !/net\.http_post|wa_avisos/.test(sinComentarios));
}

titulo('6. Ningún dato de personas en el repositorio (es público)');
{
  for (const [nombre, texto] of [['0127', M127], ['0128', M128], ['0129', M129], ['0132', M132], ['0133', M133], ['0134', M134], ['0135', M135], ['0136', M136], ['premium.js', PREMIUM], ['esta prueba', ESTE]]) {
    const celulares = (texto.match(/\b3\d{9}\b/g) || []).filter(n => n !== '3000000000');
    ok(`${nombre} no trae celulares`, celulares.length === 0, celulares.slice(0, 3).join(','));
  }
  for (const [nombre, texto] of [['0128', M128], ['0129', M129]]) {
    ok(`${nombre} no trae filas de personas escritas a mano`, !/values\s*\(\s*'[^']*\d{7,}/i.test(texto));
  }
}

console.log(fallos ? `\n${fallos} fallo(s)` : '\ntodo en verde');
process.exit(fallos ? 1 : 0);
