/**
 * Casilla opcional de novedades (0154): «Quiero recibir novedades y promociones de Tumbao por WhatsApp».
 *
 * Es OTRO consentimiento, distinto del habeas data de la reserva: opcional, desmarcado de entrada, y
 * si falla al guardarse no estorba lo que la persona vino a hacer.
 *   1. las dos páginas tienen la casilla, desmarcada y sin `required`, con el mismo texto;
 *   2. los tres formularios (reserva, mensualidad, tiquetera) mandan acepta_novedades;
 *   3. el Worker la guarda por celular después de que lo principal salió bien;
 *   4. la migración es aditiva (tabla nueva, función solo del servidor) y no borra nada;
 *   5. la plantilla de la encuesta existe, sin oferta ni descuento, con la baja.
 *
 *   node novedades.test.mjs
 */
import { readFileSync } from 'node:fs';
const leer = (p) => readFileSync(new URL(p, import.meta.url), 'utf8');

let fallos = 0;
const ok = (n, c) => { if (!c) fallos++; console.log(`${c ? '✓' : '✗'} ${n}`); };
const titulo = t => console.log(`\n-- ${t} ${'-'.repeat(Math.max(0, 54 - t.length))}`);

const index = leer('../../docs/index.html');
const mens = leer('../../docs/mensualidad.html');
const w = leer('../../tumbao-caja/src/index.js');
const sql = leer('../supabase/migrations/0154_acepta_novedades.sql').replace(/--.*$/gm, '');
const TEXTO = /Quiero recibir novedades y promociones de Tumbao por\s+WhatsApp/;
const casilla = (html, id) => (html.match(new RegExp(`<input id="${id}" type="checkbox"([^>]*)>`)) || [])[1];

titulo('1. Las páginas');
{
  ok('index: casilla de novedades, opcional y desmarcada', casilla(index, 'novedades') === '');
  ok('mensualidad: casilla en el formulario de mensualidad, opcional y desmarcada', casilla(mens, 'novedades') === '');
  ok('mensualidad: casilla en el formulario de tiquetera, opcional y desmarcada', casilla(mens, 'tiq-novedades') === '');
  ok('mismo texto en las dos páginas', TEXTO.test(index) && TEXTO.test(mens));
  ok('el habeas de la reserva sigue siendo obligatorio', /<input id="habeas" type="checkbox" required>/.test(index));
  ok('dice que es opcional', /\(opcional\)/.test(index.slice(index.indexOf('id="novedades"'), index.indexOf('id="novedades"') + 400)));
}

titulo('2. Lo que viaja al Worker');
{
  ok('reserva: manda acepta_novedades', /acepta_novedades: \$\('#novedades'\)\.checked/.test(index));
  ok('mensualidad: manda acepta_novedades', /acepta_novedades: \$\('#novedades'\)\.checked/.test(mens));
  ok('tiquetera: manda acepta_novedades', /acepta_novedades: \$\('#tiq-novedades'\)\.checked/.test(mens));
}

titulo('3. El Worker');
{
  ok('guarda por celular con la fuente de cada formulario',
     /registrarNovedades\(env, b, tel, 'reserva'\)/.test(w) && /registrarNovedades\(env, b, tel, 'mensualidad'\)/.test(w) && /registrarNovedades\(env, b, tel, 'tiquetera'\)/.test(w));
  ok('solo si la persona la marcó (true), nunca por defecto', /b\.acepta_novedades === true \|\| b\.acepta_novedades === 'true'/.test(w));
  ok('si falla al guardarse no estorba la reserva (try/catch)', /async function registrarNovedades[\s\S]{0,400}catch \(e\)/.test(w));
  ok('se guarda DESPUÉS de que lo principal salió bien',
     /!r \|\| !r\.ok\)[\s\S]{0,900}await registrarNovedades\(env, b, tel, 'reserva'\)/.test(w));
}

titulo('4. La migración 0154');
{
  ok('tabla nueva, por celular, con la fuente', /create table if not exists public\.acepta_novedades/.test(sql) && /telefono\s+text primary key/.test(sql) && /fuente\s+text not null/.test(sql));
  ok('sin acceso para anon ni authenticated; solo el servidor escribe', /enable row level security/.test(sql) && /revoke all on table public\.acepta_novedades from public, anon, authenticated/.test(sql) && /revoke all on function public\.registrar_acepta_novedades\(text, text\) from public, anon, authenticated/.test(sql));
  ok('aditiva: no borra ni altera tablas existentes', !/\bdrop\b/i.test(sql) && !/\bdelete\b/i.test(sql) && !/alter table(?! public\.acepta_novedades)/i.test(sql));
  ok('rechaza celulares inválidos y fuentes desconocidas', /t !~ '\^3\[0-9\]\{9\}\$'/.test(sql) && /p_fuente not in/.test(sql));
}

titulo('5. La plantilla encuesta_regreso');
{
  const i = w.indexOf("name: 'encuesta_regreso'");
  const t = w.slice(i, i + 1600);
  ok('existe, es MARKETING y en español', i > 0 && /language: 'es'/.test(t) && /category: 'MARKETING'/.test(t));
  ok('pregunta qué ha impedido volver', /¿Qué te ha impedido volver\?/.test(t));
  ok('las cuatro respuestas rápidas y la baja', ['Horario', 'Precio', 'Tiempo', 'Otra razón', 'No quiero más mensajes'].every(b => t.includes(`text: '${b}'`)));
  ok('sin descuento ni oferta (Damián, 27 sep)', !/descuento|promoci|gratis|\$\s?\d/i.test(t.slice(t.indexOf('BODY'), t.indexOf('FOOTER'))));
}

console.log(fallos ? `\n${fallos} fallo(s)` : '\nTodo bien');
process.exit(fallos ? 1 : 0);
