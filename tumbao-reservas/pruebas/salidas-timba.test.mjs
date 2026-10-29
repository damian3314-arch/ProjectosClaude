/**
 * Timba le pregunta a Tania a qué corresponden las salidas del banco sin clasificar (0190, 29 oct).
 *
 * Protege: que el modelo solo interprete (nunca el valor ni el día), que la base rechace lo inválido, que nazca APAGADO y que la
 * conversación termine siempre en algo claro. La conversación se prueba de punta a punta con la base y el modelo simulados.
 *
 *   node salidas-timba.test.mjs
 */
import { readFileSync } from 'node:fs';
import worker from '../../tumbao-caja/src/index.js';
import { CATEGORIAS_SALIDA, INSTRUCCIONES_SALIDAS, esLuego, interpretarSalida, textoPreguntaSalida, textoSalidaRegistrada, aclaracionesSeguidas } from '../../tumbao-caja/src/salidas.js';

let fallos = 0;
const ok = (n, c, extra = '') => { if (!c) fallos++; console.log(`${c ? '✓' : '✗'} ${n}${extra ? '  → ' + extra : ''}`); };
const titulo = t => console.log(`\n-- ${t} ${'-'.repeat(Math.max(0, 54 - t.length))}`);

titulo('1. Lo que se acepta del modelo');
{
  ok('clasificar con categoría válida y concepto', JSON.stringify(interpretarSalida({ accion: 'clasificar', categoria: 'profesores', concepto: 'Clase profe Nagle', a_quien: 'Nagle' }))
     === JSON.stringify({ accion: 'clasificar', categoria: 'profesores', concepto: 'Clase profe Nagle', a_quien: 'Nagle' }));
  ok('una categoría inventada no pasa: se le aclara', interpretarSalida({ accion: 'clasificar', categoria: 'comida', concepto: 'Almuerzo' }).accion === 'aclarar');
  ok('sin concepto no pasa', interpretarSalida({ accion: 'clasificar', categoria: 'otros', concepto: '  ' }).accion === 'aclarar');
  ok('un concepto con un monto escrito no pasa (el valor sale del banco)', interpretarSalida({ accion: 'clasificar', categoria: 'otros', concepto: 'Pago de $60.000 a Luis' }).accion === 'aclarar');
  ok('descartar pide su motivo', interpretarSalida({ accion: 'descartar', mensaje: 'Es un traslado entre cuentas' }).motivo === 'Es un traslado entre cuentas'
     && interpretarSalida({ accion: 'descartar' }).accion === 'aclarar');
  ok('«luego» se respeta', interpretarSalida({ accion: 'luego' }).accion === 'luego');
  ok('basura o JSON roto: se aclara, no se registra nada', interpretarSalida(null).accion === 'aclarar' && interpretarSalida('x').accion === 'aclarar' && interpretarSalida({ accion: 'borrar_todo' }).accion === 'aclarar');
  ok('las categorías son exactamente las que acepta la base', Object.keys(CATEGORIAS_SALIDA).join() === 'nomina,profesores,arriendo,sistema,mercadeo,talleres,viaticos,mantenimiento,impuestos,otros');
  ok('«luego» y parecidos se reconocen sin gastar una llamada al modelo', ['luego', 'Después', 'no sé', 'No recuerdo', 'siguiente', 'más tarde'].every(esLuego) && !esLuego('la clase de Nagle'));
}

titulo('2. Qué se le dice a Tania');
{
  const sig = { id: 'x', valor_cop: 60000, cuando: '20/10 14:03', cuenta_destino: '91289724619', sugerencia: { concepto: 'Clase profe Nagle' }, quizas_repetida: null };
  const p = textoPreguntaSalida(sig, 4);
  ok('la pregunta dice el valor, el día y la cuenta, y cómo salir', /\$60\.000/.test(p) && /20\/10/.test(p) && /91289724619/.test(p) && /luego/.test(p), p);
  ok('trae lo que se anotó la última vez, para que conteste «igual»', /Clase profe Nagle/.test(p));
  ok('dice cuántas quedan', /Quedan 4/.test(p));
  const r = textoSalidaRegistrada({ valor_cop: 60000, cuando: '20/10 14:03' }, { concepto: 'Clase profe Nagle', categoria: 'profesores', a_quien: 'Nagle' }, 0);
  ok('la confirmación repite lo registrado y felicita si ya no quedan', /\$60\.000/.test(r) && /Clase profe Nagle/.test(r) && /Profesores/.test(r) && /Ya no quedan/.test(r), r);
  ok('las instrucciones prohíben inventar y escribir montos', /NUNCA inventes/.test(INSTRUCCIONES_SALIDAS) && /NUNCA escribas montos/.test(INSTRUCCIONES_SALIDAS));
  ok('cuenta las aclaraciones seguidas desde la última pregunta', aclaracionesSeguidas([
    { direccion: 'saliente', texto: '💸 $60.000 el 20/10' }, { direccion: 'entrante', texto: 'algo' }, { direccion: 'saliente', texto: '¿Cuál?' }, { direccion: 'saliente', texto: '¿Y a quién?' }]) === 2);
}

