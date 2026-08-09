import { workflow, node, trigger, sticky, ifElse, expr } from '@n8n/workflow-sdk';

const CRED_OPENAI = { id: 'Mq89XkAH27Mubfus', name: 'OpenAI account OCR Tumbao' };

/* ------------------------------------------------------------------ */
/* Notas de voz                                                        */
/* ------------------------------------------------------------------ */

const webhookVoz = trigger({
  type: 'n8n-nodes-base.webhook',
  version: 2,
  config: {
    name: 'POST cheo/voz',
    parameters: {
      httpMethod: 'POST',
      path: 'tumbao/cheo/voz',
      responseMode: 'responseNode',
      options: { allowedOrigins: '*' },
    },
    position: [0, 0],
  },
  output: [{ body: { audio: 'data:audio/webm;base64,...' } }],
});

const prepararAudio = node({
  type: 'n8n-nodes-base.code',
  version: 2,
  config: {
    name: 'Preparar el audio',
    parameters: {
      mode: 'runOnceForAllItems',
      language: 'javaScript',
      jsCode:
        'const b = ($input.first().json || {}).body || {};\n' +
        'const bruto = typeof b.audio === "string" ? b.audio : "";\n' +
        '\n' +
        '// Se filtra ANTES de llamar a OpenAI: cada llamada cuesta, y una\n' +
        '// entrada basura no va a mejorar por mandarla.\n' +
        'const m = /^data:(audio\\/[a-z0-9.+-]+|video\\/webm)(;codecs=[^;]+)?;base64,(.+)$/i.exec(bruto);\n' +
        'if (!m) {\n' +
        '  return [{ json: { vale: false, motivo: "no_es_audio" } }];\n' +
        '}\n' +
        '\n' +
        '// El data URL abulta ~4/3 de los bytes reales. 8 MB de texto son\n' +
        '// unos 6 MB de audio: muchisimo mas que una nota de voz normal,\n' +
        '// que en opus pesa como 100 KB por minuto.\n' +
        'if (bruto.length > 8 * 1024 * 1024) {\n' +
        '  return [{ json: { vale: false, motivo: "muy_largo" } }];\n' +
        '}\n' +
        '// Menos de 3 KB no es una nota de voz, es un toque sin querer.\n' +
        'if (bruto.length < 3000) {\n' +
        '  return [{ json: { vale: false, motivo: "muy_corto" } }];\n' +
        '}\n' +
        '\n' +
        'const mime = m[1].toLowerCase();\n' +
        'const ext = mime.indexOf("mp4") !== -1 ? "mp4"\n' +
        '          : mime.indexOf("mpeg") !== -1 ? "mp3"\n' +
        '          : mime.indexOf("ogg") !== -1 ? "ogg"\n' +
        '          : mime.indexOf("wav") !== -1 ? "wav" : "webm";\n' +
        '\n' +
        '// La forma cruda del binario de n8n: el base64 va tal cual en .data.\n' +
        'return [{\n' +
        '  json: { vale: true },\n' +
        '  binary: { data: { data: m[3], mimeType: mime, fileName: "nota." + ext, fileExtension: ext } }\n' +
        '}];',
    },
    position: [224, 0],
  },
  output: [{ vale: true }],
});

const sirveAudio = ifElse({
  version: 2.2,
  config: {
    name: 'Sirve el audio?',
    parameters: {
      conditions: {
        options: { caseSensitive: true, leftValue: '', typeValidation: 'loose', version: 2 },
        conditions: [
          {
            id: 'v',
            leftValue: expr('{{ $json.vale }}'),
            rightValue: '',
            operator: { type: 'boolean', operation: 'true', singleValue: true },
          },
        ],
        combinator: 'and',
      },
      looseTypeValidation: true,
      options: {},
    },
    position: [448, 0],
  },
});

const transcribir = node({
  type: '@n8n/n8n-nodes-langchain.openAi',
  version: 2.3,
  config: {
    name: 'OpenAI: transcribir',
    parameters: {
      resource: 'audio',
      operation: 'transcribe',
      binaryPropertyName: 'data',
      // El español de entrada se le dice explicito: sube bastante la
      // precision con nombres propios y con acento colombiano.
      options: { language: 'es', temperature: 0 },
    },
    credentials: { openAiApi: CRED_OPENAI },
    onError: 'continueRegularOutput',
    position: [672, -96],
  },
  output: [{ text: 'Hola, les queria contar que el salon queda chiquito' }],
});

