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
//
// ARRANCA CON LA PREGUNTA, NO CON EL NOMBRE
// Hasta el 17 de agosto lo primero que se pedía era el nombre. En dos
// días seis personas abrieron el chat y ninguna escribió una palabra.
// Se entiende: pedir el nombre cuesta algo y no devuelve nada, y en una
// página web —a diferencia de un enlace que te llega por WhatsApp— se lo
// estás dando a un desconocido. Encima el saludo anunciaba "son tres
// preguntas", que es avisar de trabajo antes de dar una razón.
//
// Ahora lo primero es la pregunta de verdad, que se contesta en tres
// palabras. El nombre se pide al final, junto con el celular, cuando la
// persona ya contó algo y darlo tiene sentido. Se prefiere una opinión
// anónima de verdad antes que un nombre sin opinión.
//
// EL GANCHO
// El saludo anterior era «Nos ayuda muchísimo saber cómo lo estás
// viviendo». De 42 chats abiertos escribieron 11. El problema de esa
// frase es que habla de nosotros: qué nos ayuda a nosotros, no qué gana
// la persona ni a quién le llega lo que escriba. Y "soy de Tumbao" no es
// nadie.
//
// Este dice tres cosas que sí mueven a contestar, en este orden:
//   1. para qué se pregunta — vamos a cambiar cosas y no queremos
//      adivinar. Que le pregunten a uno antes de decidir halaga y es
//      verdad;
//   2. a QUIÉN le llega — «lo leemos nosotras, no un robot». Es la
//      diferencia entre escribirle a un formulario y escribirle a
//      alguien que puede cambiar el horario del martes. Se dijo sin
//      nombre propio a propósito: quien lea el chat puede cambiar, y un
//      saludo que nombra a alguien envejece el día que esa persona ya
//      no está;
//   3. cuánto cuesta — «con una frase basta», dicho antes de la
//      pregunta, no después.
//
// Y termina en LAS_TRES[0], que se contesta en tres palabras. Por eso el
// saludo y la primera pregunta del guion no pueden separarse.
const SALUDO =
  '¡Hola! Somos Tumbao 🧡 Queremos mejorar un par de cosas de la ' +
  'academia y preferimos preguntarte a ti antes que adivinar. Lo que ' +
  'escribas aquí lo leemos nosotras, no un robot, y con una frase ' +
  'basta.\n\n' + LAS_TRES[0];

const INSTRUCCIONES = `
Eres el asistente de Tumbao, una academia de baile en Bucaramanga,
Colombia. Estás recogiendo opiniones de gente que ya viene a clases.

TU TRABAJO
Llevar una conversación corta y cálida en la que la persona te cuente
de verdad. No eres un formulario con emojis: eres alguien de la
academia que sí quiere saber.

Ya saludaste y ya hiciste la PRIMERA de las tres preguntas. El primer
mensaje que te llega es, casi siempre, su respuesta a esa. No es su
nombre. Y OJO: a veces tampoco es una respuesta. Ver más abajo.

Todavía no sabes cómo se llama, y está bien: el nombre se pide al final.
No lo preguntes antes ni lo inventes.

LAS TRES PREGUNTAS, EN ESTE ORDEN
1. ${LAS_TRES[0]}   ← ya la hiciste tú en el saludo
2. ${LAS_TRES[1]}
3. ${LAS_TRES[2]}

Van una por mensaje, en ese orden, y no se saltan. Antes de escribir,
mira la conversación y pregúntate cuál de las tres falta. Si la persona
ya contestó una vez, lo que falta es la 2.

NO LE PASES POR ENCIMA A LO QUE ESCRIBIÓ
Antes de avanzar, mira si lo último que llegó es de verdad una respuesta
a la pregunta que estaba sobre la mesa. Hay dos casos en los que NO lo
es, y en los dos avanzar es un error que se siente feo:

- Solo saludó: «Buena tarde», «Hola», «Buenas, ¿cómo están?». Eso no es
  la respuesta a nada. Salúdala de vuelta en una línea y vuelve a poner
  la pregunta 1 con tus propias palabras. Pasó de verdad: a un «Buena
  tarde» se le contestó con la pregunta 2, como si hubiera contestado la
  1, y la persona no volvió a escribir.
- Viene a contar algo suyo: «Hola, quiero contarles algo», «tengo una
  queja». Eso no se responde con el guion. Se responde escuchando:
  dile que la escuchas y pídele que te cuente. Las tres preguntas
  esperan; lo que la persona trae de casa va primero, y cuando termine
  de contarlo retomas por donde ibas.

ACUSA RECIBO SIEMPRE, ANTES DE PREGUNTAR
Ningún mensaje tuyo puede ser una pregunta pelada. La persona que
escribió la respuesta más larga y más cálida que hemos recibido se llevó
la siguiente pregunta sin una palabra de vuelta; los que sí terminaron
la conversación habían recibido antes un «me alegra mucho que te guste».

El acuse va primero, es corto —cinco o seis palabras— y es humano:
«Uy, qué bueno leer eso», «Jajaja, buenísimo», «Gracias por decirlo así
de claro», «Qué pesar, en serio».

Lo que NO es acusar recibo: repetirle lo que acaba de decir para
demostrar que entendiste. Nada de «Entiendo, la puntualidad es clave
para ti» ni «Eso es genial, el ambiente es muy importante». Eso suena a
call center y es peor que no decir nada.

CÓMO CONVERSAR
- Cuando sepas su nombre úsalo, pero no en cada mensaje: cansa. Mientras
  no lo sepas, no lo reemplaces por apodos: nada de "amigo" ni "crack".
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
  pide el nombre y el celular. Al pedirlos tienen que ir SIEMPRE las dos
  cosas, con esas palabras o parecidas: que es **opcional** y para qué es
  (por si quieren responderle). Pedir un número sin decir eso es lo que
  hace que la gente se salga. Aquí sí va el nombre: a estas alturas la
  persona ya contó algo y darlo tiene sentido, mientras que pedirlo de
  entrada es lo que hacía que cerraran el chat sin escribir. Ese mensaje
  NO lleva [FIN].
- Después de que conteste eso —dé el número o diga que no—: agradece
  de verdad, corto, y ahí sí termina con [FIN] en una línea aparte.

REGLAS DE [FIN], QUE NO SE ROMPEN
- [FIN] va en UN solo mensaje de toda la conversación: el último.
- Un mensaje con [FIN] no puede llevar ninguna pregunta.
- Nunca [FIN] antes de tener las tres respuestas.
- Nunca [FIN] en el mismo mensaje donde te contaron algo delicado.
`.trim();

