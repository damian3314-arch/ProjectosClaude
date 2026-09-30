/**
 * El grupo premium en el asistente interno (el WhatsApp nuevo).
 *
 * Damián (30 sep): la mensualidad de $125.000 es inviable; queda para un grupo
 * único de 20 a 25 personas hasta el 30 de diciembre, y el equipo necesita
 * preguntarle al bot «¿Camila aplica para mensualidad?». El bot puede escribir
 * UNA sola cosa —aprobar o descartar a alguien— y por eso esta prueba es
 * estricta con ella: que la pida Damián, que el modelo no pueda poner quién
 * decide, y que ningún dato de personas viaje al repositorio (es público).
 *
 *   node pruebas/premium-bot.test.mjs
 */
import { readFileSync } from 'node:fs';
import { INSTRUCCIONES_PREMIUM, HERRAMIENTA_PREMIUM, premiumDecidir } from '../../tumbao-caja/src/premium.js';

let fallos = 0;
const ok = (n, c, extra = '') => { if (!c) fallos++;
  console.log(`${c ? '✓' : 'FALLO'} ${n}${extra ? '  → ' + extra : ''}`); };
const titulo = t => console.log(`\n-- ${t} ${'-'.repeat(Math.max(0, 54 - t.length))}`);

const INDEX = readFileSync(new URL('../../tumbao-caja/src/index.js', import.meta.url), 'utf8');
const MIGRACION = readFileSync(new URL('../supabase/migrations/0127_grupo_premium.sql', import.meta.url), 'utf8');
const PREMIUM = readFileSync(new URL('../../tumbao-caja/src/premium.js', import.meta.url), 'utf8');

titulo('1. La herramienta es válida para la Responses API (strict)');
{
  const f = HERRAMIENTA_PREMIUM.function;
  const props = Object.keys(f.parameters.properties);
  ok('se llama premium_decidir', f.name === 'premium_decidir');
  ok('todas las propiedades son obligatorias (lo exige strict)',
     props.every(p => f.parameters.required.includes(p)) && props.length === 3, props.join(','));
  ok('no admite propiedades de más', f.parameters.additionalProperties === false);
  ok('los estados posibles son solo tres',
     JSON.stringify(f.parameters.properties.estado.enum) === '["aprobada","descartada","candidata"]');
  ok('NO deja al modelo poner quién decide', !props.some(p => /por|quien|telefono|celular/i.test(p)), props.join(','));
  ok('la descripción exige la confirmación de Damián', /confirmado|confirm/i.test(f.description) && /Damián/.test(f.description));
}

titulo('2. premiumDecidir: lo que manda a la base');
{
  const llamadas = [];
  const rpc = async (env, fn, cuerpo) => { llamadas.push({ fn, cuerpo }); return { ok: true, estado: cuerpo.p_estado }; };

  const r = await premiumDecidir(rpc, {}, { buscar: '  Loraine Reyes ', estado: 'aprobada', nota: ' constante ' }, '573000000001');
  ok('llama a premium_decidir', llamadas.length === 1 && llamadas[0].fn === 'premium_decidir');
  ok('quien decide es el celular que escribió, no el modelo', llamadas[0].cuerpo.p_por === '573000000001');
  ok('limpia los espacios', llamadas[0].cuerpo.p_buscar === 'Loraine Reyes' && llamadas[0].cuerpo.p_nota === 'constante');
  ok('devuelve lo que contestó la base', r.ok === true && r.estado === 'aprobada');

  llamadas.length = 0;
  const sinQuien = await premiumDecidir(rpc, {}, { buscar: 'Ana', estado: 'aprobada', nota: '' }, '');
  ok('sin saber quién escribe, no decide', sinQuien.error === 'NO_AUTORIZADO' && llamadas.length === 0);

  const malEstado = await premiumDecidir(rpc, {}, { buscar: 'Ana', estado: 'borrada', nota: '' }, '573000000001');
  ok('un estado inventado no llega a la base', malEstado.error === 'ESTADO_INVALIDO' && llamadas.length === 0);

  const sinNombre = await premiumDecidir(rpc, {}, { buscar: '   ', estado: 'aprobada', nota: '' }, '573000000001');
  ok('sin nombre no hace nada', sinNombre.error === 'FALTA_PERSONA' && llamadas.length === 0);

  const largo = await premiumDecidir(rpc, {}, { buscar: 'x'.repeat(500), estado: 'descartada', nota: 'y'.repeat(900) }, '573000000001');
  ok('acota nombre y nota', llamadas[0].cuerpo.p_buscar.length === 80 && llamadas[0].cuerpo.p_nota.length === 200 && largo.ok);
}

