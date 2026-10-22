/**
 * El rescate de las tiqueteras que quedan sin validar (0176, 13 oct).
 *
 * Damián: «revisando las tiqueteras por validar encontré personas que dijeron que pagaron y la plata no entró; nadie lo había
 * notado. Que a esas personas les llegue un mensaje a los 15 minutos preguntando si pudieron pagar o necesitan ayuda. A la
 * clase suelta no le hagamos nada: esa ya manda el comprobante por WhatsApp o lo muestra en la puerta».
 *
 * La lógica de la base (quién entra, quién no, que no se repita, que se cancele si se activa) se probó en la base real con
 * compras falsas dentro de una transacción que se deshizo. Aquí se protege lo que queda escrito en los archivos:
 *   · la migración y su alcance (solo tiqueteras; nada de clase suelta);
 *   · la plantilla (utilidad, sin oferta, sin la palabra «código» junto a una variable, que Meta rechaza);
 *   · el Worker: se enciende SOLO cuando Meta aprobó la plantilla, y respeta un «apagado» puesto a mano;
 *   · el cron del Worker lo revisa cada 10 minutos.
 *
 *   node tiquetera-rescate.test.mjs
 */
import { readFileSync } from 'node:fs';
import worker from '../../tumbao-caja/src/index.js';

let fallos = 0;
const ok = (n, c, extra = '') => { if (!c) fallos++; console.log(`${c ? '✓' : '✗'} ${n}${extra ? '  → ' + extra : ''}`); };
const titulo = t => console.log(`\n-- ${t} ${'-'.repeat(Math.max(0, 54 - t.length))}`);

const w = readFileSync(new URL('../../tumbao-caja/src/index.js', import.meta.url), 'utf8');
const raw = readFileSync(new URL('../supabase/migrations/0176_rescate_de_tiqueteras_sin_validar.sql', import.meta.url), 'utf8');
const m = raw.replace(/--.*$/gm, '');

