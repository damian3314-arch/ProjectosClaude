/** Día de invitados (13 nov): 2 cupos por $24.000, el pop-up y que lo cobre la base.   node promo-dia-invitados.test.mjs */
import { readFileSync, existsSync } from 'node:fs';
const leer = (r) => readFileSync(new URL(r, import.meta.url), 'utf8');
const idx = leer('../../docs/index.html'), mig = leer('../supabase/migrations/0206_promo_dos_cupos_dia_de_invitados.sql');
let fallos = 0;
const ok = (n, c) => { if (!c) fallos++; console.log(`${c ? '✓' : '✗'} ${n}`); };
const titulo = t => console.log(`\n-- ${t} ${'-'.repeat(Math.max(0, 54 - t.length))}`);

titulo('1. La página');
ok('la promo es de exactamente 2 cupos, $24.000, solo el 13, 18 y 20 de noviembre (el 19 no)', /PROMO_DOS: \{ cupos: 2, precio: 24000, dias: \['2026-11-13', '2026-11-18', '2026-11-20'\]/.test(idx));
ok('el total usa la promo por parejas (4 = $48.000, 6, 8) solo en clase suelta de los días de la promo', /function promoAplica/.test(idx) && /pares \* P\.precio \+ \(cuantos - pares \* P\.cupos\) \* unit/.test(idx));
ok('la página hace publicidad: franja arriba, etiqueta en los días y nota en el contador', /id="franja-aguinaldos"/.test(idx) && /dia-promo/.test(idx) && /id="promo-nota"/.test(idx) && /4 por \$48\.000/.test(idx));
ok('el resumen, la cuenta y el botón leen totalGrupo()', (idx.match(/totalGrupo\(\)/g) || []).length >= 3);
ok('el pop-up existe, dice los días y se puede cerrar de tres formas', /Miércoles 18 y viernes 20/.test(idx) && /id="promo-x"/.test(idx) && /id="promo-no"/.test(idx) && /e\.target === pop/.test(idx));
ok('sale una sola vez por navegador y deja de salir al terminar el 20 de noviembre', /tumbao_promo_aguinaldos_1118/.test(idx) && /Date\.parse\('2026-11-21T00:00:00-05:00'\)/.test(idx));
ok('los navegadores automáticos no ven el pop-up (para no tapar las otras pruebas) y ?promo=1 lo fuerza', /navigator\.webdriver/.test(idx) && /promo=1/.test(idx));
ok('el botón lleva a «Clase suelta» y al próximo día de la promo', /opcion\[data-tipo="suelta"\]/.test(idx) && /data-fecha="' \+ prox/.test(idx));

titulo('2. La base cobra, la página solo lo muestra');
ok('promo_total_cupos devuelve 24000 solo con n = 2 y clase dentro del rango, y es apagable', /promo_total_cupos/.test(mig) && /activa/.test(mig));
ok('precio_del_grupo y tomar_cupos la usan', /precio_del_grupo/.test(mig) && /tomar_cupos/.test(mig));

titulo('3. Timba (asistente interno) contesta lo de la promo, cupos y asistencias');
{
  const w = leer('../../tumbao-caja/src/index.js');
  const a = w.slice(w.indexOf('const INSTRUCCIONES_AGENTE'), w.indexOf('const HERRAMIENTAS_AGENTE'));
  ok('conoce la promo de 2 cupos por $24.000 y cómo contar sus reservas (grupos)', /promo_dos_cupos/.test(a) && /24\.000/.test(a) && /grupo_id/.test(a) && /promo_del_dia/.test(a));
  ok('sabe contar cupos libres y asistencias', /cupo_total . cupo_tomado/.test(a) && /asistencias/.test(a) && /reserva_id/.test(a));
  ok('sabe contar planes y tiqueteras, y usa ventas_entre para la plata', /mensualidades_resumen/.test(a) && /tiqueteras/.test(a) && /ventas_entre/.test(a));
}

titulo('3b. Aguinaldos: la base acepta varios días y grupos grandes');
{
  const m9 = leer('../supabase/migrations/0209_promo_por_parejas.sql');
  ok('promo_total_cupos cobra por parejas y deja el sobrante a precio normal', /pares := p_n \/ k/.test(m9) && /least\(pares \*/.test(m9));
}
{
  const m8 = leer('../supabase/migrations/0208_promo_aguinaldos_18_y_20.sql');
  ok('promo_total_cupos lee la lista «fechas» y la promo queda para el 13, 18 y 20', /jsonb_array_elements_text\(v->'fechas'\)/.test(m8) && /"fechas":\["2026-11-13","2026-11-18","2026-11-20"\]/.test(m8));
  const w = leer('../../tumbao-caja/src/asistente.js') + leer('../../tumbao-caja/src/ventas.js');
  ok('Timba ofrece la promo solo el miércoles 18 y el viernes 20', /miércoles 18 y el viernes 20/.test(w) && !/solo el viernes 13 de noviembre/.test(w));
}

titulo('3c. Aviso del simulacro navideño (jueves 19)');
ok('al elegir el jueves 19 se avisa de los horarios 6:00-7:00 y 7:30-8:30 y del antojito opcional, y se repite en el resumen',
   /'2026-11-19':\s*\{[\s\S]*6:00 a 7:00 p\. m\.[\s\S]*7:30 a 8:30 p\. m\.[\s\S]*trae tu antojito/.test(idx) && /id="aviso-dia"/.test(idx) && /aviso-corto/.test(idx) && /function avisoDelDia/.test(idx));
ok('Timba sabe del simulacro', /SIMULACRO NAVIDEÑO/.test(leer('../../tumbao-caja/src/asistente.js')) && /SIMULACRO NAVIDEÑO/.test(leer('../../tumbao-caja/src/ventas.js')));

titulo('4. El cierre cuenta lo cobrado y /admin muestra quién pagó la promo');
{
  const m7 = leer('../supabase/migrations/0207_promo_visible_en_cierre_y_admin.sql');
  const adm = leer('../../docs/admin.html');
  ok('valor_reserva usa precio_del_grupo entre las personas del grupo', /function public\.valor_reserva/.test(m7) && /precio_del_grupo\(r\.id\)/.test(m7));
  ok('caja_del_dia y ventas_entre dejan de sumar precio_cop por persona', /sum\(valor_reserva\(r\.id\)\)/.test(m7) && /caja_del_dia\(text,date\)/.test(m7) && /ventas_entre\(date,date\)/.test(m7));
  ok('el cierre trae la sección promo, con repetidas marcadas', /''promo'', promo_del_dia\(v_dia\)/.test(m7) && /'repetida'/.test(m7));
  ok('/admin enseña la tarjeta de la promo en el cierre y en la tirilla', /function tarjetaPromo/.test(adm) && /\+ tarjetaPromo\(\)/.test(adm) && /Promo 2x\$24\.000/.test(adm));
  ok('no borra nada: sin DROP ni DELETE', !/\bdrop\s+(table|function|index)|\bdelete\s+from/i.test(m7.replace(/--.*$/gm, '')));
}

console.log(`\n${fallos ? '✗ ' + fallos + ' con problemas' : '✓ todo bien'}`);
process.exit(fallos ? 1 : 0);
