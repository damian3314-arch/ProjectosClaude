import { workflow, node, trigger, sticky, expr } from '@n8n/workflow-sdk';

const t0 = trigger({
  type: 'n8n-nodes-base.webhook', version: 2,
  config: { name: 'POST semana', parameters: {
    httpMethod: 'POST', path: 'tumbao/admin/semana',
    responseMode: 'responseNode', options: { allowedOrigins: '*' } } }
});

const h0 = node({
  type: 'n8n-nodes-base.httpRequest', version: 4.2,
  config: { name: 'Supabase: admin_semana',
    position: [240, 0],
    parameters: {
      method: 'POST', url: "https://fobpccreihcylpsullhu.supabase.co/rest/v1/rpc/admin_semana",
      authentication: 'predefinedCredentialType',
      nodeCredentialType: 'supabaseApi',
      sendBody: true, specifyBody: 'json',
      jsonBody: expr("={{ (() => { const b = $json.body || {}; return JSON.stringify({ p_token: b.token, p_desde: b.desde }); })() }}"),
      options: {}
    },
    credentials: {"supabaseApi":{"id":"YuDlaBP89tkmEfOb","name":"Supabase Tumbao"}}
  }
});

const r0 = node({
  type: 'n8n-nodes-base.respondToWebhook', version: 1.1,
  config: { name: 'Responder semana',
    position: [480, 0],
    parameters: {
      respondWith: 'json',
      responseBody: expr('={{ JSON.stringify($json) }}'),
      options: {
        responseCode: expr("={{ $json.ok ? 200 : ($json.error === 'NO_AUTORIZADO' ? 401 : 400) }}"),
        responseHeaders: { entries: [{ name: 'Access-Control-Allow-Origin', value: '*' }] }
      }
    }
  }
});

const t1 = trigger({
  type: 'n8n-nodes-base.webhook', version: 2,
  config: { name: 'POST guardar', parameters: {
    httpMethod: 'POST', path: 'tumbao/admin/guardar',
    responseMode: 'responseNode', options: { allowedOrigins: '*' } } }
});

const h1 = node({
  type: 'n8n-nodes-base.httpRequest', version: 4.2,
  config: { name: 'Supabase: admin_guardar_semana',
    position: [240, 200],
    parameters: {
      method: 'POST', url: "https://fobpccreihcylpsullhu.supabase.co/rest/v1/rpc/admin_guardar_semana",
      authentication: 'predefinedCredentialType',
      nodeCredentialType: 'supabaseApi',
      sendBody: true, specifyBody: 'json',
      jsonBody: expr("={{ (() => { const b = $json.body || {}; return JSON.stringify({ p_token: b.token, p_celdas: b.celdas }); })() }}"),
      options: {}
    },
    credentials: {"supabaseApi":{"id":"YuDlaBP89tkmEfOb","name":"Supabase Tumbao"}}
  }
});

const r1 = node({
  type: 'n8n-nodes-base.respondToWebhook', version: 1.1,
  config: { name: 'Responder guardar',
    position: [480, 200],
    parameters: {
      respondWith: 'json',
      responseBody: expr('={{ JSON.stringify($json) }}'),
      options: {
        responseCode: expr("={{ $json.ok ? 200 : ($json.error === 'NO_AUTORIZADO' ? 401 : 400) }}"),
        responseHeaders: { entries: [{ name: 'Access-Control-Allow-Origin', value: '*' }] }
      }
    }
  }
});

const t2 = trigger({
  type: 'n8n-nodes-base.webhook', version: 2,
  config: { name: 'POST pendientes', parameters: {
    httpMethod: 'POST', path: 'tumbao/admin/pendientes',
    responseMode: 'responseNode', options: { allowedOrigins: '*' } } }
});

const h2 = node({
  type: 'n8n-nodes-base.httpRequest', version: 4.2,
  config: { name: 'Supabase: admin_pendientes',
    position: [240, 400],
    parameters: {
      method: 'POST', url: "https://fobpccreihcylpsullhu.supabase.co/rest/v1/rpc/admin_pendientes",
      authentication: 'predefinedCredentialType',
      nodeCredentialType: 'supabaseApi',
      sendBody: true, specifyBody: 'json',
      jsonBody: expr("={{ (() => { const b = $json.body || {}; return JSON.stringify({ p_token: b.token }); })() }}"),
      options: {}
    },
    credentials: {"supabaseApi":{"id":"YuDlaBP89tkmEfOb","name":"Supabase Tumbao"}}
  }
});

const r2 = node({
  type: 'n8n-nodes-base.respondToWebhook', version: 1.1,
  config: { name: 'Responder pendientes',
    position: [480, 400],
    parameters: {
      respondWith: 'json',
      responseBody: expr('={{ JSON.stringify($json) }}'),
      options: {
        responseCode: expr("={{ $json.ok ? 200 : ($json.error === 'NO_AUTORIZADO' ? 401 : 400) }}"),
        responseHeaders: { entries: [{ name: 'Access-Control-Allow-Origin', value: '*' }] }
      }
    }
  }
});

const t3 = trigger({
  type: 'n8n-nodes-base.webhook', version: 2,
  config: { name: 'POST confirmar', parameters: {
    httpMethod: 'POST', path: 'tumbao/admin/confirmar',
    responseMode: 'responseNode', options: { allowedOrigins: '*' } } }
});

