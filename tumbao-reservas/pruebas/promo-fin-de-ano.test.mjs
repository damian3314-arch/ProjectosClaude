/** Promoción de fin de año (24 nov 2026): 45 días de vigencia en mensualidades y tiqueteras, compras hasta el 31 de diciembre.
 *  node promo-fin-de-ano.test.mjs */
import { readFileSync } from 'node:fs';
const leer = (r) => readFileSync(new URL(r, import.meta.url), 'utf8');
const js = leer('../../docs/promo-fin-de-ano.js');
const idx = leer('../../docs/index.html');
const men = leer('../../docs/mensualidad.html');
const adm = leer('../../docs/admin.html');
const mig = leer('../supabase/migrations/0215_promocion_fin_de_ano_45_dias.sql').replace(/--.*$/gm, '');
let fallos = 0;
const ok = (n, c) => { if (!c) fallos++; console.log(`${c ? '✓' : '✗'} ${n}`); };

ok('solo corre del 24 de nov al 31 de dic (hora de Bogotá); ?promo=0 la apaga y ?promo=1 la fuerza',
   /desde: '2026-11-24', hasta: '2026-12-31', dias: 45/.test(js) && /America\/Bogota/.test(js) && /q === '0'\) return/.test(js) && /q === '1'/.test(js));
ok('la cuenta regresiva termina a la medianoche del 31 de diciembre', /Date\.parse\('2027-01-01T00:00:00-05:00'\)/.test(js));
ok('el vencimiento es compra + 45 días calendario (1 dic → 15 ene; 31 dic → 14 feb)', /p\[2\] \+ P\.dias/.test(js));
{
  // Se ejecuta la misma cuenta que usa la página.
  const f = (iso) => { const p = iso.split('-').map(Number); const d = new Date(Date.UTC(p[0], p[1] - 1, p[2] + 45)); return d.toISOString().slice(0, 10); };
  ok('cuentas: 1 dic → 2027-01-15 y 31 dic → 2027-02-14 y 24 nov → 2027-01-08', f('2026-12-01') === '2027-01-15' && f('2026-12-31') === '2027-02-14' && f('2026-11-24') === '2027-01-08');
}
ok('la portada nombra los días sin clase (8, 25, 26, 31 dic; receso 1–5 ene; vuelven el 6)',
   /8 dic<\/span><span>25 dic<\/span><span>26 dic<\/span><span>31 dic<\/span><span>Receso 1–5 ene<\/span><span class="v">Volvemos mié 6 ene/.test(js));
ok('la página de reservas abre un pop-up una vez al día que lleva a /mensualidad (conserva ?r=), y no estorba a las pruebas automáticas',
   /data-modo="pop"/.test(idx) && /promo-fin-de-ano\.js/.test(idx) && /'mensualidad\.html' \+ \(refR/.test(js) && /localStorage\.setItem\(P\.llave, hoyBogota\(\)\)/.test(js) && /!navigator\.webdriver/.test(js));
ok('/mensualidad abre con la portada navideña, y la respuesta «cuánto me dura» sigue la promo',
   /data-modo="hero"/.test(men) && /window\.PROMO_FDA/.test(men) && /renovar-caja/.test(js));
ok('respeta prefers-reduced-motion (sin nieve ni brillos)', /prefers-reduced-motion:reduce/.test(js));
ok('la tiquetera sale con 45 días mientras dure la promo y vuelve sola después (base)',
   /promo_vigencia_fin_anio/.test(mig) && /"vigencia_dias":45/.test(mig) && /greatest\(\(e\.paq->>'vigencia_dias'\)::int/.test(mig) && /between \(a\.valor::jsonb->>'desde'\)::date and \(a\.valor::jsonb->>'hasta'\)::date/.test(mig));
ok('los días de cierre entran como festivos (para que no se abran clases) y no se borra nada',
   /'2026-12-26'/.test(mig) && /'2026-12-31'/.test(mig) && /'2027-01-02'/.test(mig) && /'2027-01-05'/.test(mig) && !/\bdrop\s+(table|function|index|column|constraint)|\bdelete\s+from/i.test(mig));
ok('Timba (asistente, ventas y agente del dueño) conoce la promo y sus fechas',
   ['asistente.js', 'ventas.js', 'index.js'].every(f => /PROMOCIÓN DE FIN DE AÑO[\s\S]{0,400}45 días calendario[\s\S]{0,700}15 de enero[\s\S]{0,200}14 de febrero/.test(leer('../../tumbao-caja/src/' + f))));
ok('/admin: la tiquetera apuntada a mano nace con 45 días durante la promo', /tiq-vigencia"\)\.value="45"/.test(adm) && /"2026-11-24"/.test(adm));
{
  const m16 = leer('../supabase/migrations/0216_constancia_solo_hasta_el_30_de_noviembre.sql').replace(/--.*$/gm, '');
  ok('la clase adicional por constancia solo cuenta para tiqueteras pagadas hasta el 30 de noviembre (las ya compradas la conservan)',
     /pase_constancia_hasta', '2026-11-30'/.test(m16) && /coalesce\(t\.pagado_en, t\.creada_en\)/.test(m16) && /CAMPANA: \{ activa: true, desde: '2026-11-01', hasta: '2026-11-30' \}/.test(men));
  ok('Timba no ofrece la constancia en compras nuevas desde el 1 de diciembre',
     ['asistente.js', 'ventas.js'].every(f => /SOLO PARA TIQUETERAS COMPRADAS HASTA EL 30 DE NOVIEMBRE DE 2026/.test(leer('../../tumbao-caja/src/' + f))));
}
console.log(`\n${fallos ? '✗ ' + fallos + ' con problemas' : '✓ todo bien'}`);
process.exit(fallos ? 1 : 0);
