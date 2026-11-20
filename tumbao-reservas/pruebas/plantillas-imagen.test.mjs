/**
 * Plantillas con imagen y fotos para quien responde (2 nov).   node plantillas-imagen.test.mjs
 */
import { readFileSync, existsSync } from 'node:fs';
const caja = readFileSync(new URL('../../tumbao-caja/src/index.js', import.meta.url), 'utf8');
const mig = readFileSync(new URL('../supabase/migrations/0196_plantillas_con_imagen_y_prueba_ab.sql', import.meta.url), 'utf8');
let fallos = 0;
const ok = (n, c) => { if (!c) fallos++; console.log(`${c ? '✓' : '✗'} ${n}`); };
const titulo = t => console.log(`\n-- ${t} ${'-'.repeat(Math.max(0, 54 - t.length))}`);

titulo('1. Plantillas con imagen');
for (const n of ['rumbo_2027_imagen', 'tiquetera_premio_imagen']) {
  const a = caja.indexOf(`name: '${n}'`), b = caja.indexOf("\n  },\n", a), t = caja.slice(a, b);
  ok(`${n}: encabezado de imagen, pie, enlace y botón para no recibir más`, /type: 'HEADER', format: 'IMAGE', _url: 'https:\/\/tumbaobaila\.com\/img\/campana\//.test(t) && /FOOTER/.test(t) && /URL/.test(t) && /No quiero más mensajes/.test(t));
  ok(`${n}: sin descuentos, regalo ni obsequio`, !/descuento|regalo|obsequio|gratis/i.test(t));
  const f = (t.match(/_url: '([^']+)'/) || [])[1] || '';
  ok(`${n}: la imagen existe en la página (docs/img/campana)`, existsSync(new URL('../../docs/img/campana/' + f.split('/').pop(), import.meta.url)));
}
ok('el envío manda el encabezado con la imagen cuando la plantilla lo tiene', /IMAGEN_PLANTILLA\[a\.plantilla\]/.test(caja) && /type: 'header', parameters: \[\{ type: 'image'/.test(caja));
ok('la muestra se sube a Meta con la carga reanudable y el id de la app', /conMuestraDeImagen/.test(caja) && /\/uploads\?file_length=/.test(caja) && /header_handle: \[sub\.h\]/.test(caja));

titulo('2. A quien responde se le comparte la imagen');
ok('solo en su primera respuesta, sin salidas ni pasos a recepción, y una sola vez', /Number\(chat\.turnos \|\| 0\) === 0 && !pasar && resultado !== 'no_interesado'/.test(caja));
ok('hay imagen para mensualidad, tiquetera y reactivar', /IMAGEN_RESPUESTA = \{[\s\S]*mensualidad:[\s\S]*tiquetera:[\s\S]*reactivar:/.test(caja));
ok('si la imagen falla, la conversación sigue (catch)', /enviarImagenWA\(env, m\.telefono, img\[0\], img\[1\]\)\.catch/.test(caja));

titulo('3. Prueba A/B');
ok('nace apagada y reparte por dígito impar/par del celular', /'wa_ab_imagen', 'apagado'/.test(mig) && /right\(t,1\)::int % 2 = 1/.test(mig));

console.log(`\n${fallos ? '✗ ' + fallos + ' con problemas' : '✓ todo bien'}`);
process.exit(fallos ? 1 : 0);