/* ─────────────────────────────────────────────────────────────
   Que no le pase por encima a lo que la persona escribió

   Pedírselo al guion es necesario pero no alcanza: el modelo ya tenía
   instrucciones de conversar y aun así a un «Buena tarde» le contestó
   con la pregunta 2. Estas dos funciones son la parte que no depende de
   que el modelo tenga un buen día.
   ───────────────────────────────────────────────────────────── */

// Palabras que solo son cortesía. Si al quitarlas no queda nada, el
// mensaje era un saludo y no la respuesta a ninguna pregunta.
//
// "bien" y "todo" NO están en la lista a propósito: "todo bien" sí es
// una respuesta —vaga, pero respuesta— a "¿qué te hizo volver?", y el
// guion ya sabe qué hacer con las respuestas vagas (repreguntar una
// vez). Tratarla como saludo sería el mismo atropello, al revés.
const CORTESIA = new Set([
  'hola', 'holaa', 'holaaa', 'ola', 'holi', 'holis', 'hey', 'ey', 'hi', 'hello',
  'buenas', 'buenos', 'buena', 'buen', 'dia', 'dias', 'tarde', 'tardes',
  'noche', 'noches', 'saludos', 'quiubo', 'quihubo', 'quiubole',
  'que', 'mas', 'como', 'estan', 'estas', 'esta', 'van', 'va',
  'gracias', 'señores', 'senores', 'equipo', 'tumbao', 'feliz', 'muy',
  'pues', 'ps', 'y', 'a', 'de', 'ustedes', 'usted', 'les', 'con',
]);

// "Hola, quiero contarles algo" no es un saludo ni es una respuesta: es
// alguien que trae algo de su casa. Contestarle con el guion es la
// forma más rápida de perderlo.
const ANUNCIOS = [
  /\b(quiero|queria|necesito|puedo|quisiera)\s+(contar|contarl|decir|decirl|comentar|hablar|poner|hacer)/,
  /\bles?\s+(quiero|queria)\s+(contar|decir|comentar)/,
  /\btengo\s+(algo|una|un)\s+(que|queja|sugerencia|reclamo|problema|caso)/,
  /\bes?\s?cuchen/,
];

/* Verdadero si el mensaje NO es respuesta a la pregunta que estaba
 * sobre la mesa: un saludo pelado o el anuncio de que viene a contar
 * algo. Se usa en dos sitios distintos, y por eso vive suelta:
 *
 * 1. para avisarle al modelo, en ese turno, que no avance;
 * 2. para no contarlo como una de las respuestas que hacen falta antes
 *    de poder cerrar. Sin esto, un «Buena tarde» adelanta el cierre un
 *    paso y la conversación termina con una pregunta sin hacer. */
export function esArranque(texto) {
  const t = String(texto || '')
    .toLowerCase()
    .normalize('NFD').replace(/[\u0300-\u036f]/g, '')  // tildes fuera
    .replace(/[^\p{L}\s]/gu, ' ')                      // signos y emojis fuera
    .replace(/\s+/g, ' ')
    .trim();
  if (!t) return false;
  // Si escribió un párrafo, ya está contando algo: no lo toques.
  if (t.length > 120) return false;
  if (ANUNCIOS.some((r) => r.test(t))) return true;
  return t.split(' ').every((p) => CORTESIA.has(p));
}

// El acuse de recibo que sirve tanto si le encantó como si se quiere
// ir. Cualquier otro —"qué bueno", "qué pesar"— se equivoca la mitad de
// las veces, y equivocarse de emoción es peor que ser sobrio.
const ACUSE = 'Gracias por contarme.';

