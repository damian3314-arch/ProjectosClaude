/**
 * Tumbao · caja de mostrador
 *
 * Una puerta estrecha entre el panel y Supabase. El panel manda el token
 * de admin —el mismo de siempre— y este Worker lo pasa a la función de
 * Postgres, que es la que de verdad decide si vale.
 *
 * POR QUÉ UN WORKER Y NO n8n
 * Cada venta sería una ejecución. Con 20–30 operaciones diarias son
 * 600–900 al mes sobre un plan de 2.500. Aquí caben 100.000 al día.
 *
 * POR QUÉ UN WORKER Y NO SUPABASE DIRECTO
 * Se podría abrir estas funciones a `anon` y que el panel hable con
 * Supabase de frente, como se va a hacer con los horarios. Para el
 * módulo que maneja plata no: así la única superficie pública son estos
 * cuatro endpoints, y no toda la API de Supabase dependiendo de que la
 * RLS de cada tabla esté perfecta.
 *
 * LA DECISIÓN DE AUTORIZAR NO VIVE AQUÍ
 * Vive en verificar_token_admin() dentro de Postgres. Este archivo no
 * sabe qué es un token válido, y así debe seguir.
 */

// De dónde se acepta que llamen. Un endpoint de plata no lleva '*'.
const PERMITIDOS = new Set([
  'https://tumbaobaila.com',
  'https://www.tumbaobaila.com',
  'https://tumbao.pages.dev',
]);

function cors(origen) {
  const h = {
    'Access-Control-Allow-Headers': 'Content-Type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    Vary: 'Origin',
  };
  if (origen && PERMITIDOS.has(origen)) h['Access-Control-Allow-Origin'] = origen;
  return h;
}

const json = (o, status, origen) =>
  new Response(JSON.stringify(o), {
    status,
    headers: {
      'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': 'no-store',
      ...cors(origen),
    },
  });

/** Llama a una función de Postgres por PostgREST. */
async function rpc(env, funcion, cuerpo) {
  const r = await fetch(`${env.SUPABASE_URL}/rest/v1/rpc/${funcion}`, {
    method: 'POST',
    headers: {
      apikey: env.SUPABASE_SERVICE_KEY,
      Authorization: `Bearer ${env.SUPABASE_SERVICE_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(cuerpo),
  });
  const texto = await r.text();
  if (!r.ok) throw new Error(`supabase ${r.status}: ${texto.slice(0, 200)}`);
  try { return JSON.parse(texto); } catch (_) { return {}; }
}

// Solo estos conceptos, y con el sentido que les corresponde. Si un día
// hay que agregar uno, se agrega aquí a propósito: es lo que impide que
// un error de tecleo invente una categoría nueva y ensucie el cierre.
const CONCEPTOS = {
  ingreso: new Set(['clase_suelta', 'mensualidad', 'cumpleanos', 'otro_ingreso']),
  egreso:  new Set(['profesores', 'cafeteria', 'aseo', 'papeleria', 'otro_egreso']),
};

export default {
  async fetch(request, env) {
    const origen = request.headers.get('Origin');
    const ruta = new URL(request.url).pathname;

    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: cors(origen) });
    }
    if (request.method !== 'POST') {
      return json({ ok: false, error: 'METODO' }, 405, origen);
    }
    if (!env.SUPABASE_SERVICE_KEY) {
      return json({
        ok: false, error: 'SIN_LLAVE',
        mensaje: 'Falta el secreto SUPABASE_SERVICE_KEY en el Worker.',
      }, 503, origen);
    }

    let b = {};
    try { b = await request.json(); } catch (_) {}
    const token = String(b.token || '');
    if (!token) return json({ ok: false, error: 'NO_AUTORIZADO' }, 401, origen);

    try {
      let r;

      if (ruta === '/api/dia') {
        r = await rpc(env, 'caja_del_dia', {
          p_token: token,
          p_dia: /^\d{4}-\d{2}-\d{2}$/.test(b.dia || '') ? b.dia : null,
        });

      } else if (ruta === '/api/registrar') {
        const sentido = b.sentido === 'egreso' ? 'egreso' : 'ingreso';
        const concepto = String(b.concepto || '');
        if (!CONCEPTOS[sentido].has(concepto)) {
          return json({ ok: false, error: 'CONCEPTO_INVALIDO',
            mensaje: 'Ese concepto no existe para un ' + sentido + '.' }, 400, origen);
        }
        // El valor se limpia aquí de puntos y comas —la cajera teclea
        // "15.000"— pero el rango lo sigue validando Postgres.
        const valor = parseInt(String(b.valor ?? '').replace(/[^\d]/g, ''), 10);
        if (!Number.isFinite(valor) || valor <= 0) {
          return json({ ok: false, error: 'VALOR_INVALIDO',
            mensaje: 'Escribe un valor mayor que cero.' }, 400, origen);
        }
        r = await rpc(env, 'caja_registrar', {
          p_token: token, p_sentido: sentido, p_concepto: concepto,
          p_valor: valor,
          p_medio: b.medio === 'transferencia' ? 'transferencia' : 'efectivo',
          p_nota: b.nota ? String(b.nota).slice(0, 200) : null,
        });

      } else if (ruta === '/api/anular') {
        const id = String(b.id || '');
        if (!/^[0-9a-f-]{36}$/i.test(id)) {
          return json({ ok: false, error: 'ID_INVALIDO' }, 400, origen);
        }
        r = await rpc(env, 'caja_anular', { p_token: token, p_id: id });

      } else if (ruta === '/api/cerrar') {
        const contado = parseInt(String(b.contado ?? '').replace(/[^\d]/g, ''), 10);
        if (!Number.isFinite(contado) || contado < 0) {
          return json({ ok: false, error: 'CONTADO_INVALIDO',
            mensaje: 'Escribe cuánto contaste en el cajón.' }, 400, origen);
        }
        const base = parseInt(String(b.base ?? '100000').replace(/[^\d]/g, ''), 10);
        r = await rpc(env, 'caja_cerrar', {
          p_token: token, p_contado: contado,
          p_base: Number.isFinite(base) ? base : 100000,
          p_nota: b.nota ? String(b.nota).slice(0, 300) : null,
        });

      } else {
        return json({ ok: false, error: 'NO_EXISTE' }, 404, origen);
      }

      // Postgres ya devuelve { ok: false, error } cuando el token no
      // sirve. Se traduce a 401 para que el panel mande al login solo.
      const status = r && r.ok === false
        ? (r.error === 'NO_AUTORIZADO' ? 401 : 400)
        : 200;
      return json(r, status, origen);

    } catch (e) {
      console.log('caja:', e && e.message);
      return json({ ok: false, error: 'FALLA',
        mensaje: 'No se pudo guardar. Vuelve a intentarlo.' }, 502, origen);
    }
  },
};