const armarTranscripcion = node({
  type: 'n8n-nodes-base.code',
  version: 2,
  config: {
    name: 'Armar la transcripcion',
    parameters: {
      mode: 'runOnceForAllItems',
      language: 'javaScript',
      jsCode:
        'const j = $input.first().json || {};\n' +
        'const texto = String(j.text || "").trim();\n' +
        '\n' +
        '// Con audio en silencio o puro ruido, Whisper no devuelve vacio:\n' +
        '// devuelve frases de subtitulos de YouTube que se aprendio de\n' +
        '// memoria. Si eso pasa al chat, Cheo le responde a algo que la\n' +
        '// persona nunca dijo, y eso termina en el reporte del lunes.\n' +
        'const alucinaciones = [\n' +
        '  /gracias por ver/i,\n' +
        '  /subt[ií]tulos/i,\n' +
        '  /amara\\.org/i,\n' +
        '  /thanks? for watching/i,\n' +
        '  /suscr[ií]b[ae]/i,\n' +
        '  /^\\W+$/\n' +
        '];\n' +
        '\n' +
        '// El tope de largo importa: un mensaje real y largo que de casualidad\n' +
        '// diga "gracias por ver" no se puede tirar a la basura. Las\n' +
        '// alucinaciones siempre son cortas.\n' +
        'const basura = texto.length < 60 && alucinaciones.some(function (r) { return r.test(texto); });\n' +
        '\n' +
        'if (!texto || texto.length < 2 || basura) {\n' +
        '  return [{ json: { http_status: 200, ok: false, error: "no_se_entendio",\n' +
        '    mensaje: "No alcance a oirte bien. Mandame otra nota o escribemelo." } }];\n' +
        '}\n' +
        '\n' +
        'return [{ json: { http_status: 200, ok: true, texto: texto.slice(0, 4000) } }];',
    },
    position: [896, -96],
  },
  output: [{ http_status: 200, ok: true, texto: 'Hola, el salon queda chiquito' }],
});

const audioNoSirve = node({
  type: 'n8n-nodes-base.code',
  version: 2,
  config: {
    name: 'No se pudo oir',
    parameters: {
      mode: 'runOnceForAllItems',
      language: 'javaScript',
      jsCode:
        'const j = $input.first().json || {};\n' +
        'const razones = {\n' +
        '  muy_corto: "Esa quedo muy cortica. Manten apretado un poquito mas.",\n' +
        '  muy_largo: "Uy, esa nota quedo larguisima. Mandamela en pedacitos.",\n' +
        '  no_es_audio: "No me llego el audio bien. Intenta otra vez."\n' +
        '};\n' +
        'return [{ json: { http_status: 200, ok: false, error: j.motivo || "no_es_audio",\n' +
        '  mensaje: razones[j.motivo] || razones.no_es_audio } }];',
    },
    position: [672, 128],
  },
  output: [{ http_status: 200, ok: false, error: 'muy_corto' }],
});

const responderVoz = node({
  type: 'n8n-nodes-base.respondToWebhook',
  version: 1.1,
  config: {
    name: 'Responder voz',
    parameters: {
      respondWith: 'json',
      responseBody: expr('{{ JSON.stringify($json) }}'),
      options: {
        responseCode: 200,
        responseHeaders: { entries: [{ name: 'Access-Control-Allow-Origin', value: '*' }] },
      },
    },
    position: [1120, 0],
  },
  output: [{}],
});

/* ------------------------------------------------------------------ */
/* Fotos                                                               */
/* ------------------------------------------------------------------ */

const webhookFoto = trigger({
  type: 'n8n-nodes-base.webhook',
  version: 2,
  config: {
    name: 'POST cheo/foto',
    parameters: {
      httpMethod: 'POST',
      path: 'tumbao/cheo/foto',
      responseMode: 'responseNode',
      options: { allowedOrigins: '*' },
    },
    position: [0, 480],
  },
  output: [{ body: { imagen: 'data:image/jpeg;base64,...' } }],
});

