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

const INSTRUCCIONES = `
Eres el asistente de Tumbao, una academia de baile en Bucaramanga,
Colombia. Estás recogiendo opiniones de gente que ya viene a clases.

TU TRABAJO
Llevar una conversación corta y cálida en la que la persona te cuente
de verdad. No eres un formulario con emojis: eres alguien de la
academia que sí quiere saber.

LAS TRES PREGUNTAS, EN ESTE ORDEN
1. ${LAS_TRES[0]}
2. ${LAS_TRES[1]}
3. ${LAS_TRES[2]}

CÓMO CONVERSAR
- Empieza saludando y preguntando su nombre. Nada más. Una línea.
- Usa su nombre después, pero no en cada mensaje: cansa.
- Una pregunta por mensaje. Nunca dos.
- Mensajes cortos: dos o tres líneas. Esto se lee en un celular.
- Tutea. Habla como se habla en Bucaramanga, sin ser caricatura. Nada
  de "¡Qué chévere parcero!" forzado.
- Si la respuesta es de tres palabras o vaga ("bien", "todo bueno",
  "nada"), repregunta UNA vez pidiendo algo concreto: "¿te acuerdas de
  algún momento en particular?". Solo una vez. Si insiste en ser breve,
  sigue adelante sin insistir más.
- Si te cuentan algo incómodo —que alguien la hizo sentir mal, un
  problema con un profesor, algo de plata— NO lo minimices ni lo
  arregles con optimismo. Agradece que lo diga, pregunta lo mínimo para
  entenderlo, y sigue. No prometas soluciones: tú no decides eso.
- Nunca inventes datos de Tumbao: horarios, precios, nombres de
  profesores. Si te preguntan algo así, di que eso lo confirman por
  WhatsApp.

EL CIERRE
Cuando ya tengas las tres respuestas:
1. Ofrece que mande una nota de voz si quiere agregar algo. Opcional,
   sin insistir.
2. Pide el celular, dejando claro que es opcional y para qué: por si
   quieren responderle. Si dice que no, perfecto.
3. Agradece de verdad, corto, y termina el mensaje con la marca [FIN]
   en una línea aparte.

La marca [FIN] va SOLO en el último mensaje. Nunca antes.
`.trim();

/* ─────────────────────────────────────────────────────────────
   OpenAI
   ───────────────────────────────────────────────────────────── */

async function conversar(env, historia) {
  // Sin llave, modo de ensayo: la página entera se puede probar sin
  // gastar un peso ni depender de que el secreto ya esté puesto.
  if (!env.OPENAI_API_KEY) return ensayo(historia);

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
  if (!env.OPENAI_API_KEY) return '(nota de voz de prueba: sin llave no se transcribe)';

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
  return (await r.json()).text?.trim() || '';
}

async function describirImagen(env, dataUrl) {
  if (!env.OPENAI_API_KEY) return '(imagen de prueba: sin llave no se describe)';

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
          { type: 'text', text: 'Describe en una o dos frases qué muestra esta imagen. Es algo que un cliente de una academia de baile mandó junto a su opinión.' },
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
resumen   - qué dijo, en 2 o 3 frases. Conserva entre comillas la frase
            textual más reveladora. Nada de "el cliente expresa que":
            escribe como le contarías a un compañero.
urgente   - true SOLO si hay algo que no puede esperar al lunes: acoso,
            trato irrespetuoso, riesgo físico, un cobro mal hecho, o
            alguien que dice que se va a retirar ya. Molestias normales
            NO son urgentes.
motivo    - si urgente es true, una frase de por qué. Si no, null.

Ante la duda en "urgente", pon false. Una alerta falsa cada semana hace
que dejen de leerse las de verdad.
`.trim();

async function extraerFicha(env, historia) {
  const texto = historia
    .map((m) => (m.role === 'user' ? 'CLIENTE: ' : 'TUMBAO: ') + m.content)
    .join('\n');

  if (!env.OPENAI_API_KEY) {
    return { nombre: null, telefono: null, tipo: 'mixto',
             resumen: '(ensayo sin llave) ' + texto.slice(0, 300),
             urgente: false, motivo: null };
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

  // Si el modelo devuelve algo que no es JSON, la ficha sale vacía pero
  // la conversación NO se pierde: la transcripción completa se guarda
  // igual más abajo, y de ahí se puede rehacer a mano.
  let d = {};
  try {
    const cuerpo = await r.json();
    d = JSON.parse(cuerpo.choices?.[0]?.message?.content || '{}');
  } catch (_) {
    d = {};
  }

  const txt = (v, max) => {
    if (v == null) return null;
    const s = String(v).trim();
    return s && s.length <= max ? s : (s ? s.slice(0, max) : null);
  };
  return {
    nombre:   txt(d.nombre, 80),
    telefono: d.telefono ? String(d.telefono).replace(/\D/g, '').slice(0, 15) || null : null,
    tipo:     ['queja', 'sugerencia', 'elogio', 'mixto'].includes(d.tipo) ? d.tipo : 'mixto',
    resumen:  txt(d.resumen, 1200) || '(sin resumen)',
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

        const cruda = await conversar(env, historia);
        const listo = cruda.includes('[FIN]');
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
        return json({ texto: await transcribir(env, audio) });
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