titulo('1. La migración: alcance y reglas');
{
  ok('corre cada 2 minutos de 6 am a 10 pm (hora de Bogotá), como el recordatorio de las reservas',
     /cron\.schedule\('tumbao-recordar-tiquetera', '\*\/2 11-23,0-2 \* \* \*', 'select public\.tiquetera_recordar_pago\(\)'\)/.test(m));
  ok('mira solo tiqueteras pendientes de pago o de validación, compradas en línea (no las de recepción ni los premios)',
     /t\.estado in \('pendiente_pago', 'pendiente_validacion'\)/.test(m) && /t\.creada_por is null and t\.premio_de is null/.test(m));
  ok('espera 15 minutos desde que dijo «ya pagué» (o desde que empezó la compra) y no mira compras de hace más de 14 horas',
     /coalesce\(t\.pagado_en, t\.creada_en\) <= now\(\) - interval '15 minutes'/.test(m) && /coalesce\(t\.pagado_en, t\.creada_en\) >= now\(\) - interval '14 hours'/.test(m));
  ok('no le escribe a quien volvió a intentarlo y la otra compra SÍ quedó confirmada (el caso de Dayana)',
     /o\.estado = 'confirmada'/.test(m) && /o\.creada_en > t\.creada_en - interval '6 hours'/.test(m));
  ok('no escribe a quien pidió SALIR, a las dueñas ni a un celular que no sea válido; uno por persona cada 24 horas',
     /not wa_es_dueno\(r\.tel\)/.test(m) && /wa_bajas/.test(m) && /r\.tel ~ '\^3\[0-9\]\{9\}\$'/.test(m) && /a\.creado_at > now\(\) - interval '24 hours'/.test(m));
  ok('una sola vez por tiquetera (clave única) y es un aviso transaccional, no una campaña (no se retiene fuera del horario de mercadeo)',
     /'recordatorio_tiquetera:' \|\| r\.id, 'recordatorio_tiquetera'/.test(m) && /on conflict \(clave\) do nothing/.test(m) && !/'campana'/.test(m));
  ok('vence a las 2 horas: si no alcanzó a salir, no sale tarde', /now\(\) \+ interval '2 hours'/.test(m));
  ok('la nota a Damián sale solo si la persona dijo que pagó, con la clave de la tiquetera (una vez), y no depende de Meta',
     /if r\.reporto then/.test(m) && /nota_asistente\(/.test(m) && /'tiq-sin-validar:' \|\| r\.id/.test(m));
  ok('la nota dice cómo activarla y que el aviso de «tiquetera activa» le llega solo a la persona', /panel → Tiqueteras → su nombre → Activar/.test(m) && /le llega solo su aviso de tiquetera activa/.test(m));
  ok('la CLASE SUELTA no se toca: la migración no menciona reservas de clase suelta ni sus funciones de pago',
     !/reserva_recordar_pago|from reservas|update reservas|pago_chats|marcar_pendiente_validacion/.test(m));
  ok('nace en «esperando_plantilla» (no manda nada hasta que Meta apruebe) y solo el Worker lo enciende',
     /\('wa_recordar_tiquetera', 'esperando_plantilla'/.test(m) && /where clave = 'wa_recordar_tiquetera' and valor = 'esperando_plantilla'/.test(m)
     && /grant execute on function public\.wa_recordar_tiquetera_activar\(boolean\) to service_role/.test(m) && /grant execute on function public\.tiquetera_recordar_pago\(boolean\) to service_role/.test(m));
  ok('si se activa antes de que salga el aviso, el aviso se cancela solo (y un fallo ahí no tumba la activación)',
     /after update of estado on public\.tiqueteras/.test(m) && /new\.estado = 'confirmada' and old\.estado is distinct from 'confirmada'/.test(m)
     && /motivo = 'ya_activa'/.test(m) && /exception when others then[\s\S]{0,80}return new/.test(m));
}

titulo('2. Que el sistema no confunda «dijo que pagó» con «tiene tiquetera»');
{
  ok('ventas_perfil: tiquetera vigente = la CONFIRMADA (antes bastaba con tocar «ya pagué», y las del banco no contaban)',
     /tq\.pagado_en is not null and tq\.vence_el >= hoy/.test(m) && /tq\.estado = 'confirmada' and tq\.vence_el >= hoy/.test(m));
  ok('ventas_perfil suma la tiquetera pendiente (clases, valor y si dijo que pagó)', /''tiquetera_pendiente'', v_tp/.test(m) && /''reporto_pago''/.test(m));
  ok('la campaña de constancia no le ofrece otra tiquetera a quien tiene una confirmada o una por validar',
     /t\.estado in \('confirmada', 'pendiente_validacion'\) or t\.pagado_en is not null/.test(m));
  ok('cada reemplazo falla si no encuentra la línea que cambia (no deja una función a medias) y no hace nada si ya está',
     (m.match(/raise exception '0176:/g) || []).length === 2 && (m.match(/raise notice '0176:/g) || []).length === 2);
}

titulo('3. La plantilla de WhatsApp');
{
  const i = w.indexOf("name: 'tiquetera_pago_ayuda'");
  const t = w.slice(i, w.indexOf("name: 'reserva_confirmada'", i));
  const cuerpo = (() => { const mm = /type: 'BODY',\s*text:\s*([\s\S]*?),\s*example:/.exec(t); return mm ? eval(mm[1]) : ''; })();
  ok('existe, en español y de UTILIDAD (≈ $3, no $46)', i > 0 && /category: 'UTILITY'/.test(t) && /language: 'es'/.test(t));
  ok('pregunta si pudo pagar, ofrece ayuda y dice que le avisan cuando se valide', /¿Pudiste hacer el pago\?/.test(cuerpo) && /respóndeme por aquí y te ayudo a terminar/.test(cuerpo)
     && /en cuanto lo validemos te avisamos por este chat/.test(cuerpo), cuerpo);
  ok('sin oferta, descuento, precio ni urgencia (es sobre SU compra)', !/descuento|promo|gratis|oferta|\$|últim|solo hoy|ahorra/i.test(cuerpo));
  ok('lenguaje neutro: sirve igual para un hombre', !/\b(tranquil|list|segur|content|motivad|cansad)[oa]\b|@/i.test(cuerpo));
  ok('dos variables (nombre y «tu tiquetera de N clases») con ejemplo para Meta; sin «código» (Meta lo rechaza junto a una variable)',
     /\{\{1\}\}/.test(cuerpo) && /\{\{2\}\}/.test(cuerpo) && !/\{\{3\}\}/.test(cuerpo) && !/código/i.test(cuerpo) && /body_text: \[\['Laura', 'tu tiquetera de 8 clases'\]\]/.test(t));
  ok('cabe de sobra (1024 caracteres) y la migración la encola con esas dos variables',
     cuerpo.length < 600 && /jsonb_build_array\(coalesce\(nullif\(r\.primer, ''\), 'amigo\(a\)'\),\s*'tu tiquetera de ' \|\| r\.clases_totales \|\| ' clases'\)/.test(m) && /'tiquetera_pago_ayuda'/.test(m));
}

titulo('4. El Worker: se enciende solo cuando Meta la aprueba');
async function llamar({ ajuste = 'esperando_plantilla', metaEstado = 'APPROVED', metaFalla = false, categoria = 'UTILITY' } = {}) {
  const rpcs = [];
  const original = globalThis.fetch;
  globalThis.fetch = async (url, opc = {}) => {
    url = String(url);
    const res = (o, st = 200) => new Response(JSON.stringify(o), { status: st, headers: { 'content-type': 'application/json' } });
    if (url.includes('/message_templates')) {
      if (metaFalla) return res({ error: { message: 'x' } }, 400);
      return res({ data: metaEstado ? [{ name: 'tiquetera_pago_ayuda', status: metaEstado, category: categoria, language: 'es' }] : [] });
    }
    if (url.startsWith('https://sb.test/rest/v1/rpc/')) {
      const fn = url.split('/rpc/')[1]; const b = opc.body ? JSON.parse(opc.body) : {};
      rpcs.push({ fn, b });
      if (fn === 'wa_recordar_tiquetera_activar') return res({ estado: b.p_aprobada && ajuste === 'esperando_plantilla' ? 'encendido' : ajuste });
      return res({});
    }
    return res({}, 404);
  };
  try {
    const r = await worker.fetch(new Request('https://w.test/wa/recordar-tiquetera', { method: 'GET' }),
      { SUPABASE_URL: 'https://sb.test', SUPABASE_SERVICE_KEY: 'k', WHATSAPP_TOKEN: 't', WHATSAPP_PHONE_ID: '111', WHATSAPP_WABA_ID: '222' }, { waitUntil() {} });
    return { d: await r.json(), rpcs, activo: rpcs.some(x => x.fn === 'wa_recordar_tiquetera_activar' && x.b.p_aprobada === true) };
  } finally { globalThis.fetch = original; }
}
{
  const a = await llamar({ metaEstado: 'APPROVED' });
  ok('APROBADA y esperando: la enciende', a.activo && a.d.estado === 'encendido' && a.d.categoria === 'UTILITY', JSON.stringify(a.d));
  const p = await llamar({ metaEstado: 'PENDING' });
  ok('pendiente en Meta: no la enciende', !p.activo && p.d.plantilla === 'PENDING');
  const r = await llamar({ metaEstado: 'REJECTED' });
  ok('rechazada: no la enciende', !r.activo && r.d.plantilla === 'REJECTED');
  const n = await llamar({ metaEstado: null });
  ok('no existe en Meta: no la enciende', !n.activo && n.d.plantilla === 'NO_EXISTE');
  const f = await llamar({ metaFalla: true });
  ok('si Meta no responde: no adivina que está aprobada', !f.activo && f.d.ok === false);
  const off = await llamar({ ajuste: 'apagado', metaEstado: 'APPROVED' });
  ok('«apagado» puesto a mano por Damián se respeta (ni siquiera le pregunta a Meta)', !off.activo && off.d.estado === 'apagado');
  const on = await llamar({ ajuste: 'encendido', metaEstado: 'APPROVED' });
  ok('ya encendido: no hace nada más', !on.activo && on.d.estado === 'encendido');
}
{
  ok('el cron del Worker (cada 10 minutos) lo revisa, con su propio catch para que un fallo no frene la liberación de cupos',
     /activarRecordatorioTiquetera\(env\)\.catch\(/.test(w) && /await frenoAutomatico\(env\)\.catch[\s\S]{0,200}activarRecordatorioTiquetera\(env\)[\s\S]{0,300}liberar_cupos_expirados/.test(w));
  ok('el asistente y el bot de ventas reciben la tiquetera pendiente', /tiquetera_pendiente: perfil\.tiquetera_pendiente \|\| null/.test(w));
}

console.log(fallos ? `\n${fallos} fallo(s)` : '\nTodo bien');
process.exit(fallos ? 1 : 0);
