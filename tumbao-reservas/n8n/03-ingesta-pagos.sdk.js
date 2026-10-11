import { workflow, node, trigger, sticky, placeholder, newCredential, expr } from '@n8n/workflow-sdk';

const PARSER = "const VERBOS_SALIDA = [\n  /\\btransferiste\\b/i, /\\bpagaste\\b/i, /\\bcompraste\\b/i,\n  /\\bretiraste\\b/i, /\\bavance\\b/i\n];\nconst PATRONES = [\n  { id: \"transferencia_llave\", confianza: 1.0,\n    re: /recibiste una transferencia de\\s+(?<remitente>.+?)\\s+por\\s+\\$\\s*(?<monto>[\\d.,]+)\\s+en tu cuenta\\s+\\*+(?<cuenta>\\d+)\\s+conectada a la llave\\s+(?<llave>\\d+)\\s+el\\s+(?<fecha>\\d{1,2}\\/\\d{1,2}\\/\\d{2,4})\\s+a las\\s+(?<hora>\\d{1,2}:\\d{2})/i },\n  { id: \"transferencia_simple\", confianza: 1.0,\n    re: /recibiste una transferencia por\\s+\\$\\s*(?<monto>[\\d.,]+)\\s+de\\s+(?<remitente>.+?)\\s+en tu cuenta\\s+\\*+(?<cuenta>\\d+)\\s*,?\\s*el\\s+(?<fecha>\\d{1,2}\\/\\d{1,2}\\/\\d{2,4})\\s+a las\\s+(?<hora>\\d{1,2}:\\d{2})/i },\n  { id: \"pago_qr\", confianza: 0.9,\n    re: /recibiste un pago(?:\\s+por\\s+c[oó]digo\\s+QR)?\\s+de\\s+(?<remitente>.+?)\\s+por\\s+\\$\\s*(?<monto>[\\d.,]+)\\s+en tu cuenta[^.]*?\\s+el\\s+(?<fecha>\\d{1,2}\\/\\d{1,2}\\/\\d{2,4})\\s+a las\\s+(?<hora>\\d{1,2}:\\d{2})/i },\n  { id: \"generico\", confianza: 0.4,\n    re: /recibiste[^$]*\\$\\s*(?<monto>[\\d.,]+)[\\s\\S]*?(?<fecha>\\d{1,2}\\/\\d{1,2}\\/\\d{2,4})[^\\d]{0,12}(?<hora>\\d{1,2}:\\d{2})?/i }\n];\nfunction parsearMonto(t) {\n  if (!t) return null;\n  let s = String(t).trim();\n  if (s.includes(\",\")) { s = s.replace(/\\./g, \"\").replace(\",\", \".\"); }\n  else if (/\\.\\d{2}$/.test(s)) { s = s.replace(/\\.(?=.*\\.)/g, \"\"); }\n  else { s = s.replace(/\\./g, \"\"); }\n  const n = parseFloat(s);\n  if (!Number.isFinite(n) || n <= 0) return null;\n  return Math.round(n);\n}\nfunction parsearFecha(f, h) {\n  if (!f) return null;\n  const m = /^(\\d{1,2})\\/(\\d{1,2})\\/(\\d{2,4})$/.exec(String(f).trim());\n  if (!m) return null;\n  const dia = +m[1], mes = +m[2];\n  let anio = +m[3]; if (anio < 100) anio += 2000;\n  if (dia < 1 || dia > 31 || mes < 1 || mes > 12) return null;\n  let hh = 0, mm = 0;\n  if (h) { const x = /^(\\d{1,2}):(\\d{2})$/.exec(String(h).trim());\n    if (x) { hh = +x[1]; mm = +x[2]; if (hh > 23 || mm > 59) return null; } }\n  const p = (n) => String(n).padStart(2, \"0\");\n  return anio + \"-\" + p(mes) + \"-\" + p(dia) + \"T\" + p(hh) + \":\" + p(mm) + \":00-05:00\";\n}\nconst j = $input.item.json;\nconst crudo = j.text || j.textAsHtml || j.snippet || \"\";\nconst cuerpo = String(crudo).replace(/<[^>]+>/g, \" \").replace(/\\s+/g, \" \")\n  .replace(/¡Listo!\\s*Todo sali[oó] bien con tus movimientos\\s*/i, \"\").trim();\nconst base = { gmail_id: j.id || null, asunto: j.subject || null, raw_email: cuerpo.slice(0, 4000) };\nif (!cuerpo) return { json: { ...base, es_ingreso: false, motivo: \"cuerpo_vacio\" } };\nif (VERBOS_SALIDA.some((re) => re.test(cuerpo)))\n  return { json: { ...base, es_ingreso: false, motivo: \"movimiento_de_salida\" } };\nif (!/recibiste/i.test(cuerpo))\n  return { json: { ...base, es_ingreso: false, motivo: \"no_es_movimiento_de_entrada\" } };\nfor (const p of PATRONES) {\n  const m = p.re.exec(cuerpo);\n  if (!m || !m.groups) continue;\n  const valor = parsearMonto(m.groups.monto);\n  const fecha = parsearFecha(m.groups.fecha, m.groups.hora);\n  if (valor === null || fecha === null) continue;\n  return { json: { ...base, es_ingreso: true, patron: p.id, confianza: p.confianza,\n    banco: \"bancolombia\", valor_cop: valor, fecha_pago: fecha,\n    remitente: (m.groups.remitente || \"\").trim().replace(/\\s+/g, \" \") || null,\n    ultimos_4: m.groups.cuenta ? m.groups.cuenta.slice(-4) : null,\n    llave: m.groups.llave || null } };\n}\nreturn { json: { ...base, es_ingreso: false, motivo: \"estructura_no_reconocida\" } };";

