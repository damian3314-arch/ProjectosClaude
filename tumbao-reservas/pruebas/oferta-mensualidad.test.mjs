/**
 * La invitación del cierre de «¿cómo te fue?» ahora vende primero la MENSUALIDAD (10 oct).
 *
 * Damián: «nos toca trabajar fuerte en vender más mensualidad y tiquetera». Quien acaba de vivir su primera clase y contó que
 * le encantó es la sangre nueva que reemplaza a quien no renueva, y la mensualidad ($5.000 la clase) vale 2,4 veces la
 * tiquetera chica. Protege que:
 *   1. con cupo real de mensualidad, va primero y dice los cupos EXACTOS por horario (y calla el horario lleno);
 *   2. sin cupos, sin perfil o con una consulta caída, queda la invitación de siempre (nunca se promete un cupo);
 *   3. a quien ya tiene plan o una tiquetera con clases no se le vende;
 *   4. el enlace nunca queda cortado y el precio viene del sistema, no del modelo.
 *
 *   node oferta-mensualidad.test.mjs
 */
import { invitacionPlanes, invitacionTiquetera } from '../../tumbao-caja/src/oferta.js';
import worker from '../../tumbao-caja/src/index.js';

let fallos = 0;
const ok = (n, c, extra = '') => { if (!c) fallos++; console.log(`${c ? '✓' : '✗'} ${n}${extra ? '  → ' + extra : ''}`); };
const titulo = t => console.log(`\n-- ${t} ${'-'.repeat(Math.max(0, 54 - t.length))}`);

const PAQ = [{ clases: 4, precio_cop: 52000, vigencia_dias: 30 }, { clases: 8, precio_cop: 96000, vigencia_dias: 30 }];
const PERFIL = { valor_mensualidad: 125000, mensualidad_por_clase: 5000, plan_vigente: null, tiquetera_vigente: null,
                 cupos_mensualidad: { '07:00': 8, '18:00': 3, '19:00': 0 } };

titulo('1. Con cupos: la mensualidad va primero');
{
  const t = invitacionPlanes({ paquetes: PAQ, perfil: PERFIL });
  ok('dice el precio de la mensualidad y lo que cuesta cada clase', /\$125\.000/.test(t) && /\$5\.000 la clase/.test(t), t);
  ok('lista los cupos reales por horario y calla el horario lleno', /8 cupos a las 7 am y 3 cupos a las 6 pm/.test(t) && !/7 pm/.test(t));
  ok('deja la tiquetera chica como la forma suave de empezar, con su precio', /prefieres empezar más suave, la tiquetera de 4 clases cuesta \$52\.000/.test(t));
  ok('termina con el enlace de compra, completo', t.endsWith('https://tumbaobaila.com/mensualidad'));
  ok('la mensualidad se menciona ANTES que la tiquetera', t.indexOf('mensualidad') < t.indexOf('tiquetera'));
  ok('un solo cupo: «1 cupo»', /1 cupo a las 6 pm/.test(invitacionPlanes({ paquetes: PAQ, perfil: { ...PERFIL, cupos_mensualidad: { '18:00': 1 } } })));
  ok('horas con minutos y 12 del día', /6:30 pm/.test(invitacionPlanes({ paquetes: PAQ, perfil: { ...PERFIL, cupos_mensualidad: { '18:30': 2 } } })) && /12 pm/.test(invitacionPlanes({ paquetes: PAQ, perfil: { ...PERFIL, cupos_mensualidad: { '12:00': 2 } } })));
  ok('los horarios salen en orden', /7 am[\s\S]*6 pm/.test(invitacionPlanes({ paquetes: PAQ, perfil: { ...PERFIL, cupos_mensualidad: { '18:00': 3, '07:00': 8 } } })));
  ok('sin paquetes de tiquetera igual vende la mensualidad, sin hablar de tiquetera', (() => { const x = invitacionPlanes({ paquetes: [], perfil: PERFIL }); return /\$125\.000/.test(x) && !/tiquetera/i.test(x) && /La compras aquí/.test(x); })());
  ok('si falta el costo por clase lo calcula con 25 clases al mes', /\$5\.000 la clase/.test(invitacionPlanes({ paquetes: PAQ, perfil: { ...PERFIL, mensualidad_por_clase: undefined } })));
}

titulo('2. Sin cupos o sin datos: la invitación de siempre, nunca un cupo inventado');
{
  const igual = invitacionTiquetera(PAQ);
  ok('todos los horarios llenos → la de la tiquetera', invitacionPlanes({ paquetes: PAQ, perfil: { ...PERFIL, cupos_mensualidad: { '07:00': 0, '18:00': 0, '19:00': 0 } } }) === igual);
  ok('sin cupos en el perfil → la de la tiquetera', invitacionPlanes({ paquetes: PAQ, perfil: { ...PERFIL, cupos_mensualidad: {} } }) === igual);
  ok('sin valor de mensualidad → la de la tiquetera', invitacionPlanes({ paquetes: PAQ, perfil: { ...PERFIL, valor_mensualidad: 0 } }) === igual);
  ok('la consulta del perfil falló (null) → la de la tiquetera', invitacionPlanes({ paquetes: PAQ, perfil: null }) === igual);
  ok('perfil basura → la de la tiquetera', invitacionPlanes({ paquetes: PAQ, perfil: 'x' }) === igual && invitacionPlanes({ paquetes: PAQ, perfil: [] }) === igual);
  ok('nada que ofrecer → vacío', invitacionPlanes({ paquetes: [], perfil: null }) === '' && invitacionPlanes() === '');
}

