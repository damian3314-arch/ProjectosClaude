/**
 * Cierre de año (2 nov): «Asegura tu enero», «Regala Tumbao», frecuentes → tiquetera y Timba al público correcto.
 *   node navidad-enero-regalo.test.mjs
 */
import { readFileSync } from 'node:fs';
const leer = (r) => readFileSync(new URL(r, import.meta.url), 'utf8');
const mens = leer('../../docs/mensualidad.html'), admin = leer('../../docs/admin.html'), caja = leer('../../tumbao-caja/src/index.js');
const mig = leer('../supabase/migrations/0194_frecuentes_a_tiquetera_timba_y_mensualidad_de_enero.sql');
let fallos = 0;
const ok = (n, c) => { if (!c) fallos++; console.log(`${c ? '✓' : '✗'} ${n}`); };
const titulo = t => console.log(`\n-- ${t} ${'-'.repeat(Math.max(0, 54 - t.length))}`);

titulo('1. Asegura tu enero');
ok('la sección aparece sola del 15 dic al 3 ene y se fuerza o quita con ?enero', /desde: '2026-12-15', hasta: '2027-01-03'/.test(mens) && /id="esp-enero" hidden/.test(mens));
ok('la mensualidad de enero empieza el lunes 4 de enero y la página lo dice en el pago', /inicio: '2027-01-04'/.test(mens) && /Tu mensualidad empieza el/.test(mens));
ok('la fecha viaja con la solicitud y el servidor la valida antes de guardarla', /inicio: modoEnero \? ENERO\.inicio : undefined/.test(mens) && /mensualidad_fijar_inicio/.test(caja) && /\^\\d\{4\}-\\d\{2\}-\\d\{2\}\$/.test(caja));
ok('la base solo acepta fechas entre el 15 dic y el 28 feb, y solo en solicitudes recientes', /p_inicio < date '2026-12-15' or p_inicio > date '2027-02-28'/.test(mig) && /creado_at > now\(\) - interval '2 days'/.test(mig));
ok('el panel le muestra a recepción desde qué fecha registrarla', /inicio_deseado/.test(admin) && /Empieza el/.test(admin) && /''inicio_deseado'', s\.inicio_deseado/.test(mig));

titulo('2. Regala Tumbao');
ok('la sección aparece del 15 nov al 24 dic', /desde: '2026-11-15', hasta: '2026-12-24'/.test(mens) && /id="esp-regalo" hidden/.test(mens));
ok('al terminar la compra de una tiquetera se puede mandar el código como regalo por WhatsApp', /Enviar como regalo por WhatsApp/.test(mens) && /Te regalo clases en Tumbao/.test(mens));
ok('sin descuentos ni promesas nuevas: mismo precio', /Mismo precio/.test(mens) && !/descuento/i.test(mens.match(/id="esp-regalo"[\s\S]*?<\/section>/)[0]));

titulo('3. Frecuentes → tiquetera y Timba');
ok('la campaña usa la plantilla aprobada, los filtros de siempre y es idempotente', /'tiquetera_frecuentes'/.test(mig) && /wa_bajas/.test(mig) && /on conflict \(clave\) do nothing/.test(mig) && /wa_es_dueno/.test(mig));
ok('el cron diario se detiene solo el 20 de noviembre', /current_date <= date ''2026-11-20''/.test(mig));
ok('Timba pone a los frecuentes sin plan en prioridad 3 (antes 7)', /objetivo = ''tiquetera'' then 3 else/.test(mig));

console.log(`\n${fallos ? '✗ ' + fallos + ' con problemas' : '✓ todo bien'}`);
process.exit(fallos ? 1 : 0);
