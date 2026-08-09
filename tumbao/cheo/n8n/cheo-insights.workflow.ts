import { workflow, node, trigger, sticky, ifElse, expr } from '@n8n/workflow-sdk';

const CRED_SUPABASE = { id: 'YuDlaBP89tkmEfOb', name: 'Supabase Tumbao' };
const CRED_OPENAI = { id: 'Mq89XkAH27Mubfus', name: 'OpenAI account OCR Tumbao' };
const CRED_GMAIL = { id: 'AebvmIoTh2YwjKab', name: 'Gmail OAuth2 API' };
const SUPA = 'https://fobpccreihcylpsullhu.supabase.co/rest/v1/rpc/';

/* ------------------------------------------------------------------ */
/* 1. Clasificar conversaciones frias, cada media hora                  */
/* ------------------------------------------------------------------ */

const cadaMediaHora = trigger({
  type: 'n8n-nodes-base.scheduleTrigger',
  version: 1.3,
  config: {
    name: 'Cada media hora',
    parameters: { rule: { interval: [{ field: 'cronExpression', expression: '*/30 * * * *' }] } },
    position: [0, 0],
  },
  output: [{}],
});

const traerFrias = node({
  type: 'n8n-nodes-base.httpRequest',
  version: 4.2,
  config: {
    name: 'Supabase: conversaciones frias',
    parameters: {
      method: 'POST',
      url: SUPA + 'cheo_pendientes_de_clasificar',
      authentication: 'predefinedCredentialType',
      nodeCredentialType: 'supabaseApi',
      sendBody: true,
      specifyBody: 'json',
      jsonBody: '={{ JSON.stringify({ p_minutos: 20, p_limite: 25 }) }}',
      options: { timeout: 15000 },
    },
    credentials: { supabaseApi: CRED_SUPABASE },
    retryOnFail: true,
    maxTries: 3,
    waitBetweenTries: 1000,
    position: [224, 0],
  },
  output: [{ ok: true, pendientes: [{ sesion_id: 'abc', transcripcion: 'Persona: hola' }] }],
});

const unaPorUna = node({
  type: 'n8n-nodes-base.code',
  version: 2,
  config: {
    name: 'Una por una',
    parameters: {
      mode: 'runOnceForAllItems',
      language: 'javaScript',
      jsCode:
        'const j = $input.first().json || {};\n' +
        'const lista = Array.isArray(j.pendientes) ? j.pendientes : [];\n' +
        '\n' +
        '// Si no hay ninguna, se devuelven cero items y la cadena se corta\n' +
        '// sola. Es el comportamiento que se quiere: no hay nada que\n' +
        '// clasificar, no se llama a OpenAI, no se gasta.\n' +
        'return lista.map((c) => ({ json: {\n' +
        '  sesion_id: c.sesion_id,\n' +
        '  transcripcion: String(c.transcripcion || "").slice(0, 6000)\n' +
        '} }));',
    },
    position: [448, 0],
  },
  output: [{ sesion_id: 'abc', transcripcion: 'Persona: hola' }],
});

const clasificar = node({
  type: 'n8n-nodes-base.httpRequest',
  version: 4.2,
  config: {
    name: 'OpenAI: clasificar',
    parameters: {
      method: 'POST',
      url: 'https://api.openai.com/v1/chat/completions',
      authentication: 'predefinedCredentialType',
      nodeCredentialType: 'openAiApi',
      sendBody: true,
      specifyBody: 'json',
      jsonBody: expr(
        '{{ JSON.stringify({ model: "gpt-4o-mini", temperature: 0, max_tokens: 400, response_format: { type: "json_object" }, messages: [ { role: "system", content: "Clasificas conversaciones entre clientes de una escuela de baile y Cheo, su asistente. Devuelves SOLO un objeto JSON con estas claves: tipo, tema, resumen, urgencia, sentimiento, accion.\\n\\ntipo: uno de sugerencia, queja, reclamo, duda, idea, elogio, otro. Reclamo es cuando la persona pide algo de vuelta (plata, un cupo, una reposicion); queja es cuando solo expresa molestia.\\ntema: dos o tres palabras que nombren el asunto (por ejemplo: pagos, horarios, profesores, cupos, la pagina, el salon).\\nresumen: una o dos frases, en tercera persona, con lo que de verdad paso. Nada de relleno.\\nurgencia: numero entero de 1 a 5. 5 solo si hay plata de por medio, alguien se quedo sin la clase que pago, o hay riesgo de perder a la persona.\\nsentimiento: positivo, neutral o negativo.\\naccion: que deberia hacer Tumbao, en una frase concreta y accionable. Si la persona propuso una solucion, esa manda.\\n\\nSi la conversacion no dice nada util, usa tipo otro, urgencia 1 y dilo en el resumen. No inventes contenido que no este en la transcripcion." }, { role: "user", content: $json.transcripcion } ] }) }}',
      ),
      options: { timeout: 25000 },
    },
    credentials: { openAiApi: CRED_OPENAI },
    onError: 'continueRegularOutput',
    position: [672, 0],
  },
  output: [{ choices: [{ message: { content: '{"tipo":"queja"}' } }] }],
});

