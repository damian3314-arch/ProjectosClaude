/**
 * La plantilla tiquetera_constancia (11 oct): la tiquetera vendida por constancia y disciplina, no por ahorro.
 * Damián: «anímate a tu tiquetera con constancia y disciplina; siempre vendrán cosas buenas; rétate tú»; nada de «sorpresas» ni
 * tono de vendedor; y que sirva para hombres también (también bailan): lenguaje neutro, sin «misma/mismo» ni «@».
 *
 *   node tiquetera-constancia.test.mjs
 */
import { readFileSync } from 'node:fs';
import worker from '../../tumbao-caja/src/index.js';

let fallos = 0;
const ok = (n, c, extra = '') => { if (!c) fallos++; console.log(`${c ? '✓' : '✗'} ${n}${extra ? '  → ' + extra : ''}`); };
const w = readFileSync(new URL('../../tumbao-caja/src/index.js', import.meta.url), 'utf8');
const i = w.indexOf("name: 'tiquetera_constancia'");
const t = w.slice(i, w.indexOf("name: 'tiquetera_semana'", i));
const cuerpo = (() => { const m = /type: 'BODY',\s*text:\s*([\s\S]*?),\s*example:/.exec(t); return m ? eval(m[1]) : ''; })();

ok('existe y es de MARKETING (para vender), en español', i > 0 && /category: 'MARKETING'/.test(t) && /language: 'es'/.test(t));
ok('el texto que aprobó Damián (opción 1): constancia, reto, compromiso y «cosas buenas»', /Este mes bailaste \{\{2\}\} veces, y eso ya dice mucho de ti\./.test(cuerpo)
   && /Los objetivos no se cumplen con ganas, se cumplen con constancia\./.test(cuerpo) && /Rétate a seguir: tu tiquetera es ese compromiso contigo/.test(cuerpo)
   && /siempre llegan cosas buenas/.test(cuerpo), cuerpo);
ok('lenguaje neutro: sirve igual para un hombre (sin «misma/mismo», «@», «bienvenida», «lista para ti»…)', !/\bmism[oa]\b|@|\bbienvenid[oa]\b|\b(sol|list|segur|motivad|cansad)[oa]\b/i.test(cuerpo.replace(/clases listas/, '')));
ok('sin sorpresas prometidas, sin precios, sin descuentos ni urgencias inventadas', !/sorpresa|regalo|gratis|descuento|promo|\$|últim|solo hoy|hasta el/i.test(cuerpo));
ok('dos variables: el nombre y las clases del mes, con ejemplo para Meta', /\{\{1\}\}/.test(cuerpo) && /\{\{2\}\}/.test(cuerpo) && !/\{\{3\}\}/.test(cuerpo) && /body_text: \[\['Laura', '4'\]\]/.test(t));
ok('cabe de sobra (WhatsApp: 1024 caracteres)', cuerpo.length > 100 && cuerpo.length < 600, String(cuerpo.length));
ok('botones: comprar en la página, «Cuéntame de la tiquetera» (lo contesta el asistente con los paquetes) y la baja', /type: 'URL', text: 'Quiero mi tiquetera', url: 'https:\/\/tumbaobaila\.com\/mensualidad'/.test(t)
   && /type: 'QUICK_REPLY', text: 'Cuéntame de la tiquetera'/.test(t) && /type: 'QUICK_REPLY', text: 'No quiero más mensajes'/.test(t));
ok('los textos de los botones caben (25 caracteres)', ['Quiero mi tiquetera', 'Cuéntame de la tiquetera', 'No quiero más mensajes'].every(b => b.length <= 25));
ok('«No quiero más mensajes» da la baja (lo atiende PIDE_SALIR)', /PIDE_SALIR = \/\^\\s\*\(salir\|baja\|stop\|parar\|cancelar\|no\\s\+m\[aá\]s\(\\s\+mensajes\)\?\|no\\s\+quiero\\s\+\(m\[aá\]s\\s\+\)\?mensajes\)/.test(w));
ok('la plantilla vieja sigue definida (Meta no deja editar una aprobada: se crea otra con otro nombre)', w.includes("name: 'tiquetera_semana'"));


