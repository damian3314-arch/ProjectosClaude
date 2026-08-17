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
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    Vary: 'Origin',
  };
  if (origen && PERMITIDOS.has(origen)) h['Access-Control-Allow-Origin'] = origen;
  return h;
}

/* ---------------------------------------------------------------------
 * Fechas y horas en Bogotá
 *
 * Las escribe el servidor y no el navegador a propósito: si las armara
 * la página, alguien con el celular en otra zona horaria vería la clase
 * a una hora que no es. Es el mismo formato que devolvía n8n, letra por
 * letra, para que la página no note el cambio.
 * ------------------------------------------------------------------- */
const TZ = 'America/Bogota';
const fFecha = new Intl.DateTimeFormat('es-CO',
  { timeZone: TZ, weekday: 'long', day: 'numeric', month: 'long' });
const fHora = new Intl.DateTimeFormat('es-CO',
  { timeZone: TZ, hour: 'numeric', minute: '2-digit', hour12: true });
const fClave = new Intl.DateTimeFormat('en-CA',
  { timeZone: TZ, year: 'numeric', month: '2-digit', day: '2-digit' });

// "7:00 a. m." -> "7:00 am". El espacio que mete Intl es un NBSP, no un
// espacio normal, así que hay que nombrarlo por su código o no se ve.
const compacta = (s) => String(s)
  .replace(/[  ]/g, ' ')
  .replace(/\s*a\.\s*m\./i, ' am')
  .replace(/\s*p\.\s*m\./i, ' pm');

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

/* ---------------------------------------------------------------------
 * Las cuatro rutas de la página pública
 *
 *   GET  /tumbao/clases?tipo=            horarios con cupo
 *   POST /tumbao/reservar                aparta el cupo, devuelve el código
 *   POST /tumbao/comprobante             "ya pagué" -> verificando
 *   GET  /tumbao/estado?codigo=          la barra de espera
 *   GET  /tumbao/estado?codigo=&vencido=1   se acabó el tiempo
 *
 * La decisión de confirmar NO vive aquí: vive en las funciones de
 * Postgres, que bloquean fila. Aquí solo se enruta y se da formato.
 * ------------------------------------------------------------------- */