const guardarClasificacion = node({
  type: 'n8n-nodes-base.httpRequest',
  version: 4.2,
  config: {
    name: 'Supabase: guardar clasificacion',
    parameters: {
      method: 'POST',
      url: SUPA + 'cheo_clasificar',
      authentication: 'predefinedCredentialType',
      nodeCredentialType: 'supabaseApi',
      sendBody: true,
      specifyBody: 'json',
      jsonBody: expr(
        '{{ (() => { let d = {}; try { d = JSON.parse($json.choices[0].message.content || "{}"); } catch (e) { d = {}; } const t = (v, n) => { const s = (v == null ? "" : String(v)).trim(); return s ? s.slice(0, n) : null; }; return JSON.stringify({ p_sesion_id: $("Una por una").item.json.sesion_id, p_tipo: t(d.tipo, 20), p_tema: t(d.tema, 120), p_resumen: t(d.resumen, 1000), p_urgencia: Number(d.urgencia) || 3, p_sentimiento: t(d.sentimiento, 20), p_accion: t(d.accion, 500) }); })() }}',
      ),
      options: { timeout: 10000 },
    },
    credentials: { supabaseApi: CRED_SUPABASE },
    onError: 'continueRegularOutput',
    retryOnFail: true,
    maxTries: 3,
    waitBetweenTries: 1000,
    position: [896, 0],
  },
  output: [{ ok: true }],
});

/* ------------------------------------------------------------------ */
/* 2. Reporte semanal, lunes 7am Bogota                                 */
/* ------------------------------------------------------------------ */

const lunesTemprano = trigger({
  type: 'n8n-nodes-base.scheduleTrigger',
  version: 1.3,
  config: {
    name: 'Lunes 7am',
    parameters: { rule: { interval: [{ field: 'cronExpression', expression: '0 7 * * 1' }] } },
    position: [0, 448],
  },
  output: [{}],
});

const traerSemana = node({
  type: 'n8n-nodes-base.httpRequest',
  version: 4.2,
  config: {
    name: 'Supabase: la semana',
    parameters: {
      method: 'POST',
      url: SUPA + 'cheo_semana',
      authentication: 'predefinedCredentialType',
      nodeCredentialType: 'supabaseApi',
      sendBody: true,
      specifyBody: 'json',
      jsonBody: '={{ JSON.stringify({}) }}',
      options: { timeout: 20000 },
    },
    credentials: { supabaseApi: CRED_SUPABASE },
    retryOnFail: true,
    maxTries: 3,
    waitBetweenTries: 2000,
    position: [224, 448],
  },
  output: [
    {
      ok: true,
      semana_inicio: '2026-08-03',
      semana_fin: '2026-08-09',
      total_conversaciones: 4,
      total_mensajes: 20,
      por_tipo: { sugerencia: 2, queja: 2 },
      conversaciones: [{ tipo: 'queja', tema: 'pagos', urgencia: 5 }],
    },
  ],
});

const huboAlgo = ifElse({
  version: 2.2,
  config: {
    name: 'Hubo conversaciones?',
    parameters: {
      conditions: {
        options: { caseSensitive: true, leftValue: '', typeValidation: 'loose', version: 2 },
        conditions: [
          {
            id: 'hay',
            leftValue: expr('{{ $json.total_conversaciones }}'),
            rightValue: 0,
            operator: { type: 'number', operation: 'gt' },
          },
        ],
        combinator: 'and',
      },
      looseTypeValidation: true,
      options: {},
    },
    position: [448, 448],
  },
});