titulo('3. La migración: nace apagada y la base se defiende');
{
  const m = readFileSync(new URL('../supabase/migrations/0190_panel_meta_planes_limpieza_y_salidas_con_timba.sql', import.meta.url), 'utf8').replace(/--.*$/gm, '');
  ok('salidas_timba nace «apagado»', /\('salidas_timba', 'apagado'/.test(m));
  ok('el cron del día no hace nada mientras esté apagado', /salidas_timba'\), 'apagado'\) <> 'encendido' then[\s\S]{0,120}'activo', false/.test(m));
  ok('solo se pregunta por salidas con 16 horas sin clasificar y máximo 3 veces', /interval '16 hours'/.test(m) && /s\.preguntas < 3/.test(m));
  ok('la pregunta solo existe para el número de Tania y se vence a los 3 días', /<> v_tania then return null/.test(m) && /interval '3 days' then return null/.test(m));
  ok('la base exige una categoría de su lista', /p_categoria not in \('nomina','profesores','arriendo','sistema','mercadeo','talleres',\s*'viaticos','mantenimiento','impuestos','otros'\)/.test(m));
  ok('el valor y el día salen de la salida del banco, no de lo que llegue', /v_s\.valor_cop/.test(m) && /v_s\.ocurrio_at at time zone 'America\/Bogota'\)::date/.test(m));
  ok('lo que clasifica Timba queda marcado como tal', /Clasificada por Timba con lo que respondió Tania/.test(m) && /'Timba · respuesta de Tania'/.test(m));
  ok('ninguna función de Timba la puede llamar el público', ['salida_siguiente_por_preguntar()', 'salida_abrir_pregunta(uuid)', 'salida_pregunta_actual(text)', 'salida_clasificar_timba(uuid, text, text, text)',
     'salida_descartar_timba(uuid, text)', 'salidas_preguntar_a_tania()', 'nota_a(text, text, text, text)', 'pendientes_viejos_limpiar()']
     .every(f => m.includes(`revoke all on function public.${f} from public, anon, authenticated`)));
  ok('no es domingo ni se le abre otra conversación si ya hay una abierta de 20 horas', /isodow from v_hoy\) = 7/.test(m) && /interval '20 hours'/.test(m));
  ok('la limpieza cierra solo tiqueteras que NUNCA reportaron pago, de 3 días, compradas en línea', /estado = 'pendiente_pago'/.test(m) && /pagado_en is null and pago_id is null/.test(m)
     && /creada_por is null and premio_de is null/.test(m) && /creada_en < now\(\) - interval '3 days'/.test(m));
  ok('la meta la cambia solo el propietario y el cajero no la ve', /v_admin\.rol <> 'propietario'/.test(m) && /v_admin\.rol = 'cajero' then/.test(m));
}