const h3 = node({
  type: 'n8n-nodes-base.httpRequest', version: 4.2,
  config: { name: 'Supabase: admin_confirmar',
    position: [240, 600],
    parameters: {
      method: 'POST', url: "https://fobpccreihcylpsullhu.supabase.co/rest/v1/rpc/admin_confirmar",
      authentication: 'predefinedCredentialType',
      nodeCredentialType: 'supabaseApi',
      sendBody: true, specifyBody: 'json',
      jsonBody: expr("={{ (() => { const b = $json.body || {}; return JSON.stringify({ p_token: b.token, p_codigo: b.codigo, p_pago_id: b.pago_id || null }); })() }}"),
      options: {}
    },
    credentials: {"supabaseApi":{"id":"YuDlaBP89tkmEfOb","name":"Supabase Tumbao"}}
  }
});

const r3 = node({
  type: 'n8n-nodes-base.respondToWebhook', version: 1.1,
  config: { name: 'Responder confirmar',
    position: [480, 600],
    parameters: {
      respondWith: 'json',
      responseBody: expr('={{ JSON.stringify($json) }}'),
      options: {
        responseCode: expr("={{ $json.ok ? 200 : ($json.error === 'NO_AUTORIZADO' ? 401 : 400) }}"),
        responseHeaders: { entries: [{ name: 'Access-Control-Allow-Origin', value: '*' }] }
      }
    }
  }
});

const t4 = trigger({
  type: 'n8n-nodes-base.webhook', version: 2,
  config: { name: 'POST rechazar', parameters: {
    httpMethod: 'POST', path: 'tumbao/admin/rechazar',
    responseMode: 'responseNode', options: { allowedOrigins: '*' } } }
});

const h4 = node({
  type: 'n8n-nodes-base.httpRequest', version: 4.2,
  config: { name: 'Supabase: admin_rechazar',
    position: [240, 800],
    parameters: {
      method: 'POST', url: "https://fobpccreihcylpsullhu.supabase.co/rest/v1/rpc/admin_rechazar",
      authentication: 'predefinedCredentialType',
      nodeCredentialType: 'supabaseApi',
      sendBody: true, specifyBody: 'json',
      jsonBody: expr("={{ (() => { const b = $json.body || {}; return JSON.stringify({ p_token: b.token, p_codigo: b.codigo }); })() }}"),
      options: {}
    },
    credentials: {"supabaseApi":{"id":"YuDlaBP89tkmEfOb","name":"Supabase Tumbao"}}
  }
});

const r4 = node({
  type: 'n8n-nodes-base.respondToWebhook', version: 1.1,
  config: { name: 'Responder rechazar',
    position: [480, 800],
    parameters: {
      respondWith: 'json',
      responseBody: expr('={{ JSON.stringify($json) }}'),
      options: {
        responseCode: expr("={{ $json.ok ? 200 : ($json.error === 'NO_AUTORIZADO' ? 401 : 400) }}"),
        responseHeaders: { entries: [{ name: 'Access-Control-Allow-Origin', value: '*' }] }
      }
    }
  }
});

const t5 = trigger({
  type: 'n8n-nodes-base.webhook', version: 2,
  config: { name: 'POST asistentes', parameters: {
    httpMethod: 'POST', path: 'tumbao/admin/asistentes',
    responseMode: 'responseNode', options: { allowedOrigins: '*' } } }
});

const h5 = node({
  type: 'n8n-nodes-base.httpRequest', version: 4.2,
  config: { name: 'Supabase: admin_reservas_de_clase',
    position: [240, 1000],
    parameters: {
      method: 'POST', url: "https://fobpccreihcylpsullhu.supabase.co/rest/v1/rpc/admin_reservas_de_clase",
      authentication: 'predefinedCredentialType',
      nodeCredentialType: 'supabaseApi',
      sendBody: true, specifyBody: 'json',
      jsonBody: expr("={{ (() => { const b = $json.body || {}; return JSON.stringify({ p_token: b.token, p_clase_id: b.clase_id }); })() }}"),
      options: {}
    },
    credentials: {"supabaseApi":{"id":"YuDlaBP89tkmEfOb","name":"Supabase Tumbao"}}
  }
});

const r5 = node({
  type: 'n8n-nodes-base.respondToWebhook', version: 1.1,
  config: { name: 'Responder asistentes',
    position: [480, 1000],
    parameters: {
      respondWith: 'json',
      responseBody: expr('={{ JSON.stringify($json) }}'),
      options: {
        responseCode: expr("={{ $json.ok ? 200 : ($json.error === 'NO_AUTORIZADO' ? 401 : 400) }}"),
        responseHeaders: { entries: [{ name: 'Access-Control-Allow-Origin', value: '*' }] }
      }
    }
  }
});

const nota = sticky("## Panel de admin de Tumbao\n\nSeis webhooks que consume web/admin.html. Todos POST, para que el token\nno viaje en la URL y no quede en logs ni en el Referer.\n\nPOST /tumbao/admin/semana      la cuadricula de una semana\nPOST /tumbao/admin/guardar     guarda la semana entera (crear/apagar/cupos)\nPOST /tumbao/admin/pendientes  cola de pagos por validar a mano\nPOST /tumbao/admin/confirmar   el check\nPOST /tumbao/admin/rechazar    rechaza y suelta el cupo\nPOST /tumbao/admin/asistentes  quien viene a una clase\n\nQuien decide si el token vale es Postgres, no n8n: cada funcion llama a\nverificar_token_admin() antes de hacer nada. Aqui solo se enruta.\n\nEl token se emite una sola vez con:  select crear_token_admin('Tania');", [], { color: 3 });

export default workflow('tumbao-admin', 'Tumbao · Panel de admin')
  .add(nota)
  .add(t0).to(h0).to(r0)
  .add(t1).to(h1).to(r1)
  .add(t2).to(h2).to(r2)
  .add(t3).to(h3).to(r3)
  .add(t4).to(h4).to(r4)
  .add(t5).to(h5).to(r5);
