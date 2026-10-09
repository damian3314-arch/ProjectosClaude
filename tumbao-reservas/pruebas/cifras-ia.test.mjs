/**
 * Las cifras que escribe la IA: el modelo redacta, el código calcula y revisa (tumbao-caja/src/cifras.js).
 *
 * Caso real, cierre del 5 oct: el informe dijo «valor típico de $118.333» y «renovaciones en juego cerca de
 * $2.722.000». La mensualidad vale $125.000 y las cuentas correctas eran 21 planes completos × $125.000 =
 * $2.625.000. Esta prueba protege que:
 *   1. los precios oficiales y las cuentas lleguen hechos al modelo (y el «valor típico» engañoso no),
 *   2. un monto que no sale de los datos se detecte, y los correctos pasen,
 *   3. el informe y el asistente usen esas protecciones.
 *
 *   node cifras-ia.test.mjs
 */
import { readFileSync } from 'node:fs';
import { prepararTablero, derivar, cifrasSospechosas, montosEnTexto, numerosDe, REGLAS_DE_CIFRAS, REGLAS_DE_CIFRAS_AGENTE,
         esConteoDeMensualidades, textoMensualidades, totalesNoCuadran }
  from '../../tumbao-caja/src/cifras.js';

let fallos = 0;
const ok = (n, c, extra = '') => { if (!c) fallos++;
  console.log(`${c ? '✓' : '✗'} ${n}${extra ? '  → ' + extra : ''}`); };
const titulo = t => console.log(`\n-- ${t} ${'-'.repeat(Math.max(0, 54 - t.length))}`);

// Cierre real del lunes 5 de octubre.
const tablero = {
  tipo: 'noche',
  ventas: {
    hoy: { otros_n: 0, otros_cop: 0, total_cop: 355000, sueltas_cop: 105000, efectivo_cop: 15000, tiqueteras_n: 0, tiqueteras_cop: 0,
           mensualidades_n: 2, sueltas_personas: 8, mensualidades_cop: 250000, promedio_mismo_dia_4_semanas_cop: 899250 },
    mes: { meta_cop: null, total_cop: 1610000, mensualidades_n: 6, sueltas_personas: 66, mensualidades_cop: 710000,
           mes_anterior_mismo_tramo_cop: 2020000, dias_con_clase_que_quedan: 22 },
  },
  cruce_banco: { cruzado_cop: 565000, entro_al_banco_hoy_cop: 786000, pendiente_por_cruzar_cop: 221000, efectivo_diferencia_cop: 0 },
  para_insights: { renovaciones_7_dias: { personas: 23, valor_tipico_mensualidad_cop: 118333 } },
};
const precios = { mensualidad_plan_completo_cop: 125000, clase_suelta_cop: 15000,
  tiquetera_paquetes: [{ clases: 4, precio_cop: 52000 }, { clases: 8, precio_cop: 96000 }] };
const renov = { personas_total: 23, planes_completos_n: 21, medias_mensualidades_n: 2, valor_planes_completos_cop: 2625000 };

titulo('1. Lo que le llega al modelo');
{
  const t = prepararTablero(tablero, precios, renov);
  ok('el «valor típico» engañoso ($118.333) ya no se le pasa', !JSON.stringify(t).includes('118333'));
  ok('el original no se modifica', tablero.para_insights.renovaciones_7_dias.valor_tipico_mensualidad_cop === 118333);
  ok('la mensualidad oficial va en datos_fijos: $125.000', t.datos_fijos.mensualidad_plan_completo_cop === 125000);
  const c = t.calculos_hechos;
  ok('hoy contra el promedio: −$544.250 y −60,5 %', c.hoy.contra_promedio_cop === -544250 && c.hoy.contra_promedio_pct === -60.5);
  ok('el mes contra el anterior: −$410.000 y −20,3 %', c.mes.contra_mes_anterior_cop === -410000 && c.mes.contra_mes_anterior_pct === -20.3);
  ok('las partes del día suman el total', c.hoy.suma_de_las_partes_cop === 355000);
  ok('renovaciones en juego: 21 planes × $125.000 = $2.625.000', c.renovaciones_en_juego.valor_planes_completos_cop === 2625000);
  ok('banco: entró − cruzado = pendiente', c.banco.entro_menos_cruzado_cop === 221000 && c.banco.pendiente_cop === 221000);
  ok('tiquetera de 8: $12.000 por clase y ahorra $24.000',
     c.tiquetera_por_clase_cop[1].por_clase_cop === 12000 && c.tiquetera_por_clase_cop[1].ahorro_contra_sueltas_cop === 24000);
  const conMeta = derivar({ ventas: { hoy: {}, mes: { total_cop: 1000000, meta_cop: 15000000, dias_con_clase_que_quedan: 20 } } }, precios, renov);
  ok('con meta: falta $14.000.000 y hay que vender $700.000 por día',
     conMeta.mes.falta_para_meta_cop === 14000000 && conMeta.mes.necesario_por_dia_cop === 700000);
}

