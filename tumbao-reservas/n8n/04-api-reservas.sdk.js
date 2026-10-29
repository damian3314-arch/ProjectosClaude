import { workflow, node, trigger, sticky, ifElse, newCredential, expr } from '@n8n/workflow-sdk';

const AGRUPAR   = "const SUP = $input.all().map(i => i.json).filter(c => c && c.id);\nconst tz = \"America/Bogota\";\nconst fFecha = new Intl.DateTimeFormat(\"es-CO\", { timeZone: tz, weekday: \"long\", day: \"numeric\", month: \"long\" });\nconst fHora  = new Intl.DateTimeFormat(\"es-CO\", { timeZone: tz, hour: \"numeric\", minute: \"2-digit\", hour12: true });\nconst fClave = new Intl.DateTimeFormat(\"en-CA\", { timeZone: tz, year: \"numeric\", month: \"2-digit\", day: \"2-digit\" });\nconst compacta = (s) => s.replace(/ | /g, \" \").replace(/\\s*a\\.\\s*m\\./i, \" am\").replace(/\\s*p\\.\\s*m\\./i, \" pm\");\nconst dias = new Map();\nfor (const c of SUP) {\n  const d = new Date(c.fecha_hora);\n  const clave = fClave.format(d);\n  if (!dias.has(clave)) dias.set(clave, { fecha: clave, etiqueta: fFecha.format(d), clases: [] });\n  const libres = Math.max((c.cupo_total || 0) - (c.cupo_tomado || 0), 0);\n  dias.get(clave).clases.push({\n    clase_id: c.id, nombre: c.nombre, profesor: c.profesor, lugar: c.lugar,\n    hora: compacta(fHora.format(d)), fecha_hora: c.fecha_hora,\n    duracion_min: c.duracion_min, precio_cop: c.precio_cop,\n    cupo_total: c.cupo_total, cupos_disponibles: libres, agotada: libres <= 0\n  });\n}\nreturn [{ json: { ok: true, timezone: tz, dias: [...dias.values()] } }];\n";
const NORMALIZAR = "const b = $input.first().json.body || {};
const esBot = (b.apellido2 || \"\").toString().trim() !== \"\";
const txt = (v, max) => (v == null ? \"\" : v.toString().trim().slice(0, max));
let tel = txt(b.telefono, 25).replace(/\D/g, \"\");
if (tel.length === 12 && tel.startsWith(\"57\")) tel = tel.slice(2);
const tipo = txt(b.tipo, 10) === \"miembro\" ? \"miembro\" : \"suelta\";
return [{ json: {
  es_bot: esBot,
  tipo,
  clase_id: txt(b.clase_id, 40),
  nombre: txt(b.nombre, 80),
  telefono: tel,
  email: txt(b.email, 120),
  habeas: b.habeas === true || b.habeas === \"true\",
  valido: !esBot && txt(b.nombre, 80).length >= 2 && tel.length === 10
        && (b.habeas === true || b.habeas === \"true\") && txt(b.clase_id, 40).length > 10
} }];
";
const RESP_RES   = "const j = $input.first().json;
const r = (j && j.ok !== undefined) ? j : (Array.isArray(j) ? j[0] : {});
if (!r.ok) {
  const mapa = {
    SIN_CUPO: 409, CLASE_NO_EXISTE: 404, CLASE_INACTIVA: 410, CLASE_YA_PASO: 410,
    MEMBRESIA_NO_ENCONTRADA: 404, PLAN_YA_CUBRE: 409, OTRO_HORARIO: 409
  };
  return [{ json: { http_status: mapa[r.error] || 400, ok: false,
    error: r.error || \"desconocido\",
    hora_plan: r.hora_plan || null,
    mensaje: r.mensaje || \"No pudimos apartar el cupo. Escribenos por WhatsApp.\" } }];
}
const d = new Date(r.fecha_hora);
const fecha = new Intl.DateTimeFormat(\"es-CO\", { timeZone: \"America/Bogota\", weekday: \"long\", day: \"numeric\", month: \"long\" }).format(d);
const hora = new Intl.DateTimeFormat(\"es-CO\", { timeZone: \"America/Bogota\", hour: \"numeric\", minute: \"2-digit\", hour12: true })
  .format(d).replace(/ | /g, \" \").replace(/\s*a\.\s*m\./i, \" am\").replace(/\s*p\.\s*m\./i, \" pm\");
return [{ json: { http_status: 200, ok: true,
  tipo: r.tipo, requiere_pago: r.requiere_pago === true, estado: r.estado,
  codigo: r.codigo, reserva_id: r.reserva_id, clase: r.clase, profesor: r.profesor,
  lugar: r.lugar, fecha, hora, precio_cop: r.precio_cop, expira_en: r.expira_en } }];
";
const RESP_EST  = "const j = $input.first().json;\nconst r = (j && j.ok !== undefined) ? j : (Array.isArray(j) ? j[0] : {});\nif (!r.ok) return [{ json: { http_status: 404, ok: false, error: r.error || \"no_encontrada\" } }];\nconst mensajes = {\n  confirmada: \"Pago confirmado. Tu cupo esta asegurado.\",\n  verificando: \"Estamos esperando la confirmacion del banco.\",\n  pendiente_validacion: \"Recibimos tu comprobante. Alguien del equipo lo valida y te escribimos por WhatsApp.\",\n  pendiente_pago: \"Falta subir el comprobante.\",\n  rechazada: \"No pudimos validar el pago. Escribenos por WhatsApp.\",\n  expirada: \"Se solto el cupo por falta de pago.\"\n};\nreturn [{ json: { http_status: 200, ok: true, estado: r.estado, codigo: r.codigo,\n  clase: r.clase, metodo: r.metodo || null, mensaje: mensajes[r.estado] || \"\" } }];\n";

const CORS = { entries: [{ name: 'Access-Control-Allow-Origin', value: '*' }] };

// ---------- 1. Horarios ----------
const wClases = trigger({
  type: 'n8n-nodes-base.webhook', version: 2,
  config: { name: 'GET clases', parameters: { httpMethod: 'GET', path: 'tumbao/clases', responseMode: 'responseNode', options: { allowedOrigins: '*' } } },
  output: [{ query: {} }]
});

const traerClases = node({
  type: 'n8n-nodes-base.httpRequest', version: 4.2,
  config: {
    name: 'Supabase: clases activas',
    alwaysOutputData: true,
    parameters: {
      method: 'GET',
      url: 'https://fobpccreihcylpsullhu.supabase.co/rest/v1/clases',
      authentication: 'predefinedCredentialType', nodeCredentialType: 'supabaseApi',
      sendQuery: true,
      queryParameters: { parameters: [
        { name: 'select', value: 'id,nombre,profesor,lugar,fecha_hora,duracion_min,precio_cop,cupo_total,cupo_tomado' },
        { name: 'activa', value: 'eq.true' },
        { name: 'fecha_hora', value: expr('=gt.{{ $now.toISO() }}') },
        { name: 'order', value: 'fecha_hora.asc' },
        { name: 'limit', value: '200' }
      ] },
      options: {}
    },
    credentials: { supabaseApi: newCredential('Supabase Tumbao') }
  },
  output: [{ id: 'uuid-demo', nombre: 'Salsa Principiante', profesor: 'Kevin', lugar: 'Sede Tumbao', fecha_hora: '2026-07-28T00:00:00+00:00', duracion_min: 60, precio_cop: 15000, cupo_total: 20, cupo_tomado: 3 }]
});

const agrupar = node({
  type: 'n8n-nodes-base.code', version: 2,
  config: { name: 'Agrupar por dia', parameters: { mode: 'runOnceForAllItems', language: 'javaScript', jsCode: AGRUPAR } },
  output: [{ ok: true, timezone: 'America/Bogota', dias: [] }]
});

const respClases = node({
  type: 'n8n-nodes-base.respondToWebhook', version: 1.1,
  config: { name: 'Responder clases', parameters: { respondWith: 'json', responseBody: expr('={{ JSON.stringify($json) }}'), options: { responseCode: 200, responseHeaders: CORS } } },
  output: [{ ok: true }]
});

// ---------- 2. Reservar ----------
const wReservar = trigger({
  type: 'n8n-nodes-base.webhook', version: 2,
  config: { name: 'POST reservar', parameters: { httpMethod: 'POST', path: 'tumbao/reservar', responseMode: 'responseNode', options: { allowedOrigins: '*' } } },
  output: [{ body: { clase_id: 'uuid-demo', nombre: 'Camila', telefono: '3001234567', habeas: true } }]
});

const normalizar = node({
  type: 'n8n-nodes-base.code', version: 2,
  config: { name: 'Normalizar datos', parameters: { mode: 'runOnceForAllItems', language: 'javaScript', jsCode: NORMALIZAR } },
  output: [{ es_bot: false, valido: true, clase_id: 'uuid-demo', nombre: 'Camila', telefono: '3001234567', email: '', habeas: true }]
});

const esValido = ifElse({
  version: 2.2,
  config: { name: 'Datos validos?', parameters: {
    conditions: { options: { caseSensitive: true, leftValue: '', typeValidation: 'loose', version: 2 },
      conditions: [{ id: 'v', leftValue: expr('{{ $json.valido }}'), rightValue: '', operator: { type: 'boolean', operation: 'true', singleValue: true } }],
      combinator: 'and' },
    looseTypeValidation: true, options: {} } }
});

const tomarCupo = node({
  type: 'n8n-nodes-base.httpRequest', version: 4.2,
  config: {
    name: 'Supabase: tomar_cupo',
    parameters: {
      method: 'POST', url: 'https://fobpccreihcylpsullhu.supabase.co/rest/v1/rpc/tomar_cupo',
      authentication: 'predefinedCredentialType', nodeCredentialType: 'supabaseApi',
      sendBody: true, specifyBody: 'json',
      jsonBody: expr('={{ JSON.stringify({ p_clase_id: $json.clase_id, p_nombre: $json.nombre, p_telefono: $json.telefono, p_email: $json.email || null, p_origen: "formulario" }) }}'),
      options: {}
    },
    credentials: { supabaseApi: newCredential('Supabase Tumbao') }
  },
  output: [{ ok: true, codigo: 'ABC234', clase: 'Salsa Principiante', precio_cop: 15000, fecha_hora: '2026-07-28T00:00:00+00:00', expira_en: '2026-07-26T22:00:00+00:00' }]
});

const respReserva = node({
  type: 'n8n-nodes-base.code', version: 2,
  config: { name: 'Armar respuesta reserva', parameters: { mode: 'runOnceForAllItems', language: 'javaScript', jsCode: RESP_RES } },
  output: [{ http_status: 200, ok: true, codigo: 'ABC234', clase: 'Salsa Principiante', fecha: 'martes, 28 de julio', hora: '7:00 pm', precio_cop: 15000 }]
});

const datosMalos = node({
  type: 'n8n-nodes-base.set', version: 3.4,
  config: { name: 'Datos incompletos', parameters: { mode: 'raw',
    jsonOutput: expr('={{ JSON.stringify({ http_status: $json.es_bot ? 200 : 400, ok: $json.es_bot, codigo: $json.es_bot ? "OK" : null, error: $json.es_bot ? null : "datos_incompletos", mensaje: $json.es_bot ? "" : "Revisa nombre, celular y la autorizacion de datos." }) }}') } },
  output: [{ http_status: 400, ok: false, error: 'datos_incompletos' }]
});

const respReservaHttp = node({
  type: 'n8n-nodes-base.respondToWebhook', version: 1.1,
  config: { name: 'Responder reserva', parameters: { respondWith: 'json', responseBody: expr('={{ JSON.stringify($json) }}'), options: { responseCode: expr('={{ $json.http_status }}'), responseHeaders: CORS } } },
  output: [{ ok: true }]
});

// ---------- 3. Comprobante ----------
const wComprobante = trigger({
  type: 'n8n-nodes-base.webhook', version: 2,
  config: { name: 'POST comprobante', parameters: { httpMethod: 'POST', path: 'tumbao/comprobante', responseMode: 'responseNode', options: { allowedOrigins: '*' } } },
  output: [{ body: { codigo: 'ABC234' } }]
});

const marcarVerificando = node({
  type: 'n8n-nodes-base.httpRequest', version: 4.2,
  config: {
    name: 'Supabase: pasa a verificando',
    alwaysOutputData: true,
    parameters: {
      method: 'PATCH', url: 'https://fobpccreihcylpsullhu.supabase.co/rest/v1/reservas',
      authentication: 'predefinedCredentialType', nodeCredentialType: 'supabaseApi',
      sendQuery: true,
      queryParameters: { parameters: [
        { name: 'codigo', value: expr('=eq.{{ ($json.body.codigo || "").toString().trim().toUpperCase() }}') },
        { name: 'estado', value: 'eq.pendiente_pago' }
      ] },
      sendHeaders: true,
      headerParameters: { parameters: [{ name: 'Prefer', value: 'return=representation' }] },
      sendBody: true, specifyBody: 'json',
      jsonBody: expr('={{ JSON.stringify({ estado: "verificando", updated_at: new Date().toISOString() }) }}'),
      options: {}
    },
    credentials: { supabaseApi: newCredential('Supabase Tumbao') }
  },
  output: [{ codigo: 'ABC234', estado: 'verificando' }]
});

const respComprobante = node({
  type: 'n8n-nodes-base.respondToWebhook', version: 1.1,
  config: { name: 'Responder comprobante', parameters: { respondWith: 'json',
    responseBody: expr('={{ JSON.stringify({ ok: true, estado: "verificando", codigo: $("POST comprobante").item.json.body.codigo }) }}'),
    options: { responseCode: 200, responseHeaders: CORS } } },
  output: [{ ok: true, estado: 'verificando' }]
});

// ---------- 4. Estado (barra de progreso) ----------
const wEstado = trigger({
  type: 'n8n-nodes-base.webhook', version: 2,
  config: { name: 'GET estado', parameters: { httpMethod: 'GET', path: 'tumbao/estado', responseMode: 'responseNode', options: { allowedOrigins: '*' } } },
  output: [{ query: { codigo: 'ABC234' } }]
});

const seVencio = ifElse({
  version: 2.2,
  config: { name: 'Se vencieron los 5 min?', parameters: {
    conditions: { options: { caseSensitive: true, leftValue: '', typeValidation: 'loose', version: 2 },
      conditions: [{ id: 'v', leftValue: expr('{{ $json.query.vencido }}'), rightValue: '1', operator: { type: 'string', operation: 'equals' } }],
      combinator: 'and' },
    looseTypeValidation: true, options: {} } }
});

const aValidacionHumana = node({
  type: 'n8n-nodes-base.httpRequest', version: 4.2,
  config: {
    name: 'Supabase: a validacion humana',
    parameters: {
      method: 'POST', url: 'https://fobpccreihcylpsullhu.supabase.co/rest/v1/rpc/marcar_pendiente_validacion',
      authentication: 'predefinedCredentialType', nodeCredentialType: 'supabaseApi',
      sendBody: true, specifyBody: 'json',
      jsonBody: expr('={{ JSON.stringify({ p_codigo: $json.query.codigo }) }}'),
      options: {}
    },
    credentials: { supabaseApi: newCredential('Supabase Tumbao') }
  },
  output: [{ ok: true, estado: 'pendiente_validacion', codigo: 'ABC234' }]
});

const conciliar = node({
  type: 'n8n-nodes-base.httpRequest', version: 4.2,
  config: {
    name: 'Supabase: conciliar_reserva',
    parameters: {
      method: 'POST', url: 'https://fobpccreihcylpsullhu.supabase.co/rest/v1/rpc/conciliar_reserva',
      authentication: 'predefinedCredentialType', nodeCredentialType: 'supabaseApi',
      sendBody: true, specifyBody: 'json',
      jsonBody: expr('={{ JSON.stringify({ p_codigo: $json.query.codigo }) }}'),
      options: {}
    },
    credentials: { supabaseApi: newCredential('Supabase Tumbao') }
  },
  output: [{ ok: true, estado: 'verificando', codigo: 'ABC234', clase: 'Salsa Principiante' }]
});

const respEstado = node({
  type: 'n8n-nodes-base.code', version: 2,
  config: { name: 'Armar respuesta estado', parameters: { mode: 'runOnceForAllItems', language: 'javaScript', jsCode: RESP_EST } },
  output: [{ http_status: 200, ok: true, estado: 'verificando', codigo: 'ABC234', mensaje: 'Estamos esperando la confirmacion del banco.' }]
});

const respEstadoHttp = node({
  type: 'n8n-nodes-base.respondToWebhook', version: 1.1,
  config: { name: 'Responder estado', parameters: { respondWith: 'json', responseBody: expr('={{ JSON.stringify($json) }}'), options: { responseCode: expr('={{ $json.http_status }}'), responseHeaders: CORS } } },
  output: [{ ok: true }]
});

const nota = sticky(
  '## API de reservas de Tumbao\n\n' +
  'Cuatro webhooks que la pagina consume. Todos hablan con Supabase por HTTPS\n' +
  'con la credencial "Supabase Tumbao" (service_role).\n\n' +
  'GET  /tumbao/clases           horarios con cupo\n' +
  'POST /tumbao/reservar         toma el cupo, devuelve el codigo\n' +
  'POST /tumbao/comprobante      la persona dice que ya pago -> verificando\n' +
  'GET  /tumbao/estado?codigo=   lo llama la barra de 5 minutos\n' +
  'GET  /tumbao/estado?codigo=&vencido=1   se acabo el tiempo -> validacion humana\n\n' +
  'La decision de confirmar NO vive aqui: vive en las funciones de Postgres,\n' +
  'que bloquean fila. Aqui solo se enruta.\n\n' +
  'PENDIENTE: guardar la imagen del comprobante. Hoy el endpoint solo marca\n' +
  'verificando. Falta crear el bucket en Supabase Storage y subir ahi el\n' +
  'archivo. La confirmacion automatica no depende de la imagen (depende del\n' +
  'correo del banco); la imagen solo la necesita quien valida a mano.',
  [wClases, traerClases, agrupar], { color: 4 });

export default workflow('tumbao-api-reservas', 'Tumbao - API de reservas')
  .add(wClases).to(traerClases).to(agrupar).to(respClases)
  .add(wReservar).to(normalizar).to(esValido
    .onTrue(tomarCupo.to(respReserva.to(respReservaHttp)))
    .onFalse(datosMalos.to(respReservaHttp)))
  .add(wComprobante).to(marcarVerificando).to(respComprobante)
  .add(wEstado).to(seVencio
    .onTrue(aValidacionHumana.to(respEstado.to(respEstadoHttp)))
    .onFalse(conciliar.to(respEstado.to(respEstadoHttp))))
  .add(nota);