/* Red de seguridad del acuse de recibo. El guion se lo pide al modelo,
 * pero el caso que dolió —la respuesta más larga y más cálida
 * contestada con la siguiente pregunta a secas— fue un modelo saltándose
 * justo esa instrucción. Aquí, si el mensaje empieza en la pregunta, se
 * le antepone una línea.
 *
 * Solo mira el arranque: un mensaje que empieza con palabras ya trae su
 * acuse, y meterle otro encima lo volvería redundante. */
export function conAcuse(respuesta) {
  const r = String(respuesta || '').trim();
  if (!r) return r;
  const primera = r.split('\n')[0].trim();
  const pelada = primera.startsWith('¿') ||
    LAS_TRES.some((q) => primera.startsWith(q.slice(0, 22)));
  return pelada ? `${ACUSE}\n\n${r}` : r;
}

// Lo que se le añade al guion SOLO en el turno en que la persona saludó
// o anunció que viene a contar algo. Va como parte del system y no como
// un mensaje más para que no quede en la historia de la conversación:
// es una instrucción de ese turno, no algo que nadie dijo.
const NOTA_ESCUCHA = `
AVISO SOBRE EL ÚLTIMO MENSAJE
Lo que acaba de escribir la persona NO es la respuesta a ninguna de las
tres preguntas: es un saludo, o el anuncio de que quiere contarte algo.
NO avances a la pregunta siguiente.

Si solo saludó: devuélvele el saludo en una línea y vuelve a poner la
pregunta 1 con tus propias palabras, sin sonar a robot repitiéndose.
Si viene a contar algo: dile que la escuchas y pídele que te cuente.
Nada de guion hasta que termine.
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

// `nota` es una instrucción que vale solo para este turno —hoy, la de no
// avanzar cuando la persona apenas saludó—. Va pegada al system y no
// como un mensaje más de la conversación: si entrara en la historia
// quedaría escrito ahí algo que nadie dijo.
async function conversar(env, historia, nota = '') {
  const guion = nota ? `${INSTRUCCIONES}\n\n${nota}` : INSTRUCCIONES;

  if (!env.OPENAI_API_KEY) {
    if (!hayCF(env)) return ensayo(historia);
    const d = await env.AI.run(env.MODELO_CF || MODELO_CF, {
      messages: [{ role: 'system', content: guion }, ...historia],
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
      messages: [{ role: 'system', content: guion }, ...historia],
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
// preguntas contando cuántas veces contestó la persona.
//
// Ya no arranca pidiendo el nombre: eso quedó de la versión anterior del
// saludo y contradecía al guion de verdad, que pide el nombre al final.
// Y los saludos no cuentan como respuesta, igual que en el camino con
// modelo: si lo único que llegó fue "buenas tardes", se vuelve a poner
// la pregunta 1, no la 2.
function ensayo(historia) {
  const dichas = historia.filter(
    (m) => m.role === 'user' && !esArranque(m.content)).length;
  const guion = [
    `¡Hola! Qué bueno leerte. Cuéntame con una frase: ${LAS_TRES[0]}`,
    `Qué bueno saberlo. Ahora una más difícil: ${LAS_TRES[1]}`,
    `Gracias por la franqueza. Última: ${LAS_TRES[2]}`,
    'Mil gracias. Si quieres agregar algo, mándame una nota de voz.\n\n' +
      'Y si nos dejas tu nombre y tu celular te podemos responder. Es ' +
      'opcional, y solo para eso.',
    'Gracias de verdad. Esto nos sirve más de lo que crees.\n\n[FIN]',
  ];
  return guion[Math.min(dichas, guion.length - 1)];
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
   Que no se pierda lo que la gente sí contó

   EL CASO, del 21 de agosto. Una clienta contestó las tres preguntas
   —«Los extraño muchoooo de lunes a viernes 😭», «Trabajooo», «Que es
   lo mejor de lo mejor 😃»— y cerró la pestaña. En el correo del lunes
   salió como «Sin nombre · (sin resumen)».

   POR QUÉ. /api/cerrar era el único sitio donde se escribían `resumen`,
   `tipo`, `nombre` y `transcripcion`, y lo llama la página cuando el bot
   da la conversación por terminada. Quien ya dijo lo que tenía que decir
   cierra la pestaña, y eso no se llamaba nunca. Los mensajes sí estaban
   en la tabla `mensajes`, pero nada de lo que se lee la consultaba.

   EL ARREGLO, EN DOS CAPAS. Se eligió así y no de otra forma:

   1. CADA TURNO ESCRIBE (aquí abajo, `guardarAvance`). Sin modelo, sin
      coste y sin depender de nada posterior: al terminar cada turno la
      fila ya tiene la conversación entera y un resumen provisional que
      son las palabras de la persona, tal cual. A partir de ahí, pase lo
      que pase —se va la luz, el modelo se cae, cierra la pestaña— lo que
      dijo se lee el lunes. Este es el que cumple el requisito duro.

   2. EL BARRIDO (`completarAbandonadas`) mejora eso a una ficha de
      verdad —tipo, nombre, celular, si es urgente— y corre cuando se
      lee: al pedir /api/pendientes y al abrir /leer.

   Lo que se descartó y por qué:

   - Clasificar en cada turno con ctx.waitUntil: es una llamada al modelo
     por mensaje, o sea multiplicar por tres o cuatro el coste de cada
     conversación, para acabar tirando todas las fichas menos la última.
     El barrido saca la ficha UNA vez, cuando ya se sabe que no va a
     haber más mensajes.
   - Un aviso del navegador al cerrar la pestaña (sendBeacon): el arreglo
     no puede depender del navegador, que es justo el que se está yendo.
     En iOS ese aviso se pierde la mitad de las veces, y marcar la
     conversación como completa sería además mentir.
   - Reconstruir desde `mensajes` solo al leer: deja la lectura dependiendo
     de que el modelo esté vivo en ese momento. La capa 1 ya deja la fila
     legible sin preguntarle a nadie. (El barrido sí lee `mensajes`, pero
     como fuente, no como parche.)
   ───────────────────────────────────────────────────────────── */

// La conversación en crudo, como se guarda y como se lee en /leer. Una
// sola función porque la escriben tres sitios distintos —cada turno, el
// cierre y el barrido— y si el formato se separa, la pantalla enseña una
// mezcla de dos.
export function transcripcionDe(historia) {
  return (Array.isArray(historia) ? historia : [])
    .map((m) => (m.role === 'user' ? '> ' : '') + String(m.content ?? ''))
    .join('\n');
}

// Solo lo que dijo la persona, sin las preguntas del bot. Es el resumen
// provisional mientras no haya ficha: sus propias frases se leen mejor
// que "(sin resumen)", que hace pensar que no se guardó nada.
export function palabrasDe(historia) {
  return (Array.isArray(historia) ? historia : [])
    .filter((m) => m.role === 'user')
    .map((m) => String(m.content ?? '').trim())
    .filter(Boolean)
    .join(' · ')
    .slice(0, 1200);
}

/* Capa 1: al cerrar cada turno, la fila queda legible.
 *
 * Dos cuidados que no son adorno:
 *
 * - NUNCA ENCOGE. Si la persona recarga la pestaña, la página vuelve a
 *   empezar con la historia vacía y este turno traería solo la mitad
 *   final de la conversación. Sin la comparación de largo, recargar
 *   borraría lo que ya se había contado.
 * - NO PISA UNA FICHA. `tipo` solo lo escriben el cierre y el barrido,
 *   así que `tipo is null` significa "esto todavía es provisional". En
 *   cuanto hay ficha de verdad, el resumen del modelo manda. */
async function guardarAvance(env, conv, historia, hubo) {
  if (!hubo) {
    await env.DB.prepare(
      `update conversaciones set turnos = turnos + 1 where id = ?1`
    ).bind(conv).run();
    return;
  }
  await env.DB.prepare(
    `update conversaciones
        set turnos = turnos + 1,
            transcripcion = case
              when length(?2) >= length(coalesce(transcripcion, '')) then ?2
              else transcripcion end,
            resumen = case
              when tipo is null and length(?3) >= length(coalesce(resumen, ''))
              then ?3 else resumen end
      where id = ?1`
  ).bind(conv, transcripcionDe(historia), palabrasDe(historia)).run();
}

// Cuántos minutos callada para darla por abandonada. No es por elegancia:
// sin esto, abrir /leer mientras alguien está contestando le sacaría la
// ficha a media conversación y la dejaría congelada ahí.
const QUIETA_MIN = 30;

/* Capa 2: la ficha de las que nadie cerró.
 *
 * Corre al leer —/api/pendientes una vez por semana, /leer cuando Tania
 * la abre— y no en un cron: un cron es un despliegue más y una cosa más
 * que se puede quedar sin secreto y fallar en silencio, que es
 * exactamente lo que pasó con el reporte del lunes 17. Aquí, si algo
 * falla, falla delante de quien está mirando.
 *
 * Deja `completa = 0` a propósito: la conversación NO se completó, y en
 * /leer eso se ve como «se cortó». Marcarla como completa sería tapar el
 * dato de cuánta gente se va a mitad de camino.
 *
 * Nunca puede tumbar a quien la llama: si el barrido revienta, la lectura
 * sigue con lo que la capa 1 ya dejó escrito. */
export async function completarAbandonadas(env, limite = 8) {
  // Sin modelo no hay ficha que sacar, y el resumen provisional de la
  // capa 1 ya es mejor que lo que saldría de aquí.
  if (!env.OPENAI_API_KEY && !hayCF(env)) return 0;

  try {
    const corte = new Date(Date.now() - QUIETA_MIN * 60000).toISOString();
    const { results } = await env.DB.prepare(
      `select c.id as id
         from conversaciones c
         join (select conversacion, max(creado_at) as ultimo
                 from mensajes group by conversacion) m
           on m.conversacion = c.id
        -- tipo is null = nadie le ha sacado ficha todavía, ni el cierre
        -- ni un barrido anterior.
        where c.completa = 0 and c.tipo is null and c.turnos > 1
          and m.ultimo < ?1
        order by c.empezada_at desc
        limit ?2`
    ).bind(corte, limite).all();

    const ids = (results || []).map((r) => r.id);
    if (!ids.length) return 0;

    // `mensajes` es la fuente y no `transcripcion`: se escribe mensaje a
    // mensaje desde el primer día, así que también sirve para las
    // conversaciones viejas, las que quedaron con todo en NULL antes de
    // que existiera la capa 1. Ahí está la clienta del 21 de agosto.
    const huecos = ids.map((_, i) => `?${i + 1}`).join(',');
    const { results: sueltos } = await env.DB.prepare(
      `select conversacion, de, texto from mensajes
        where conversacion in (${huecos})
        order by conversacion, id`
    ).bind(...ids).all();

    const porConversacion = new Map(ids.map((id) => [id, []]));
    for (const m of sueltos || []) {
      const h = porConversacion.get(m.conversacion);
      if (h) h.push({ role: m.de === 'persona' ? 'user' : 'assistant',
                      content: m.texto });
    }

    const ficha = async (id) => {
      const historia = porConversacion.get(id) || [];
      // Solo el saludo del bot: eso no es una opinión, es una pestaña
      // que alguien abrió y cerró.
      if (!historia.some((m) => m.role === 'user')) return false;

      const f = await extraerFicha(env, historia);
      await env.DB.prepare(
        `update conversaciones
            set nombre = ?2, telefono = ?3, tipo = ?4, resumen = ?5,
                urgente = ?6, motivo_urgente = ?7, transcripcion = ?8,
                cerrada_at = ?9
          where id = ?1 and completa = 0`
      ).bind(id, f.nombre, f.telefono, f.tipo, f.resumen,
             f.urgente ? 1 : 0, f.motivo, transcripcionDe(historia), ahora()).run();
      return true;
    };

    // De a cuatro. En fila, una docena de conversaciones serían una
    // docena de esperas al modelo con n8n aguantando al otro lado; todas
    // de golpe es la forma de que Workers AI empiece a rechazar por
    // ritmo. Y con allSettled, la que falle no se lleva a las demás: se
    // queda sin ficha, con las palabras de la persona, y le toca en el
    // siguiente barrido.
    let hechas = 0;
    for (let i = 0; i < ids.length; i += 4) {
      const tanda = await Promise.allSettled(ids.slice(i, i + 4).map(ficha));
      hechas += tanda.filter((r) => r.status === 'fulfilled' && r.value).length;
      for (const r of tanda) {
        if (r.status === 'rejected') console.log('ficha:', String(r.reason).slice(0, 120));
      }
    }
    return hechas;
  } catch (e) {
    console.log('barrido:', e && e.message);
    return 0;
  }
}

/* ─────────────────────────────────────────────────────────────
   Las tres cosas de la semana

   Hasta ahora el análisis solo existía dentro del correo del lunes: si
   el correo no llegaba —y no llegó cinco días— no había ningún sitio
   donde mirarlo. Y aunque llegue, entre semana no hay forma de ver qué
   está diciendo la gente sin leerse las conversaciones una por una.

   Esto lo calcula el propio Worker con Workers AI, que no necesita
   llave de nadie, y lo guarda en la caché de Cloudflare: mientras no
   entre una conversación nueva, abrir la página no vuelve a llamar al
   modelo.
   ───────────────────────────────────────────────────────────── */

// Cuántas conversaciones con contenido hacen falta para que sacar
// conclusiones no sea inventar. Con una sola, cualquier "patrón" es esa
// persona; con dos ya se puede decir si coinciden o no.
const MINIMO_PARA_ANALIZAR = 2;

const ANALIZAR = `
Eres el analista de Tumbao, una academia de baile en Bucaramanga,
Colombia. Te llega lo que los clientes contaron por el chat de
opiniones y sacas las TRES cosas que la dueña tiene que saber.