const armarEncargo = node({
  type: 'n8n-nodes-base.code',
  version: 2,
  config: {
    name: 'Armar el encargo',
    parameters: {
      mode: 'runOnceForAllItems',
      language: 'javaScript',
      jsCode:
        'const s = $input.first().json || {};\n' +
        '\n' +
        'const SISTEMA = [\n' +
        '  "Eres el analista de Tumbao, una escuela de baile en Colombia. Recibes las conversaciones que tuvo Cheo con los clientes durante una semana y produces el reporte que lee el equipo el lunes en la manana.",\n' +
        '  "",\n' +
        '  "Devuelves SOLO un objeto JSON con estas claves: titular, insights, criticos, acciones, cita.",\n' +
        '  "",\n' +
        '  "titular: UNA frase que diga lo mas importante de la semana. Concreta, no generica. Mal: la gente dio feedback variado. Bien: tres personas distintas no pudieron pagar desde el celular.",\n' +
        '  "insights: array de 2 a 4 objetos con titulo, detalle y cuantos. Un insight es un patron que se repite o una causa detras de varias quejas, no un resumen de una conversacion suelta. cuantos va como texto corto, por ejemplo 3 de 7 personas, o una persona. Nunca un numero suelto.",\n' +
        '  "criticos: array de 0 a 3 objetos con que y por_que_importa. Aqui va solo lo que hace perder plata o clientes esta semana. Si no hay nada critico de verdad, devuelve un array vacio: inventar urgencias quema la confianza en el reporte.",\n' +
        '  "acciones: array de 2 a 4 objetos con accion, por_que y esfuerzo. La accion se escribe como una tarea que alguien puede empezar el lunes. esfuerzo es bajo, medio o alto. Prioriza lo que propusieron los mismos clientes.",\n' +
        '  "cita: UNA sola frase textual de un cliente.",\n' +
        '  "",\n' +
        '  "OJO CON LAS CITAS: en los datos, el campo dice_la_persona trae VARIOS mensajes de la misma persona pegados y separados por el simbolo de barra vertical. No es una sola frase. Para la cita tienes que escoger UNA sola de esas frases, la mas reveladora, y copiarla sin la barra y sin pegarle las demas. Si ninguna vale la pena, devuelve cadena vacia.",\n' +
        '  "",\n' +
        '  "Reglas que mandan sobre todo:",\n' +
        '  "- No inventes nada que no este en los datos. Es preferible un reporte corto y cierto que uno largo y adornado.",\n' +
        '  "- Si la semana tuvo poquitas conversaciones, dilo en el titular en vez de estirar conclusiones.",\n' +
        '  "- Escribe para alguien que tiene tres minutos y tiene que decidir que hacer.",\n' +
        '  "- En espanol, directo, sin lenguaje corporativo."\n' +
        '].join("\\n");\n' +
        '\n' +
        'const DATOS = JSON.stringify({\n' +
        '  semana_inicio: s.semana_inicio,\n' +
        '  semana_fin: s.semana_fin,\n' +
        '  total_conversaciones: s.total_conversaciones,\n' +
        '  por_tipo: s.por_tipo,\n' +
        '  conversaciones: s.conversaciones\n' +
        '});\n' +
        '\n' +
        'return [{ json: { sistema: SISTEMA, datos: DATOS } }];',
    },
    position: [672, 352],
  },
  output: [{ sistema: 'Eres el analista de Tumbao...', datos: '{}' }],
});

const consolidar = node({
  type: 'n8n-nodes-base.httpRequest',
  version: 4.2,
  config: {
    name: 'OpenAI: consolidar la semana',
    parameters: {
      method: 'POST',
      url: 'https://api.openai.com/v1/chat/completions',
      authentication: 'predefinedCredentialType',
      nodeCredentialType: 'openAiApi',
      sendBody: true,
      specifyBody: 'json',
      jsonBody: expr(
        '{{ JSON.stringify({ model: "gpt-4o", temperature: 0.3, max_tokens: 1600, response_format: { type: "json_object" }, messages: [ { role: "system", content: $json.sistema }, { role: "user", content: $json.datos } ] }) }}',
      ),
      options: { timeout: 90000 },
    },
    credentials: { openAiApi: CRED_OPENAI },
    onError: 'continueRegularOutput',
    position: [896, 352],
  },
  output: [{ choices: [{ message: { content: '{"titular":"..."}' } }] }],
});