const revisarFoto = node({
  type: 'n8n-nodes-base.code',
  version: 2,
  config: {
    name: 'Revisar la foto',
    parameters: {
      mode: 'runOnceForAllItems',
      language: 'javaScript',
      jsCode:
        'const b = ($input.first().json || {}).body || {};\n' +
        'const img = typeof b.imagen === "string" ? b.imagen : "";\n' +
        '\n' +
        'if (!/^data:image\\/(jpe?g|png|webp|heic);base64,/i.test(img)) {\n' +
        '  return [{ json: { vale: false, motivo: "no_es_imagen" } }];\n' +
        '}\n' +
        '// La burbuja ya la encoge antes de mandarla; esto es el tope duro.\n' +
        'if (img.length > 6 * 1024 * 1024) {\n' +
        '  return [{ json: { vale: false, motivo: "muy_grande" } }];\n' +
        '}\n' +
        'return [{ json: { vale: true, imagen: img } }];',
    },
    position: [224, 480],
  },
  output: [{ vale: true, imagen: 'data:image/jpeg;base64,...' }],
});

const sirveFoto = ifElse({
  version: 2.2,
  config: {
    name: 'Sirve la foto?',
    parameters: {
      conditions: {
        options: { caseSensitive: true, leftValue: '', typeValidation: 'loose', version: 2 },
        conditions: [
          {
            id: 'v',
            leftValue: expr('{{ $json.vale }}'),
            rightValue: '',
            operator: { type: 'boolean', operation: 'true', singleValue: true },
          },
        ],
        combinator: 'and',
      },
      looseTypeValidation: true,
      options: {},
    },
    position: [448, 480],
  },
});

const mirarFoto = node({
  type: 'n8n-nodes-base.httpRequest',
  version: 4.2,
  config: {
    name: 'OpenAI: mirar la foto',
    parameters: {
      method: 'POST',
      url: 'https://api.openai.com/v1/chat/completions',
      authentication: 'predefinedCredentialType',
      nodeCredentialType: 'openAiApi',
      sendBody: true,
      specifyBody: 'json',
      jsonBody: expr(
        '{{ JSON.stringify({ model: "gpt-4o-mini", temperature: 0, max_tokens: 160, messages: [ { role: "system", content: "Miras fotos que manda gente de una escuela de baile cuando esta dando feedback. Devuelves UNA sola frase, corta, describiendo lo que se ve y que sea relevante para la escuela: el salon, cuanta gente hay, el piso, los espejos, una pantalla con un error, un comprobante, un afiche. Escribe en espanol, en tercera persona, sin adornos y sin opinar. Si en la foto hay una cara, no la describas ni digas quien es. Si la foto no tiene nada que ver con una escuela de baile ni con la pagina, responde exactamente: nada relevante." }, { role: "user", content: [ { type: "text", text: "Que se ve aca?" }, { type: "image_url", image_url: { url: $json.imagen, detail: "low" } } ] } ] }) }}',
      ),
      options: { timeout: 25000 },
    },
    credentials: { openAiApi: CRED_OPENAI },
    onError: 'continueRegularOutput',
    position: [672, 384],
  },
  output: [{ choices: [{ message: { content: 'Un salon de baile con unas quince personas.' } }] }],
});

const armarDescripcion = node({
  type: 'n8n-nodes-base.code',
  version: 2,
  config: {
    name: 'Armar la descripcion',
    parameters: {
      mode: 'runOnceForAllItems',
      language: 'javaScript',
      jsCode:
        'const j = $input.first().json || {};\n' +
        '\n' +
        'let texto = "";\n' +
        'try {\n' +
        '  texto = j.choices && j.choices[0] && j.choices[0].message\n' +
        '        ? String(j.choices[0].message.content || "").trim() : "";\n' +
        '} catch (e) {\n' +
        '  texto = "";\n' +
        '}\n' +
        '\n' +
        '// La foto NO se guarda en ningun lado: lo que queda es esta frase.\n' +
        '// Misma decision que con los comprobantes de pago. Asi el reporte\n' +
        '// tiene el contenido sin que Tumbao termine con un album de fotos\n' +
        '// de sus clientes que nadie pidio administrar.\n' +
        'if (!texto || /^nada relevante\\.?$/i.test(texto)) {\n' +
        '  return [{ json: { http_status: 200, ok: true, vista: false,\n' +
        '    descripcion: "Una foto" } }];\n' +
        '}\n' +
        '\n' +
        'return [{ json: { http_status: 200, ok: true, vista: true,\n' +
        '  descripcion: texto.slice(0, 400) } }];',
    },
    position: [896, 384],
  },
  output: [{ http_status: 200, ok: true, vista: true, descripcion: 'Un salon con quince personas.' }],
});

