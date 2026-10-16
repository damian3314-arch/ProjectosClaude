/**
 * La fidelidad de los cupos de 6 y 7 pm, pausada (0180 y 0181, 14 oct).
 *
 * Damián: «las mensualidades están caídas, necesitamos nuevos clientes: esa de dar los puestos por fidelidad se puede
 * pausar. Lo único que se necesita es guardar 5 días el cupo a la gente que se vence y luego ya se vende al que compre.
 * Y que la página de mensualidad dé el QR y que la gente pague».
 *
 * Se probó en la base real (una persona nueva, sin historial, pide 6 pm, 7 pm y 7 am y a las tres se le abre el pago;
 * Timba propone mensualidad de 6 y de 7 pm; la consulta interna dice «SÍ puede»). Aquí se protege lo que queda escrito:
 *
 *   node fidelidad-pausada.test.mjs
 */
import { readFileSync } from 'node:fs';
import { opcionesDeVenta, INSTRUCCIONES_VENTAS, textoSeguimientoVentas, textoRecepcionEnlace } from '../../tumbao-caja/src/ventas.js';
import { INSTRUCCIONES_PREMIUM } from '../../tumbao-caja/src/premium.js';

let fallos = 0;
const ok = (n, c, extra = '') => { if (!c) fallos++; console.log(`${c ? '✓' : '✗'} ${n}${extra ? '  → ' + extra : ''}`); };
const titulo = t => console.log(`\n-- ${t} ${'-'.repeat(Math.max(0, 54 - t.length))}`);

const leer = (n) => readFileSync(new URL(`../supabase/migrations/${n}`, import.meta.url), 'utf8').replace(/--.*$/gm, '');
const m80 = leer('0180_pausar_la_fidelidad_de_6_y_7_pm.sql');
const m81 = leer('0181_la_consulta_interna_con_la_fidelidad_pausada.sql');

