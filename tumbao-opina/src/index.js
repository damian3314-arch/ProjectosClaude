/**
 * Tumbao · bot de opiniones
 *
 * Un Worker de Cloudflare que conversa con los clientes, entiende texto,
 * notas de voz e imágenes, y guarda lo que dicen.
 *
 * Por qué aquí y no en n8n: cada mensaje de una conversación sería una
 * ejecución, y el plan de n8n son 2.500 al mes. Aquí caben 100.000 al
 * día en el plan gratis. n8n solo se usa una vez por semana, para el
 * reporte.
 *
 * El audio NO se guarda. Se transcribe y se suelta, igual que las
 * capturas de los comprobantes.
 */

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'Content-Type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const json = (o, status = 200) =>
  new Response(JSON.stringify(o), {
    status,
    headers: { 'Content-Type': 'application/json; charset=utf-8', ...CORS },
  });

const ahora = () => new Date().toISOString();

/* ─────────────────────────────────────────────────────────────
   El guion. Esto es el producto: el resto es plomería.
   ───────────────────────────────────────────────────────────── */

const LAS_TRES = [
  '¿Qué te hizo volver la segunda vez?',
  'Si mañana dejaras de venir a Tumbao, ¿cuál sería la razón más probable?',
  '¿Qué le dirías a alguien que está pensando en venir por primera vez?',
];

// El primer mensaje siempre es el mismo, así que no se le pide a ningún
// modelo. Tres razones: la persona abre un enlace de WhatsApp sin saber
// qué es —si el saludo no dice quién habla y para qué, cierra—, un
// modelo pequeño lo resume a "Hola, ¿cómo te llamas?" y se pierde toda
// la razón de estar ahí, y además es una llamada menos que pagar.
const SALUDO =
  '¡Hola! Soy de Tumbao. Estamos preguntándole a la gente que ya viene ' +
  'cómo nos está yendo, para mejorar de verdad.\n\nSon tres preguntas, ' +
  'nada más. ¿Cómo te llamas?';

const INSTRUCCIONES = `
Eres el asistente de Tumbao, una academia de baile en Bucaramanga,
Colombia. Estás recogiendo opiniones de gente que ya viene a clases.

TU TRABAJO
Llevar una conversación corta y cálida en la que la persona te cuente
de verdad. No eres un formulario con emojis: eres alguien de la
academia que sí quiere saber.

Ya saludaste y ya preguntaste el nombre. El primer mensaje que te llega
es su nombre.

LAS TRES PREGUNTAS, EN ESTE ORDEN
1. ${LAS_TRES[0]}
2. ${LAS_TRES[1]}
3. ${LAS_TRES[2]}

Van una por mensaje, en ese orden, y no se saltan. Antes de escribir,
mira la conversación y pregúntate cuál de las tres falta.

CÓMO CONVERSAR
- Usa su nombre después, pero no en cada mensaje: cansa.
- UNA sola pregunta por mensaje. Si ya escribiste un "?", ya terminaste:
  lo que sigue va en el mensaje siguiente, cuando la persona conteste.
- Escribes un mensaje de chat, no un guion. Nunca escribas acotaciones
  sobre lo que vas a hacer, ni entre paréntesis ni fuera: nada de "(si
  contesta corto sigo con la otra)" ni "ahora le pregunto lo último".
  La persona ve todo lo que escribes.
- Mensajes cortos: dos o tres líneas. Esto se lee en un celular.
- Tutea. Habla como se habla en Bucaramanga, sin ser caricatura. Nada
  de "¡Qué chévere parcero!" forzado.
- Escribe en español de Colombia. Nada de "feedback", "tips", "staff"
  ni "apreciar tu input": se dice "lo que nos contaste", "consejos",
  "el equipo". Tampoco "agradezco tu honestidad", que suena a carta.
- No abras el mensaje resumiendo lo que la persona acabó de decir para
  demostrar que entendiste: "Entiendo, la puntualidad es clave para
  ti", "Eso es genial, el ambiente es muy importante". Suena a manual
  de call center. Una frase corta y humana, o nada, y sigue.
- Si la respuesta es de tres palabras o vaga ("bien", "todo bueno",
  "nada"), repregunta UNA vez pidiendo algo concreto: "¿te acuerdas de
  algún momento en particular?". Solo una vez. Si insiste en ser breve,
  sigue adelante sin insistir más.
- Nunca inventes datos de Tumbao: horarios, precios, nombres de
  profesores. Si te preguntan algo así, di que eso lo confirman por
  WhatsApp.

CUANDO TE CUENTAN ALGO DELICADO
Que alguien la hizo sentir mal, un problema con un profesor, algo de
plata, ganas de retirarse. Ahí:
- NO lo minimices ni lo arregles con optimismo.
- NO cierres la conversación en ese mensaje. Eso es colgarle a alguien
  que acaba de abrirse. Pase lo que pase, ese mensaje NO lleva [FIN].
- Agradece corto que lo diga y haz UNA sola pregunta para entenderlo
  mejor: cuándo fue, o qué pasó exactamente.
- No prometas soluciones ni castigos: tú no decides eso. Sí puedes
  decir que eso lo va a leer la dueña.

EL CIERRE
Solo cuando ya tengas respuesta a las TRES preguntas. Si falta alguna,
no estás cerrando: estás preguntando.

Y va en dos mensajes distintos, no en uno:
- Primero: ofrece que mande una nota de voz si quiere agregar algo, y
  pide el celular. Al pedirlo tienen que ir SIEMPRE las dos cosas, con
  esas palabras o parecidas: que es **opcional** y para qué es (por si
  quieren responderle). Pedir un número sin decir eso es lo que hace
  que la gente se salga. Ese mensaje NO lleva [FIN].
- Después de que conteste eso —dé el número o diga que no—: agradece
  de verdad, corto, y ahí sí termina con [FIN] en una línea aparte.

REGLAS DE [FIN], QUE NO SE ROMPEN
- [FIN] va en UN solo mensaje de toda la conversación: el último.
- Un mensaje con [FIN] no puede llevar ninguna pregunta.
- Nunca [FIN] antes de tener las tres respuestas.
- Nunca [FIN] en el mismo mensaje donde te contaron algo delicado.
`.trim();