async function pagina(request, env, ruta, origen) {
  const url = new URL(request.url);
  const q = url.searchParams;
  const metodo = request.method;

  let b = {};
  if (metodo === 'POST') { try { b = await request.json(); } catch (_) {} }

  const txt = (v, max) => (v == null ? '' : String(v).trim().slice(0, max));

  try {
    // ── los horarios ──────────────────────────────────────────────
    if (ruta === '/tumbao/clases' && metodo === 'GET') {
      const filas = await rpc(env, 'clases_para', {
        p_tipo: q.get('tipo') === 'miembro' ? 'miembro' : 'suelta',
      });
      const lista = Array.isArray(filas) ? filas.filter((c) => c && c.id) : [];

      // Agrupadas por día, en el orden en que vienen: clases_para ya las
      // devuelve ordenadas por fecha.
      const dias = new Map();
      for (const c of lista) {
        const d = new Date(c.fecha_hora);
        const clave = fClave.format(d);
        if (!dias.has(clave)) {
          dias.set(clave, { fecha: clave, etiqueta: fFecha.format(d), clases: [] });
        }
        const libres = Math.max((c.cupo_total || 0) - (c.cupo_tomado || 0), 0);
        dias.get(clave).clases.push({
          clase_id: c.id, nombre: c.nombre, profesor: c.profesor, lugar: c.lugar,
          hora: compacta(fHora.format(d)), fecha_hora: c.fecha_hora,
          duracion_min: c.duracion_min, precio_cop: c.precio_cop,
          cupo_total: c.cupo_total, cupos_disponibles: libres, agotada: libres <= 0,
        });
      }
      return json({ ok: true, timezone: TZ, dias: [...dias.values()] }, 200, origen);
    }

    // ── apartar el cupo ───────────────────────────────────────────
    if (ruta === '/tumbao/reservar' && metodo === 'POST') {
      // La trampa para bots: un campo escondido que un humano nunca
      // llena. Se responde ok para no enseñarle al bot que lo pillaron.
      if (txt(b.apellido2, 40) !== '') {
        return json({ ok: true, codigo: 'OK' }, 200, origen);
      }

      let tel = txt(b.telefono, 25).replace(/\D/g, '');
      // Los que teclean el indicativo del país: 57 + 10 dígitos.
      if (tel.length === 12 && tel.startsWith('57')) tel = tel.slice(2);

      const nombre = txt(b.nombre, 80);
      const claseId = txt(b.clase_id, 40);
      const habeas = b.habeas === true || b.habeas === 'true';

      if (!(nombre.length >= 2 && tel.length === 10 && habeas && claseId.length > 10)) {
        return json({ ok: false, error: 'datos_incompletos',
          mensaje: 'Revisa nombre, celular y la autorizacion de datos.' }, 400, origen);
      }

      // SIN REINTENTO, a propósito. tomar_cupo no es idempotente:
      // repetirlo tras un timeout crearía una segunda reserva y se
      // comería dos cupos. Es preferible fallar y que la persona
      // vuelva a intentar.
      const r = await rpc(env, 'tomar_cupo', {
        p_clase_id: claseId,
        p_nombre:   nombre,
        p_telefono: tel,
        p_email:    txt(b.email, 120) || null,
        p_origen:   'formulario',
        p_tipo:     txt(b.tipo, 10) === 'miembro' ? 'miembro' : 'suelta',
      });

      if (!r || !r.ok) {
        const mapa = {
          SIN_CUPO: 409, CLASE_NO_EXISTE: 404, CLASE_INACTIVA: 410,
          CLASE_YA_PASO: 410, MEMBRESIA_NO_ENCONTRADA: 404,
          PLAN_YA_CUBRE: 409, OTRO_HORARIO: 409,
        };
        return json({
          ok: false,
          error: (r && r.error) || 'desconocido',
          hora_plan: (r && r.hora_plan) || null,
          mensaje: (r && r.mensaje) ||
            'No pudimos apartar el cupo. Escribenos por WhatsApp.',
        }, mapa[r && r.error] || 400, origen);
      }

      const d = new Date(r.fecha_hora);
      return json({
        ok: true,
        tipo: r.tipo, requiere_pago: r.requiere_pago === true, estado: r.estado,
        codigo: r.codigo, reserva_id: r.reserva_id, clase: r.clase,
        profesor: r.profesor, lugar: r.lugar,
        fecha: fFecha.format(d), hora: compacta(fHora.format(d)),
        precio_cop: r.precio_cop, expira_en: r.expira_en,
      }, 200, origen);
    }

    // ── "ya pagué" ────────────────────────────────────────────────
    if (ruta === '/tumbao/comprobante' && metodo === 'POST') {
      const opc = (v, n) => (txt(v, n) || null);
      const r = await rpc(env, 'registrar_aviso_pago', {
        p_codigo:     txt(b.codigo, 40).toUpperCase(),
        p_pagado_en:  b.pagado_en || null,
        p_referencia: opc(b.referencia, 40),
        p_pagador:    opc(b.pagador, 80),
        p_qr:         opc(b.qr, 500),
      });
      if (r && r.ok) {
        return json({ ok: true, estado: r.estado, codigo: r.codigo,
          mensaje: r.mensaje || null }, 200, origen);
      }
      return json({
        ok: false,
        error: (r && r.error) || 'no_encontrada',
        mensaje: (r && r.mensaje) ||
          'No encontramos esa reserva, o ya habia registrado el pago.',
      }, r && r.error === 'referencia_repetida' ? 409 : 404, origen);
    }

    // ── la barra de espera ────────────────────────────────────────
    if (ruta === '/tumbao/estado' && metodo === 'GET') {
      const codigo = txt(q.get('codigo'), 40);
      // Con `vencido=1` se acabaron los minutos y la reserva pasa a la
      // cola humana. Sin él, se intenta cruzar con lo que haya llegado
      // del banco. Son dos funciones distintas, no dos ramas de la
      // misma: cruzar no debe poder mandar nada a validación por su
      // cuenta.
      const r = q.get('vencido') === '1'
        ? await rpc(env, 'marcar_pendiente_validacion', { p_codigo: codigo })
        : await rpc(env, 'conciliar_reserva', { p_codigo: codigo });

      if (!r || !r.ok) {
        return json({ ok: false, error: (r && r.error) || 'no_encontrada' },
          404, origen);
      }

      // La página pinta su propio texto en los dos casos normales; esto
      // es el respaldo y lo que se ve si alguien consulta por fuera.
      const mensajes = {
        confirmada: 'Pago confirmado. Tu cupo esta asegurado.',
        verificando: 'Estamos esperando la confirmacion del banco.',
        pendiente_validacion: 'No pudimos confirmar tu pago automaticamente. ' +
          'Tu cupo sigue apartado: comparte el soporte por WhatsApp y lo ' +
          'validamos a mano.',
        pendiente_pago: 'Falta registrar el pago.',
        rechazada: 'No pudimos validar el pago. Escribenos por WhatsApp.',
        expirada: 'Se solto el cupo por falta de pago.',
      };
      return json({ ok: true, estado: r.estado, codigo: r.codigo,
        clase: r.clase, metodo: r.metodo || null,
        mensaje: mensajes[r.estado] || '' }, 200, origen);
    }

    return json({ ok: false, error: 'NO_EXISTE' }, 404, origen);

  } catch (e) {
    console.log('pagina:', ruta, e && e.message);
    return json({ ok: false, error: 'FALLA',
      mensaje: 'No pudimos conectarnos. Inténtalo otra vez.' }, 502, origen);
  }
}