titulo('3. A quien ya tiene plan o tiquetera no se le vende');
{
  ok('con plan vigente → nada', invitacionPlanes({ paquetes: PAQ, perfil: { ...PERFIL, plan_vigente: { horario: '18:00:00', vence: '2026-10-20' } } }) === '');
  ok('con una tiquetera con clases → nada', invitacionPlanes({ paquetes: PAQ, perfil: { ...PERFIL, tiquetera_vigente: { clases_restantes: 3, vence: '2026-10-30' } } }) === '');
  ok('con una tiquetera ya gastada (0 clases) → sí se le ofrece', /mensualidad/.test(invitacionPlanes({ paquetes: PAQ, perfil: { ...PERFIL, tiquetera_vigente: { clases_restantes: 0 } } })));
}

// ── el Worker con todo simulado ────────────────────────────────────────────
const GRAPH = 'https://graph.facebook.com/v21.0';
async function correr({ perfil, paquetes = PAQ, perfilFalla = false, modelo }) {
  const enviados = []; const llamadas = [];
  const original = globalThis.fetch;
  globalThis.fetch = async (url, opc = {}) => {
    url = String(url);
    const cuerpo = opc.body && typeof opc.body === 'string' ? opc.body : '';
    const res = (obj, status = 200) => new Response(JSON.stringify(obj), { status, headers: { 'content-type': 'application/json' } });
    if (url.startsWith('https://sb.test/rest/v1/rpc/')) {
      const fn = url.split('/rpc/')[1];
      llamadas.push(fn);
      if (fn === 'wa_tomar_opinion') return res({ id: 9, telefono: '573001234567', wa_msg_id: 'wamid.IN', tipo: 'text', texto: 'Me encantó, todo muy bien', historial: [],
        opinion: { id: 3, nombre: 'Laura', clase: 'Rumba básica', estado: 'conversando', turnos: 1 } });
      if (fn === 'tiquetera_paquetes') return res(paquetes);
      if (fn === 'ventas_perfil') return perfilFalla ? res({ message: 'boom' }, 500) : res(perfil);
      return res({});
    }
    if (url === `${GRAPH}/111/messages`) {
      const b = JSON.parse(cuerpo);
      if (b.type === 'text') enviados.push(b.text.body);
      return res({ messages: [{ id: 'wamid.OUT' }] });
    }
    if (url === 'https://api.openai.com/v1/responses') return res({ output_text: JSON.stringify(modelo) });
    return res({}, 404);
  };
  const env = { SUPABASE_URL: 'https://sb.test', SUPABASE_SERVICE_KEY: 'k', WHATSAPP_TOKEN: 't', WHATSAPP_PHONE_ID: '111', OPENAI_API_KEY: 'o' };
  try {
    const r = await worker.fetch(new Request('https://w.test/wa/opinion', { method: 'POST', body: JSON.stringify({ id: 9 }) }), env, { waitUntil() {} });
    return { respuesta: await r.json(), enviados, llamadas };
  } finally { globalThis.fetch = original; }
}
const ELOGIO = { respuesta: '¡Qué alegría leerte, Laura! 🧡 Gracias por contarnos cómo te fue en tu primera clase.', cerrar: true, tipo: 'elogio', resumen: 'Le encantó' };

titulo('4. En el Worker: el cierre del «me encantó»');
{
  const t = await correr({ perfil: PERFIL, modelo: ELOGIO });
  const m = t.enviados[0] || '';
  ok('manda la respuesta del modelo y, aparte, la invitación con la mensualidad primero', /Qué alegría/.test(m) && /\$125\.000/.test(m) && /8 cupos a las 7 am y 3 cupos a las 6 pm/.test(m), m.slice(-260));
  ok('el enlace llega completo (el mensaje ya no se corta a los 900)', m.endsWith('https://tumbaobaila.com/mensualidad'), String(m.length));
  ok('pidió el perfil y los paquetes al sistema (no los inventa el código)', t.llamadas.includes('ventas_perfil') && t.llamadas.includes('tiquetera_paquetes'));
}
{
  const t = await correr({ perfil: { ...PERFIL, cupos_mensualidad: { '07:00': 0, '18:00': 0, '19:00': 0 } }, modelo: ELOGIO });
  ok('sin cupos: la invitación de siempre, la tiquetera', /tiquetera de 4 clases sale a \$52\.000/.test(t.enviados[0]) && !/cupos a las/.test(t.enviados[0]));
}
{
  const t = await correr({ perfil: null, perfilFalla: true, modelo: ELOGIO });
  ok('si la consulta del perfil se cae: la de la tiquetera, y la conversación no se rompe', /tiquetera de 4 clases/.test(t.enviados[0]) && t.respuesta.ok === true);
}
{
  const t = await correr({ perfil: { ...PERFIL, plan_vigente: { horario: '18:00:00' } }, modelo: ELOGIO });
  ok('a quien ya tiene plan no se le manda invitación', /Qué alegría/.test(t.enviados[0]) && !/mensualidad|tiquetera/i.test(t.enviados[0]));
}
{
  const t = await correr({ perfil: PERFIL, modelo: { respuesta: 'Lamento que no haya sido lo que esperabas, Laura.', cerrar: true, tipo: 'queja', resumen: 'Queja' } });
  ok('una queja NO recibe invitación', !/mensualidad|tiquetera|cupos/i.test(t.enviados[0]) && !t.llamadas.includes('ventas_perfil'));
}

console.log(fallos ? `\n${fallos} fallo(s)` : '\nTodo bien');
process.exit(fallos ? 1 : 0);
