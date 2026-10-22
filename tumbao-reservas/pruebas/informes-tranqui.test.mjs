/**
 * Informes diarios en dos tamaños (0160): tranqui y completo.
 *
 * Damián (9 oct): «a veces me siento infotoxicado… que algunos días sea más tranqui, solo cómo estuvo el día, y otros
 * con todo el detalle». Esta prueba protege que:
 *   1. el calendario sea fijo y predecible (3 completos de 14 informes) y respete el modo que él elija;
 *   2. lo grave NO se esconda en el tranqui: las alertas las decide el código;
 *   3. «detalle» y «informes tranquilos/mixtos/completos» se entiendan;
 *   4. el prompt tranqui sea corto, sin nombres de clientes ni «a quién buscar», y use las mismas revisiones de cifras.
 *
 *   node informes-tranqui.test.mjs
 */
import { readFileSync } from 'node:fs';
import { estiloDelInforme, alertasDelDia, esPedidoDeDetalle, modoPedido, INSTRUCCIONES_INFORME_TRANQUI }
  from '../../tumbao-caja/src/informes.js';

let fallos = 0;
const ok = (n, c, extra = '') => { if (!c) fallos++; console.log(`${c ? '✓' : '✗'} ${n}${extra ? '  → ' + extra : ''}`); };
const titulo = t => console.log(`\n-- ${t} ${'-'.repeat(Math.max(0, 54 - t.length))}`);

titulo('1. El calendario');
{
  const semana = [];
  for (let d = 1; d <= 7; d++) for (const t of ['manana', 'noche']) semana.push([t, d, estiloDelInforme(t, d)]);
  const completos = semana.filter(x => x[2] === 'completo').map(x => `${x[0]}-${x[1]}`);
  ok('solo 3 de los 14 informes de la semana son completos', completos.length === 3, completos.join(', '));
  ok('lunes y miércoles en la mañana (a quién buscar) y viernes en la noche (cierre de la semana)',
     completos.includes('manana-1') && completos.includes('manana-3') && completos.includes('noche-5'));
  ok('los domingos siempre tranqui (no hay clases)', estiloDelInforme('manana', 7) === 'tranqui' && estiloDelInforme('noche', 7) === 'tranqui');
  ok('modo «tranqui»: todos cortos', semana.every(([t, d]) => estiloDelInforme(t, d, 'tranqui') === 'tranqui'));
  ok('modo «completo»: todos largos (como antes)', semana.every(([t, d]) => estiloDelInforme(t, d, 'completo') === 'completo'));
  ok('un modo desconocido cae al calendario', estiloDelInforme('noche', 5, 'raro') === 'completo' && estiloDelInforme('noche', 2, 'raro') === 'tranqui');
}

titulo('2. Lo grave no se esconde');
{
  const base = { tipo: 'noche', fecha: '2026-10-08', cruce_banco: { cierre_hecho: true, efectivo_diferencia_cop: 0 },
                 ventas: { hoy: { total_cop: 305000, promedio_mismo_dia_4_semanas_cop: 388750 } } };
  ok('un día normal no trae alertas', alertasDelDia(base).length === 0);
  ok('cierre sin hacer', /cierre de caja.*no se ha hecho/.test(alertasDelDia({ ...base, cruce_banco: { cierre_hecho: false } })[0]));
  ok('efectivo descuadrado, con la diferencia', /efectivo no cuadró.*\$15\.000/.test(alertasDelDia({ ...base, cruce_banco: { cierre_hecho: true, efectivo_diferencia_cop: -15000 } })[0]));
  ok('ventas por debajo de la mitad de lo normal, con las dos cifras',
     /\$150\.000.*\$388\.750/.test(alertasDelDia({ ...base, ventas: { hoy: { total_cop: 150000, promedio_mismo_dia_4_semanas_cop: 388750 } } })[0]));
  ok('sin promedio (domingo o primer día) no se inventa una alerta', alertasDelDia({ ...base, ventas: { hoy: { total_cop: 0, promedio_mismo_dia_4_semanas_cop: 0 } } }).length === 0);
  const m = { tipo: 'manana', fecha: '2026-10-08', mensualidades: { vencen_proximos_7_dias: [
    { vence: '2026-10-08' }, { vence: '2026-10-08' }, { vence: '2026-10-08' }, { vence: '2026-10-08' }, { vence: '2026-10-09' }] } };
  ok('mañana con 4 o más vencimientos hoy avisa cuántos', /Hoy vencen 4 mensualidades/.test(alertasDelDia(m)[0]));
  ok('con menos de 4 no molesta', alertasDelDia({ ...m, mensualidades: { vencen_proximos_7_dias: m.mensualidades.vencen_proximos_7_dias.slice(0, 3) } }).length === 0);
  ok('máximo dos alertas', alertasDelDia({ tipo: 'noche', cruce_banco: { cierre_hecho: true, efectivo_diferencia_cop: 5000 }, ventas: { hoy: { total_cop: 1000, promedio_mismo_dia_4_semanas_cop: 300000 } } }).length <= 2);
}