titulo('1. Un solo interruptor, reversible');
{
  ok('ajustes.premium_fidelidad = «pausada» y cualquier otro valor la reactiva',
     /'premium_fidelidad', 'pausada'/.test(m80) && /coalesce\(\(select valor from ajustes where clave = 'premium_fidelidad'\), 'activa'\) = 'pausada'/.test(m80));
  ok('el interruptor lo leen la página (puede pagar, fila de espera, aviso a la lista), Timba (cupos, candidatos, perfil) y la consulta interna',
     /premium_puede_pagar/.test(m80) && /mensualidad_fila/.test(m80) && /mensualidad_avisar_lista_espera/.test(m80) &&
     /ventas_perfil/.test(m80) && /create or replace function public\.ventas_cupos/.test(m80) && /create or replace function public\.ventas_candidatos/.test(m80) &&
     /mensualidad_decision/.test(m81) && /mensualidad_cupo_liberado_texto/.test(m81));
  ok('cada parche se aplica una sola vez y falla en vez de dejar algo a medias',
     (m80.match(/ya estaba pausable|ya tenía mensualidad_7pm/g) || []).length >= 5 && (m80.match(/raise exception '0180:/g) || []).length >= 5 &&
     /raise exception '0181:/.test(m81));
}

titulo('2. La página: cupo libre = se vende, con el QR');
{
  ok('con la pausa nadie paga «por encima del tope» por fidelidad: premium_puede_pagar devuelve falso y manda el cupo libre de la página',
     /if premium_pausado\(\) then return false; end if;/.test(m80));
  ok('la fila de espera deja de ordenarse por fidelidad (nadie «aplica») y mensualidad_cupos() ya no aparta cupos para ella',
     /\(coalesce\(\(p ->> 'veredicto'\) = 'aplica', false\) and not premium_pausado\(\)\) as ap/.test(m80));
  ok('la gracia de 5 días no se toca (ya estaba: mensualidad_gracia_dias = 5 y mensualidad_cupos() cuenta fin + gracia); aquí solo se lee',
     !/(insert into|update)\s+(public\.)?ajustes[^;]*mensualidad_gracia_dias/s.test(m80) && !/create or replace function public\.mensualidad_cupos/.test(m80));
  ok('el aviso de cupo a la lista de espera sale por orden de llegada, con el cupo que muestra la página',
     /\(f\.aplica or premium_pausado\(\)\) order by f\.orden/.test(m80) && /mensualidad_cupos\(\) -> 'horas'\) h where h ->> 'hora' = v_hora/.test(m80));
}

titulo('3. Timba ofrece la mensualidad de 6 y de 7 pm');
{
  const sin = { cupos_mensualidad: { '07:00': 12, '18:00': 4, '19:00': 8 }, aplica_mensualidad: false };
  const con = { cupos_mensualidad: { '07:00': 12, '18:00': 4, '19:00': 8 }, aplica_mensualidad: true };
  ok('con la fidelidad activa y sin cumplirla, no se le ofrece 6 ni 7 pm (como antes)',
     opcionesDeVenta(sin, 'tiquetera').mensualidad_6pm === false && opcionesDeVenta(sin, 'tiquetera').mensualidad_7pm === false);
  ok('con la fidelidad pausada (la base dice que aplica a cualquiera) se le ofrece 6 pm y 7 pm si hay cupo',
     opcionesDeVenta(con, 'tiquetera').mensualidad_6pm === true && opcionesDeVenta(con, 'tiquetera').mensualidad_7pm === true);
  ok('si el horario no tiene cupo, no se le ofrece',
     opcionesDeVenta({ ...con, cupos_mensualidad: { '07:00': 12, '18:00': 0, '19:00': 0 } }, 'tiquetera').mensualidad_7pm === false);
  ok('a quien se le abrió con «mensualidad_7pm» se le ofrece ese cupo',
     opcionesDeVenta(sin, 'mensualidad_7pm').mensualidad_7pm === true);
  ok('el prompt de Timba conoce la mensualidad de 7 pm y ya no dice que 7 pm es solo lista de espera',
     /mensualidad_7pm/.test(INSTRUCCIONES_VENTAS) && !/7 pm: lista de espera \(apuntarse es gratis en el enlace\)\. Si no hay cupo/.test(INSTRUCCIONES_VENTAS));
  ok('sigue sin prometer lo que no se puede: nada de «últimos cupos», descuentos ni requisitos',
     /NO hables de requisitos/.test(INSTRUCCIONES_VENTAS) && /Nunca inventes un descuento/.test(INSTRUCCIONES_VENTAS));
  ok('el seguimiento y el aviso a recepción también conocen la mensualidad de 7 pm',
     /¿Pudiste inscribirte en el cupo de las 7 pm\?/.test(textoSeguimientoVentas({ nombre: 'Ana', objetivo: 'mensualidad_7pm', hora: '19:00' })) &&
     /la mensualidad de 7 pm/.test(textoRecepcionEnlace({ nombre: 'Ana', telefono: '3001234567', objetivo: 'mensualidad_7pm' })));
  ok('Timba arma la invitación de 7 pm con el gancho nuevo',
     /when 'mensualidad_7pm' then 'Hay cupo de mensualidad en el horario de 7 pm/.test(m80));
}

titulo('4. El asistente interno y recepción dicen lo mismo');
{
  ok('el asistente interno sabe que la fidelidad está pausada, que se vende a quien pague primero y que la gracia es de 5 días',
     /FIDELIDAD está PAUSADA|fidelidad está PAUSADA/.test(INSTRUCCIONES_PREMIUM) && /quien pague primero/.test(INSTRUCCIONES_PREMIUM) && /5 días después de vencer/.test(INSTRUCCIONES_PREMIUM));
  ok('la consulta «¿puedo procesar a Fulana?» contesta «SÍ puede» según el cupo del horario, sin requisitos',
     /SÍ puede: la fidelidad está pausada y hay/.test(m81) && /escanea el QR/.test(m81));
  ok('la nota de las 8:20 am manda a pagar la mensualidad a quien está en la fila y hay cupo (no «ofréceles tiquetera»)',
     /\(x\.aplica or premium_pausado\(\)\) and x\.orden <= v_libres/.test(m81));
  ok('no borra nada ni toca precios, topes ni la gracia',
     !/\bdelete\b|\bdrop\b|\btruncate\b/i.test(m80 + m81) && !/mensualidad_topes|mensualidad_valor_cop/.test(m80 + m81));
}

console.log(`\n${fallos ? '✗ ' + fallos + ' con problemas' : '✓ todo bien'}`);
process.exit(fallos ? 1 : 0);