/* ─────────────────────────────────────────────────────────────
   Quién contesta

   Tres motores, en este orden:

   1. OpenAI, si está OPENAI_API_KEY. Es para lo que se escribió el
      guion y da la mejor conversación.
   2. Workers AI, que corre en este mismo Worker. NO necesita llave ni
      cuenta de OpenAI: es un binding de Cloudflare. Conversa de
      verdad, entiende lo que le escriben y contesta a eso.
   3. El guion fijo, si no hay ni lo uno ni lo otro.

   El 2 existe porque el bot llevaba semanas parado esperando un
   secreto. Un bot que contesta preguntas fijas ignorando lo que la
   persona escribe no está "en modo de prueba": está roto, y el cliente
   que abrió el enlace se da cuenta a los dos mensajes.

   Poner la llave de OpenAI después no rompe nada: se sube sola al 1.
   ───────────────────────────────────────────────────────────── */

const MODELO_CF        = '@cf/meta/llama-3.3-70b-instruct-fp8-fast';
const MODELO_CF_VOZ    = '@cf/openai/whisper-large-v3-turbo';
const MODELO_CF_VISION = '@cf/meta/llama-3.2-11b-vision-instruct';

const hayCF = (env) => Boolean(env.AI && typeof env.AI.run === 'function');

async function conversar(env, historia) {
  if (!env.OPENAI_API_KEY) {
    if (!hayCF(env)) return ensayo(historia);
    const d = await env.AI.run(env.MODELO_CF || MODELO_CF, {
      messages: [{ role: 'system', content: INSTRUCCIONES }, ...historia],
      max_tokens: 220,
      temperature: 0.7,
    });
    return (d.response || '').trim() || '…';
  }

  const r = await fetch('https://api.openai.com/v1/chat/completions', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${env.OPENAI_API_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model: env.MODELO_CHAT || 'gpt-4o-mini',
      temperature: 0.7,
      max_tokens: 220,
      messages: [{ role: 'system', content: INSTRUCCIONES }, ...historia],
    }),
  });

  if (!r.ok) {
    const detalle = (await r.text()).slice(0, 300);
    throw new Error(`OpenAI ${r.status}: ${detalle}`);
  }
  const d = await r.json();
  return d.choices?.[0]?.message?.content?.trim() || '…';
}

// Respuestas fijas para probar sin llave. Avanzan por las tres
// preguntas contando cuántas veces habló la persona.
function ensayo(historia) {
  const turnos = historia.filter((m) => m.role === 'user').length;
  const guion = [
    '¡Hola! Soy de Tumbao. Queremos mejorar y tu opinión nos sirve muchísimo.\n\n¿Cómo te llamas?',
    `Un gusto. Cuéntame: ${LAS_TRES[0]}`,
    `Qué bueno saberlo. Ahora una más difícil: ${LAS_TRES[1]}`,
    `Gracias por la franqueza. Última: ${LAS_TRES[2]}`,
    'Si quieres agregar algo, mándame una nota de voz.\n\nY si nos dejas tu celular te podemos responder. Es opcional.',
    'Gracias de verdad. Esto nos sirve más de lo que crees.\n\n[FIN]',
  ];
  return guion[Math.min(turnos, guion.length - 1)];
}