titulo('2. El error real se detecta y lo correcto pasa');
{
  const t = prepararTablero(tablero, precios, renov);
  const malo = 'Hay 23 renovaciones en juego en los próximos 7 días; al valor típico de $118.333, representan cerca de $2.722.000.';
  const sosp = cifrasSospechosas(malo, t);
  ok('detecta el valor típico engañoso ($118.333)', sosp.includes(118333), sosp.join(', '));
  ok('detecta el total inventado ($2.722.000)', sosp.includes(2722000));
  const bueno = '*Ventas de hoy:* $355.000: 8 sueltas ($105.000) y 2 mensualidades ($250.000). Fue $544.250 menos que el promedio (−60,5 %). ' +
                '*El mes:* $1.610.000 frente a $2.020.000. *Banco:* entraron $786.000; $565.000 cruzados y $221.000 pendientes. ' +
                '21 planes completos × $125.000 = $2.625.000 en juego. La tiquetera de 8 sale a $12.000 la clase.';
  ok('el informe correcto no levanta alertas', cifrasSospechosas(bueno, t).length === 0, cifrasSospechosas(bueno, t).join(', '));
  ok('un redondeo claro pasa («cerca de $2.600.000» sale de $2.625.000)', cifrasSospechosas('cerca de $2.600.000', t).length === 0);
  ok('un precio de mensualidad cambiado se detecta ($120.000)', cifrasSospechosas('La mensualidad vale $120.000', t).includes(120000));
  ok('una suma de dos datos pasa (2 mensualidades = $250.000)', cifrasSospechosas('2 mensualidades, $250.000', t).length === 0);
  ok('sin montos en pesos no hay nada que revisar', cifrasSospechosas('Hubo 8 sueltas y 2 mensualidades, 62 %.', t).length === 0);
}

titulo('3. Cómo se leen los montos');
{
  ok('«$1.250.000», «$12.000» y «$355000»', montosEnTexto('$1.250.000 y $12.000 y $355000').sort((a, b) => a - b).join() === '12000,355000,1250000');
  ok('«$3,6 M» = 3.600.000', montosEnTexto('Ventas $3,6 M').includes(3600000));
  ok('«355.000 pesos»', montosEnTexto('355.000 pesos').includes(355000));
  ok('lo que no es plata no cuenta (horas, personas, %)', montosEnTexto('a las 7:00 pm, 23 personas, -60,5 %').length === 0);
  ok('números de un texto o un objeto', [...numerosDe({ a: 125000, b: [1, 2], c: 'cuesta 52.000' })].sort((x, y) => x - y).join() === '1,2,52000,125000');
}

titulo('4. El asistente de preguntas');
{
  const sesion = [{ salida: '{"mensualidades_n": 6, "mensualidades_cop": 710000}' }];
  const pre = precios;
  ok('«la mensualidad vale $125.000» pasa', cifrasSospechosas('La mensualidad vale $125.000', sesion, pre, '¿cuánto vale la mensualidad?').length === 0);
  ok('«vale $118.333» se detecta (promedio de pagos, no el precio)', cifrasSospechosas('La mensualidad vale $118.333', sesion, pre, '').includes(118333));
  ok('el promedio real de la base sí se permite si la base lo trae', cifrasSospechosas('Cada mensualidad salió en promedio a $118.333', ['{"promedio": 118333}'], pre, '').length === 0);
}

