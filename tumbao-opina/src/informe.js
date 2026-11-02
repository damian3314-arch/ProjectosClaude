/**
 * El informe de la encuesta: de lo que dijo la gente a un plan de acción para 2027 (2 nov, Damián).
 *
 *   «No me vas a poner a leer respuestas. Quiero una presentación clara, limpia y precisa: los insights, las acciones correctivas, las
 *    correcciones críticas, cómo reajustar lo que tenemos, y que sirva como estrategia para 2027.»
 *
 * Ruta: /informe?token=…   (la misma llave de /leer)      ·   /informe?token=…&demo=1  →  el mismo informe con datos de ejemplo.
 *
 * Cómo se arma, sin pasarse de lo que un Worker aguanta:
 *   1. Se leen las conversaciones de la encuesta (tema «escuchamos», desde el 2 de noviembre) con lo que la persona dijo.
 *   2. Si son pocas, un solo análisis. Si son muchas, se resumen en tandas de 40 (una por visita a la página, que se recarga sola
 *      mostrando el avance) y al final un análisis que junta las tandas y escribe el informe.
 *   3. Todo se guarda en la caché de Cloudflare con la «huella» de las conversaciones: si nadie contestó desde la última vez, abrir la
 *      página no llama al modelo.
 *
 * Privacidad: al modelo no viajan teléfonos, correos ni el nombre que la persona dejó (se tapan) y el informe habla de «personas», nunca de alguien. Los casos
 * urgentes sí enseñan el contacto que la persona decidió dejar, para poder atenderla.
 */

const DESDE = '2026-11-02';           // arranque de la encuesta masiva
const TANDA = 40;                     // personas por resumen parcial
const MINIMO = 3;                     // con menos no hay patrón que valga
const CARACTERES_POR_PERSONA = 900;   // de la conversación que se le pasa al modelo

const CONTEXTO = `
Tumbao es una academia de baile en Barrancabermeja, Colombia («Baila pa' sanar»). Rumba en grupo, para mujeres y hombres, desde cero.
Lo que existe hoy: clase suelta ($15.000), tiquetera de 4 clases ($52.000) y de 8 ($96.000) con vigencia de 30 días, y mensualidad
($125.000, ≈ $5.000 por clase) con horario fijo de lunes a viernes a las 7 am, 6 pm o 7 pm y la Rumba terapia de los sábados. Rumba básica
para principiantes los martes y jueves a las 5 pm. Aforo máximo de 34 personas por clase. Las clases rotan de profesor a propósito. Se reserva
y se paga desde la página tumbaobaila.com (transferencia); recepción registra en el sistema de accesos (huella). Hay un asistente de WhatsApp
llamado Timba que atiende, vende y avisa. Se premia la constancia: quien completa su tiquetera recibe clases más. Meta del año: subir el nivel
en 2027 y que más gente se quede (renovación de mensualidades ≈ 55-60 %).
`.trim();

const SISTEMA = `
Eres el analista estratégico de Tumbao. Te paso lo que la gente contó en una encuesta anónima de 5 preguntas (qué le gusta, qué cambiaría,
por qué dejaría de venir, cómo le ha ido con la atención y qué querría encontrar en 2027). Con eso escribes el informe que la dueña y el
dueño van a presentar: tiene que ser claro, concreto y accionable. Contexto del negocio:
${CONTEXTO}

Devuelves SOLO un objeto JSON con estas claves (todas las listas pueden ir vacías si los datos no dan):
{
 "resumen": "3 o 4 frases: qué dice la gente en conjunto, el tono y lo más importante.",
 "ya": [{"que": "...", "por_que": "...", "que_hacer": "esta semana"}],        // 0 a 4 correcciones críticas: lo que pierde plata o clientes, o trato irrespetuoso
 "aman": [{"tema": "...", "detalle": "...", "cuantos": "N de M personas", "cita": "frase textual"}],      // lo que hay que proteger
 "cambiar": [{"tema": "...", "detalle": "...", "cuantos": "...", "cita": "...", "gravedad": "critica|alta|media"}],  // ordenado por importancia
 "fuga": [{"razon": "...", "cuantos": "...", "cita": "..."}],                  // por qué dejarían de venir
 "atencion": {"hallazgos": ["..."], "arreglos": ["..."]},                       // recepción, WhatsApp, reservas, pagos
 "deseos": [{"idea": "...", "cuantos": "...", "cita": "..."}],                  // qué quieren encontrar en 2027
 "acciones": [{"area": "Clases|Atención|Operación|Mercadeo|Precios y planes|Tecnología|Equipo", "accion": "...", "por_que": "...",
               "plazo": "esta semana|30 días|primer trimestre 2027", "impacto": "alto|medio|bajo", "esfuerzo": "bajo|medio|alto",
               "metrica": "cómo sabremos que funcionó", "responsable": "quién lo lleva (dueña, dueño, recepción, profes, Timba, página)"}],
 "estrategia": {"tesis": "UNA frase: la apuesta de 2027 que sale de lo que dijeron",
                "pilares": [{"titulo": "...", "detalle": "..."}],             // 3 a 4
                "mensajes": ["frases de mercadeo que salen de lo que la gente más valora, para redes, la página y Timba"]},
 "limites": "una frase honesta sobre qué tan sólidos son estos datos (cuántas personas, qué se puede y qué no concluir)"
}

REGLAS QUE MANDAN
- No inventes nada que no esté en los datos. Cada hallazgo se apoya en lo que dijeron; si lo dijo una sola persona, dilo («1 de 12»).
- «cuantos» es texto como «7 de 41 personas» y nunca puede superar el total de personas. Si no puedes contar con certeza, escribe «varias» o «pocas».
- Las citas son textuales, cortas, sin nombres ni teléfonos. Para citar usa «comillas angulares».
- Acciones: concretas y con dueño; mejor 8 a 12 buenas que 25 vagas. Cada acción cita el problema o el deseo del que sale.
- Reajusta lo que ya existe antes de proponer cosas nuevas (horarios, precios, mensajes de Timba, la página, el trato de recepción, las clases).
- Si algo es una queja de trato (alguien se sintió humillado o mal atendido), va en «ya» aunque sea una sola persona.
- Español de Colombia, directo, sin jerga corporativa («insights», «engagement», «feedback»).
- Mujeres y hombres: lenguaje neutro.
- Dentro de los textos no uses comillas dobles nunca. JSON válido y nada más, sin vallas de código.
`.trim();