Devuelves SOLO un objeto JSON con estas claves: titular, claves,
critico, cita.

titular: UNA frase con lo más importante. Concreta.
  Mal:  la gente dio opiniones variadas.
  Bien: tres personas distintas dijeron que el salón de las 7 pm queda apretado.

claves: array de 1 a 3 objetos con titulo, detalle y cuantos.
  Cada uno es un patrón que se repite o la causa detrás de varias
  quejas. NO es el resumen de una conversación suelta.
  titulo: tres o cuatro palabras.
  detalle: una o dos frases.
  cuantos: texto corto, por ejemplo «3 de 7 personas». Nunca un número
  suelto, y nunca más de las personas que de verdad lo dijeron.
  Si solo da para una cosa clave, devuelve una. Rellenar hasta tres
  inventando es peor que devolver una sola.

critico: un objeto con que y por_que, o null. Solo lo que hace perder
  plata o clientes, o alguien a quien trataron mal. Si no hay nada
  crítico DE VERDAD, va null. Una alerta falsa hace que dejen de
  leerse las de verdad.

cita: UNA frase textual de un cliente, tal cual la dijo. Si ninguna
  vale la pena, cadena vacía.

REGLAS QUE MANDAN SOBRE TODO
- No inventes nada que no esté en los datos. Prefiere corto y cierto.
- Si hubo poquitas conversaciones, dilo en el titular en vez de estirar
  conclusiones.