const fotoNoSirve = node({
  type: 'n8n-nodes-base.code',
  version: 2,
  config: {
    name: 'No se pudo ver',
    parameters: {
      mode: 'runOnceForAllItems',
      language: 'javaScript',
      jsCode:
        'const j = $input.first().json || {};\n' +
        '// Que no se pueda leer la foto no rompe nada: la persona igual\n' +
        '// puede seguir contando, y Cheo se queda con que mando una foto.\n' +
        'return [{ json: { http_status: 200, ok: true, vista: false,\n' +
        '  error: j.motivo || "no_es_imagen", descripcion: "Una foto" } }];',
    },
    position: [672, 608],
  },
  output: [{ http_status: 200, ok: true, vista: false, descripcion: 'Una foto' }],
});

const responderFoto = node({
  type: 'n8n-nodes-base.respondToWebhook',
  version: 1.1,
  config: {
    name: 'Responder foto',
    parameters: {
      respondWith: 'json',
      responseBody: expr('{{ JSON.stringify($json) }}'),
      options: {
        responseCode: 200,
        responseHeaders: { entries: [{ name: 'Access-Control-Allow-Origin', value: '*' }] },
      },
    },
    position: [1120, 480],
  },
  output: [{}],
});

const NOTA =
  '## Cheo escucha y mira\n' +
  '\n' +
  'POST /tumbao/cheo/voz    { audio: dataURL }   -> { texto }\n' +
  'POST /tumbao/cheo/foto   { imagen: dataURL }  -> { descripcion }\n' +
  '\n' +
  'Ninguno de los dos guarda nada ni habla con Supabase. Solo convierten\n' +
  'a texto y devuelven. La burbuja toma ese texto y lo manda al chat\n' +
  'normal (/tumbao/cheo), que es el que si guarda.\n' +
  '\n' +
  '## Por que separado del chat\n' +
  '\n' +
  'Asi la persona VE lo que se transcribio antes de que quede guardado, y\n' +
  'si Whisper entendio mal puede corregirlo. Meterlo dentro del chat en un\n' +
  'solo paso habria escondido ese error.\n' +
  '\n' +
  '## La foto no se guarda\n' +
  '\n' +
  'Se mira, se saca una frase de lo que hay, y se suelta. Lo que queda en\n' +
  'la base es la frase, no la imagen. Misma decision que con los\n' +
  'comprobantes de pago. Si algun dia se quiere guardar, hay que abrir un\n' +
  'bucket en Supabase y decidir cuanto tiempo se conservan.\n' +
  '\n' +
  '## Se puede apagar\n' +
  '\n' +
  'Si se desactiva este workflow, la burbuja esconde los botones de\n' +
  'microfono y foto sola, y el chat de texto sigue funcionando igual.';

export default workflow('tumbao-cheo-voz-fotos', 'Tumbao · Cheo (voz y fotos)')
  .add(webhookVoz)
  .to(prepararAudio)
  .to(
    sirveAudio
      .onTrue(transcribir.to(armarTranscripcion).to(responderVoz))
      .onFalse(audioNoSirve.to(responderVoz)),
  )
  .add(webhookFoto)
  .to(revisarFoto)
  .to(
    sirveFoto
      .onTrue(mirarFoto.to(armarDescripcion).to(responderFoto))
      .onFalse(fotoNoSirve.to(responderFoto)),
  )
  .add(sticky(NOTA, [webhookVoz, prepararAudio, sirveAudio], { color: 6, width: 440, height: 320 }));