async function transcribir(env, archivo) {
  if (!env.OPENAI_API_KEY) {
    if (!hayCF(env)) return '(nota de voz de prueba: sin llave no se transcribe)';
    // Whisper por el binding recibe los bytes crudos, no un FormData.
    const d = await env.AI.run(env.MODELO_CF_VOZ || MODELO_CF_VOZ, {
      audio: [...new Uint8Array(await archivo.arrayBuffer())],
    });
    // La misma limpieza que la otra rama: Whisper alucina subtítulos de
    // YouTube cuando el audio es silencio, y eso no lo dijo nadie.
    return limpiarTranscripcion(d.text?.trim() || '');
  }

  const fd = new FormData();
  fd.append('file', archivo, 'audio.webm');
  fd.append('model', env.MODELO_VOZ || 'whisper-1');
  fd.append('language', 'es');

  const r = await fetch('https://api.openai.com/v1/audio/transcriptions', {
    method: 'POST',
    headers: { Authorization: `Bearer ${env.OPENAI_API_KEY}` },
    body: fd,
  });
  if (!r.ok) throw new Error(`Whisper ${r.status}: ${(await r.text()).slice(0, 200)}`);
  return limpiarTranscripcion((await r.json()).text?.trim() || '');
}

// Con audio en silencio o puro ruido, Whisper no devuelve vacío: devuelve
// frases de subtítulos de YouTube que se aprendió de memoria. Si eso pasa,
// entra al chat como si la persona lo hubiera dicho, el bot le responde a
// algo que nadie dijo, y termina en la ficha, en la hoja y en el reporte
// del lunes como si fuera la opinión de un cliente.
//
// El tope de largo importa: una nota larga y real que de casualidad diga
// "gracias por ver" no se puede tirar a la basura. Las alucinaciones
// siempre son cortas.
const ALUCINACIONES = [
  /gracias por ver/i,
  /subt[ií]tulos/i,
  /amara\.org/i,
  /thanks? for watching/i,
  /suscr[ií]b[ae]/i,
  /^\W+$/,
];

function limpiarTranscripcion(texto) {
  const t = String(texto || '').trim();
  if (t.length < 2) return '';
  if (t.length < 60 && ALUCINACIONES.some((r) => r.test(t))) return '';
  return t;
}

const PIDE_IMAGEN =
  'Describe en una o dos frases qué muestra esta imagen. Es algo que un ' +
  'cliente de una academia de baile mandó junto a su opinión.';

async function describirImagen(env, dataUrl) {
  if (!env.OPENAI_API_KEY) {
    if (!hayCF(env)) return '(imagen de prueba: sin llave no se describe)';
    const base64 = dataUrl.slice(dataUrl.indexOf(',') + 1);
    const crudo = Uint8Array.from(atob(base64), (c) => c.charCodeAt(0));
    const d = await env.AI.run(env.MODELO_CF_VISION || MODELO_CF_VISION, {
      image: [...crudo],
      prompt: PIDE_IMAGEN,
      max_tokens: 150,
    });
    return (d.description || d.response || '').trim();
  }

  const r = await fetch('https://api.openai.com/v1/chat/completions', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${env.OPENAI_API_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model: env.MODELO_CHAT || 'gpt-4o-mini',
      max_tokens: 150,
      messages: [{
        role: 'user',
        content: [
          { type: 'text', text: PIDE_IMAGEN },
          { type: 'image_url', image_url: { url: dataUrl } },
        ],
      }],
    }),
  });
  if (!r.ok) throw new Error(`Visión ${r.status}`);
  return (await r.json()).choices?.[0]?.message?.content?.trim() || '';
}

/* ─────────────────────────────────────────────────────────────
   Extraer la ficha al cerrar
   ───────────────────────────────────────────────────────────── */

const EXTRAER = `
Te paso una conversación entre una academia de baile y un cliente.
Devuelve SOLO un objeto JSON con estas claves:

nombre    - como se presentó, o null
telefono  - solo dígitos, o null si no lo dio
tipo      - "queja" | "sugerencia" | "elogio" | "mixto"
resumen   - qué dijo, en 2 o 3 frases. Conserva la frase textual más
            reveladora entre comillas angulares «así». Nada de "el
            cliente expresa que": escribe como le contarías a un
            compañero.
urgente   - true SOLO si hay algo que no puede esperar al lunes: acoso,
            trato irrespetuoso, riesgo físico, un cobro mal hecho, o
            alguien que dice que se va a retirar ya. Molestias normales
            NO son urgentes.
motivo    - si urgente es true, una frase de por qué. Si no, null.

Qué cuenta como trato irrespetuoso, que es lo que más se falla: que un
profesor o alguien del equipo la haya humillado, ridiculizado, gritado
o dejado en evidencia delante de la clase. "Me hizo sentir mal delante
de todos" ES urgente. Que la clase estuviera llena o que el profesor
llegara tarde NO lo es.

Fuera de eso, ante la duda pon false. Una alerta falsa cada semana hace
que dejen de leerse las de verdad.

EL FORMATO IMPORTA
Devuelve JSON válido y nada más: sin vallas de código, sin
explicaciones antes ni después. Dentro de los textos no uses comillas
dobles nunca —para citar usa «comillas angulares»—, porque una comilla
doble suelta parte el JSON y la ficha se pierde.
`.trim();