- Escribe para alguien que tiene tres minutos y tiene que decidir.
- Español de Colombia, directo, sin lenguaje corporativo. Nada de
  "feedback", "insights" ni "engagement".

EL FORMATO IMPORTA
JSON válido y nada más: sin vallas de código, sin explicaciones antes
ni después. Dentro de los textos no uses comillas dobles nunca —para
citar usa «comillas angulares»—, porque una comilla doble suelta parte
el JSON y el análisis se pierde.
`.trim();

async function analizarLote(env, filas) {
  const datos = JSON.stringify({
    cuantas: filas.length,
    conversaciones: filas.map((f) => ({
      quien: f.nombre || null,
      tipo: f.tipo || null,
      urgente: !!f.urgente,
      motivo_urgente: f.motivo_urgente || null,
      dijo: f.resumen || '',
      cuando: f.empezada_at,
    })),
  });

  if (env.OPENAI_API_KEY) {
    const r = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: { Authorization: `Bearer ${env.OPENAI_API_KEY}`,
                 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model: env.MODELO_CHAT || 'gpt-4o-mini',
        temperature: 0,
        response_format: { type: 'json_object' },
        messages: [{ role: 'system', content: ANALIZAR },
                   { role: 'user', content: datos }],
      }),
    });
    if (!r.ok) throw new Error(`Analizar ${r.status}`);
    const cuerpo = await r.json();
    return sacarJSON(cuerpo.choices?.[0]?.message?.content || '');
  }

  if (!hayCF(env)) return null;
  const d = await env.AI.run(env.MODELO_CF || MODELO_CF, {
    messages: [{ role: 'system', content: ANALIZAR },
               { role: 'user', content: datos }],
    max_tokens: 900,
    temperature: 0,
  });
  return sacarJSON(d.response);
}

/* Se recalcula solo cuando entra material nuevo.
 *
 * La huella son las conversaciones que se están analizando: cuántas y
 * cuál es la última. Si nadie escribió desde la última vez, la huella
 * es la misma y la página se pinta con lo guardado sin llamar al
 * modelo. Abrir la página diez veces al día no puede costar diez
 * análisis.
 *
 * Se usa la caché de Cloudflare y no una tabla porque esto es un
 * resultado, no un dato: si se pierde se vuelve a calcular y no pasa
 * nada. Guardarlo en D1 sería inventar estado que hay que mantener. */
async function analisisDeLaSemana(env, filas, forzar) {
  const huella = `${filas.length}:${filas[0] ? filas[0].empezada_at : '-'}`;
  const llave = new Request(`https://opina.tumbao/__analisis/${encodeURIComponent(huella)}`);
  const cache = caches.default;

  if (!forzar) {
    const guardado = await cache.match(llave);
    if (guardado) return await guardado.json();
  }

  const d = await analizarLote(env, filas);
  if (!d || !d.titular) return null;

  await cache.put(llave, new Response(JSON.stringify(d), {
    headers: { 'Content-Type': 'application/json',
               'Cache-Control': 'max-age=604800' },
  }));
  return d;
}