const RESUMEN = "const r = $input.item.json.registrar_pago_y_conciliar || {};\nconst p = $(\"Parsear correo\").item.json;\nreturn { json: {\n  accion: r.accion || \"desconocida\",\n  confirmada: r.accion === \"reserva_confirmada\",\n  codigo: r.codigo || null,\n  nombre: r.nombre || null,\n  telefono: r.telefono || null,\n  valor_cop: p.valor_cop,\n  remitente: p.remitente,\n  fecha_pago: p.fecha_pago,\n  patron: p.patron,\n  confianza: p.confianza\n} };";

const correoBanco = trigger({
  type: 'n8n-nodes-base.gmailTrigger',
  version: 1.4,
  config: {
    name: 'Correo de Bancolombia',
    parameters: {
      pollTimes: { item: [{ mode: 'everyMinute' }] },
      simple: false,
      maxResults: 25,
      filters: {
        q: 'from:(alertasynotificaciones@an.notificacionesbancolombia.com OR alertasynotificaciones@bancolombia.com.co) newer_than:1d',
        readStatus: 'both',
      },
      options: {},
    },
    credentials: { gmailOAuth2: newCredential('Gmail Tumbao') },
  },
  output: [{
    id: '19f706a3ac7d082d',
    subject: 'Alertas y Notificaciones',
    text: 'Tumbao, recibiste una transferencia de CAMILA ROJAS por $15000.00 en tu cuenta *4471 conectada a la llave 3017833550 el 26/07/26 a las 19:05.',
  }],
});

const parsearCorreo = node({
  type: 'n8n-nodes-base.code',
  version: 2,
  config: {
    name: 'Parsear correo',
    parameters: { mode: 'runOnceForEachItem', language: 'javaScript', jsCode: PARSER },
  },
  output: [{
    es_ingreso: true, patron: 'transferencia_llave', confianza: 1,
    banco: 'bancolombia', valor_cop: 15000, fecha_pago: '2026-07-26T19:05:00-05:00',
    remitente: 'CAMILA ROJAS', ultimos_4: '4471', llave: '3017833550',
    gmail_id: '19f706a3ac7d082d', asunto: 'Alertas y Notificaciones', raw_email: 'Tumbao, recibiste una transferencia...',
  }],
});

const soloIngresos = node({
  type: 'n8n-nodes-base.filter',
  version: 2.3,
  config: {
    name: 'Solo dinero que entra',
    parameters: {
      conditions: {
        options: { caseSensitive: true, leftValue: '', typeValidation: 'loose', version: 2 },
        conditions: [{
          id: 'es-ingreso',
          leftValue: expr('{{ $json.es_ingreso }}'),
          rightValue: '',
          operator: { type: 'boolean', operation: 'true', singleValue: true },
        }],
        combinator: 'and',
      },
      looseTypeValidation: true,
      options: {},
    },
  },
  output: [{ es_ingreso: true, valor_cop: 15000, fecha_pago: '2026-07-26T19:05:00-05:00' }],
});

