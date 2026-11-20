/** Auditoría de caja (19 nov): motivos obligatorios, apuntar con cómo pagó, liberar sin soporte y «para revisar» en el cierre.
 *  node auditoria-caja.test.mjs */
import { readFileSync } from 'node:fs';
const leer = (r) => readFileSync(new URL(r, import.meta.url), 'utf8');
const mig = leer('../supabase/migrations/0210_auditoria_de_caja.sql');
const sql = mig.replace(/--.*$/gm, '');
const w = leer('../../tumbao-caja/src/index.js');
const adm = leer('../../docs/admin.html');
const idx = leer('../../docs/index.html');
let fallos = 0;
const ok = (n, c) => { if (!c) fallos++; console.log(`${c ? '✓' : '✗'} ${n}`); };
const titulo = t => console.log(`\n-- ${t} ${'-'.repeat(Math.max(0, 54 - t.length))}`);

titulo('1. Nada se libera ni se anula sin motivo');
ok('admin_rechazar con motivo (mín. 5 letras) lo guarda en la reserva y en la auditoría (parcha la función existente)',
   /admin_rechazar\(p_token text, p_codigo text, p_motivo text\)/.test(mig) && /length\(v_motivo\) < 5/.test(mig)
   && /motivo_rechazo = v_motivo/.test(mig) && /auditar\(v_admin, ''liberar_reserva''/.test(mig) && /parche de admin_rechazar no aplicó/.test(mig));
ok('la versión de dos argumentos ya no libera: devuelve MOTIVO_OBLIGATORIO',
   /function public\.admin_rechazar\(p_token text, p_codigo text\)\s+returns jsonb[\s\S]*?MOTIVO_OBLIGATORIO/.test(sql));
ok('caja_anular con motivo lo guarda (anulado_motivo) y lo audita',
   /function public\.caja_anular\(p_token text, p_id uuid, p_motivo text\)/.test(sql) && /anulado_motivo = left\(btrim\(p_motivo\), 200\)/.test(sql)
   && /auditar\(v_admin, 'anular_movimiento'/.test(sql));
ok('el Worker no manda a rechazar ni a anular sin motivo',
   /rechazar:\s*\{ fn: 'admin_rechazar'[\s\S]*?MOTIVO_OBLIGATORIO/.test(w) && /p_motivo: motivoAnular/.test(w) && /motivoAnular\.length < 5/.test(w));
ok('el panel pide el motivo al liberar un cupo, al rechazar desde la cola y al anular un movimiento',
   /function pedirMotivo/.test(adm) && /pedirMotivo\(\s*`¿Liberar el cupo/.test(adm) && /pedirMotivo\(`¿Rechazar la reserva/.test(adm)
   && /pedirMotivo\('¿Anular este movimiento\?'/.test(adm) && /api\('rechazar', \{ codigo: p\.codigo, motivo \}\)/.test(adm)
   && /alWorker\('anular', \{ id: an\.dataset\.anular, motivo \}\)/.test(adm));
ok('deshacer también deja huella', /auditar\(v_admin, ''deshacer''|auditar\(v_admin, 'deshacer'/.test(mig));

titulo('2. Apuntar a mano: cómo pagó, sí o sí');
ok('sin medio de pago no se apunta una clase suelta', /MEDIO_OBLIGATORIO/.test(sql) && /p_tipo <> 'miembro' and v_medio is null/.test(sql));
ok('la transferencia exige número de comprobante y no deja repetirlo',
   /COMPROBANTE_OBLIGATORIO/.test(sql) && /REFERENCIA_REPETIDA/.test(sql) && /referencia_pago = left\(v_comp, 60\)/.test(sql));
ok('el efectivo sigue entrando a la caja en la misma llamada', /caja_registrar\(\s*p_token, 'ingreso', 'clase_suelta', v_precio, 'efectivo'/.test(sql));
ok('el panel pide el comprobante cuando es transferencia y lo manda al Worker',
   /id="ap-comprobante"/.test(adm) && /comprobante\.replace\(\/\\s\/g, ''\)\.length < 4/.test(adm) && /comprobante: apMedio === 'transferencia'/.test(adm)
   && /String\(b\.comprobante\)\.slice\(0, 60\)/.test(w));

titulo('3. Sin soporte por WhatsApp, el cupo se libera');
ok('verificando / pendiente_validacion sin pago y sin imagen o documento por WhatsApp se liberan solas',
   /r\.estado in \('verificando', 'pendiente_validacion'\)/.test(sql) && /m\.tipo in \('image', 'document'\)/.test(sql)
   && /validacion_max_min/.test(sql) && /estado = 'expirada', motivo_rechazo = 'Sin soporte por WhatsApp/.test(sql));
ok('devuelve el cupo a la clase y deja la huella', /cupo_tomado = greatest\(0, c\.cupo_tomado - p\.n\)/.test(sql) && /'liberar_sin_soporte'/.test(sql));
ok('la página y el Worker le dicen claro que, sin soporte, el cupo se libera',
   /si no lo compartes, tu cupo se libera/.test(idx) && (idx.match(/si no lo compartes, tu cupo se libera/g) || []).length >= 2
   && /si no\s*\+?\s*'lo compartes, tu cupo se libera/.test(w.replace(/\s+/g, ' ').replace(/' \+ '/g, '')) || /tu cupo se libera/.test(w));

titulo('4. El registro queda, el cierre no cambia');
ok('auditoria_del_dia existe para consultar liberadas, anulaciones, recepción sin respaldo y comprobantes repetidos',
   /function public\.auditoria_del_dia/.test(sql) && /'recepcion_sin_respaldo'/.test(sql) && /'comprobantes_repetidos'/.test(sql) && /'por_revisar'/.test(sql));
ok('el cierre NO se toca: caja_del_dia no se parcha y el panel no pinta tarjeta de auditoría',
   !/caja_del_dia/.test(sql) && !/tarjetaAuditoria/.test(adm));
ok('Timba sabe consultar el registro (caja_auditoria)', /caja_auditoria/.test(w) && /auditoria_del_dia\('AAAA-MM-DD'\)/.test(w));
ok('no borra nada: sin DROP ni DELETE', !/\bdrop\s+(table|function|index|column)|\bdelete\s+from/i.test(sql));

console.log(`\n${fallos ? '✗ ' + fallos + ' con problemas' : '✓ todo bien'}`);
process.exit(fallos ? 1 : 0);