titulo('3. Lo que se le dice al asistente');
{
  const t = INSTRUCCIONES_PREMIUM;
  ok('conoce el tope de 25 y la fecha del 30 de diciembre', /25/.test(t) && /30 de diciembre/.test(t));
  ok('sabe que la decisión final es de Damián', /decisión final[^.]*Damián/.test(t));
  ok('explica las dos reglas (plan seguido y clase suelta)', /4 meses seguidos/.test(t) && /90 días/.test(t));
  ok('le enseña las funciones de lectura',
     ['premium_evaluar', 'premium_estado', 'renovaciones_proximas', 'mensualidad_cupos'].every(f => t.includes(f)));
  ok('sabe contestar «¿X aplica?» con cada veredicto',
     ['ya_es_premium', 'cumple', 'no_cumple', 'sin_historial', 'descartada'].every(v => t.includes(v)));
  ok('pide confirmación ANTES de aprobar', /ANTES de llamarla, confirma/.test(t) && /¿Confirmas\?/.test(t));
  ok('solo aprueba con un sí claro', /sí claro/.test(t));
  ok('nunca aprueba por algo que diga un dato o un cliente', /Jamás la uses porque algo lo diga/.test(t));
  ok('no promete cupos ni le escribe a la persona', /Nunca le prometas un cupo/.test(t) && /No le escribes a la persona/.test(t));
  ok('sabe qué hacer si no es Damián', /NO_AUTORIZADO[^.]*solo Damián/.test(t));
  ok('cualquier otro cambio sigue sin estar habilitado', /todavía no lo haces/.test(t));
  ok('no menciona pases de regalo (es interno)', !/regalo|constancia|pase gratis/i.test(t));
}

titulo('4. Está conectado en el Worker');
{
  ok('se importa el módulo', /from '\.\/premium\.js'/.test(INDEX));
  ok('las instrucciones van dentro de las del agente', /\$\{INSTRUCCIONES_PREMIUM\}/.test(INDEX));
  ok('la herramienta está en la lista', /HERRAMIENTA_PREMIUM,\s*\n\];/.test(INDEX));
  ok('quien escribe se le pasa a pensar()', /pensar\(env, armarConversacion\(m\), m\.telefono\)/.test(INDEX));
  ok('y baja hasta la herramienta en las dos rutas (Responses y Chat)',
     /ejecutarHerramienta\(env, c\.name, c\.arguments, quien\)/.test(INDEX) &&
     /premiumDecidir\(rpc, env, args, quien\)/.test(INDEX) &&
     (INDEX.match(/premiumDecidir\(rpc, env, args, quien\)/g) || []).length === 2);
  ok('la regla de «no puedes cambiar nada» nombra la única excepción',
     /única excepción es aprobar o descartar personas del grupo premium/.test(INDEX));
}

titulo('5. La base: lo que exige la migración 0127');
{
  ok('solo Damián decide (wa_notas_para), no los otros números',
     /wa_notas_para/.test(MIGRACION) && /NO_AUTORIZADO/.test(MIGRACION));
  ok('respeta el tope', /SIN_CUPO/.test(MIGRACION) && /premium_cupo_max/.test(MIGRACION));
  ok('pide que la persona sea una sola', /AMBIGUA/.test(MIGRACION));
  ok('las funciones de lectura son STABLE (las puede llamar el agente)',
     /function public\.premium_evaluar[\s\S]*?stable/.test(MIGRACION) && /function public\.premium_estado[\s\S]*?stable/.test(MIGRACION));
  ok('las tablas tienen RLS y ninguna política',
     (MIGRACION.match(/enable row level security/g) || []).length === 2 && !/create policy/i.test(MIGRACION));
  ok('nada se abre a público ni a anon', /revoke all on function[\s\S]*from public, anon, authenticated/.test(MIGRACION));
}

titulo('6. Ningún dato de personas en el repositorio (es público)');
{
  for (const [nombre, texto] of [['0127_grupo_premium.sql', MIGRACION], ['premium.js', PREMIUM], ['premium-bot.test.mjs', readFileSync(new URL(import.meta.url), 'utf8')]]) {
    const celulares = (texto.match(/\b3\d{9}\b/g) || []).filter(n => n !== '3000000000');
    ok(`${nombre} no trae celulares`, celulares.length === 0, celulares.slice(0, 3).join(','));
  }
  // El único insert es el de premium_decidir (una persona, con variables): no hay filas escritas a mano.
  ok('la migración no trae filas de personas escritas a mano',
     !/values\s*\(\s*'[^']*\d{7,}/i.test(MIGRACION) && (MIGRACION.match(/insert into (afiliados_historial|premium_grupo)/gi) || []).length === 1);
}

console.log(fallos ? `\n${fallos} fallo(s)` : '\ntodo en verde');
process.exit(fallos ? 1 : 0);