titulo('5. Cableado en el Worker');
{
  const w = readFileSync(new URL('../../tumbao-caja/src/index.js', import.meta.url), 'utf8');
  // 0160: ahora también lleva el estilo (tranqui o completo) y «detalle» arma el completo.
  ok('el informe pasa por redactarInforme (borrador, real y «detalle»)', (w.match(/redactarInforme\(env, tablero, 'medium', /g) || []).length === 3);
  const desde = w.indexOf('async function redactarInforme'), hasta = w.indexOf('async function redactar(env');
  const usos = [...w.matchAll(/(?<!function )redactar\(env, instrucciones/g)].map((x) => x.index);
  ok('ningún informe se redacta fuera de redactarInforme con las instrucciones del informe', !/redactar\(env, INSTRUCCIONES_INFORME/.test(w));
  ok('el informe solo se redacta dentro de redactarInforme (nunca con el tablero crudo)', usos.length > 0 && usos.every((i) => i > desde && i < hasta));
  ok('las reglas de cifras van al prompt del informe', /\$\{REGLAS_DE_CIFRAS\}/.test(w) && /calculos_hechos/.test(REGLAS_DE_CIFRAS));
  ok('el asistente recibe los precios oficiales y las reglas', /DATOS FIJOS DEL NEGOCIO/.test(w) && /REGLAS_DE_CIFRAS_AGENTE/.test(w) && /renovaciones_en_juego/.test(REGLAS_DE_CIFRAS_AGENTE));
  ok('el asistente revisa sus cifras y reintenta', /cifrasSospechosas\(respuesta, registro\.salidas/.test(w) && /Revisión interna/.test(w));
  ok('si persiste, la línea «por confirmar» va en el mensaje', /Cifras por confirmar/.test(w) && /Confirma estas cifras antes de usarlas/.test(w));
}

titulo('4. Mensualidades: una sola verdad (8 oct: «58» y luego 26 / 20 / 23 con «Total: 58»)');
{
  const w = readFileSync(new URL('../../tumbao-caja/src/index.js', import.meta.url), 'utf8');
  const sql = readFileSync(new URL('../supabase/migrations/0159_mensualidades_resumen_una_sola_verdad.sql', import.meta.url), 'utf8').replace(/--.*$/gm, '');
  // Lo que devolvió la base el 8 de octubre.
  const resumen = { dias_de_gracia: 5, total_vigentes: 58, total_en_gracia: 11, total_ocupan_cupo: 69, por_horario: [
    { hora: '07:00', etiqueta: '7:00 am', vigentes: 24, en_gracia: 2, ocupan_cupo: 26, libres_pagina: 9 },
    { hora: '18:00', etiqueta: '6:00 pm', vigentes: 19, en_gracia: 1, ocupan_cupo: 20, libres_pagina: 0 },
    { hora: '19:00', etiqueta: '7:00 pm', vigentes: 15, en_gracia: 8, ocupan_cupo: 23, libres_pagina: 0 }] };
  const t = textoMensualidades(resumen);
  ok('la pregunta de Damián se contesta sin modelo', esConteoDeMensualidades('Cuantos activos en mensualidad hay?'));
  ok('lo demás NO se desvía (ventas, vencimientos, cupos de clase, precio, seguimiento)',
     !['cuántas mensualidades vendimos este mes', 'cuántas mensualidades vencen esta semana', 'cuántos cupos hay el jueves 5 pm', 'cuánto vale la mensualidad', 'En cada horario?']
       .some(esConteoDeMensualidades));
  ok('el texto trae los tres números rotulados y cada total es la suma de su columna',
     /Activas.*\*58\*.*\*24\*.*\*19\*.*\*15\*/.test(t) && /En gracia.*\*11\*.*\*2\*.*\*1\*.*\*8\*/.test(t) && /Ocupan cupo.*\*69\*.*\*26\*.*\*20\*.*\*23\*/.test(t)
     && 24 + 19 + 15 === 58 && 2 + 1 + 8 === 11 && 26 + 20 + 23 === 69 && 58 + 11 === 69);
  ok('el texto exacto no dispara la revisión de totales', totalesNoCuadran(t).length === 0);
  ok('el error de Damián se detecta: 26 + 20 + 23 con «Total: 58»',
     totalesNoCuadran('Activos en mensualidad por horario:\n\n• 7:00 am: *26*\n• 6:00 pm: *20*\n• 7:00 pm: *23*\n\n*Total: 58.*')[0].suma === 69);
  ok('un total correcto o una frase suelta no se marcan', !totalesNoCuadran('• 7 am: *24*\n• 6 pm: *19*\n• 7 pm: *15*\n\n*Total: 58*').length && !totalesNoCuadran('Hoy: 7 am: 2 reservas + 24 mensualidades. Total de la semana: 90').length);
  ok('las reglas del asistente mandan a mensualidades_resumen() y prohíben sumar a mano', /mensualidades_resumen\(\)/.test(REGLAS_DE_CIFRAS_AGENTE) && /no los sumes ni los restes tú/.test(REGLAS_DE_CIFRAS_AGENTE) && /MISMA columna/.test(REGLAS_DE_CIFRAS_AGENTE));
  ok('el asistente usa el atajo exacto y la revisión de totales', /esConteoDeMensualidades\(m\.texto\)/.test(w) && /mensualidades_resumen/.test(w) && /totalesNoCuadran\(respuesta\)/.test(w));
  ok('0159: cuenta personas (no filas), con los totales sumados en SQL y lo que cuenta la página',
     /count\(distinct coalesce\(nullif\(right\(regexp_replace/.test(sql) && /'total_ocupan_cupo'/.test(sql) && /mensualidad_cupos\(\)/.test(sql) && /'en_gracia', o\.n - v\.n/.test(sql));
  ok('0159: el informe diario deja de contar filas y trae el resumen exacto', /tablero_tumbao/.test(sql) && /'resumen_exacto', mensualidades_resumen\(d\)/.test(sql));
  ok('0159: sin DROP ni DELETE', !/\bdrop\b/i.test(sql) && !/\bdelete\b/i.test(sql));
}

console.log(fallos ? `\n${fallos} fallo(s)` : '\nTodo bien');
process.exit(fallos ? 1 : 0);
