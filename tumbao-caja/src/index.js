/**
 * Tumbao · el panel entero contra Supabase
 *
 * Una puerta estrecha entre el panel de admin y Postgres. El panel manda
 * el token —el mismo de siempre— y este Worker lo pasa a la función de
 * Postgres, que es la que de verdad decide si vale.
 *
 * POR QUÉ UN WORKER Y NO n8n
 * n8n cobra por ejecución y el panel gasta una POR CLIC. Medido el 11 de
 * agosto: 483 ejecuciones del workflow del panel en 24 horas, contra un
 * plan de 2.500 AL MES. Eso son cinco días de vida.
 *
 * Y cuando el plan se agota no cae solo el panel: la página pública
 * reserva por n8n también. O sea que un cajero repasando el tablero
 * podía dejar sin reservas a los clientes. Aquí caben 100.000 peticiones
 * diarias y no cuestan nada.
 *
 * El nombre del Worker sigue siendo "tumbao-caja" por lo primero que
 * hizo. Cambiarlo obligaría a mover la URL y a reconfigurar el secreto
 * un día en que lo urgente es dejar de gastar.
 *
 * POR QUÉ UN WORKER Y NO SUPABASE DIRECTO
 * Se podría abrir estas funciones a `anon` y que el panel hable con
 * Supabase de frente. No: así la única superficie pública son estas
 * rutas, y no toda la API de Supabase dependiendo de que la RLS de cada
 * tabla esté perfecta.
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

/* ---------------------------------------------------------------------
 * El panel de admin
 *
 * Una tabla en vez de una escalera de ifs: cada ruta dice a qué función
 * de Postgres va y cómo se arman sus argumentos. Añadir una es una línea,
 * y se ve de un vistazo que ninguna hace nada raro.
 *
 * Los validadores no repiten lo que ya valida Postgres —los permisos y
 * las reglas de negocio viven allá— sino que atajan la basura evidente
 * para no gastar un viaje: un uuid que no es uuid, una fecha que no es
 * fecha. Si algo se cuela, Postgres lo rechaza igual.
 * ------------------------------------------------------------------- */
const UUID  = (v) => (/^[0-9a-f-]{36}$/i.test(String(v || '')) ? String(v) : null);
const FECHA = (v) => (/^\d{4}-\d{2}-\d{2}$/.test(String(v || '')) ? String(v) : null);
const TXT   = (v, max) => (v == null ? null : String(v).slice(0, max));

