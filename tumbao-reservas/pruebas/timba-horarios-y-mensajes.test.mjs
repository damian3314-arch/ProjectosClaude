/**
 * Timba, 14-15 oct: los horarios reales de clase, no contestar respuestas automáticas de otros negocios y no mandar tres
 * respuestas a quien escribe tres mensajes seguidos.
 *
 *   node timba-horarios-y-mensajes.test.mjs
 */
import { readFileSync } from 'node:fs';
import { esRespuestaAutomatica, INSTRUCCIONES_VENTAS } from '../../tumbao-caja/src/ventas.js';

let fallos = 0;
const ok = (n, c, extra = '') => { if (!c) fallos++; console.log(`${c ? '✓' : '✗'} ${n}${extra ? '  → ' + extra : ''}`); };
const titulo = t => console.log(`\n-- ${t} ${'-'.repeat(Math.max(0, 54 - t.length))}`);

const index = readFileSync(new URL('../../tumbao-caja/src/index.js', import.meta.url), 'utf8');
const m185 = readFileSync(new URL('../supabase/migrations/0185_horarios_reales_y_mensajes_agrupados.sql', import.meta.url), 'utf8').replace(/^\s*--.*$/gm, '');

titulo('1. Horarios reales');
{
  ok('Timba sabe: lunes a viernes 7:00 am, 6:00 pm y 7:00 pm',
     /de lunes a viernes a las 7:00 am, 6:00 pm y 7:00 pm/.test(INSTRUCCIONES_VENTAS));
  ok('Timba sabe: martes y jueves, Rumba básica a las 5:00 pm',
     /Martes y jueves, Rumba básica a las 5:00 pm/.test(INSTRUCCIONES_VENTAS));
  ok('Timba sabe: sábados, Rumba terapia a las 8:00 am y 9:00 am',
     /Sábados, Rumba terapia a las 8:00 am y a las 9:00 am/.test(INSTRUCCIONES_VENTAS));
  ok('no existe clase de 7 am, 6 pm ni 7 pm los sábados, y no inventa lo que no sabe de la Rumba',
     /NO existe clase de 7 am, 6 pm ni 7 pm los sábados/.test(INSTRUCCIONES_VENTAS) && /pasa a recepción \(pasar_a_recepcion=true\) y no lo inventes/.test(INSTRUCCIONES_VENTAS));
  ok('sigue diciendo lo que dijo Damián de la mensualidad (lunes a sábado, sin domingos ni festivos)',
     /lunes a sábado, sin domingos ni festivos/.test(INSTRUCCIONES_VENTAS));
  ok('el asistente general también recibe los horarios (ajustes.asistente_info, una sola vez)',
     /valor \|\| ' Horarios de clase: de lunes a viernes a las 7:00 am, 6:00 pm y 7:00 pm\./.test(m185) &&
     /Sábados, Rumba terapia a las 8:00 am y a las 9:00 am/.test(m185) && /valor not like '%Rumba terapia%'/.test(m185));
  ok('la migración no lleva punto y coma dentro de un texto (la herramienta de Supabase se cuelga)',
     !/'[^']*;[^']*'/.test(m185.replace(/\$\$[\s\S]*?\$\$/g, '')));
}

titulo('2. Respuestas automáticas de otros negocios');
{
  const reales = [
    '¡Hola! Gracias por comunicarte con Jessica Andrades Odontología Integral y Estética.🦷✨\nCuéntanos, ¿cómo podemos ayudarte? 😊 Déjanos tu mensaje y con gusto te enviaremos toda la información.',
    '🦷 ¡Hola, hola! 😊\n¡Bienvenid@ a mi consultorio!\nSoy la Dra. Paola Yazo, odontóloga 👩🏼‍⚕️\n¿En qué puedo ayudarte hoy?',
    'Este número no revisa mensajes. Escríbenos al otro.',
    'Hola, este es un mensaje automático: estamos en consulta.',
  ];
  reales.forEach((t, i) => ok(`automático ${i + 1}: no se contesta`, esRespuestaAutomatica(t)));
  const humanos = ['Cuéntame más', 'Si ya casi vuelvo', 'No me ha pagado 🫠', 'Puedo ir cancelar 20🙏', 'Es que podría solos los sábado a las 8 am',
    'Los martes tienes clases en la mañana', '????', 'Gracias', 'Hola buenas, quiero información de la mensualidad de las 6 pm', ''];
  humanos.forEach((t) => ok(`persona «${t.slice(0, 30)}»: sí se contesta`, !esRespuestaAutomatica(t)));
  ok('lo automático NO cierra la conversación ni cuenta un turno (puede escribir después una persona de verdad)',
     /esRespuestaAutomatica\(m\.texto\)\) \{\s*await rpc\(env, 'wa_cerrar_mensaje', \{ p_id: m\.id, p_estado: 'ignorado' \}\)\.catch\(\(\) => \{\}\);\s*return json\(\{ ok: true, automatica: true \}/.test(index));
}

titulo('3. Mensajes seguidos: una sola respuesta');
{
  ok('antes de contestar espera unos segundos y pregunta si llegó un mensaje más nuevo',
     /ESPERA_MENSAJES_SEGUIDOS_MS = 3500/.test(index) && /rpc\(env, 'wa_hay_mensaje_mas_nuevo', \{ p_id: m\.id \}\)/.test(index));
  ok('si llegó uno más nuevo, este no se contesta (lo contesta el último, que ya ve los anteriores en el historial)',
     /hayMasNuevo === true[\s\S]{0,260}p_estado: 'ignorado'[\s\S]{0,80}agrupado: true/.test(index));
  ok('la función de la base solo lee y solo la puede llamar el Worker',
     /create or replace function public\.wa_hay_mensaje_mas_nuevo\(p_id bigint\)/.test(m185) && /\bstable\b/.test(m185) &&
     /revoke execute on function public\.wa_hay_mensaje_mas_nuevo\(bigint\) from public, anon, authenticated/.test(m185) &&
     /grant execute on function public\.wa_hay_mensaje_mas_nuevo\(bigint\) to service_role/.test(m185));
  ok('solo mira mensajes ENTRANTES de la misma persona de los últimos 2 minutos',
     /b\.direccion = 'entrante'/.test(m185) && /b\.telefono = a\.telefono/.test(m185) && /interval '2 minutes'/.test(m185));
  ok('el orden en ventasWA: primero «salir», luego lo automático, luego el agrupado',
     index.indexOf("salir: true }, 200, origen);\n    }\n\n    // 14 oct: el saludo automático") > 0 &&
     index.indexOf('esRespuestaAutomatica(m.texto)') < index.indexOf("'wa_hay_mensaje_mas_nuevo'"));
}

console.log(`\n${fallos ? '✗ ' + fallos + ' con problemas' : '✓ todo bien'}`);
process.exit(fallos ? 1 : 0);