const armarReporte = node({
  type: 'n8n-nodes-base.code',
  version: 2,
  config: {
    name: 'Armar el reporte',
    parameters: {
      mode: 'runOnceForAllItems',
      language: 'javaScript',
      jsCode:
        'const j = $input.first().json || {};\n' +
        'const s = $("Supabase: la semana").first().json || {};\n' +
        '\n' +
        'let d = {};\n' +
        'try {\n' +
        '  d = JSON.parse((j.choices && j.choices[0] && j.choices[0].message ? j.choices[0].message.content : "") || "{}");\n' +
        '} catch (e) {\n' +
        '  d = {};\n' +
        '}\n' +
        '\n' +
        'const esc = (v) => String(v == null ? "" : v)\n' +
        '  .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");\n' +
        '\n' +
        'const arr = (v) => Array.isArray(v) ? v : [];\n' +
        '\n' +
        '// El campo dice_la_persona trae varios mensajes pegados con " | ", y el\n' +
        '// modelo a veces copia el bloque entero como si fuera una cita. Si pasa,\n' +
        '// se toma el fragmento mas largo: una cita es una frase, no un pegote.\n' +
        '// La correccion de fondo esta en el prompt; esto es el cinturon.\n' +
        'let cita = String(d.cita == null ? "" : d.cita).trim();\n' +
        'if (cita.indexOf(" | ") !== -1) {\n' +
        '  cita = cita.split(" | ").map((x) => x.trim()).sort((a, b) => b.length - a.length)[0] || "";\n' +
        '}\n' +
        '\n' +
        '// Si el modelo fallo, el correo sale igual con los numeros crudos.\n' +
        '// Un reporte feo se lee; un reporte que no llega, no.\n' +
        'const fallo = !d.titular;\n' +
        'const titular = fallo\n' +
        '  ? "No se pudo generar el analisis de esta semana. Abajo quedan los numeros y las conversaciones tal cual."\n' +
        '  : String(d.titular);\n' +
        '\n' +
        'const fechaCorta = (iso) => {\n' +
        '  try {\n' +
        '    return new Intl.DateTimeFormat("es-CO", { timeZone: "America/Bogota", day: "numeric", month: "long" })\n' +
        '      .format(new Date(String(iso) + "T12:00:00Z"));\n' +
        '  } catch (e) { return String(iso); }\n' +
        '};\n' +
        'const rango = fechaCorta(s.semana_inicio) + " al " + fechaCorta(s.semana_fin);\n' +
        '\n' +
        'const porTipo = s.por_tipo || {};\n' +
        'const chips = Object.keys(porTipo).map((k) =>\n' +
        '  "<span style=\\"display:inline-block;background:#f1f0ec;border-radius:99px;padding:4px 11px;' +
        'margin:0 6px 6px 0;font-size:12px;color:#444\\">" + esc(k) + " " + esc(porTipo[k]) + "</span>"\n' +
        ').join("");\n' +
        '\n' +
        'const bloqueCriticos = arr(d.criticos).map((c) =>\n' +
        '  "<div style=\\"border-left:3px solid #c0392b;padding:2px 0 2px 14px;margin:0 0 14px\\">" +\n' +
        '  "<b style=\\"font-size:14px\\">" + esc(c.que) + "</b>" +\n' +
        '  "<div style=\\"color:#666;font-size:13px;margin-top:3px\\">" + esc(c.por_que_importa) + "</div></div>"\n' +
        ').join("");\n' +
        '\n' +
        'const bloqueInsights = arr(d.insights).map((i) =>\n' +
        '  "<div style=\\"margin:0 0 16px\\">" +\n' +
        '  "<b style=\\"font-size:14px\\">" + esc(i.titulo) + "</b>" +\n' +
        '  (i.cuantos ? " <span style=\\"color:#999;font-size:12px\\">(" + esc(i.cuantos) + ")</span>" : "") +\n' +
        '  "<div style=\\"color:#555;font-size:13px;margin-top:3px;line-height:1.5\\">" + esc(i.detalle) + "</div></div>"\n' +
        ').join("");\n' +
        '\n' +
        'const bloqueAcciones = arr(d.acciones).map((a, n) =>\n' +
        '  "<tr>" +\n' +
        '  "<td style=\\"padding:11px 10px 11px 0;border-bottom:1px solid #eee;vertical-align:top;color:#bbb;font-size:13px\\">" + (n + 1) + "</td>" +\n' +
        '  "<td style=\\"padding:11px 10px 11px 0;border-bottom:1px solid #eee;vertical-align:top\\">" +\n' +
        '  "<b style=\\"font-size:14px\\">" + esc(a.accion) + "</b>" +\n' +
        '  "<div style=\\"color:#666;font-size:13px;margin-top:3px\\">" + esc(a.por_que) + "</div></td>" +\n' +
        '  "<td style=\\"padding:11px 0;border-bottom:1px solid #eee;vertical-align:top;font-size:12px;color:#888;white-space:nowrap\\">" + esc(a.esfuerzo || "") + "</td>" +\n' +
        '  "</tr>"\n' +
        ').join("");\n' +
        '\n' +
        'const html = [\n' +
        '  "<div style=\\"font-family:system-ui,-apple-system,Segoe UI,Roboto,sans-serif;max-width:640px;color:#111;line-height:1.55\\">",\n' +
        '  "<p style=\\"margin:0 0 4px;color:#999;font-size:12px;letter-spacing:.06em;text-transform:uppercase\\">Cheo &middot; semana del ", esc(rango), "</p>",\n' +
        '  "<h1 style=\\"margin:0 0 20px;font-size:21px;line-height:1.35;font-weight:600\\">", esc(titular), "</h1>",\n' +
        '  "<p style=\\"margin:0 0 6px;font-size:13px;color:#666\\"><b>", esc(s.total_conversaciones), "</b> conversaciones &middot; <b>", esc(s.total_mensajes), "</b> mensajes</p>",\n' +
        '  "<div style=\\"margin:0 0 26px\\">", chips, "</div>",\n' +
        '  bloqueCriticos ? "<h2 style=\\"font-size:12px;letter-spacing:.06em;text-transform:uppercase;color:#c0392b;margin:0 0 12px\\">Critico</h2>" + bloqueCriticos : "",\n' +
        '  bloqueInsights ? "<h2 style=\\"font-size:12px;letter-spacing:.06em;text-transform:uppercase;color:#999;margin:28px 0 12px\\">Lo que esta diciendo la gente</h2>" + bloqueInsights : "",\n' +
        '  bloqueAcciones ? "<h2 style=\\"font-size:12px;letter-spacing:.06em;text-transform:uppercase;color:#999;margin:28px 0 6px\\">Que hacer</h2><table style=\\"border-collapse:collapse;width:100%\\">" + bloqueAcciones + "</table>" : "",\n' +
        '  cita ? "<blockquote style=\\"margin:30px 0 0;padding:14px 18px;background:#faf9f6;border-radius:8px;font-size:14px;color:#444;font-style:italic\\">&ldquo;" + esc(cita) + "&rdquo;</blockquote>" : "",\n' +
        '  "<p style=\\"margin:32px 0 0;padding-top:16px;border-top:1px solid #eee;color:#aaa;font-size:11px\\">Lo escribio Cheo con lo que la gente conto en tumbaobaila.com. Las conversaciones completas estan en Supabase, tabla cheo_conversaciones.</p>",\n' +
        '  "</div>"\n' +
        '].join("");\n' +
        '\n' +
        'return [{ json: {\n' +
        '  asunto: "Cheo · la semana del " + rango + (fallo ? " (sin analisis)" : ""),\n' +
        '  html: html,\n' +
        '  insights: d,\n' +
        '  resumen_md: titular,\n' +
        '  semana_inicio: s.semana_inicio,\n' +
        '  semana_fin: s.semana_fin,\n' +
        '  total_conversaciones: s.total_conversaciones,\n' +
        '  total_mensajes: s.total_mensajes\n' +
        '} }];',
    },
    position: [1120, 352],
  },
  output: [
    {
      asunto: 'Cheo · la semana',
      html: '<div></div>',
      insights: {},
      resumen_md: 'titular',
      semana_inicio: '2026-08-03',
      semana_fin: '2026-08-09',
      total_conversaciones: 4,
      total_mensajes: 20,
    },
  ],
});