const anotarEnHoja = node({
  type: 'n8n-nodes-base.googleSheets',
  version: 4.7,
  config: {
    name: 'Anotar en la hoja',
    onError: 'continueRegularOutput',
    parameters: {
      resource: 'sheet',
      operation: 'append',
      documentId: { __rl: true, mode: 'list', value: '', cachedResultName: 'Pagos Tumbao' },
      sheetName: { __rl: true, mode: 'name', value: 'Pagos' },
      columns: {
        mappingMode: 'defineBelow',
        value: {
          fecha_pago: expr('{{ $json.fecha_pago }}'),
          banco: expr('{{ $json.banco }}'),
          valor_cop: expr('{{ $json.valor_cop }}'),
          remitente: expr('{{ $json.remitente }}'),
          ultimos_4: expr('{{ $json.ultimos_4 }}'),
          gmail_id: expr('{{ $json.gmail_id }}'),
          confianza: expr('{{ $json.confianza }}'),
        },
        schema: [
          { id: 'fecha_pago', displayName: 'fecha_pago', required: false, defaultMatch: false, display: true, type: 'string', canBeUsedToMatch: true },
          { id: 'banco', displayName: 'banco', required: false, defaultMatch: false, display: true, type: 'string', canBeUsedToMatch: false },
          { id: 'valor_cop', displayName: 'valor_cop', required: false, defaultMatch: false, display: true, type: 'number', canBeUsedToMatch: true },
          { id: 'remitente', displayName: 'remitente', required: false, defaultMatch: false, display: true, type: 'string', canBeUsedToMatch: false },
          { id: 'ultimos_4', displayName: 'ultimos_4', required: false, defaultMatch: false, display: true, type: 'string', canBeUsedToMatch: false },
          { id: 'gmail_id', displayName: 'gmail_id', required: false, defaultMatch: false, display: true, type: 'string', canBeUsedToMatch: true },
          { id: 'confianza', displayName: 'confianza', required: false, defaultMatch: false, display: true, type: 'number', canBeUsedToMatch: false },
        ],
      },
      options: { cellFormat: 'USER_ENTERED' },
    },
    credentials: { googleSheetsOAuth2Api: newCredential('Google Sheets Tumbao') },
  },
  output: [{ fecha_pago: '2026-07-26T19:05:00-05:00', valor_cop: 15000 }],
});

const registrarYConciliar = node({
  type: 'n8n-nodes-base.postgres',
  version: 2.6,
  config: {
    name: 'Registrar y conciliar',
    parameters: {
      operation: 'executeQuery',
      query: 'SELECT registrar_pago_y_conciliar($1, $2::int, $3::timestamptz, $4, $5, $6, $7::numeric, $8, $9) AS registrar_pago_y_conciliar;',
      options: {
        queryReplacement: expr('{{ [ $json.banco, $json.valor_cop, $json.fecha_pago, $json.llave, $json.remitente, $json.ultimos_4, $json.confianza, $json.raw_email, $json.gmail_id ] }}'),
      },
    },
    credentials: { postgres: newCredential('Supabase Tumbao') },
  },
  output: [{ registrar_pago_y_conciliar: { ok: true, accion: 'reserva_confirmada', codigo: 'XF3KS2', nombre: 'Camila', telefono: '3001234567' } }],
});

const resumir = node({
  type: 'n8n-nodes-base.code',
  version: 2,
  config: {
    name: 'Resumir resultado',
    parameters: { mode: 'runOnceForEachItem', language: 'javaScript', jsCode: RESUMEN },
  },
  output: [{ accion: 'reserva_confirmada', confirmada: true, codigo: 'XF3KS2', nombre: 'Camila', valor_cop: 15000 }],
});

const notaSetup = sticky(
  '## Antes de activar\n\n' +
  '1. **Gmail Tumbao** — credencial OAuth2 de la cuenta que RECIBE las alertas del banco. ' +
  'No sirve una cuenta personal: tienen que ser los correos de la cuenta de Tumbao.\n' +
  '2. **Supabase Tumbao** — credencial Postgres. Usa el pooler (puerto 6543) si n8n es cloud.\n' +
  '3. **Google Sheets Tumbao** — elige la hoja de pagos en el nodo. La pestaña debe llamarse ' +
  '`Pagos` y traer los encabezados: fecha_pago, banco, valor_cop, remitente, ultimos_4, gmail_id, confianza.\n\n' +
  '## Cómo decide\n\n' +
  'El parser rechaza todo lo que sea plata SALIENDO (transferiste, pagaste, compraste, retiraste). ' +
  'Solo pasa lo que entra. Probado contra los 6 formatos de salida y 5 de entrada de Bancolombia ' +
  '(`pruebas/parser.test.js`).\n\n' +
  'La decisión de confirmar NO está aquí: está en `registrar_pago_y_conciliar()` en Postgres, ' +
  'que bloquea la fila. Si dos personas pagaron el mismo monto en la misma ventana, no adivina — ' +
  'manda a validación humana.',
  [correoBanco, parsearCorreo, soloIngresos],
  { color: 4 },
);

const notaOjo = sticky(
  '## Ojo con el QR\n\n' +
  'El patrón `pago_qr` está escrito por analogía: no tengo un correo real de Bancolombia ' +
  'avisando un cobro RECIBIDO por QR Bre-B, solo de pagos enviados.\n\n' +
  'Cuando llegue el primer cobro real por QR a la cuenta de Tumbao, hay que mirar el texto ' +
  'exacto y ajustar la expresión regular. Mientras tanto cae en el patrón `generico` ' +
  'con confianza 0.4, que registra el pago pero **no** confirma solo — va a validación humana.',
  [registrarYConciliar, resumir],
  { color: 3 },
);

export default workflow('tumbao-ingesta-pagos', 'Tumbao · Ingesta de pagos')
  .add(correoBanco)
  .to(parsearCorreo)
  .to(soloIngresos)
  .to(anotarEnHoja)
  .to(registrarYConciliar)
  .to(resumir)
  .add(notaSetup)
  .add(notaOjo);