async function extraerFicha(env, historia) {
  const texto = historia
    .map((m) => (m.role === 'user' ? 'CLIENTE: ' : 'TUMBAO: ') + m.content)
    .join('\n');

  if (!env.OPENAI_API_KEY && !hayCF(env)) {
    return { nombre: null, telefono: null, tipo: 'mixto',
             resumen: '(ensayo sin llave) ' + texto.slice(0, 300),
             urgente: false, motivo: null };
  }

  // La ficha es lo que se lee el lunes: sin ella la conversación queda
  // como un ladrillo de texto que nadie abre. Por eso también se saca
  // sin llave de OpenAI.
  if (!env.OPENAI_API_KEY) {
    const d = await env.AI.run(env.MODELO_CF || MODELO_CF, {
      messages: [{ role: 'system', content: EXTRAER },
                 { role: 'user', content: texto }],
      // De sobra para la ficha. Con el tope corto el JSON se parte a
      // media frase, no parsea, y la conversación aparece el lunes como
      // "Sin nombre · (sin resumen)" aunque se haya guardado entera.
      max_tokens: 700,
      temperature: 0,
    });
    return limpiarFicha(sacarJSON(d.response), texto);
  }

  const r = await fetch('https://api.openai.com/v1/chat/completions', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${env.OPENAI_API_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model: env.MODELO_CHAT || 'gpt-4o-mini',
      temperature: 0,
      response_format: { type: 'json_object' },
      messages: [
        { role: 'system', content: EXTRAER },
        { role: 'user', content: texto },
      ],
    }),
  });
  if (!r.ok) throw new Error(`Extraer ${r.status}`);

  const cuerpo = await r.json();
  return limpiarFicha(sacarJSON(cuerpo.choices?.[0]?.message?.content || ''), texto);
}

// OpenAI devuelve JSON pelado porque se le pide `response_format`. Los
// modelos de Workers AI no siempre: a veces lo envuelven en ```json, o
// le anteponen "Aquí está el objeto:". Se busca del primer { al último
// }, que es lo único que hace falta.
//
// Si aun así no sale JSON, la ficha queda vacía pero la conversación NO
// se pierde: la transcripción completa se guarda igual, y de ahí se
// rehace a mano.
export function sacarJSON(crudo) {
  // Workers AI a veces devuelve la ficha YA parseada, como objeto, y no
  // como texto: pasa justo cuando el modelo contesta bien, sin vallas de
  // código. Sin esta línea, ese caso —el bueno— se convertía en
  // "[object Object]", no parseaba, y la ficha salía vacía. Que el
  // camino correcto sea el que se rompe es lo que lo hizo difícil de
  // ver: en las pruebas con texto todo pasaba.
  if (crudo && typeof crudo === 'object') return crudo;

  const s = String(crudo || '');
  const a = s.indexOf('{');
  const b = s.lastIndexOf('}');
  if (a < 0 || b <= a) return {};
  const trozo = s.slice(a, b + 1);
  try {
    return JSON.parse(trozo);
  } catch (_) {
    try {
      return JSON.parse(taparComillas(trozo));
    } catch (_) {
      return {};
    }
  }
}

// La forma en que esto se rompe de verdad: al pedirle que conserve la
// frase textual del cliente, el modelo la mete entre comillas dobles
// DENTRO de una cadena JSON:
//
//   "resumen": "le gustó porque "nadie lo mira raro", pero ..."
//
// y ahí se acabó el JSON. Ya se pidió en el guion que cite con «», pero
// eso es pedir, no garantizar, y perder la ficha por una comilla es
// caro: es la fila que Tania lee el lunes.
//
// Se recorre la cadena y se escapa toda comilla que esté dentro de un
// texto. La parte difícil es decidir cuándo una comilla cierra de
// verdad, porque el caso que rompió la ficha en producción fue este:
//
//   "resumen": "le gustó porque "nadie lo mira raro", pero ..."
//
// La comilla de después de «raro» viene seguida de una coma, igual que
// una que cierra. Mirar solo el carácter siguiente no alcanza.
//
// Lo que sí distingue: tras una coma que cierra un campo viene OTRO
// campo, o sea "algo":. Si después de la coma no hay una clave, la
// comilla era del cliente y va escapada.
//
// Esto asume el objeto plano de la ficha —seis campos, sin listas ni
// anidados—, que es lo que pide EXTRAER. Sobre un JSON ya válido no
// cambia nada.
const OTRA_CLAVE = /^\s*"[^"\\]*"\s*:/;

