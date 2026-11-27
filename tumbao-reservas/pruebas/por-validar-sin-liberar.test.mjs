/** 27 nov (0224): «ya pagué» se queda en Por validar, Timba pide el comprobante y se vigila el correo del banco. node por-validar-sin-liberar.test.mjs */
import { readFileSync } from 'node:fs';
const leer = (r) => readFileSync(new URL(r, import.meta.url), 'utf8');
const crudo = leer('../supabase/migrations/0224_por_validar_no_se_libera_y_seguimiento_del_banco.sql');
const m = leer('../supabase/migrations/0224_por_validar_no_se_libera_y_seguimiento_del_banco.sql').replace(/--.*$/gm, '');
const w = leer('../../tumbao-caja/src/index.js');
let fallos = 0;
const ok = (n, c) => { if (!c) fallos++; console.log(`${c ? '✓' : '✗'} ${n}`); };
ok('sin soporte solo se libera después de terminar la clase', /cl\.fecha_hora \+ make_interval\(mins => coalesce\(cl\.duracion_min, 60\)\) < now\(\)/.test(crudo));
ok('la reserva en espera se recuerda a los 8 y a los 90 minutos, una vez cada paso, y se cancela si se confirma',
   /interval '8 minutes'/.test(m) && /interval '90 minutes'/.test(m) && /recordatorio_comprobante:' \|\| e\.id \|\| ':' \|\| e\.paso/.test(m) && /ya_confirmada/.test(m));
ok('nace esperando plantilla y respeta bajas, dueños y uno por hora', /'esperando_plantilla'/.test(m) && /wa_bajas/.test(m) && /wa_es_dueno/.test(m) && /interval '60 minutes'/.test(m));
ok('seguimiento del banco: log cada 10 min y nota con máximo una por hora', /banco_correo_log/.test(m) && /\*\/10 11-23,0-2/.test(m) && /'banco-sin-correo:' \|\| to_char\(now\(\) at time zone 'America\/Bogota', 'YYYY-MM-DD-HH24'\)/.test(m));
ok('no borra nada', !/\bdrop\b|\bdelete\b/i.test(m));
const i = w.indexOf("name: 'reserva_comprobante_pendiente'");
const t = i < 0 ? '' : w.slice(i, i + 1400);
ok('plantilla de UTILIDAD: espera de validación, comprobante a recepción 301 783 3550, «si ya lo enviaste respóndeme», sin garantía de cupo',
   /category: 'UTILITY'/.test(t) && /en espera de validación/.test(t) && /301 783 3550/.test(t) && /Si ya lo enviaste, respóndeme/.test(t) && /no podemos garantizar tu cupo/.test(t) && !/descuento|promo|oferta/i.test(t));
ok('el Worker enciende el aviso cuando Meta aprueba la plantilla', /wa_recordar_comprobante_activar/.test(w) && /activarRecordatorioComprobante\(env\)\.catch/.test(w) && /'\/wa\/recordar-comprobante'/.test(w));
console.log(fallos ? '\n✗ fallos' : '\n✓ todo bien'); process.exit(fallos ? 1 : 0);