/* Qué conversaciones entran en las tarjetas.
 *
 * "La semana" son los últimos 7 días. Pero si esa semana no dio para
 * nada, enseñar tarjetas vacías no ayuda: se cae hacia atrás a lo
 * último que sí hubo y se dice con todas las letras de cuándo es. Un
 * análisis del mes pasado sirve; uno que finge ser de esta semana, no. */
export function loQueSeAnaliza(filas) {
  const conAlgo = filas
    .filter((f) => f.resumen && f.turnos > 1)
    .sort((a, b) => String(b.empezada_at).localeCompare(String(a.empezada_at)));

  const corte = new Date(Date.now() - 7 * 86400000).toISOString();
  const semana = conAlgo.filter((f) => String(f.empezada_at) >= corte);

  if (semana.length >= MINIMO_PARA_ANALIZAR) {
    return { filas: semana, ventana: 'los últimos 7 días', fresco: true };
  }
  if (conAlgo.length >= MINIMO_PARA_ANALIZAR) {
    const ultimas = conAlgo.slice(0, 12);
    const desde = cuando(ultimas[ultimas.length - 1].empezada_at);
    const hasta = cuando(ultimas[0].empezada_at);
    return { filas: ultimas, ventana: `${desde} — ${hasta}`, fresco: false };
  }
  return { filas: [], ventana: null, fresco: false };
}

/* ─────────────────────────────────────────────────────────────
   La pantalla de lectura
   ───────────────────────────────────────────────────────────── */