const guardarReporte = node({
  type: 'n8n-nodes-base.httpRequest',
  version: 4.2,
  config: {
    name: 'Supabase: guardar reporte',
    parameters: {
      method: 'POST',
      url: SUPA + 'cheo_guardar_reporte',
      authentication: 'predefinedCredentialType',
      nodeCredentialType: 'supabaseApi',
      sendBody: true,
      specifyBody: 'json',
      jsonBody: expr(
        '{{ JSON.stringify({ p_desde: $json.semana_inicio, p_hasta: $json.semana_fin, p_total_conv: $json.total_conversaciones, p_total_msg: $json.total_mensajes, p_insights: $json.insights, p_resumen_md: $json.resumen_md, p_html: $json.html }) }}',
      ),
      options: { timeout: 20000 },
    },
    credentials: { supabaseApi: CRED_SUPABASE },
    onError: 'continueRegularOutput',
    retryOnFail: true,
    maxTries: 3,
    waitBetweenTries: 2000,
    position: [1344, 352],
  },
  output: [{ ok: true, reporte_id: 'uuid' }],
});

const enviarReporte = node({
  type: 'n8n-nodes-base.gmail',
  version: 2.2,
  config: {
    name: 'Enviar el reporte',
    parameters: {
      resource: 'message',
      operation: 'send',
      sendTo: 'bailatumbao@gmail.com',
      subject: expr('{{ $("Armar el reporte").item.json.asunto }}'),
      emailType: 'html',
      message: expr('{{ $("Armar el reporte").item.json.html }}'),
      options: { appendAttribution: false, senderName: 'Cheo de Tumbao' },
    },
    credentials: { gmailOAuth2: CRED_GMAIL },
    retryOnFail: true,
    maxTries: 3,
    waitBetweenTries: 2000,
    position: [1568, 352],
  },
  output: [{ id: 'msg' }],
});