titulo('3. Lo que escribe Damián');
{
  ok('«detalle» y variantes piden el completo', ['detalle', 'Detalle', 'ver detalle', 'ver todo', 'informe completo', 'completo', 'detalle!'].every(esPedidoDeDetalle));
  ok('una pregunta normal NO se toma por «detalle»', !['cuántos activos hay', 'dame el detalle de las ventas de ayer', 'detalle de renovaciones'].some(esPedidoDeDetalle));
  ok('«informes tranquilos» / «mixtos» / «completos»', modoPedido('informes tranquilos') === 'tranqui' && modoPedido('Informes mixtos') === 'mixto' && modoPedido('los informes completos') === 'completo' && modoPedido('informes siempre cortos') === 'tranqui');
  ok('preguntas normales no cambian el modo', modoPedido('cuántos activos hay') === null && modoPedido('ver resumen') === null && modoPedido('dame un informe de ventas') === null);
}

titulo('4. El prompt tranqui y el cableado');
{
  const w = readFileSync(new URL('../../tumbao-caja/src/index.js', import.meta.url), 'utf8');
  const sql = readFileSync(new URL('../supabase/migrations/0160_informes_tranqui_y_completo.sql', import.meta.url), 'utf8').replace(/--.*$/gm, '');
  const p = INSTRUCCIONES_INFORME_TRANQUI;
  ok('mañana: máximo 4 líneas; noche: máximo 6', /máximo 4 líneas/.test(p) && /máximo 6 líneas/.test(p));
  ok('no lleva nombres de clientes, a quién buscar, metas, insights ni banco', /NO pongas en la versión tranqui: nombres de clientes, quién se fue o a quién buscar, renovaciones, metas del mes, insights, banco/.test(p));
  ok('las alertas salen tal cual y la puerta al detalle siempre está', /"alertas"/.test(p) && /escribe \*detalle\*/.test(p));
  ok('solo cifras del JSON y los cálculos hechos', /Solo cifras del JSON/.test(p) && /calculos_hechos/.test(p));
  ok('el informe real elige estilo por calendario o modo y lo pasa al redactor', /estiloParaHoy\(env, tipo, null\)/.test(w) && /redactarInforme\(env, tablero, 'medium', estilo\)/.test(w));
  ok('el tranqui usa las mismas revisiones de cifras que el completo', /\$\{INSTRUCCIONES_INFORME_TRANQUI\}\\n\\n\$\{REGLAS_DE_CIFRAS\}/.test(w) && /cifrasSospechosas\(texto, tablero\)/.test(w));
  ok('la voz de la semana del lunes solo va en el completo', /estilo === 'completo' && esLunesBogota\(\)/.test(w));
  ok('«detalle» arma el completo en el momento y avisa que se está armando', /esPedidoDeDetalle\(m\.texto\)/.test(w) && /'completo'\);/.test(w) && /armo el detalle/.test(w));
  ok('el modo se cambia por una función de la base, validada', /informe_modo_cambiar/.test(w) && /p_modo not in \('mixto', 'tranqui', 'completo'\)/.test(sql) && /'informe_modo', 'mixto'/.test(sql));
  ok('0160: sin DROP ni DELETE', !/\bdrop\b/i.test(sql) && !/\bdelete\b/i.test(sql));
}

console.log(fallos ? `\n${fallos} fallo(s)` : '\nTodo bien');
process.exit(fallos ? 1 : 0);