titulo('4. La conversación de punta a punta (base y modelo simulados)');
const ENV = { SUPABASE_URL: 'https://sb.test', SUPABASE_SERVICE_KEY: 'k', WHATSAPP_TOKEN: 't', WHATSAPP_PHONE_ID: '111', WHATSAPP_WABA_ID: '222', OPENAI_API_KEY: 'o' };
async function conversacion({ texto, modelo, abierta = true, siguiente = null, historial = [], clasifica = { ok: true, quedan: 3 } }) {
  const rpcs = []; const enviados = [];
  const original = globalThis.fetch;
  globalThis.fetch = async (url, opc = {}) => {
    url = String(url);
    const res = (o, st = 200) => new Response(JSON.stringify(o), { status: st, headers: { 'content-type': 'application/json' } });
    if (url.startsWith('https://sb.test/rest/v1/rpc/')) {
      const fn = url.split('/rpc/')[1]; const b = opc.body ? JSON.parse(opc.body) : {};
      rpcs.push({ fn, b });
      if (fn === 'wa_tomar_mensaje') return res({ id: 7, telefono: '573006121806', tipo: 'text', texto, wa_msg_id: 'w1', historial });
      if (fn === 'salida_pregunta_actual') return res(abierta ? { id: 'S1', valor_cop: 60000, cuando: '20/10 14:03', cuenta_destino: '91289724619', sugerencia: { concepto: 'Clase profe Nagle' } } : null);
      if (fn === 'salida_clasificar_timba') return res(clasifica);
      if (fn === 'salida_descartar_timba') return res({ ok: true, quedan: 2 });
      if (fn === 'salida_siguiente_por_preguntar') return res(siguiente);
      return res({});
    }
    if (url.includes('api.openai.com/v1/responses')) return res({ output: [{ type: 'message', content: [{ type: 'output_text', text: JSON.stringify(modelo) }] }], output_text: JSON.stringify(modelo) });
    if (url.includes('/messages')) { enviados.push(JSON.parse(opc.body)); return res({ messages: [{ id: 'wamid.X' }] }); }
    return res({}, 404);
  };
  try {
    const r = await worker.fetch(new Request('https://w.test/wa/agente', { method: 'POST', body: JSON.stringify({ id: 7 }) }), ENV, { waitUntil() {} });
    return { rpcs, enviados, d: await r.json() };
  } finally { globalThis.fetch = original; }
}
const textoEnviado = (t) => t.enviados.map(e => e.text && e.text.body).filter(Boolean).join('\n---\n');
{
  const t = await conversacion({ texto: 'es la clase de Nagle', modelo: { accion: 'clasificar', categoria: 'profesores', concepto: 'Clase profe Nagle', a_quien: 'Nagle' },
    siguiente: { id: 'S2', valor_cop: 55500, cuando: '29/10 08:10', cuenta_destino: null } });
  const c = t.rpcs.find(r => r.fn === 'salida_clasificar_timba');
  ok('clasifica con la categoría y el concepto interpretados, sobre la salida correcta', c && c.b.p_id === 'S1' && c.b.p_categoria === 'profesores' && c.b.p_concepto === 'Clase profe Nagle' && c.b.p_a_quien === 'Nagle');
  ok('NO manda ningún valor ni día a la base: salen del banco', c && !('p_valor_cop' in c.b) && !('p_dia' in c.b));
  const tx = textoEnviado(t);
  ok('responde confirmando lo registrado y pregunta la siguiente en el mismo mensaje', /Anotado/.test(tx) && /Clase profe Nagle/.test(tx) && /55\.500/.test(tx), tx);
  ok('deja abierta la pregunta de la siguiente', t.rpcs.some(r => r.fn === 'salida_abrir_pregunta' && r.b.p_id === 'S2'));
  ok('cierra el mensaje del agente como respondido', t.rpcs.some(r => r.fn === 'wa_cerrar_mensaje' && r.b.p_estado === 'respondido'));
}
{
  const t = await conversacion({ texto: 'la de siempre', modelo: { accion: 'clasificar', categoria: 'profesores', concepto: 'Clase profe Nagle' }, siguiente: null, clasifica: { ok: true, quedan: 0 } });
  ok('si no quedan más, lo dice', /Ya no quedan salidas/.test(textoEnviado(t)), textoEnviado(t));
}
{
  const t = await conversacion({ texto: 'eso fue un traslado a mi cuenta', modelo: { accion: 'descartar', mensaje: 'Traslado entre cuentas' }, siguiente: null });
  const d = t.rpcs.find(r => r.fn === 'salida_descartar_timba');
  ok('descartar lleva su motivo', d && d.b.p_nota === 'Traslado entre cuentas' && !t.rpcs.some(r => r.fn === 'salida_clasificar_timba'));
}
{
  const t = await conversacion({ texto: 'luego', modelo: { accion: 'clasificar', categoria: 'otros', concepto: 'no debería llamarse' } });
  ok('«luego» la salta sin llamar al modelo ni clasificar', t.rpcs.some(r => r.fn === 'salida_saltar_timba') && !t.rpcs.some(r => r.fn === 'salida_clasificar_timba') && /Sin problema/.test(textoEnviado(t)));
}
{
  const t = await conversacion({ texto: 'pagué algo', modelo: { accion: 'aclarar', mensaje: '¿A quién le pagaste?' } });
  ok('si no alcanza, pregunta UNA cosa y no registra nada', /¿A quién le pagaste\?/.test(textoEnviado(t)) && !t.rpcs.some(r => r.fn === 'salida_clasificar_timba'));
}
{
  const t = await conversacion({ texto: 'una categoría rara', modelo: { accion: 'clasificar', categoria: 'comida', concepto: 'Almuerzo' } });
  ok('una categoría inventada por el modelo no llega a la base', !t.rpcs.some(r => r.fn === 'salida_clasificar_timba'));
}
{
  const t = await conversacion({ texto: 'hola', abierta: false, modelo: { accion: 'clasificar', categoria: 'otros', concepto: 'x' } });
  ok('sin pregunta abierta (o con Timba apagado) el mensaje sigue su camino normal y NO se registra nada', !t.rpcs.some(r => r.fn === 'salida_clasificar_timba' || r.fn === 'salida_descartar_timba'));
}
{
  const t = await conversacion({ texto: 'es de Nagle', modelo: { accion: 'clasificar', categoria: 'profesores', concepto: 'Clase profe Nagle' }, clasifica: { ok: false, error: 'CATEGORIA_INVALIDA' } });
  ok('si la base rechaza, Tania lo sabe y la salida queda pendiente para recepción', /No pude registrarla/.test(textoEnviado(t)));
}
{
  const hist = [{ direccion: 'saliente', texto: '💸 $60.000' }, { direccion: 'entrante', texto: 'a' }, { direccion: 'saliente', texto: '¿cuál?' }, { direccion: 'saliente', texto: '¿y?' }, { direccion: 'saliente', texto: '¿entonces?' }];
  const t = await conversacion({ texto: 'mmm', historial: hist, modelo: { accion: 'aclarar', mensaje: '¿otra?' } });
  ok('tres aclaraciones seguidas: la deja para recepción en vez de dar vueltas', t.rpcs.some(r => r.fn === 'salida_saltar_timba') && /recepción/.test(textoEnviado(t)));
}

console.log(`\n${fallos ? '✗ ' + fallos + ' con problemas' : '✓ todo bien'}`);
process.exit(fallos ? 1 : 0);