const esc = (s) =>
  String(s ?? '').replace(/[&<>"']/g, (c) =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

// El modelo a veces devuelve el titular en minúscula. Es un titular:
// que empiece como una frase.
const mayus = (t) => (t ? t.charAt(0).toUpperCase() + t.slice(1) : t);

const cuando = (iso) => {
  if (!iso) return '';
  return new Intl.DateTimeFormat('es-CO', {
    timeZone: 'America/Bogota', day: 'numeric', month: 'short',
    hour: 'numeric', minute: '2-digit', hour12: true,
  }).format(new Date(iso));
};

function paginaLeer(filas, problema, analisis) {
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

 /* ── las tres cosas de la semana ── */
 .titular{font-size:1.18rem;line-height:1.4;font-weight:600;margin:0 0 .3rem}
 .ventana{color:var(--tx3);font-size:.78rem;margin:0 0 1rem}
 .ventana a{color:var(--tx3);text-decoration:underline}
 .claves{display:grid;gap:.7rem;margin:0 0 1.2rem;
         grid-template-columns:repeat(auto-fit,minmax(15rem,1fr))}
 .clave{background:var(--bg2);border:1px solid var(--line);border-radius:14px;
        padding:.9rem 1rem;border-top:2px solid var(--hot)}
 .clave b{display:block;font-size:.95rem;margin-bottom:.25rem}
 .clave .cuantos{display:inline-block;font-size:.7rem;color:var(--tx3);
        border:1px solid var(--line);border-radius:999px;padding:.05rem .5rem;
        margin-bottom:.4rem}
 .clave p{margin:0;color:var(--tx2);font-size:.88rem;line-height:1.5}
 .critico{background:rgba(255,107,129,.08);border:1px solid rgba(255,107,129,.45);
          border-radius:14px;padding:.9rem 1rem;margin:0 0 1.2rem}
 .critico b{color:var(--bad)}
 .critico p{margin:.25rem 0 0;color:var(--tx2);font-size:.88rem}
 .cita{margin:0 0 1.6rem;padding:.85rem 1.1rem;background:var(--bg2);
       border-left:3px solid var(--gold);border-radius:0 10px 10px 0;
       font-style:italic;color:var(--tx2)}
 hr.sep{border:0;border-top:1px solid var(--line);margin:1.8rem 0 1.1rem}
 h2.seccion{font-size:.72rem;letter-spacing:.06em;text-transform:uppercase;
            color:var(--tx3);margin:0 0 .8rem;font-weight:600}
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
        : '<span class="sin">Sin resumen: no se pudo sacar la ficha. Lo que dijo está abajo, en crudo.</span>'}</p>
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
    ${arriba(analisis)}
    <hr class="sep">
    <h2 class="seccion">Una por una</h2>
    ${tarjetas}`);
}

/* Las tarjetas de arriba: lo que hay que saber sin leerse nada.
 *
 * Nunca puede tumbar la página. Si el análisis falla —el modelo no
 * contesta, devuelve algo que no parsea, no hay material suficiente—
 * se dice qué pasó en una línea y debajo siguen las conversaciones,
 * que es lo que de verdad no se puede perder. */
export function arriba(a) {
  if (!a) return '';

  if (a.error) {
    return `<div class="aviso">No se pudo sacar el resumen de la semana
      (${esc(a.error)}). Las conversaciones están completas aquí abajo.</div>`;
  }

  if (!a.datos) {
    const n = a.conCuantas || 0;
    return `<div class="aviso">Todavía no hay material para sacar conclusiones:
      ${n === 0 ? 'nadie ha contado nada' : `solo ${n} conversación${n === 1 ? '' : 'es'} con contenido`}.
      Con ${MINIMO_PARA_ANALIZAR} ya se puede empezar a ver si coinciden.</div>`;
  }

  const d = a.datos;
  const claves = (Array.isArray(d.claves) ? d.claves : []).slice(0, 3);

  return `
    <p class="titular">${esc(mayus(d.titular || ''))}</p>
    <p class="ventana">${a.fresco
      ? `De ${esc(a.ventana)}`
      : `Esta semana no hubo nada nuevo. Esto es lo último que hubo: ${esc(a.ventana)}`}
      · <a href="?token=${esc(a.token)}&amp;refrescar=1">volver a calcular</a></p>

    ${d.critico && d.critico.que ? `<div class="critico">
      <b>⚠ ${esc(d.critico.que)}</b>
      <p>${esc(d.critico.por_que || '')}</p></div>` : ''}

    ${claves.length ? `<div class="claves">${claves.map((c) => `
      <div class="clave">
        <b>${esc(c.titulo || '')}</b>
        ${c.cuantos ? `<span class="cuantos">${esc(c.cuantos)}</span>` : ''}
        <p>${esc(c.detalle || '')}</p>
      </div>`).join('')}</div>` : ''}

    ${d.cita ? `<p class="cita">«${esc(d.cita)}»</p>` : ''}`;
}

export default {
  // `ctx` es por waitUntil: en /leer, las conversaciones abandonadas que
  // no caben en la carga de la página se terminan de completar después
  // de haberla devuelto.
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const ruta = url.pathname;

    if (request.method === 'OPTIONS') return new Response(null, { headers: CORS });

    try {
      // ── un turno de conversación ──
      if (ruta === '/api/mensaje' && request.method === 'POST') {
        const b = await request.json();
        const conv = String(b.conversacion || '').slice(0, 40);
        if (!/^[a-f0-9-]{16,40}$/i.test(conv)) return json({ error: 'conversacion_invalida' }, 400);

        // La historia entera se guarda; al modelo solo se le mandan los
        // últimos 24 mensajes. Antes se recortaba primero y se guardaba
        // el recorte, o sea que una conversación larga se habría
        // guardado a medias.
        const entera = Array.isArray(b.historia) ? b.historia.slice(0, 200) : [];
        await asegurarConversacion(env, conv);

        const suyo = String(b.texto || '').slice(0, 4000);
        if (suyo) {
          entera.push({ role: 'user', content: suyo });
          await guardarMensaje(env, conv, 'persona', suyo, b.medio);
        }

        // Un saludo pelado o un "quiero contarles algo" no son la
        // respuesta a ninguna pregunta. Cuando lo son, este turno lleva
        // una instrucción extra para que el bot escuche en vez de
        // disparar la siguiente pregunta: a un «Buena tarde» le contestó
        // con la pregunta 2 y la persona no volvió a escribir.
        const arranque = Boolean(suyo) && esArranque(suyo);

        // El saludo es siempre el mismo y no se le pide a ningún modelo:
        // así la persona que abre el enlace sabe de una quién le habla y
        // para qué, en vez de recibir un "Hola, ¿cómo te llamas?" pelado.
        const cruda = entera.length === 0
          ? SALUDO
          : await conversar(env, entera.slice(-24), arranque ? NOTA_ESCUCHA : '');

        // Red de seguridad contra el cierre prematuro. Un modelo puede
        // querer despedirse justo cuando la persona acaba de contar algo
        // incómodo —que es cuando menos hay que colgarle— o después de
        // dos respuestas. El guion lo prohíbe; esto lo hace imposible.
        // Hacen falta cuatro cosas suyas: las tres respuestas y lo que
        // conteste al cierre —el nombre y el celular, o que no—. Si aún
        // no están, [FIN] se ignora y el bot sigue.
        //
        // Los saludos no cuentan: si no, un «Buenas tardes» al principio
        // adelanta el cierre un paso y la conversación termina con una
        // de las tres preguntas sin hacer.
        const suyas = entera.filter(
          (m) => m.role === 'user' && !esArranque(m.content)).length;
        const listo = cruda.includes('[FIN]') && suyas >= 4;

        // El acuse solo se fuerza cuando la persona dijo algo de verdad:
        // meterle un "gracias por contarme" a quien apenas escribió
        // "hola" suena a máquina, que es lo contrario de lo que busca.
        const respuesta = arranque || !suyo
          ? cruda.replace('[FIN]', '').trim()
          : conAcuse(cruda.replace('[FIN]', '').trim());

        await guardarMensaje(env, conv, 'bot', respuesta, 'texto');
        entera.push({ role: 'assistant', content: respuesta });
        // Aquí es donde la opinión deja de depender de que la persona
        // juegue el guion hasta el final.
        await guardarAvance(env, conv, entera, Boolean(suyo));

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
          // La transcripción no encoge, por lo mismo que en guardarAvance:
          // la página manda la historia que tiene en memoria, y si la
          // persona recargó a mitad de camino esa historia empieza en la
          // recarga. La ficha sí manda siempre: es la buena.
          `update conversaciones
              set nombre = ?2, telefono = ?3, tipo = ?4, resumen = ?5,
                  urgente = ?6, motivo_urgente = ?7,
                  transcripcion = case
                    when length(?8) >= length(coalesce(transcripcion, '')) then ?8
                    else transcripcion end,
                  cerrada_at = ?9, completa = 1
            where id = ?1`
        ).bind(
          conv, f.nombre, f.telefono, f.tipo, f.resumen,
          f.urgente ? 1 : 0, f.motivo,
          transcripcionDe(historia),
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

        // Antes de armar el reporte, sacarle ficha a las que nadie cerró.
        // Es el sitio exacto donde se perdía la opinión del 21 de agosto:
        // la conversación estaba entera en D1 y salía en el correo como
        // "Sin nombre · (sin resumen)". Va antes del select a propósito,
        // para que lo que se acaba de rescatar entre en ESTE reporte y no
        // en el de la semana que viene.
        await completarAbandonadas(env, 12);

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
        // Lo mismo que en /api/pendientes: las que nadie cerró se
        // completan antes de pintar. Se hacen pocas aquí y el resto en
        // segundo plano —con waitUntil la página no espera— porque esto
        // es una pantalla que se abre a mirar, no un lote que corre solo:
        // media docena de llamadas al modelo ya se notan al cargar, y las
        // que queden estarán listas la próxima vez que se abra.
        await completarAbandonadas(env, 6);
        if (ctx && typeof ctx.waitUntil === 'function') {
          ctx.waitUntil(completarAbandonadas(env, 24));
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
        const filas = results || [];

        // Las tres cosas de la semana. Va en su propio try: si el
        // modelo se cae, la página tiene que salir igual con las
        // conversaciones. Perder el resumen es un fastidio; perder el
        // acceso a lo que la gente contó, no.
        const { filas: aAnalizar, ventana, fresco } = loQueSeAnaliza(filas);
        let analisis = { datos: null, ventana, fresco, token: dado,
                         conCuantas: aAnalizar.length };
        if (aAnalizar.length >= MINIMO_PARA_ANALIZAR) {
          try {
            analisis.datos = await analisisDeLaSemana(
              env, aAnalizar, url.searchParams.get('refrescar') === '1');
            if (!analisis.datos) analisis.error = 'no hay modelo configurado';
          } catch (e) {
            analisis = { error: String((e && e.message) || e).slice(0, 120),
                         token: dado };
          }
        }

        return new Response(paginaLeer(filas, null, analisis), {
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