const semanaVacia = node({
  type: 'n8n-nodes-base.code',
  version: 2,
  config: {
    name: 'Semana sin conversaciones',
    parameters: {
      mode: 'runOnceForAllItems',
      language: 'javaScript',
      jsCode:
        'const s = $input.first().json || {};\n' +
        '\n' +
        '// Este correo parece inutil y no lo es: confirma que Cheo esta vivo.\n' +
        '// Si el reporte deja de llegar, es que algo se rompio, no que la\n' +
        '// gente dejo de escribir. Esa diferencia importa.\n' +
        'const fechaCorta = (iso) => {\n' +
        '  try {\n' +
        '    return new Intl.DateTimeFormat("es-CO", { timeZone: "America/Bogota", day: "numeric", month: "long" })\n' +
        '      .format(new Date(String(iso) + "T12:00:00Z"));\n' +
        '  } catch (e) { return String(iso); }\n' +
        '};\n' +
        'const rango = fechaCorta(s.semana_inicio) + " al " + fechaCorta(s.semana_fin);\n' +
        '\n' +
        'const html = [\n' +
        '  "<div style=\\"font-family:system-ui,-apple-system,Segoe UI,Roboto,sans-serif;max-width:560px;color:#111;line-height:1.55\\">",\n' +
        '  "<p style=\\"margin:0 0 4px;color:#999;font-size:12px;letter-spacing:.06em;text-transform:uppercase\\">Cheo &middot; semana del ", rango, "</p>",\n' +
        '  "<h1 style=\\"margin:0 0 14px;font-size:20px;font-weight:600\\">Nadie le escribio a Cheo esta semana.</h1>",\n' +
        '  "<p style=\\"margin:0 0 8px;font-size:14px;color:#555\\">El sistema esta corriendo bien; simplemente no hubo conversaciones. ",\n' +
        '  "Si esto se repite varias semanas seguidas, lo que hay que revisar es si la burbuja se ve y se entiende, no el reporte.</p>",\n' +
        '  "</div>"\n' +
        '].join("");\n' +
        '\n' +
        'return [{ json: { asunto: "Cheo · semana del " + rango + " (sin conversaciones)", html: html } }];',
    },
    position: [672, 608],
  },
  output: [{ asunto: 'Cheo · sin conversaciones', html: '<div></div>' }],
});