export function taparComillas(s) {
  let salida = '';
  let dentro = false;
  for (let i = 0; i < s.length; i++) {
    const c = s[i];
    if (c === '\\') { salida += c + (s[i + 1] || ''); i++; continue; }
    if (c !== '"') { salida += c; continue; }
    if (!dentro) { dentro = true; salida += c; continue; }

    let j = i + 1;
    while (j < s.length && /\s/.test(s[j])) j++;
    const sig = s[j];

    let cierra;
    if (j >= s.length || sig === '}' || sig === ']' || sig === ':') {
      cierra = true;                              // fin, o era una clave
    } else if (sig === ',') {
      cierra = OTRA_CLAVE.test(s.slice(j + 1));   // ¿empieza otro campo?
    } else {
      cierra = false;                             // texto que sigue: era del cliente
    }

    if (cierra) { dentro = false; salida += c; } else salida += '\\"';
  }
  return salida;
}

// Lo que la persona dijo, sin las preguntas del bot. Es el paracaídas
// del resumen: vale mucho más leer sus propias frases que un
// "(sin resumen)" que hace pensar que la conversación se perdió.
export function loQueDijo(texto) {
  const suyo = String(texto || '')
    .split('\n')
    .filter((l) => l.startsWith('CLIENTE: '))
    .map((l) => l.slice(9).trim())
    .filter(Boolean)
    .join(' · ');
  return suyo ? suyo.slice(0, 1200) : '';
}