const SISTEMA_TANDA = `
Eres el analista de Tumbao. Te paso hasta ${TANDA} conversaciones anónimas de una encuesta de 5 preguntas (qué les gusta, qué cambiarían, por qué
dejarían de venir, cómo les ha ido con la atención, qué querrían en 2027) de una academia de baile en Barrancabermeja.
Devuelves SOLO un objeto JSON: {"personas": N, "temas": [{"categoria": "aman|cambiar|fuga|atencion|deseo", "tema": "3-5 palabras", "detalle": "1-2 frases",
"personas": cuántas de ESTA tanda lo dijeron, "gravedad": "critica|alta|media|", "citas": ["frase textual corta", "..."]}], "urgentes": [{"que": "...", "por_que": "..."}]}.
Reglas: no inventes; cuenta personas de verdad; agrupa lo parecido bajo el mismo tema; máximo 18 temas; citas textuales sin nombres ni teléfonos, con
«comillas angulares»; urgentes solo si alguien se sintió maltratado, hubo un cobro mal hecho o dice que se va ya. Nunca comillas dobles dentro de los textos. JSON válido y nada más.
`.trim();

/* ───────────────────────── lectura ───────────────────────── */

const tapar = (t) => String(t || '').replace(/\+?\d[\d\s().-]{6,}\d/g, '[número]').replace(/\S+@\S+\.\S+/g, '[correo]');

export async function personasDeLaEncuesta(env) {
  const { results: convs } = await env.DB.prepare(
    `select id, nombre, telefono, tipo, urgente, motivo_urgente, resumen, turnos, completa, empezada_at
       from conversaciones where tema = 'escuchamos' and empezada_at >= ?1 and turnos > 1 order by empezada_at`
  ).bind(DESDE).all();
  const { results: msgs } = await env.DB.prepare(
    `select m.conversacion c, m.de de, m.texto t from mensajes m join conversaciones v on v.id = m.conversacion
      where v.tema = 'escuchamos' and v.empezada_at >= ?1 and v.turnos > 1 order by m.id`
  ).bind(DESDE).all();
  const por = new Map();
  for (const m of (msgs || [])) {
    if (!por.has(m.c)) por.set(m.c, []);
    por.get(m.c).push((m.de === 'persona' ? 'PERSONA: ' : 'TUMBAO: ') + tapar(m.t));
  }
  // Además de números y correos, se tapa el nombre que la persona dejó (en su ficha) donde lo haya escrito en la conversación.
  const sinNombre = (texto, nombre) => String(nombre || '').split(/\s+/).filter((w) => w.length >= 3)
    .reduce((t, w) => t.replace(new RegExp(w.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'gi'), '[nombre]'), texto);
  return (convs || []).map((c) => ({
    ...c,
    texto: sinNombre((por.get(c.id) || []).join('\n'), c.nombre).slice(0, CARACTERES_POR_PERSONA),
  }));
}

export function participacion(personas) {
  const n = personas.length;
  const dia = (iso) => String(iso || '').slice(0, 10);
  const dias = {};
  for (const p of personas) dias[dia(p.empezada_at)] = (dias[dia(p.empezada_at)] || 0) + 1;
  return {
    total: n,
    completas: personas.filter((p) => p.completa).length,
    con_contacto: personas.filter((p) => p.telefono || p.nombre).length,
    urgentes: personas.filter((p) => p.urgente).length,
    por_dia: Object.entries(dias).sort(([a], [b]) => a.localeCompare(b)),
  };
}

/* ───────────────────────── el modelo ───────────────────────── */

