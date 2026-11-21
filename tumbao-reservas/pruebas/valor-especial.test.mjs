/** Valor especial al apuntar a mano (21 nov, pedido de Damián: personas que pagaron $12.000 por tarifa especial).
 *  node valor-especial.test.mjs */
import { readFileSync } from 'node:fs';
const leer = (r) => readFileSync(new URL(r, import.meta.url), 'utf8');
const sql = leer('../supabase/migrations/0213_valor_especial_al_apuntar.sql').replace(/--.*$/gm, '');
const w = leer('../../tumbao-caja/src/index.js');
const adm = leer('../../docs/admin.html');
let fallos = 0;
const ok = (n, c) => { if (!c) fallos++; console.log(`${c ? '✓' : '✗'} ${n}`); };

ok('la reserva guarda el valor especial y su motivo, entre $1.000 y $100.000',
   /add column if not exists valor_especial int check \(valor_especial is null or valor_especial between 1000 and 100000\)/.test(sql) && /valor_especial_motivo text/.test(sql));
ok('valor_reserva manda con lo especial (cierre y ventas lo cuentan)', /select r\.valor_especial from reservas r where r\.id = p_id/.test(sql));
ok('solo clase suelta, rango válido y motivo obligatorio si no es el precio normal',
   /VALOR_SOLO_SUELTA/.test(sql) && /VALOR_INVALIDO/.test(sql) && /MOTIVO_VALOR_OBLIGATORIO/.test(sql) && /if p_valor <> v_normal then/.test(sql));
ok('el motivo se pide ANTES de tomar el cupo (no queda una reserva a medias)', sql.indexOf('MOTIVO_VALOR_OBLIGATORIO') < sql.indexOf('v_r := tomar_cupo'));
ok('el efectivo entra a la caja por el valor especial y queda en la auditoría con el motivo',
   /caja_registrar\(\s*p_token, 'ingreso', 'clase_suelta', v_precio/.test(sql) && /VALOR ESPECIAL/.test(sql));
ok('quien paga al llegar se cobra por su valor, no por el de la clase', /valor_reserva\(v_res\.id\), ''efectivo''/.test(sql) && /valor_reserva\(r\.id\)/.test(sql));
ok('no es promo: se puede reprogramar y la lista de la puerta lo marca «especial»', /r\.valor_especial is null then/.test(sql) && /then ''especial''/.test(sql));
ok('no borra nada', !/\bdrop\s+(table|function|index|column|constraint)|\bdelete\s+from/i.test(sql));
ok('el Worker manda valor y motivo, solo con clase suelta', /p_valor: \(b\.tipo !== 'miembro'/.test(w) && /p_motivo_valor:/.test(w));
ok('admin: botón «Cobró otro valor» con valor y motivo obligatorios, solo con clase suelta',
   /id="ap-especial"/.test(adm) && /id="ap-valor"/.test(adm) && /id="ap-valor-motivo"/.test(adm) && /Falta el motivo/.test(adm)
   && /\$\('#ap-valor-caja'\)\.hidden = apTipo === 'miembro'/.test(adm) && /valor: valorEsp, motivo_valor: motivoValor/.test(adm));
console.log(`\n${fallos ? '✗ ' + fallos + ' con problemas' : '✓ todo bien'}`);
process.exit(fallos ? 1 : 0);