export default {
  async fetch(request, env) {
    const origen = request.headers.get('Origin');
    const ruta = new URL(request.url).pathname;

    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: cors(origen) });
    }
    if (request.method !== 'POST' && request.method !== 'GET') {
      return json({ ok: false, error: 'METODO' }, 405, origen);
    }
    if (!env.SUPABASE_SERVICE_KEY) {
      return json({
        ok: false, error: 'SIN_LLAVE',
        mensaje: 'Falta el secreto SUPABASE_SERVICE_KEY en el Worker.',
      }, 503, origen);
    }

    /* ─────────────────────────────────────────────────────────────
     * La página pública — lo que antes eran cuatro webhooks de n8n
     *
     * Van ANTES del token, como reservar-varios: las pide el navegador
     * de un cliente, que no tiene ni puede tener uno. Lo que las
     * protege es que las funciones de Postgres no aceptan nada que no
     * sea una clase existente con cupo, y el aforo lo cierra la base
     * con bloqueo de fila.
     *
     * POR QUÉ SE MUDARON
     * n8n cobra por ejecución y estas cuatro se llevaban ~1.220 al mes
     * de un plan de 2.500. La más cara es `estado`: la barra de espera
     * pregunta cada pocos segundos, así que UNA reserva gastaba varias
     * ejecuciones. Aquí caben 100.000 peticiones al día y no cuestan.
     *
     * Los webhooks de n8n se dejan vivos mientras se comprueba. Volver
     * atrás es cambiar una línea en la página, sin tocar la base.
     *
     * La respuesta es la MISMA, campo por campo, para que la página no
     * tenga que enterarse de nada.
     * ───────────────────────────────────────────────────────────── */
    if (ruta.startsWith('/tumbao/')) {
      return await pagina(request, env, ruta, origen);
    }

    if (request.method !== 'POST') {
      return json({ ok: false, error: 'METODO' }, 405, origen);
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