const ADMIN = {
  tablero:    { fn: 'admin_tablero',
                args: (b) => ({ p_dia: FECHA(b.dia) }) },
  semana:     { fn: 'admin_semana',
                args: (b) => ({ p_desde: FECHA(b.desde) }) },
  guardar:    { fn: 'admin_guardar_semana',
                args: (b) => (Array.isArray(b.celdas)
                  ? { p_celdas: b.celdas }
                  : { _error: 'CELDAS_INVALIDAS' }) },
  pendientes: { fn: 'admin_pendientes',
                args: () => ({}) },
  lista:      { fn: 'admin_lista_clase',
                args: (b) => (UUID(b.clase_id)
                  ? { p_clase_id: UUID(b.clase_id) }
                  : { _error: 'CLASE_INVALIDA' }) },
  asistencia: { fn: 'admin_marcar_asistencia',
                args: (b) => (UUID(b.clase_id)
                  ? { p_clase_id: UUID(b.clase_id), p_ref: TXT(b.ref, 80),
                      p_asistio: b.asistio === true }
                  : { _error: 'CLASE_INVALIDA' }) },
  deshacer:   { fn: 'admin_deshacer',
                args: (b) => ({ p_codigo: TXT(b.codigo, 40) }) },
  // pago_id opcional: es el que enlaza la reserva con el depósito del
  // banco cuando se resuelve desde la cola con el botón "Es este".
  confirmar:  { fn: 'admin_confirmar',
                args: (b) => ({ p_codigo: TXT(b.codigo, 40),
                                p_pago_id: UUID(b.pago_id) }) },
  // El panel manda pago_id también aquí, pero rechazar no lo usa: no hay
  // nada que enlazar cuando se descarta.
  rechazar:   { fn: 'admin_rechazar',
                args: (b) => ({ p_codigo: TXT(b.codigo, 40) }) },
  // Pagó y no vino. No suelta el cupo ni toca la plata: abre un crédito
  // de tres días para usar esa clase otro día.
  no_vino:    { fn: 'admin_marcar_no_vino',
                args: (b) => (UUID(b.clase_id)
                  ? { p_clase_id: UUID(b.clase_id), p_ref: TXT(b.ref, 80),
                      p_no_vino: b.no_vino !== false }
                  : { _error: 'CLASE_INVALIDA' }) },
  disfrutar:  { fn: 'admin_por_disfrutar',
                args: () => ({}) },
  reprogramar:{ fn: 'admin_reprogramar',
                args: (b) => (UUID(b.clase_id)
                  ? { p_codigo: TXT(b.codigo, 40), p_clase_id: UUID(b.clase_id) }
                  : { _error: 'CLASE_INVALIDA' }) },
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

    /* ─────────────────────────────────────────────────────────────
     * Reservar varios cupos — la ÚNICA ruta pública de este Worker
     *
     * Va antes del token a propósito: la pide tumbaobaila.com desde el
     * navegador de un cliente, que no tiene ni puede tener uno. Es
     * exactamente lo mismo que ya hace el webhook de reservar en n8n;
     * lo que la protege es que tomar_cupos no acepta nada que no sea
     * una clase existente con cupo, y el aforo lo cierra Postgres.
     *
     * Se pone aquí y no en n8n para no tocar el webhook de reservar,
     * que es por donde entra el 95% de las reservas y funciona. Si esto
     * se rompiera, reservar de a uno seguiría intacto.
     * ───────────────────────────────────────────────────────────── */
    if (ruta === '/api/reservar-varios') {
      // La trampa para bots: un campo escondido que un humano nunca
      // llena. Se responde ok para no enseñarle al bot que lo pillaron.
      if (String(b.apellido2 || '').trim() !== '') {
        return json({ ok: true, codigo: 'OK' }, 200, origen);
      }
      const nombres = Array.isArray(b.nombres)
        ? b.nombres.map((n) => String(n || '').trim().slice(0, 80)).filter(Boolean)
        : [];
      if (!UUID(b.clase_id)) {
        return json({ ok: false, error: 'CLASE_INVALIDA',
          mensaje: 'No se reconoce la clase. Vuelve a elegir el horario.' }, 400, origen);
      }
      if (nombres.length < 1 || nombres.length > 8) {
        return json({ ok: false, error: 'CANTIDAD_INVALIDA',
          mensaje: 'Se pueden reservar entre 1 y 8 cupos a la vez.' }, 400, origen);
      }
      if (String(b.telefono || '').replace(/\D/g, '').length !== 10) {
        return json({ ok: false, error: 'CELULAR_INVALIDO',
          mensaje: 'El celular tiene que ser de 10 dígitos.' }, 400, origen);
      }
      try {
        const r = await rpc(env, 'tomar_cupos', {
          p_clase_id: UUID(b.clase_id),
          p_nombres:  nombres,
          p_telefono: String(b.telefono),
          p_email:    b.email ? String(b.email).slice(0, 120) : null,
          p_origen:   'web',
        });
        return json(r, r && r.ok === false ? 400 : 200, origen);
      } catch (e) {
        // Mientras la migración 0034 no esté pegada, la función no
        // existe y PostgREST devuelve 404. No es un fallo pasajero y
        // reintentar no arregla nada: hay que decirle a la persona que
        // aparte de a una, no dejarla dándole al botón.
        const detalle = String((e && e.message) || '');
        const noExiste = /supabase 404/.test(detalle) || /PGRST202/.test(detalle);
        return json({
          ok: false,
          error: noExiste ? 'SIN_VARIOS' : 'FALLA',
          mensaje: noExiste
            ? 'Todavía no podemos apartar varios cupos de una. Aparta el tuyo ' +
              'y escríbenos por WhatsApp para los demás.'
            : 'No pudimos apartar los cupos. Inténtalo otra vez.',
        }, noExiste ? 503 : 502, origen);
      }
    }

    const token = String(b.token || '');
    if (!token) return json({ ok: false, error: 'NO_AUTORIZADO' }, 401, origen);

    try {
      let r;

      // ── el panel de admin ──
      if (ruta.startsWith('/api/admin/')) {
        const cual = ADMIN[ruta.slice('/api/admin/'.length)];
        if (!cual) return json({ ok: false, error: 'NO_EXISTE' }, 404, origen);

        const args = cual.args(b);
        if (args._error) {
          return json({ ok: false, error: args._error,
            mensaje: 'Faltan datos o no se reconocen. Recarga la página.' }, 400, origen);
        }
        r = await rpc(env, cual.fn, { p_token: token, ...args });

      } else if (ruta === '/api/dia') {
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
        // El depósito del banco que respalda el cobro, si la cajera lo
        // escogió de la lista. Postgres valida que exista, que esté
        // libre y que el valor sea el mismo; aquí solo se comprueba la
        // forma para no mandar basura a la RPC.
        const pago = b.pago_id ? String(b.pago_id) : null;
        if (pago && !/^[0-9a-f-]{36}$/i.test(pago)) {
          return json({ ok: false, error: 'PAGO_INVALIDO',
            mensaje: 'No se reconoce ese depósito. Recarga la lista.' }, 400, origen);
        }
        const args = {
          p_token: token, p_sentido: sentido, p_concepto: concepto,
          p_valor: valor,
          p_medio: b.medio === 'transferencia' ? 'transferencia' : 'efectivo',
          p_nota: b.nota ? String(b.nota).slice(0, 200) : null,
        };
        // Solo se manda cuando de verdad hay depósito escogido. PostgREST
        // resuelve la función por los parámetros que recibe: mandar
        // p_pago_id siempre obligaría a que la migración 0027 ya
        // estuviera aplicada, y hasta entonces no se podría ni cobrar.
        if (pago) args.p_pago_id = pago;
        r = await rpc(env, 'caja_registrar', args);

      } else if (ruta === '/api/abrir') {
        const contado = parseInt(String(b.contado ?? '').replace(/[^\d]/g, ''), 10);
        if (!Number.isFinite(contado) || contado < 0) {
          return json({ ok: false, error: 'CONTADO_INVALIDO',
            mensaje: 'Escribe cuánto hay en el cajón.' }, 400, origen);
        }
        r = await rpc(env, 'caja_abrir', {
          p_token: token, p_contado: contado,
          p_nota: b.nota ? String(b.nota).slice(0, 300) : null,
        });

      } else if (ruta === '/api/reserva') {
        // Apuntar a alguien a mano. La validación de verdad —nombre,
        // celular, y sobre todo el aforo— vive en admin_crear_reserva,
        // que pasa por tomar_cupo. Aquí solo se comprueba que el id de
        // la clase tenga forma de uuid, para no mandar basura a la RPC.
        const clase = String(b.clase_id || '');
        if (!/^[0-9a-f-]{36}$/i.test(clase)) {
          return json({ ok: false, error: 'CLASE_INVALIDA',
            mensaje: 'No se reconoce la clase. Vuelve a abrirla y reintenta.' }, 400, origen);
        }
        r = await rpc(env, 'admin_crear_reserva', {
          p_token: token,
          p_clase_id: clase,
          p_nombre: String(b.nombre || '').slice(0, 80),
          p_telefono: String(b.telefono || '').slice(0, 20),
          p_tipo: b.tipo === 'miembro' ? 'miembro' : 'suelta',
          p_nota: b.nota ? String(b.nota).slice(0, 80) : null,
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
        const dejado = parseInt(String(b.dejado ?? '100000').replace(/[^\d]/g, ''), 10);
        const arg = {
          p_token: token, p_contado: contado,
          p_base: Number.isFinite(base) ? base : 100000,
          p_nota: b.nota ? String(b.nota).slice(0, 300) : null,
          p_dejado: Number.isFinite(dejado) ? dejado : 100000,
        };
        // Rehacer un cierre ya hecho se pide a propósito y con motivo.
        // Los dos parámetros se mandan SOLO cuando de verdad se está
        // rehaciendo: PostgREST resuelve la función por los parámetros
        // que recibe, así que mandarlos siempre exigiría tener ya
        // aplicada la migración 0031 — y hasta entonces no se podría ni
        // cerrar el día. Ese fallo se coló en el despliegue de esta
        // noche y dejó la caja sin cerrar durante unos minutos.
        if (b.rehacer === true) {
          arg.p_rehacer = true;
          arg.p_motivo = b.motivo ? String(b.motivo).slice(0, 300) : null;
        }
        r = await rpc(env, 'caja_cerrar', arg);

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

  /* -------------------------------------------------------------------
   * Lo que antes hacía un workflow de n8n cada hora
   *
   * Cuando alguien aparta un cupo, la reserva nace en `pendiente_pago`
   * con media hora de vida. Si completa el pago sigue su curso; si
   * abandona, se queda ahí PARA SIEMPRE si nadie la limpia — y ese cupo
   * no aparece en ninguna cola del panel, así que tampoco hay forma de
   * soltarlo a mano. `liberar_cupos_expirados()` existía desde el primer
   * día con un comentario que decía "la llama el cron". Ese cron nunca
   * se creó.
   *
   * POR QUÉ SE MUDÓ AQUÍ
   * Era una llamada a Postgres por hora y le costaba a n8n ~400
   * ejecuciones al mes, de un plan de 2.500 que ya estaba en la raya. Al
   * agotarse no se cae solo esto: se caen los webhooks de reservas y la
   * ingesta de pagos, o sea que nadie puede reservar y a quien pagó no
   * se le confirma. Aquí no cuesta nada.
   *
   * Es idempotente: si no hay ninguna vencida devuelve 0 y no toca nada.
   * Por eso puede convivir con el workflow viejo mientras se comprueba,
   * sin que se pisen.
   *
   * PERO HOY ESTO NO CORRE. Los cron de Cloudflare quedan registrados en
   * esta cuenta y no se ejecutan nunca — comprobado a las 15:00 y 16:00
   * UTC, y con un cron de prueba cada minuto durante siete minutos: cero
   * invocaciones, ni log ni error, confirmado también por la API de
   * analítica. Ver el comentario largo en `wrangler.jsonc`.
   *
   * El que de verdad libera los cupos sigue siendo el workflow de n8n.
   * Esto se queda escrito y probado para el día que los cron funcionen,
   * o como referencia si se mueve a pg_cron dentro de Supabase.
   * ----------------------------------------------------------------- */
  async scheduled(evento, env, ctx) {
    ctx.waitUntil((async () => {
      try {
        const r = await rpc(env, 'liberar_cupos_expirados', {});
        // PostgREST devuelve el entero pelado o envuelto según el caso.
        const n = typeof r === 'number' ? r
                : (typeof r?.liberar_cupos_expirados === 'number'
                    ? r.liberar_cupos_expirados : 0);
        console.log(`liberar_cupos_expirados: ${n} cupo(s) · ${evento.cron}`);
      } catch (e) {
        // Se deja el error en el log y se relanza: así el fallo queda
        // marcado como tal en Cloudflare y no pasa por una corrida sana.
        console.log('liberar_cupos_expirados FALLÓ:', e && e.message);
        throw e;
      }
    })());
  },
};
