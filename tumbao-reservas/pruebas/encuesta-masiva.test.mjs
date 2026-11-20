/** Encuesta masiva (2 nov): plantilla, campaña y chat «Tumbao opina» de 5 preguntas, anónimo.   node encuesta-masiva.test.mjs */
import { readFileSync } from 'node:fs';
const leer = (r) => readFileSync(new URL(r, import.meta.url), 'utf8');
const caja = leer('../../tumbao-caja/src/index.js'), opina = leer('../../tumbao-opina/src/index.js'), ui = leer('../../tumbao-opina/public/index.html');
const mig = leer('../supabase/migrations/0197_encuesta_masiva.sql');
let fallos = 0;
const ok = (n, c) => { if (!c) fallos++; console.log(`${c ? '✓' : '✗'} ${n}`); };
const titulo = t => console.log(`\n-- ${t} ${'-'.repeat(Math.max(0, 54 - t.length))}`);

titulo('1. Plantilla y campaña');
const a = caja.indexOf("name: 'encuesta_tumbao'"), t = caja.slice(a, caja.indexOf('\n  },\n', a));
ok('la plantilla lleva a Tumbao opina, dice que es anónimo y deja salir', /opina\.tumbaobaila\.com/.test(t) && /anónimo/.test(t) && /No quiero más mensajes/.test(t));
ok('sin descuentos ni regalos', !/descuento|regalo|gratis|premio/i.test(t));
ok('la campaña respeta bajas, dueñas, campañas recientes y no repite', /wa_bajas/.test(mig) && /wa_es_dueno/.test(mig) && /interval '2 days'/.test(mig) && /plantilla='encuesta_tumbao'/.test(mig) && /on conflict \(clave\) do nothing/.test(mig));
ok('con p_ejecutar en false solo cuenta', /where p_ejecutar/.test(mig) && /default false/.test(mig));

ok('3 nov: reactivar la encuesta va solo por la ventana de 24 h, una vez por persona y sin ofertas',
   /'\/wa\/reactivar-encuesta'/.test(caja) && /encuesta_reactivar_lista/.test(caja) && /p_marcar: true/.test(caja) &&
   !/descuento|regalo|gratis|promoci/i.test(caja.slice(caja.indexOf('export function textoReactivarEncuesta'), caja.indexOf('async function reactivarEncuesta'))));

titulo('2. El chat de Tumbao opina');
const g = opina.slice(opina.indexOf('  escuchamos: {'), opina.indexOf('  aniversario: {'));
ok('son cinco preguntas y dos extras opcionales (horario y música)', /nucleo: 5/.test(g) && /otro horario/.test(g) && /música o ritmos/.test(g) && (g.slice(g.indexOf('preguntas: [')).match(/^      '/gm) || []).length === 7);
ok('dice que es anónimo y que el contacto es opcional y al final', /anónimo/.test(g) && /solo si quieres/.test(g));
ok('tiene una regla de seguridad y de decir la verdad si preguntan si es un robot', /SEGURIDAD Y CONFIANZA/.test(g) && /asistente virtual de Tumbao/.test(g));
ok('profundiza con UNA pregunta de seguimiento y pide ejemplos concretos', /UNA pregunta de seguimiento/.test(g) && /ejemplos concretos/.test(g));
ok('cierra solo con las cinco respuestas y lo del contacto', /nucleo \|\| .*preguntas\.length\) \+ 1/.test(opina));

titulo('3. La página');
ok('muestra que es anónimo, el avance «Pregunta N de 5» y un avatar', /🔒 Anónimo/.test(ui) && /Pregunta ' \+ \(dijo \+ 1\) \+ ' de ' \+ PREGUNTAS/.test(ui) && /class="avatar"/.test(ui));
ok('los puntitos de «escribiendo» se quedan un rato para que se sienta una persona', /const espera = Math\.min\(1900/.test(ui));
ok('al cerrar agradece y dice que se usará para mejorar en 2027', /subir el nivel en 2027/.test(ui));

console.log(`\n${fallos ? '✗ ' + fallos + ' con problemas' : '✓ todo bien'}`);
process.exit(fallos ? 1 : 0);