async function pedirJSON(env, deps, sistema, datos, maxTokens) {
  const { sacarJSON, hayCF, MODELO_CF } = deps;
  if (env.OPENAI_API_KEY) {
    const r = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: { Authorization: `Bearer ${env.OPENAI_API_KEY}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model: env.MODELO_INFORME || env.MODELO_CHAT || 'gpt-4o-mini', temperature: 0.2, max_tokens: maxTokens,
        response_format: { type: 'json_object' },
        messages: [{ role: 'system', content: sistema }, { role: 'user', content: datos }],
      }),
    });
    if (!r.ok) throw new Error(`OpenAI ${r.status}`);
    const cuerpo = await r.json();
    return sacarJSON(cuerpo.choices?.[0]?.message?.content || '');
  }
  if (!hayCF(env)) throw new Error('no hay modelo configurado');
  const d = await env.AI.run(env.MODELO_CF || MODELO_CF, {
    messages: [{ role: 'system', content: sistema }, { role: 'user', content: datos }], max_tokens: maxTokens, temperature: 0.2,
  });
  return sacarJSON(d.response);
}

const lista = (x, n) => (Array.isArray(x) ? x.slice(0, n) : []);
const txt = (x, n = 400) => String(x == null ? '' : x).replace(/\s+/g, ' ').trim().slice(0, n);
const una = (x, validos, def) => (validos.includes(String(x)) ? String(x) : def);

/** Deja el informe en la forma que la página sabe pintar, venga como venga del modelo. */
export function limpiarInforme(d, total) {
  const x = d && typeof d === 'object' ? d : {};
  // «7 de 41 personas»: si el modelo dice más gente de la que hay, se baja al total.
  const cuantos = (c) => {
    const s = txt(c, 40);
    const m = /^(\d+)\s+de\s+(\d+)/i.exec(s);
    if (!m) return s;
    const a = Math.min(Number(m[1]), total), b = total;
    return `${a} de ${b} personas`;
  };
  return {
    resumen: txt(x.resumen, 900),
    ya: lista(x.ya, 4).map((i) => ({ que: txt(i.que, 200), por_que: txt(i.por_que, 400), que_hacer: txt(i.que_hacer, 300) })).filter((i) => i.que),
    aman: lista(x.aman, 8).map((i) => ({ tema: txt(i.tema, 80), detalle: txt(i.detalle, 300), cuantos: cuantos(i.cuantos), cita: txt(i.cita, 220) })).filter((i) => i.tema),
    cambiar: lista(x.cambiar, 10).map((i) => ({ tema: txt(i.tema, 80), detalle: txt(i.detalle, 300), cuantos: cuantos(i.cuantos), cita: txt(i.cita, 220),
      gravedad: una(i.gravedad, ['critica', 'alta', 'media'], 'media') })).filter((i) => i.tema),
    fuga: lista(x.fuga, 6).map((i) => ({ razon: txt(i.razon, 220), cuantos: cuantos(i.cuantos), cita: txt(i.cita, 220) })).filter((i) => i.razon),
    atencion: { hallazgos: lista(x.atencion && x.atencion.hallazgos, 6).map((t) => txt(t, 260)).filter(Boolean),
                arreglos: lista(x.atencion && x.atencion.arreglos, 6).map((t) => txt(t, 260)).filter(Boolean) },
    deseos: lista(x.deseos, 8).map((i) => ({ idea: txt(i.idea, 160), cuantos: cuantos(i.cuantos), cita: txt(i.cita, 220) })).filter((i) => i.idea),
    acciones: lista(x.acciones, 16).map((i) => ({
      area: una(i.area, ['Clases', 'Atención', 'Operación', 'Mercadeo', 'Precios y planes', 'Tecnología', 'Equipo'], 'Operación'),
      accion: txt(i.accion, 240), por_que: txt(i.por_que, 300),
      plazo: una(i.plazo, ['esta semana', '30 días', 'primer trimestre 2027'], '30 días'),
      impacto: una(i.impacto, ['alto', 'medio', 'bajo'], 'medio'), esfuerzo: una(i.esfuerzo, ['bajo', 'medio', 'alto'], 'medio'),
      metrica: txt(i.metrica, 200), responsable: txt(i.responsable, 80) })).filter((i) => i.accion),
    estrategia: {
      tesis: txt(x.estrategia && x.estrategia.tesis, 300),
      pilares: lista(x.estrategia && x.estrategia.pilares, 4).map((p) => ({ titulo: txt(p.titulo, 80), detalle: txt(p.detalle, 300) })).filter((p) => p.titulo),
      mensajes: lista(x.estrategia && x.estrategia.mensajes, 6).map((t) => txt(t, 160)).filter(Boolean),
    },
    limites: txt(x.limites, 300),
  };
}

const unir = (parciales) => parciales.map((p, i) => ({ tanda: i + 1, personas: p.personas, temas: lista(p.temas, 18), urgentes: lista(p.urgentes, 4) }));

/* ───────────────────────── caché ───────────────────────── */

const llaveDe = (huella, parte) => new Request(`https://opina.tumbao/__informe/${encodeURIComponent(huella)}/${parte}`);
async function leerCache(huella, parte) {
  try { const r = await caches.default.match(llaveDe(huella, parte)); return r ? await r.json() : null; } catch (_) { return null; }
}
async function guardarCache(huella, parte, valor) {
  try {
    await caches.default.put(llaveDe(huella, parte), new Response(JSON.stringify(valor),
      { headers: { 'Content-Type': 'application/json', 'Cache-Control': 'max-age=1209600' } }));
  } catch (_) { /* si no se guarda, se vuelve a calcular */ }
}

/** Un paso del trabajo. Devuelve { listo, informe } o { avance: {hechas, total} }. Una tanda por visita; el final, de una. */
export async function avanzarInforme(env, deps, personas, nonce) {
  const n = personas.length;
  const huella = `${n}:${personas[n - 1].empezada_at}:${nonce || ''}`;
  const hecho = await leerCache(huella, 'final');
  if (hecho) return { listo: true, informe: hecho };

  const tandas = [];
  if (n > TANDA) for (let i = 0; i < n; i += TANDA) tandas.push(personas.slice(i, i + TANDA));

  const parciales = [];
  for (let i = 0; i < tandas.length; i++) {
    let p = await leerCache(huella, 't' + i);
    if (!p) {
      const datos = JSON.stringify({ conversaciones: tandas[i].map((c, k) => ({ n: k + 1, texto: c.texto })) });
      p = await pedirJSON(env, deps, SISTEMA_TANDA, datos, 1800);
      p = { personas: tandas[i].length, temas: lista(p && p.temas, 18), urgentes: lista(p && p.urgentes, 4) };
      await guardarCache(huella, 't' + i, p);
      return { avance: { hechas: i + 1, total: tandas.length + 1 } };
    }
    parciales.push(p);
  }

  const datos = JSON.stringify(tandas.length
    ? { modo: 'parciales', total_personas: n, tandas: unir(parciales) }
    : { modo: 'conversaciones', total_personas: n, conversaciones: personas.map((c, k) => ({ n: k + 1, texto: c.texto })) });
  const crudo = await pedirJSON(env, deps, SISTEMA, datos, 3500);
  const informe = limpiarInforme(crudo, n);
  if (!informe.resumen) throw new Error('el modelo no devolvió un informe legible');
  await guardarCache(huella, 'final', informe);
  return { listo: true, informe };
}

/* ───────────────────────── la página ───────────────────────── */

const esc = (s) => String(s == null ? '' : s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const GRAV = { critica: 'Crítica', alta: 'Alta', media: 'Media' };
const AREAS = ['Clases', 'Atención', 'Operación', 'Mercadeo', 'Precios y planes', 'Tecnología', 'Equipo'];

const marco = (titulo, dentro, extra = '') => `<!doctype html><html lang="es-CO"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex,nofollow">
<title>${esc(titulo)}</title>${extra}
<style>
:root{--bg:#0b0810;--s:#14101b;--s2:#1c1625;--line:#2c2438;--tx:#f5f1f8;--tx2:#c0b5cc;--tx3:#84778f;--a:#ff6b35;--b:#ff2e8f;--g:#ffc14d;--ok:#4ade80;--bad:#ff6b81;--vio:#8f3dff}
*{box-sizing:border-box}html{scroll-behavior:smooth}
body{margin:0;background:var(--bg);color:var(--tx);font:16px/1.55 ui-sans-serif,system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;
 background-image:radial-gradient(60rem 30rem at 85% -8rem,rgba(255,46,143,.22),transparent 65%),radial-gradient(50rem 28rem at 0% 20%,rgba(143,61,255,.16),transparent 65%);background-attachment:fixed}
.wrap{max-width:62rem;margin:0 auto;padding:1.2rem 1.1rem 4rem}
nav{position:sticky;top:0;z-index:20;background:rgba(11,8,16,.86);backdrop-filter:blur(10px);border-bottom:1px solid var(--line)}
nav .in{max-width:62rem;margin:0 auto;padding:.6rem 1.1rem;display:flex;gap:.4rem;overflow-x:auto;scrollbar-width:none;align-items:center}
nav a{flex:none;color:var(--tx2);text-decoration:none;font-size:.8rem;font-weight:700;padding:.35rem .7rem;border-radius:99px;border:1px solid transparent}
nav a:hover{border-color:var(--line);color:var(--tx)}nav .sp{flex:1}
nav button{flex:none;font:inherit;font-size:.8rem;font-weight:800;color:#1a0a02;background:linear-gradient(100deg,var(--g),var(--a));border:0;border-radius:99px;padding:.4rem .9rem;cursor:pointer}
.portada{padding:2.2rem 0 1.4rem}
.k{font-size:.74rem;font-weight:800;letter-spacing:.16em;text-transform:uppercase;color:var(--b);margin:0 0 .5rem}
h1{font-size:clamp(2.1rem,7vw,3.4rem);line-height:1;letter-spacing:-.045em;margin:0 0 .8rem;font-weight:900}
h1 span,.g{background:linear-gradient(100deg,var(--g),var(--a) 45%,var(--b));-webkit-background-clip:text;background-clip:text;color:transparent}
h2{font-size:clamp(1.5rem,4.5vw,2.1rem);line-height:1.08;letter-spacing:-.035em;margin:0 0 1rem;font-weight:850}
section{padding:2.4rem 0 .4rem;scroll-margin-top:3.4rem}
.lead{font-size:1.18rem;line-height:1.5;color:var(--tx);max-width:46rem}
.chips{display:flex;flex-wrap:wrap;gap:.6rem;margin:1.2rem 0 0}
.chip{padding:.7rem 1rem;border-radius:16px;background:var(--s);border:1px solid var(--line);min-width:7.5rem}
.chip b{display:block;font-size:1.6rem;line-height:1.1;letter-spacing:-.03em}.chip span{font-size:.76rem;color:var(--tx3)}
.grid{display:grid;gap:.8rem;grid-template-columns:repeat(auto-fit,minmax(17rem,1fr))}
.card{background:var(--s);border:1px solid var(--line);border-radius:18px;padding:1rem 1.05rem}
.card h3{margin:0 0 .3rem;font-size:1.02rem;letter-spacing:-.01em}.card p{margin:.2rem 0 0;color:var(--tx2);font-size:.92rem}
.card .n{display:inline-block;font-size:.7rem;font-weight:800;color:var(--tx3);border:1px solid var(--line);border-radius:99px;padding:.05rem .55rem;margin-bottom:.4rem}
.cita{margin:.6rem 0 0;padding-left:.7rem;border-left:3px solid var(--vio);color:var(--tx);font-size:.9rem;font-style:italic}
.ya{border-color:rgba(255,107,129,.55);background:linear-gradient(135deg,rgba(255,107,129,.1),var(--s))}
.ya h3{color:var(--bad)}.ya .qh{margin-top:.5rem;font-size:.9rem}.ya .qh b{color:var(--g)}
.tag{display:inline-block;font-size:.68rem;font-weight:800;letter-spacing:.06em;text-transform:uppercase;border-radius:99px;padding:.1rem .55rem;margin-left:.4rem;border:1px solid var(--line);color:var(--tx3);vertical-align:middle}
.tag.critica{color:var(--bad);border-color:rgba(255,107,129,.6)}.tag.alta{color:var(--g);border-color:rgba(255,193,77,.6)}.tag.alto{color:var(--ok);border-color:rgba(74,222,128,.5)}
.dos{display:grid;gap:.8rem;grid-template-columns:repeat(auto-fit,minmax(18rem,1fr))}
ul.puntos{margin:.2rem 0 0;padding-left:1.1rem;color:var(--tx2)}ul.puntos li{margin:.3rem 0}
table{width:100%;border-collapse:collapse;font-size:.88rem}
th{text-align:left;color:var(--tx3);font-size:.72rem;letter-spacing:.08em;text-transform:uppercase;padding:.5rem .6rem;border-bottom:1px solid var(--line)}
td{padding:.7rem .6rem;border-bottom:1px solid var(--line);vertical-align:top;color:var(--tx2)}td b{color:var(--tx)}
.area{margin:1.6rem 0 .5rem;font-size:.95rem;font-weight:850;color:var(--g)}
.matriz{display:grid;grid-template-columns:1fr 1fr;gap:.6rem}
.cuad{background:var(--s);border:1px solid var(--line);border-radius:16px;padding:.8rem .9rem;min-height:7rem}
.cuad h4{margin:0 0 .4rem;font-size:.82rem;letter-spacing:.06em;text-transform:uppercase}
.cuad.q1{border-color:rgba(74,222,128,.5)}.cuad.q1 h4{color:var(--ok)}.cuad.q2 h4{color:var(--g)}.cuad.q3 h4{color:var(--tx3)}.cuad.q4 h4{color:var(--bad)}
.cuad li{font-size:.86rem;color:var(--tx2);margin:.25rem 0}
.tesis{font-size:clamp(1.3rem,4vw,1.9rem);line-height:1.2;letter-spacing:-.03em;font-weight:850;margin:0 0 1rem}
.aviso{margin:1rem 0;padding:.9rem 1rem;border-radius:14px;background:rgba(255,193,77,.08);border:1px solid rgba(255,193,77,.4);color:var(--tx2);font-size:.9rem}
.demo{background:linear-gradient(90deg,var(--b),var(--vio));color:#fff;text-align:center;font-weight:800;padding:.5rem;font-size:.85rem;letter-spacing:.04em}
.barra{height:8px;background:var(--s2);border-radius:99px;overflow:hidden;margin:1rem 0}.barra i{display:block;height:100%;background:linear-gradient(90deg,var(--g),var(--b))}
a{color:var(--g)}footer{margin-top:3rem;color:var(--tx3);font-size:.78rem;text-align:center}
@media print{
 :root{--bg:#fff;--s:#fff;--s2:#f3f0f6;--line:#d9d2e0;--tx:#17121d;--tx2:#3a3144;--tx3:#6c617a}
 body{background:#fff}nav,.noimp{display:none}section{break-inside:avoid-page;padding-top:1.2rem}.card,.cuad{break-inside:avoid}
 h1 span,.g{color:#d4430f;-webkit-text-fill-color:#d4430f;background:none}.demo{background:#eee;color:#333}
}
</style></head><body>${dentro}</body></html>`;

export function paginaInforme(estado) {
  const { token, demo, part, informe: r, urgentes = [], desde } = estado;
  const personas = part.total;
  const barra = `<div class="demo" ${demo ? '' : 'hidden'}>EJEMPLO · datos inventados para mostrar cómo se verá el informe</div>`;
  const nav = `<nav class="noimp"><div class="in">
   <a href="#resumen">Resumen</a><a href="#ya">Lo urgente</a><a href="#aman">Lo que aman</a><a href="#cambiar">Qué cambiar</a><a href="#fuga">Por qué se irían</a>
   <a href="#atencion">Atención</a><a href="#deseos">2027</a><a href="#plan">Plan de acción</a><a href="#estrategia">Estrategia</a>${urgentes.length ? '<a href="#casos">Casos</a>' : ''}
   <span class="sp"></span><button onclick="print()">Imprimir / PDF</button></div></nav>`;

  const tarjeta = (i, extra = '') => `<div class="card"><span class="n">${esc(i.cuantos || '')}</span>
     <h3>${esc(i.tema || i.razon || i.idea)}${i.gravedad ? `<span class="tag ${esc(i.gravedad)}">${esc(GRAV[i.gravedad] || i.gravedad)}</span>` : ''}</h3>
     ${i.detalle ? `<p>${esc(i.detalle)}</p>` : ''}${i.cita ? `<div class="cita">«${esc(i.cita)}»</div>` : ''}${extra}</div>`;

  const acc = r.acciones;
  const grupos = AREAS.map((a) => [a, acc.filter((x) => x.area === a)]).filter(([, l]) => l.length);
  const q = (imp, esf) => acc.filter((x) => (imp === 'alto' ? x.impacto === 'alto' : x.impacto !== 'alto') && (esf === 'bajo' ? x.esfuerzo === 'bajo' : x.esfuerzo !== 'bajo'));
  const cuad = (c, titulo, l) => `<div class="cuad ${c}"><h4>${titulo}</h4><ul class="puntos">${l.map((x) => `<li>${esc(x.accion)}</li>`).join('') || '<li style="color:var(--tx3)">—</li>'}</ul></div>`;

  const cuerpo = `${barra}${nav}<div class="wrap">
  <div class="portada"><p class="k">Tumbao · Rumbo a 2027</p><h1>Lo que nos dijeron.<br><span>Lo que vamos a hacer.</span></h1>
   <p class="lead" id="resumen">${esc(r.resumen)}</p>
   <div class="chips"><div class="chip"><b>${personas}</b><span>personas respondieron</span></div>
    <div class="chip"><b>${part.completas}</b><span>terminaron las 5 preguntas</span></div>
    <div class="chip"><b>${part.con_contacto}</b><span>dejaron sus datos</span></div>
    <div class="chip"><b>${part.urgentes}</b><span>casos para atender</span></div></div>
   ${desde ? `<p class="aviso">${esc(desde)}</p>` : ''}</div>

  <section id="ya"><p class="k">Esta semana</p><h2>Lo urgente: corregir ya</h2>
   ${r.ya.length ? `<div class="grid">${r.ya.map((i) => `<div class="card ya"><h3>${esc(i.que)}</h3><p>${esc(i.por_que)}</p>
      <p class="qh"><b>Qué hacer:</b> ${esc(i.que_hacer)}</p></div>`).join('')}</div>` : '<p class="aviso">Nada crítico en lo que dijeron. Bien: se puede trabajar el plan sin apagar incendios.</p>'}</section>

  <section id="aman"><p class="k">Lo que hay que proteger</p><h2>Lo que más aman de Tumbao</h2><div class="grid">${r.aman.map((i) => tarjeta(i)).join('')}</div></section>
  <section id="cambiar"><p class="k">Lo que hay que mejorar</p><h2>Qué cambiarían, en orden de importancia</h2><div class="grid">${r.cambiar.map((i) => tarjeta(i)).join('')}</div></section>
  <section id="fuga"><p class="k">Riesgo de perderlos</p><h2>Por qué dejarían de venir</h2><div class="grid">${r.fuga.map((i) => tarjeta(i)).join('')}</div></section>
  <section id="atencion"><p class="k">Recepción · WhatsApp · reservas · pagos</p><h2>La atención</h2><div class="dos">
   <div class="card"><h3>Lo que encontramos</h3><ul class="puntos">${r.atencion.hallazgos.map((t) => `<li>${esc(t)}</li>`).join('')}</ul></div>
   <div class="card"><h3>Cómo arreglarlo</h3><ul class="puntos">${r.atencion.arreglos.map((t) => `<li>${esc(t)}</li>`).join('')}</ul></div></div></section>
  <section id="deseos"><p class="k">Mirando a 2027</p><h2>Lo que quieren encontrar</h2><div class="grid">${r.deseos.map((i) => tarjeta(i)).join('')}</div></section>

  <section id="plan"><p class="k">Todo accionable</p><h2>Plan de acción</h2>
   <div class="matriz">
    ${cuad('q1', 'Hacer primero · mucho impacto, poco esfuerzo', q('alto', 'bajo'))}${cuad('q2', 'Apuestas · mucho impacto, más esfuerzo', q('alto', 'mas'))}
    ${cuad('q3', 'Cuando se pueda · menos impacto, poco esfuerzo', q('bajo', 'bajo'))}${cuad('q4', 'Pensarlo bien · menos impacto, más esfuerzo', q('bajo', 'mas'))}</div>
   ${grupos.map(([a, l]) => `<div class="area">${esc(a)}</div><div style="overflow-x:auto"><table style="min-width:34rem"><thead><tr><th>Acción</th><th>Plazo</th><th>Impacto</th><th>Cómo sabremos</th><th>Lleva</th></tr></thead><tbody>${l.map((x) =>
     `<tr><td><b>${esc(x.accion)}</b><br><span style="color:var(--tx3)">${esc(x.por_que)}</span></td><td>${esc(x.plazo)}</td>
       <td><span class="tag ${x.impacto === 'alto' ? 'alto' : ''}">${esc(x.impacto)}</span> <span style="color:var(--tx3);font-size:.75rem">esfuerzo ${esc(x.esfuerzo)}</span></td>
       <td>${esc(x.metrica)}</td><td>${esc(x.responsable)}</td></tr>`).join('')}</tbody></table></div>`).join('')}</section>

  <section id="estrategia"><p class="k">La apuesta</p><h2>Estrategia 2027</h2>
   <p class="tesis g">${esc(r.estrategia.tesis)}</p>
   <div class="grid">${r.estrategia.pilares.map((p) => `<div class="card"><h3>${esc(p.titulo)}</h3><p>${esc(p.detalle)}</p></div>`).join('')}</div>
   ${r.estrategia.mensajes.length ? `<div class="card" style="margin-top:.8rem"><h3>Frases para mercadeo (redes, página y Timba)</h3><ul class="puntos">${r.estrategia.mensajes.map((m) => `<li>${esc(m)}</li>`).join('')}</ul></div>` : ''}</section>

  ${urgentes.length ? `<section id="casos"><p class="k">Para responder</p><h2>Casos para atender</h2><div class="grid">${urgentes.map((u) => `<div class="card ya"><h3>${esc(u.motivo || 'Para atender')}</h3>
    <p>${esc(u.resumen || '')}</p><p class="qh"><b>Contacto:</b> ${esc([u.nombre, u.telefono].filter(Boolean).join(' · ') || 'no dejó datos')}</p></div>`).join('')}</div></section>` : ''}

  <section><p class="k">Cómo leer esto</p><h2>Límites</h2><p class="aviso">${esc(r.limites || 'Son las personas que quisieron responder: hablan por ellas, no por toda la base.')}</p>
   <p class="noimp" style="color:var(--tx3);font-size:.82rem"><a href="/leer?token=${esc(token)}">Ver las conversaciones una por una</a> · <a href="/informe?token=${esc(token)}&amp;n=${Date.now()}">volver a calcular</a>${demo ? '' : ` · <a href="/informe?token=${esc(token)}&amp;demo=1">ver ejemplo</a>`}</p></section>
  <footer>Informe generado el ${new Date().toLocaleDateString('es-CO', { timeZone: 'America/Bogota', day: 'numeric', month: 'long', year: 'numeric' })} · Tumbao · Baila pa' sanar</footer></div>`;
  return marco('Lo que nos dijeron · Plan 2027 · Tumbao', cuerpo);
}

function paginaEstado(titulo, texto, refrescar, token, nonce, avance) {
  const pct = avance ? Math.round((avance.hechas / avance.total) * 100) : 0;
  const meta = refrescar ? `<meta http-equiv="refresh" content="2;url=/informe?token=${encodeURIComponent(token)}${nonce ? '&n=' + encodeURIComponent(nonce) : ''}">` : '';
  return marco(titulo, `<div class="wrap" style="padding-top:4rem"><p class="k">Tumbao · Rumbo a 2027</p><h1>${esc(titulo)}</h1><p class="lead">${esc(texto)}</p>
   ${avance ? `<div class="barra"><i style="width:${pct}%"></i></div><p style="color:var(--tx3)">Analizando… ${avance.hechas} de ${avance.total}. Esta página se actualiza sola.</p>` : ''}
   <p style="margin-top:2rem"><a href="/informe?token=${esc(token)}&amp;demo=1">Ver cómo se verá con datos de ejemplo</a> · <a href="/leer?token=${esc(token)}">Ver conversaciones</a></p></div>`, meta);
}

/* ───────────────────────── el ejemplo ───────────────────────── */

export const EJEMPLO = {
  part: { total: 87, completas: 61, con_contacto: 23, urgentes: 2, por_dia: [] },
  urgentes: [
    { motivo: 'Se sintió incómoda cuando le corrigieron delante de todos', resumen: 'Dijo que un día la sacaron a bailar sin preguntarle y no volvió a la clase de las 6 pm.', nombre: 'Persona de ejemplo', telefono: '300 000 0000' },
  ],
  informe: {
    resumen: 'La gente quiere a Tumbao por el ambiente y por sentirse en confianza, y lo que más pide es más horarios y que reservar y pagar sea más fácil. El riesgo de fuga viene del tiempo y de la rutina, no de la calidad. En conjunto el tono es cálido: hay mucho cariño y pocas quejas graves.',
    ya: [
      { que: 'Dos personas se sintieron expuestas en clase', por_que: 'Trato en clase: es lo que más rápido ahuyenta a alguien que apenas está perdiendo la pena.', que_hacer: 'Hablar con los profes esta semana: nadie sale a bailar sin que quiera. Probar con una norma visible en el salón.' },
      { que: 'Reservar y pagar confunde a varias personas', por_que: 'Cuando alguien paga y no sabe si quedó, pide ayuda por WhatsApp y a veces se pierde.', que_hacer: 'Revisar con recepción la pantalla final de pago y dejar claro «ya quedó tu cupo» y qué sigue.' },
    ],
    aman: [
      { tema: 'El ambiente y la confianza', detalle: 'Se sienten bienvenidas y bienvenidos, sin juicio, aunque no sepan bailar.', cuantos: '52 de 87 personas', cita: 'Llegué sin saber bailar y nadie me hizo sentir mal' },
      { tema: 'Salir con la cabeza liviana', detalle: 'Hablan de estrés que se va, de desconectarse del día.', cuantos: '38 de 87 personas', cita: 'Es mi hora para mí' },
      { tema: 'Los profes y la energía', detalle: 'La música y la energía de la clase los hace volver.', cuantos: '29 de 87 personas', cita: 'La energía de las clases es única' },
    ],
    cambiar: [
      { tema: 'Más horarios', detalle: 'Piden una clase más temprano, más tarde o los domingos.', cuantos: '31 de 87 personas', cita: 'Ojalá hubiera una clase a las 8 pm', gravedad: 'alta' },
      { tema: 'Reservar y pagar más fácil', detalle: 'El proceso de reserva y comprobante les parece largo.', cuantos: '22 de 87 personas', cita: 'No sabía si mi pago ya había quedado', gravedad: 'alta' },
      { tema: 'Salón apretado en horas pico', detalle: 'El de las 6 pm se siente lleno.', cuantos: '14 de 87 personas', cita: 'A las 6 casi no se puede mover uno', gravedad: 'media' },
      { tema: 'Más variedad de ritmos', detalle: 'Quieren probar otros géneros además de la rumba.', cuantos: '11 de 87 personas', cita: '', gravedad: 'media' },
    ],
    fuga: [
      { razon: 'Falta de tiempo y cambios de horario laboral', cuantos: '33 de 87 personas', cita: 'Si me cambian el turno en el trabajo no puedo venir' },
      { razon: 'Pasar a otro plan o lugar por precio o comodidad', cuantos: '12 de 87 personas', cita: '' },
      { razon: 'Pena o sentirse expuesto en clase', cuantos: '5 de 87 personas', cita: 'Me daba pena que me vieran' },
    ],
    atencion: {
      hallazgos: ['Recepción es cálida, pero a veces no sabe responder por pagos pendientes.', 'WhatsApp responde rápido pero a veces repite lo mismo.', 'Les confunde saber si su reserva quedó confirmada.'],
      arreglos: ['Un mensaje claro de «tu cupo ya quedó» al confirmar el pago.', 'Que Timba reconozca a quien ya pagó y no le repita la oferta.', 'Una hoja corta para recepción con las 5 preguntas más comunes.'],
    },
    deseos: [
      { idea: 'Una clase de fin de semana más', cuantos: '19 de 87 personas', cita: 'Un domingo en la mañana sería perfecto' },
      { idea: 'Eventos: noche de baile, aniversario', cuantos: '17 de 87 personas', cita: '' },
      { idea: 'Retos o seguimiento de constancia', cuantos: '9 de 87 personas', cita: 'Me motivaría que me contaran mi progreso' },
    ],
    acciones: [
      { area: 'Atención', accion: 'Mensaje de «tu cupo ya quedó» al terminar el pago', por_que: 'La confusión al pagar es la queja de operación más repetida.', plazo: 'esta semana', impacto: 'alto', esfuerzo: 'bajo', metrica: 'Menos mensajes de «¿ya quedó mi pago?»', responsable: 'página y Timba' },
      { area: 'Clases', accion: 'Norma visible: nadie sale a bailar si no quiere', por_que: 'Evita que se pierdan personas nuevas por pena.', plazo: 'esta semana', impacto: 'alto', esfuerzo: 'bajo', metrica: 'Cero quejas de exposición', responsable: 'dueña y profes' },
      { area: 'Operación', accion: 'Probar una clase más (domingo o 8 pm) por un mes', por_que: 'Es el cambio más pedido.', plazo: '30 días', impacto: 'alto', esfuerzo: 'medio', metrica: 'Asistencia promedio de la clase de prueba', responsable: 'dueño' },
      { area: 'Mercadeo', accion: 'Mensajes basados en «es mi hora para mí» y «sin saber bailar»', por_que: 'Es lo que más valoran, dicho con sus palabras.', plazo: '30 días', impacto: 'medio', esfuerzo: 'bajo', metrica: 'Respuestas y compras por mensaje', responsable: 'Timba y redes' },
      { area: 'Precios y planes', accion: 'Un plan flexible para quien cambia de turno laboral', por_que: 'La falta de tiempo es la primera razón de fuga.', plazo: 'primer trimestre 2027', impacto: 'alto', esfuerzo: 'medio', metrica: 'Renovación de mensualidades', responsable: 'dueña y dueño' },
      { area: 'Tecnología', accion: 'Seguimiento de constancia visible para cada persona', por_que: 'Responde al deseo de retos y refuerza el premio por constancia.', plazo: 'primer trimestre 2027', impacto: 'medio', esfuerzo: 'medio', metrica: 'Personas que completan su tiquetera', responsable: 'página' },
    ],
    estrategia: {
      tesis: 'En 2027 Tumbao es el lugar donde llegas sin saber bailar y sales con la cabeza liviana: más fácil de reservar, más flexible con tu tiempo y con constancia que se celebra.',
      pilares: [
        { titulo: 'Sin pena', detalle: 'Proteger el ambiente de confianza: es lo que más aman y lo que no se puede perder.' },
        { titulo: 'Más fácil', detalle: 'Reservar, pagar y renovar sin dudas ni mensajes de más.' },
        { titulo: 'Más flexible', detalle: 'Horarios y planes que se adapten a turnos y a la vida real.' },
        { titulo: 'Constancia que se celebra', detalle: 'Retos, seguimiento y premios que hagan sentir el progreso.' },
      ],
      mensajes: ['Llega sin saber bailar. Sales con la cabeza liviana.', 'Tu hora para ti.', 'Aquí nadie te mira: todos bailamos.', 'Tu constancia se celebra en Tumbao.'],
    },
    limites: 'Ejemplo con datos inventados. Con datos reales, este informe se basará en quienes respondan y no habla por toda la base.',
  },
};

/* ───────────────────────── la ruta ───────────────────────── */

export async function rutaInforme(request, env, deps) {
  const url = new URL(request.url);
  const html = (cuerpo, estado = 200) => new Response(cuerpo, { status: estado, headers: { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' } });
  if (!env.TOKEN_REPORTE) return html(paginaEstado('Falta la llave', 'Pon TOKEN_REPORTE en el Worker para abrir el informe.', false, '', ''), 503);
  const token = url.searchParams.get('token') || '';
  if (token !== env.TOKEN_REPORTE) return html(paginaEstado('Esa llave no es', 'Revisa el enlace.', false, '', ''), 401);

  if (url.searchParams.get('demo') === '1') return html(paginaInforme({ token, demo: true, ...EJEMPLO }));

  const personas = await personasDeLaEncuesta(env);
  const nonce = url.searchParams.get('n') || '';
  if (personas.length < MINIMO) {
    return html(paginaEstado('Todavía no hay suficientes respuestas',
      `Van ${personas.length}. Con ${MINIMO} o más ya se puede armar el informe; entre más respondan, más sólido sale.`, false, token, nonce));
  }
  try {
    const paso = await avanzarInforme(env, deps, personas, nonce);
    if (paso.avance) return html(paginaEstado('Armando el informe…', 'Estamos leyendo y agrupando lo que contó la gente.', true, token, nonce, paso.avance));
    const urgentes = personas.filter((p) => p.urgente).slice(0, 12).map((p) => ({ motivo: p.motivo_urgente, resumen: p.resumen, nombre: p.nombre, telefono: p.telefono }));
    const aviso = personas.length < 30 ? `Son ${personas.length} respuestas: sirve para ver por dónde va la cosa, pero hay que leerlo con cuidado.` : '';
    return html(paginaInforme({ token, demo: false, part: participacion(personas), informe: paso.informe, urgentes, desde: aviso }));
  } catch (e) {
    return html(paginaEstado('No se pudo armar el informe', `Falló el análisis (${String((e && e.message) || e).slice(0, 100)}). Vuelve a intentarlo en un momento.`, false, token, nonce), 502);
  }
}