// El saludo pregunta el nombre, así que lo primero que escribe la
// persona casi siempre lo es. Solo se usa si de verdad parece un
// nombre: dos o tres palabras de letras. Así "bien" o "quiero poner una
// queja" no terminan de nombre en el reporte.
export function primerNombre(texto) {
  const primera = String(texto || '')
    .split('\n').find((l) => l.startsWith('CLIENTE: '));
  if (!primera) return null;
  const s = primera.slice(9).trim().replace(/[.,;!]+$/, '');
  return /^[\p{L}][\p{L}\s'’-]{1,39}$/u.test(s) && s.split(/\s+/).length <= 3
    ? s : null;
}

export function limpiarFicha(d, texto) {
  const txt = (v, max) => {
    if (v == null) return null;
    const s = String(v).trim();
    return s && s.length <= max ? s : (s ? s.slice(0, max) : null);
  };
  const crudo = loQueDijo(texto);
  return {
    nombre:   txt(d.nombre, 80) || primerNombre(texto),
    telefono: d.telefono ? String(d.telefono).replace(/\D/g, '').slice(0, 15) || null : null,
    tipo:     ['queja', 'sugerencia', 'elogio', 'mixto'].includes(d.tipo) ? d.tipo : 'mixto',
    // Si el modelo no devolvió resumen —JSON partido, respuesta rara—
    // van sus propias palabras. Nunca "(sin resumen)" habiendo texto.
    resumen:  txt(d.resumen, 1200) || crudo || '(sin resumen)',
    urgente:  d.urgente === true,
    motivo:   txt(d.motivo, 300),
  };
}

/* ─────────────────────────────────────────────────────────────
   Rutas
   ───────────────────────────────────────────────────────────── */

async function guardarMensaje(env, conv, de, texto, medio) {
  await env.DB.prepare(
    `insert into mensajes (conversacion, de, texto, medio, creado_at)
     values (?1, ?2, ?3, ?4, ?5)`
  ).bind(conv, de, texto, medio || 'texto', ahora()).run();
}

async function asegurarConversacion(env, conv) {
  await env.DB.prepare(
    `insert into conversaciones (id, empezada_at) values (?1, ?2)
     on conflict(id) do nothing`
  ).bind(conv, ahora()).run();
}

/* ─────────────────────────────────────────────────────────────
   La pantalla de lectura
   ───────────────────────────────────────────────────────────── */

const esc = (s) =>
  String(s ?? '').replace(/[&<>"']/g, (c) =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

const cuando = (iso) => {
  if (!iso) return '';
  return new Intl.DateTimeFormat('es-CO', {
    timeZone: 'America/Bogota', day: 'numeric', month: 'short',
    hour: 'numeric', minute: '2-digit', hour12: true,
  }).format(new Date(iso));
};

function paginaLeer(filas, problema) {
  const marco = (dentro) => `<!doctype html><html lang="es-CO"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex,nofollow">
<title>Lo que dice la gente · Tumbao</title>
<style>
 :root{--bg:#0d0b0f;--bg2:#17141a;--bg3:#211c26;--line:#2e2833;
       --tx:#f2eef5;--tx2:#b8adc2;--tx3:#7d7288;
       --hot:#ff6b35;--gold:#ffc14d;--ok:#4ade80;--bad:#ff6b81}
 *{box-sizing:border-box}
 body{margin:0;background:var(--bg);color:var(--tx);
      font:15px/1.55 ui-sans-serif,system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;
      padding:1.2rem;max-width:56rem;margin-inline:auto}
 h1{font-size:1.5rem;margin:0 0 .2rem;
    background:linear-gradient(100deg,var(--gold),var(--hot) 70%);
    -webkit-background-clip:text;background-clip:text;color:transparent}
 .sub{color:var(--tx3);font-size:.85rem;margin:0 0 1.4rem}
 .tarjeta{background:var(--bg2);border:1px solid var(--line);border-radius:14px;
          padding:1rem;margin-bottom:.8rem}
 .tarjeta.urge{border-color:rgba(255,107,129,.5)}
 .top{display:flex;align-items:baseline;gap:.6rem;flex-wrap:wrap;margin-bottom:.35rem}
 .nom{font-weight:600}
 .et{font-size:.7rem;text-transform:uppercase;letter-spacing:.04em;
     border:1px solid var(--line);border-radius:999px;padding:.1rem .5rem;color:var(--tx3)}
 .et.queja{border-color:rgba(255,107,129,.5);color:var(--bad)}
 .et.elogio{border-color:rgba(74,222,128,.45);color:var(--ok)}
 .et.sugerencia{border-color:rgba(255,193,77,.5);color:var(--gold)}
 .et.urge{border-color:var(--bad);color:var(--bad);font-weight:700}
 .sp{flex:1}
 .fecha{font-size:.75rem;color:var(--tx3)}
 .res{margin:.3rem 0 .5rem}
 .sin{color:var(--tx3);font-style:italic}
 a{color:var(--gold)}
 details{margin-top:.5rem}
 summary{cursor:pointer;font-size:.8rem;color:var(--tx3)}
 pre{white-space:pre-wrap;word-break:break-word;background:var(--bg3);
     border:1px solid var(--line);border-radius:10px;padding:.7rem;
     font:12.5px/1.5 ui-monospace,SFMono-Regular,Menlo,monospace;color:var(--tx2);
     margin:.5rem 0 0}
 .vacio{text-align:center;color:var(--tx3);padding:3rem 1rem}
 .aviso{background:var(--bg2);border:1px solid var(--line);border-left:3px solid var(--hot);
        border-radius:10px;padding:1rem;color:var(--tx2)}
 code{background:var(--bg3);padding:.1rem .35rem;border-radius:5px;font-size:.85em}
</style></head><body>${dentro}</body></html>`;

  if (problema === 'sin-token') {
    return marco(`<h1>Falta la llave</h1>
      <div class="aviso">Esta página enseña nombres, celulares y quejas de
      clientes, así que no se abre sin llave. Falta el secreto
      <code>TOKEN_REPORTE</code> en el Worker:<br><br>
      Cloudflare → Workers → <b>tumbao-opina</b> → Settings → Variables →
      Add secret.</div>`);
  }
  if (problema === 'mal-token') {
    return marco(`<h1>Esa llave no es</h1>
      <p class="sub">Revisa el enlace. Va con <code>?token=…</code> al final.</p>`);
  }

  if (!filas.length) {
    return marco(`<h1>Lo que dice la gente</h1>
      <p class="sub">Todavía nadie ha contado nada.</p>
      <div class="vacio">Comparte el enlace
        <a href="https://opina.tumbaobaila.com">opina.tumbaobaila.com</a>
        por WhatsApp y aquí van apareciendo.</div>`);
  }

  const urgentes = filas.filter((f) => f.urgente).length;
  const tarjetas = filas.map((f) => {
    const tipo = String(f.tipo || '').toLowerCase();
    return `<div class="tarjeta${f.urgente ? ' urge' : ''}">
      <div class="top">
        <span class="nom">${esc(f.nombre || 'Sin nombre')}</span>
        ${f.tipo ? `<span class="et ${esc(tipo)}">${esc(f.tipo)}</span>` : ''}
        ${f.urgente ? '<span class="et urge">mirar hoy</span>' : ''}
        ${!f.completa ? '<span class="et">se cortó</span>' : ''}
        <span class="sp"></span>
        <span class="fecha">${esc(cuando(f.empezada_at))}</span>
      </div>
      ${f.telefono
        ? `<div class="fecha">📱 <a href="https://wa.me/57${esc(String(f.telefono).replace(/\D/g, ''))}"
             target="_blank" rel="noopener">${esc(f.telefono)}</a></div>` : ''}
      <p class="res">${f.resumen ? esc(f.resumen)
        : '<span class="sin">Sin resumen — falta la llave de OpenAI. Lo que dijo está abajo, en crudo.</span>'}</p>
      ${f.urgente && f.motivo_urgente
        ? `<p class="res" style="color:var(--bad)">⚠ ${esc(f.motivo_urgente)}</p>` : ''}
      ${f.transcripcion
        ? `<details><summary>Ver la conversación entera (${f.turnos} turnos)</summary>
             <pre>${esc(f.transcripcion)}</pre></details>` : ''}
    </div>`;
  }).join('');

  return marco(`<h1>Lo que dice la gente</h1>
    <p class="sub">${filas.length} conversacion${filas.length === 1 ? '' : 'es'}${
      urgentes ? ` · <b style="color:var(--bad)">${urgentes} para mirar hoy</b>` : ''
    } · lo urgente va primero</p>
    ${tarjetas}`);
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const ruta = url.pathname;

    if (request.method === 'OPTIONS') return new Response(null, { headers: CORS });

    try {
      // ── un turno de conversación ──
      if (ruta === '/api/mensaje' && request.method === 'POST') {
        const b = await request.json();
        const conv = String(b.conversacion || '').slice(0, 40);
        if (!/^[a-f0-9-]{16,40}$/i.test(conv)) return json({ error: 'conversacion_invalida' }, 400);

        const historia = Array.isArray(b.historia) ? b.historia.slice(-24) : [];
        await asegurarConversacion(env, conv);

        const suyo = String(b.texto || '').slice(0, 4000);
        if (suyo) {
          historia.push({ role: 'user', content: suyo });
          await guardarMensaje(env, conv, 'persona', suyo, b.medio);
        }

        // El saludo es siempre el mismo y no se le pide a ningún modelo:
        // así la persona que abre el enlace sabe de una quién le habla y
        // para qué, en vez de recibir un "Hola, ¿cómo te llamas?" pelado.
        const cruda = historia.length === 0 && !suyo
          ? SALUDO
          : await conversar(env, historia);

        // Red de seguridad contra el cierre prematuro. Un modelo puede
        // querer despedirse justo cuando la persona acaba de contar algo
        // incómodo —que es cuando menos hay que colgarle— o después de
        // dos respuestas. El guion lo prohíbe; esto lo hace imposible.
        // Hacen falta cuatro cosas suyas: el nombre y las tres
        // respuestas. Si aún no están, [FIN] se ignora y el bot sigue.
        const suyas = historia.filter((m) => m.role === 'user').length;
        const listo = cruda.includes('[FIN]') && suyas >= 4;
        const respuesta = cruda.replace('[FIN]', '').trim();

        await guardarMensaje(env, conv, 'bot', respuesta, 'texto');
        await env.DB.prepare(
          `update conversaciones set turnos = turnos + 1 where id = ?1`
        ).bind(conv).run();

        return json({ respuesta, listo });
      }

      // ── nota de voz ──
      if (ruta === '/api/voz' && request.method === 'POST') {
        const fd = await request.formData();
        const audio = fd.get('audio');
        if (!audio) return json({ error: 'sin_audio' }, 400);
        // El audio se transcribe y se suelta. No se guarda en ninguna parte.
        const dicho = await transcribir(env, audio);
        // Vacío quiere decir que no se entendió nada, o que lo único que
        // llegó fue una alucinación de Whisper. Se le pide otra en vez de
        // meter al chat algo que la persona nunca dijo.
        if (!dicho) return json({ error: 'no_se_entendio' }, 200);
        return json({ texto: dicho });
      }

      // ── imagen ──
      if (ruta === '/api/imagen' && request.method === 'POST') {
        const b = await request.json();
        const img = String(b.imagen || '');
        if (!/^data:image\/(jpe?g|png|webp);base64,/.test(img)) return json({ error: 'no_es_imagen' }, 400);
        if (img.length > 6 * 1024 * 1024) return json({ error: 'muy_grande' }, 400);
        return json({ texto: await describirImagen(env, img) });
      }

      // ── cerrar y guardar la ficha ──
      if (ruta === '/api/cerrar' && request.method === 'POST') {
        const b = await request.json();
        const conv = String(b.conversacion || '').slice(0, 40);
        if (!/^[a-f0-9-]{16,40}$/i.test(conv)) return json({ error: 'conversacion_invalida' }, 400);

        const historia = Array.isArray(b.historia) ? b.historia : [];
        const f = await extraerFicha(env, historia);

        await env.DB.prepare(
          `update conversaciones
              set nombre = ?2, telefono = ?3, tipo = ?4, resumen = ?5,
                  urgente = ?6, motivo_urgente = ?7, transcripcion = ?8,
                  cerrada_at = ?9, completa = 1
            where id = ?1`
        ).bind(
          conv, f.nombre, f.telefono, f.tipo, f.resumen,
          f.urgente ? 1 : 0, f.motivo,
          historia.map((m) => (m.role === 'user' ? '> ' : '') + m.content).join('\n'),
          ahora()
        ).run();

        return json({ ok: true, urgente: f.urgente });
      }

      // ── lo que se lleva n8n una vez por semana ──
      if (ruta === '/api/pendientes' && request.method === 'POST') {
        const b = await request.json();
        if (!env.TOKEN_REPORTE || b.token !== env.TOKEN_REPORTE) {
          return json({ ok: false, error: 'NO_AUTORIZADO' }, 401);
        }
        const { results } = await env.DB.prepare(
          `select id, nombre, telefono, tipo, resumen, urgente, motivo_urgente,
                  empezada_at, cerrada_at, turnos, completa
             from conversaciones
            where en_hoja = 0
              -- Las que no pasaron del saludo no son una opinión, son una
              -- pestaña que alguien abrió y cerró. Se veía en el primer
              -- reporte de verdad: quince "Sin nombre · (sin resumen)"
              -- seguidos, y las dos que sí decían algo perdidas en medio.
              and turnos > 1
            order by empezada_at`
        ).all();
        return json({ ok: true, conversaciones: results || [] });
      }

      if (ruta === '/api/marcar-en-hoja' && request.method === 'POST') {
        const b = await request.json();
        if (!env.TOKEN_REPORTE || b.token !== env.TOKEN_REPORTE) {
          return json({ ok: false, error: 'NO_AUTORIZADO' }, 401);
        }
        const ids = (Array.isArray(b.ids) ? b.ids : []).slice(0, 500);
        if (!ids.length) return json({ ok: true, marcadas: 0 });
        const huecos = ids.map((_, i) => `?${i + 1}`).join(',');
        await env.DB.prepare(
          `update conversaciones set en_hoja = 1 where id in (${huecos})`
        ).bind(...ids).run();
        return json({ ok: true, marcadas: ids.length });
      }

      /* ── leer lo que dijo la gente ──
       *
       * Sin esto, mandar el enlace es abrir un buzón sin llave: lo que
       * la gente cuenta se queda en D1 y solo se puede ver por Google
       * Sheets o por el reporte del lunes, y ninguno de los dos está
       * configurado todavía.
       *
       * Es una página aparte y no una pestaña del panel de admin a
       * propósito: el panel vive contra Supabase y esto contra D1, y
       * cruzarlos obligaría a que un Worker le pidiera datos al otro
       * para enseñar una lista que se mira una vez a la semana.
       *
       * La llave es TOKEN_REPORTE, el mismo secreto que ya usa n8n.
       * Mientras no exista, la página lo dice en vez de quedar abierta:
       * aquí hay nombres, celulares y quejas de clientes.
       */
      if (ruta === '/leer') {
        if (!env.TOKEN_REPORTE) {
          return new Response(paginaLeer(null, 'sin-token'), {
            status: 503, headers: { 'Content-Type': 'text/html; charset=utf-8' },
          });
        }
        const dado = url.searchParams.get('token') || '';
        if (dado !== env.TOKEN_REPORTE) {
          return new Response(paginaLeer(null, 'mal-token'), {
            status: 401, headers: { 'Content-Type': 'text/html; charset=utf-8' },
          });
        }
        const { results } = await env.DB.prepare(
          `select id, nombre, telefono, tipo, resumen, urgente, motivo_urgente,
                  transcripcion, turnos, completa, empezada_at, cerrada_at
             from conversaciones
            -- Las que no pasaron del saludo no son una opinión, son una
            -- pestaña que alguien abrió y cerró. Ensucian la lista.
            where turnos > 1
            -- Lo urgente primero, y dentro de eso lo más reciente. Una
            -- queja de hace tres horas importa más que un elogio de ayer.
            order by urgente desc, empezada_at desc
            limit 200`
        ).all();
        return new Response(paginaLeer(results || [], null), {
          headers: { 'Content-Type': 'text/html; charset=utf-8',
                     'Cache-Control': 'no-store' },
        });
      }

      // ── la página ──
      return env.ASSETS.fetch(request);
    } catch (e) {
      // Que el cliente nunca vea una pantalla rota: si algo falla, el bot
      // dice algo humano y la conversación puede seguir.
      console.log('error:', e && e.message);
      return json({ error: 'falla', mensaje: String(e && e.message).slice(0, 200) }, 500);
    }
  },
};