const enviarVacio = node({
  type: 'n8n-nodes-base.gmail',
  version: 2.2,
  config: {
    name: 'Enviar aviso de semana vacia',
    parameters: {
      resource: 'message',
      operation: 'send',
      sendTo: 'bailatumbao@gmail.com',
      subject: expr('{{ $json.asunto }}'),
      emailType: 'html',
      message: expr('{{ $json.html }}'),
      options: { appendAttribution: false, senderName: 'Cheo de Tumbao' },
    },
    credentials: { gmailOAuth2: CRED_GMAIL },
    retryOnFail: true,
    maxTries: 3,
    waitBetweenTries: 2000,
    position: [896, 608],
  },
  output: [{ id: 'msg' }],
});

const NOTA_CLASIF =
  '## Clasificar, cada media hora\n' +
  '\n' +
  'Toma las conversaciones que llevan mas de 20 minutos quietas y todavia\n' +
  'no tienen tipo/urgencia, y se las pasa al modelo de a una.\n' +
  '\n' +
  'Se clasifica al enfriarse y no en vivo por dos razones: en mitad de la\n' +
  'charla todavia no se sabe de que iba, y clasificar cada turno costaria\n' +
  'una llamada por mensaje en vez de una por conversacion.\n' +
  '\n' +
  'Si no hay ninguna pendiente, Una por una devuelve cero items y la\n' +
  'cadena se corta sola. No se llama a OpenAI y no se gasta.\n' +
  '\n' +
  'Si alguien retoma una conversacion ya clasificada, cheo_guardar_turno\n' +
  'la marca clasificada=false otra vez y vuelve a esta cola.';

const NOTA_REPORTE =
  '## El reporte, lunes 7am\n' +
  '\n' +
  'cheo_semana() sin argumentos devuelve la semana pasada completa,\n' +
  'de lunes a domingo en hora Bogota. La hora del cron es literal porque\n' +
  'este workflow tiene timezone America/Bogota en Settings.\n' +
  '\n' +
  '## Dos caminos a proposito\n' +
  '\n' +
  'Si no hubo conversaciones, NO se le pide al modelo que analice una\n' +
  'lista vacia: se manda un correo corto diciendo que no hubo. Pedirle\n' +
  'conclusiones a cero datos es la forma mas rapida de que el reporte se\n' +
  'llene de cosas que nadie dijo.\n' +
  '\n' +
  '## Si el modelo falla, el correo sale igual\n' +
  '\n' +
  'Armar el reporte detecta que no vino titular y manda los numeros\n' +
  'crudos con el asunto marcado (sin analisis). Un reporte feo se lee;\n' +
  'uno que no llega, no.\n' +
  '\n' +
  'Aca se usa gpt-4o y no gpt-4o-mini: es una llamada por semana y es la\n' +
  'que de verdad hay que leer.';

const notaClasif = sticky(NOTA_CLASIF, [cadaMediaHora, traerFrias, unaPorUna], {
  color: 4,
  width: 440,
  height: 300,
});

const notaReporte = sticky(NOTA_REPORTE, [lunesTemprano, traerSemana, huboAlgo], {
  color: 3,
  width: 440,
  height: 320,
});

export default workflow('tumbao-cheo-insights', 'Tumbao · Cheo (insights)')
  .add(cadaMediaHora)
  .to(traerFrias)
  .to(unaPorUna)
  .to(clasificar)
  .to(guardarClasificacion)
  .add(lunesTemprano)
  .to(traerSemana)
  .to(
    huboAlgo
      .onTrue(
        armarEncargo.to(consolidar).to(armarReporte).to(guardarReporte).to(enviarReporte),
      )
      .onFalse(semanaVacia.to(enviarVacio)),
  )
  .add(notaClasif)
  .add(notaReporte);
