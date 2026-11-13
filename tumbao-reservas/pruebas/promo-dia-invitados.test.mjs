/** Día de invitados (13 nov): 2 cupos por $24.000, el pop-up y que lo cobre la base.   node promo-dia-invitados.test.mjs */
import { readFileSync, existsSync } from 'node:fs';
const leer = (r) => readFileSync(new URL(r, import.meta.url), 'utf8');
const idx = leer('../../docs/index.html'), mig = leer('../supabase/migrations/0206_promo_dos_cupos_dia_de_invitados.sql');
let fallos = 0;
const ok = (n, c) => { if (!c) fallos++; console.log(`${c ? '✓' : '✗'} ${n}`); };
const titulo = t => console.log(`\n-- ${t} ${'-'.repeat(Math.max(0, 54 - t.length))}`);

titulo('1. La página');
ok('la promo es de exactamente 2 cupos, $24.000, solo el 13 de noviembre', /PROMO_DOS: \{ cupos: 2, precio: 24000, desde: '2026-11-13', hasta: '2026-11-13'/.test(idx));
ok('el total usa la promo solo con 2 cupos de suelta ese día (3 cupos siguen a precio normal)', /function promoAplica/.test(idx) && /cuantos === CONFIG\.PROMO_DOS\.cupos\) return Math\.min\(CONFIG\.PROMO_DOS\.precio, normal\)/.test(idx));
ok('el resumen, la cuenta y el botón leen totalGrupo()', (idx.match(/totalGrupo\(\)/g) || []).length >= 3);
ok('el pop-up existe, muestra el flyer y se puede cerrar de tres formas', existsSync(new URL('../../docs/img/promo-dia-de-invitados.jpg', import.meta.url)) && /id="promo-x"/.test(idx) && /id="promo-no"/.test(idx) && /e\.target === pop/.test(idx));
ok('sale una sola vez por navegador y deja de salir al terminar el 13 de noviembre', /tumbao_promo_invitados_1113/.test(idx) && /Date\.parse\('2026-11-14T00:00:00-05:00'\)/.test(idx));
ok('los navegadores automáticos no ven el pop-up (para no tapar las otras pruebas) y ?promo=1 lo fuerza', /navigator\.webdriver/.test(idx) && /promo=1/.test(idx));
ok('el botón lleva a «Clase suelta» y al viernes 13', /opcion\[data-tipo="suelta"\]/.test(idx) && /data-fecha="' \+ P\.dia/.test(idx));

titulo('2. La base cobra, la página solo lo muestra');
ok('promo_total_cupos devuelve 24000 solo con n = 2 y clase dentro del rango, y es apagable', /promo_total_cupos/.test(mig) && /activa/.test(mig));
ok('precio_del_grupo y tomar_cupos la usan', /precio_del_grupo/.test(mig) && /tomar_cupos/.test(mig));

titulo('3. Timba (asistente interno) contesta lo de la promo, cupos y asistencias');
{
  const w = leer('../../tumbao-caja/src/index.js');
  const a = w.slice(w.indexOf('const INSTRUCCIONES_AGENTE'), w.indexOf('const HERRAMIENTAS_AGENTE'));
  ok('conoce la promo de 2 cupos por $24.000 y cómo contar sus reservas (grupos)', /promo_dos_cupos/.test(a) && /24000/.test(a) && /grupo_id/.test(a));
  ok('sabe contar cupos libres y asistencias', /cupo_total . cupo_tomado/.test(a) && /asistencias/.test(a) && /reserva_id/.test(a));
  ok('sabe contar planes y tiqueteras, y usa ventas_entre para la plata', /mensualidades_resumen/.test(a) && /tiqueteras/.test(a) && /ventas_entre/.test(a));
}

console.log(`\n${fallos ? '✗ ' + fallos + ' con problemas' : '✓ todo bien'}`);
process.exit(fallos ? 1 : 0);