// ── el envío: solo cuando Meta la aprobó; la cola solo manda campañas en horario de mercadeo ─────────────────────
async function llamar(estadoMeta, { metaFalla = false } = {}) {
  const rpcs = []; const enviados = [];
  const original = globalThis.fetch;
  globalThis.fetch = async (url, opc = {}) => {
    url = String(url);
    const res = (o, st = 200) => new Response(JSON.stringify(o), { status: st, headers: { 'content-type': 'application/json' } });
    if (url.includes('/message_templates')) {
      if (metaFalla) return res({ error: { message: 'x' } }, 400);
      return res({ data: estadoMeta ? [{ name: 'tiquetera_constancia', status: estadoMeta, language: 'es' }, { name: 'tiquetera_semana', status: 'APPROVED', language: 'es' }] : [] });
    }
    if (url.startsWith('https://sb.test/rest/v1/rpc/')) {
      const fn = url.split('/rpc/')[1]; const b = opc.body ? JSON.parse(opc.body) : {};
      rpcs.push({ fn, b });
      if (fn === 'campana_tiquetera_constancia') return res({ candidatos: 20, encolados: 20, ejecutado: true });
      if (fn === 'wa_tomar_avisos') return res(rpcs.filter(r => r.fn === 'wa_tomar_avisos').length === 1 ? [{ id: 1, para: '573001234567', plantilla: 'tiquetera_constancia', variables: ['Laura', '4'] }] : []);
      return res({});
    }
    if (url.includes('/messages')) { enviados.push(JSON.parse(opc.body)); return res({ messages: [{ id: 'wamid.X' }] }); }
    return res({}, 404);
  };
  try {
    const r = await worker.fetch(new Request('https://w.test/wa/campana-tiquetera', { method: 'POST', body: '{}' }),
      { SUPABASE_URL: 'https://sb.test', SUPABASE_SERVICE_KEY: 'k', WHATSAPP_TOKEN: 't', WHATSAPP_PHONE_ID: '111', WHATSAPP_WABA_ID: '222' }, { waitUntil() {} });
    return { d: await r.json(), rpcs, enviados };
  } finally { globalThis.fetch = original; }
}
{
  const t = await llamar('PENDING');
  ok('con la plantilla PENDIENTE en Meta no encola ni manda nada (un envío así fallaría y la cola no reintenta)', t.d.ok === true && t.d.estado === 'PENDING' && !t.rpcs.some(r => r.fn === 'campana_tiquetera_constancia') && t.enviados.length === 0);
  const r = await llamar('REJECTED');
  ok('rechazada: tampoco', r.d.estado === 'REJECTED' && !r.rpcs.some(x => x.fn === 'campana_tiquetera_constancia'));
  const n = await llamar(null);
  ok('si no existe en Meta: tampoco', n.d.estado === 'NO_EXISTE' && n.enviados.length === 0);
  const f = await llamar('APPROVED', { metaFalla: true });
  ok('si Meta no responde: no encola (no adivina que está aprobada)', f.d.ok === false && !f.rpcs.some(x => x.fn === 'campana_tiquetera_constancia'));
}
{
  const t = await llamar('APPROVED');
  const c = t.rpcs.find(r => r.fn === 'campana_tiquetera_constancia');
  ok('APROBADA: encola la campaña (p_ejecutar = true) apenas la encuentra aprobada', c && c.b.p_ejecutar === true && t.d.encolados === 20);
  ok('…y despacha la cola de una vez (la cola decide si es horario de mercadeo)', t.rpcs.some(r => r.fn === 'wa_tomar_avisos') && t.enviados.length === 1 && t.enviados[0].template.name === 'tiquetera_constancia'
     && JSON.stringify(t.enviados[0].template.components[0].parameters) === JSON.stringify([{ type: 'text', text: 'Laura' }, { type: 'text', text: '4' }]));
}
{
  const raw = readFileSync(new URL('../supabase/migrations/0171_campana_tiquetera_constancia.sql', import.meta.url), 'utf8');
  const m = raw.replace(/--.*$/gm, '');
  ok('migración: los mismos filtros de siempre (frecuentes de suelta, sin mensualidad ni tiquetera vigente, sin baja, no dueños, máx. 2 campañas en 14 días)',
     /r\.veces >= 2/.test(m) && /not in \(select tel from vig\)/.test(m) && /not wa_es_dueno\(r\.tel\)/.test(m) && /wa_bajas/.test(m) && /interval '14 days'\) < 2/.test(m) && /t\.pagado_en is not null and t\.vence_el >= hoy/.test(m));
  ok('migración: nunca a quien ya recibió una plantilla de tiquetera, y cada persona UNA sola vez (clave tiqconst:<celular>)',
     /'tiquetera_semana', 'tiquetera_frecuentes', 'tiquetera_constancia'/.test(m) && /'tiqconst:' \|\| c\.tel/.test(m) && /on conflict \(clave\) do nothing/.test(m));
  ok('migración: aviso tipo campaña (la cola solo lo manda en horario de mercadeo) y vence en 4 días (sobrevive un puente festivo)', /'campana', c\.tel, 'tiquetera_constancia'/.test(m) && /now\(\) \+ interval '4 days'/.test(m));
  ok('migración: con p_ejecutar = false solo cuenta; solo el Worker (service_role) la ejecuta', /where p_ejecutar/.test(m) && /grant execute on function public\.campana_tiquetera_constancia\(boolean\) to service_role/.test(m) && /revoke all on function public\.campana_tiquetera_constancia\(boolean\) from public, anon, authenticated/.test(m));
  ok('migración: un cron cada hora llama la ruta del Worker (y nada destructivo)', /cron\.schedule\('tumbao-tiquetera-constancia', '5 \* \* \* \*'/.test(m) && /wa_campana_tiquetera_url/.test(m) && !/\b(delete|drop|truncate)\b/i.test(m));
  const h = readFileSync(new URL('../../tumbao-caja/src/index.js', import.meta.url), 'utf8');
  ok('el Worker tiene la ruta /wa/campana-tiquetera (la llama el cron por POST; GET para revisarla a mano)', /ruta === '\/wa\/campana-tiquetera' && \(request\.method === 'POST' \|\| request\.method === 'GET'\)/.test(h));
}

console.log(fallos ? `\n${fallos} fallo(s)` : '\nTodo en verde.');
process.exit(fallos ? 1 : 0);
