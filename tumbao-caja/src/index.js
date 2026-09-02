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

/** Lee filas de una tabla por PostgREST. Solo lectura. */
async function leer(env, tabla, consulta) {
  const r = await fetch(`${env.SUPABASE_URL}/rest/v1/${tabla}?${consulta}`, {
    headers: {
      apikey: env.SUPABASE_SERVICE_KEY,
      Authorization: `Bearer ${env.SUPABASE_SERVICE_KEY}`,
    },
  });
  const texto = await r.text();
  if (!r.ok) throw new Error(`supabase ${r.status}: ${texto.slice(0, 200)}`);
  try { return JSON.parse(texto); } catch (_) { return []; }
}

/* ---------------------------------------------------------------------
 * Supabase Auth — login, invitación y contraseña
 *
 * La llave de servicio ya vive en este Worker (rpc() y leer() la usan
 * hace rato) y GoTrue la acepta igual que la anon: sirve para invitar,
 * pedir un correo de recuperación y validar un login. Así no hace
 * falta un segundo secreto solo para esto.
 *
 * El "access_token" de un login o de un enlace de invitación/
 * recuperación SÍ es del usuario, no del Worker — eso se manda como
 * Bearer solo cuando la propia persona lo trae (definirClave), nunca
 * como credencial nuestra.
 * ------------------------------------------------------------------- */
async function auth(env, ruta, cuerpo, tokenUsuario, metodo) {
  const r = await fetch(`${env.SUPABASE_URL}/auth/v1/${ruta}`, {
    method: metodo || 'POST',
    headers: {
      apikey: env.SUPABASE_SERVICE_KEY,
      Authorization: `Bearer ${tokenUsuario || env.SUPABASE_SERVICE_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(cuerpo),
  });
  const texto = await r.text();
  let datos = {};
  try { datos = JSON.parse(texto); } catch (_) {}
  return { ok: r.status >= 200 && r.status < 300, status: r.status, datos };
}

/* ---------------------------------------------------------------------
 * /salud — ¿está bien la página?
 *
 * PARA QUÉ
 * Todo lo que se ha roto en este proyecto se rompió en silencio, y nos
 * enteramos tarde y por casualidad: la semana que no abrió, los cupos
 * ofrecidos que ya tenían dueño, el reporte del lunes que llevaba cinco
 * días sin salir. Esto es la lista de esas cosas, preguntadas todos los
 * días a las 6 de la mañana.
 *
 * SIN LLAVE A PROPÓSITO
 * La revisión no devuelve ni un nombre, ni un teléfono, ni una cifra de
 * caja: solo cuentas. Así el chequeo diario no necesita cargar con un
 * secreto —que habría que guardar en algún sitio y rotar— y además se
 * puede abrir desde el celular cuando algo huela raro.
 *
 * SIEMPRE 200
 * Aunque algo esté mal. Un 500 lo devuelve también un Worker caído o un
 * Cloudflare con hipo, y entonces no se distingue "la página tiene un
 * problema" de "no pude preguntar". El veredicto va en el cuerpo.
 * ------------------------------------------------------------------- */
async function salud(env, origen) {
  const revisiones = [];
  const apunta = (que, ok, detalle) => revisiones.push({ que, ok, detalle });
  const arranque = Date.now();

  const hoyBogota = () => {
    const f = new Intl.DateTimeFormat('en-CA', {
      timeZone: TZ, year: 'numeric', month: '2-digit', day: '2-digit',
    }).format(new Date());
    return f;
  };

  try {
    // ── 1. ¿Se puede reservar algo? ──
    // Es la pregunta que de verdad importa: si esto falla, quien entra a
    // tumbaobaila.com ve una página vacía y se va.
    const clases = await rpc(env, 'clases_para', { p_tipo: 'suelta' });
    const lista = Array.isArray(clases) ? clases.filter((c) => c && c.id) : [];
    const dias = new Set(lista.map((c) => String(c.fecha_hora).slice(0, 10)));
    apunta('hay clases que reservar', lista.length > 0,
           `${lista.length} clase(s) en ${dias.size} día(s)`);

    // ── 2. ¿Está abierta la semana entrante? ──
    // La abre sola el sábado a las 7 am. Preguntarlo todos los días da
    // aviso con antelación en vez de descubrirlo el lunes, que es
    // cuando ya no se puede reservar.
    const hoy = hoyBogota();
    const d = new Date(hoy + 'T12:00:00Z');
    const isodow = ((d.getUTCDay() + 6) % 7) + 1;
    const lunes = new Date(d.getTime() + ((8 - isodow) % 7 || 7) * 86400000);
    const desde = lunes.toISOString().slice(0, 10);
    const hasta = new Date(lunes.getTime() + 6 * 86400000).toISOString().slice(0, 10);
    const proximas = await leer(env, 'clases',
      `select=id&fecha_hora=gte.${desde}T00:00:00-05:00&fecha_hora=lte.${hasta}T23:59:59-05:00`);
    // Antes del sábado que la abre, que esté vacía es lo normal y no es
    // un fallo: solo se avisa. Del sábado en adelante sí es un problema.
    const yaTocaba = isodow >= 6;
    apunta('la semana entrante está abierta',
           proximas.length > 0 || !yaTocaba,
           proximas.length > 0
             ? `del ${desde} al ${hasta}: ${proximas.length} clases`
             : (yaTocaba ? `NADA del ${desde} al ${hasta} — el lunes no se podrá reservar`
                         : `todavía vacía, la abre el sábado (del ${desde} al ${hasta})`));

    // ── 3. ¿Los cupos cuadran con los afiliados? ──
    // El 15 de agosto la página ofreció 30 puestos donde 20 ya eran de
    // gente con plan. Se comprueba la resta, no el resultado: una clase
    // con cero afiliados puede ofrecer el aforo entero y estar bien.
    const futuras = await leer(env, 'clases',
      'select=id,aforo,activos_plan,cupo_total,cupo_manual,cupo_miembros' +
      '&fecha_hora=gte.now()&limit=500');
    const torcidas = futuras.filter((c) =>
      c.cupo_manual == null && c.cupo_miembros == null &&
      c.cupo_total !== Math.max((c.aforo || 0) - (c.activos_plan || 0), 0));
    apunta('los cupos cuadran con los afiliados', torcidas.length === 0,
           torcidas.length === 0
             ? `${futuras.length} clases revisadas, todas cuadran`
             : `${torcidas.length} de ${futuras.length} ofrecen puestos que ya tienen dueño`);

    // ── 4. ¿Se están soltando los cupos vencidos? ──
    // Los suelta el propio Worker cuando alguien mira los horarios, como
    // mucho cada cinco minutos. Si aparece una reserva vencida hace rato
    // y todavía tomada, ese mecanismo dejó de funcionar.
    const colgadas = await leer(env, 'reservas',
      'select=id&estado=eq.pendiente_pago&expira_en=lt.' +
      new Date(Date.now() - 20 * 60000).toISOString() + '&limit=50');
    apunta('los cupos vencidos se sueltan', colgadas.length === 0,
           colgadas.length === 0 ? 'ninguna reserva vencida sin soltar'
             : `${colgadas.length} reserva(s) vencidas hace más de 20 min siguen ocupando cupo`);

    apunta('Supabase responde', true, `${Date.now() - arranque} ms`);
  } catch (e) {
    apunta('Supabase responde', false, String((e && e.message) || e).slice(0, 160));
  }

  const ok = revisiones.every((r) => r.ok);
  return json({
    ok,
    revisado: new Date().toISOString(),
    mal: revisiones.filter((r) => !r.ok).map((r) => r.que),
    revisiones,
  }, 200, origen);
}

// Solo estos conceptos, y con el sentido que les corresponde. Si un día
// hay que agregar uno, se agrega aquí a propósito: es lo que impide que
// un error de tecleo invente una categoría nueva y ensucie el cierre.
const CONCEPTOS = {
  ingreso: new Set(['clase_suelta', 'media_mensualidad', 'mensualidad',
                    'cumpleanos', 'camiseta', 'otro_ingreso']),
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

const ROLES = new Set(['propietario', 'administrador', 'cajero']);

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
  // La referencia del comprobante la teclea la cajera antes de poder
  // confirmar: es el freno para que no se confirme a ojo. Va opcional
  // aquí porque cruzar con "Es este" enlaza un depósito REAL del banco,
  // que prueba más que cualquier referencia y no debe pedir nada.
  confirmar:  { fn: 'admin_confirmar',
                args: (b) => ({ p_codigo: TXT(b.codigo, 40),
                                p_pago_id: UUID(b.pago_id),
                                p_referencia: TXT(b.referencia, 60) || null }) },
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
  // Gestión de usuarios — Postgres es quien de verdad exige que el
  // token sea de un propietario; aquí solo se le da forma a lo que
  // llega. "usuarios_crear" no está en esta tabla porque además manda
  // la invitación por Supabase Auth: tiene su propia ruta más abajo.
  'usuarios-listar': { fn: 'admin_listar_usuarios', args: () => ({}) },
  'usuarios-estado': { fn: 'admin_cambiar_estado_usuario',
                args: (b) => (UUID(b.id)
                  ? { p_id: UUID(b.id), p_activo: b.activo === true }
                  : { _error: 'ID_INVALIDO' }) },
  'usuarios-rol':    { fn: 'admin_cambiar_rol_usuario',
                args: (b) => (UUID(b.id) && ROLES.has(b.rol)
                  ? { p_id: UUID(b.id), p_rol: b.rol }
                  : { _error: 'DATO_INVALIDO' }) },
};

/* ---------------------------------------------------------------------
 * Soltar los cupos vencidos, aprovechando que alguien está mirando
 *
 * EL PROBLEMA
 * Quien aparta un cupo y no paga lo tiene bloqueado hasta que alguien
 * llame a liberar_cupos_expirados(). Eso lo hacía un workflow de n8n
 * cada hora, de 6am a 10pm: 17 ejecuciones al día, ~510 al mes, que es
 * una quinta parte del plan entero gastada en una llamada de una línea.
 *
 * Lo natural sería un cron de Cloudflare, pero en esta cuenta los cron
 * NO disparan (está documentado en wrangler.jsonc, con las pruebas).
 *
 * LO QUE SE HACE
 * Se llama justo antes de leer los horarios y antes de pintar el
 * tablero de recepción, como mucho una vez cada cinco minutos.
 *
 * Y sale mejor que el cron, no peor:
 *   · Con el cron, un cupo abandonado a las 3:05 seguía bloqueado hasta
 *     las 4:00 — casi una hora en que nadie podía tomarlo.
 *   · Así, los números que se ven SIEMPRE están recién calculados,
 *     porque la limpieza corre antes de leerlos.
 *   · Si no entra nadie no se limpia, y da igual: si nadie está mirando,
 *     no hay nadie a quien el cupo bloqueado le esté estorbando. Y el
 *     primero que llegue limpia antes de ver la lista.
 *
 * El freno de los cinco minutos vive en la caché de Cloudflare, con el
 * cubo de tiempo como llave. La marca se pone ANTES de llamar, para que
 * dos visitas simultáneas no disparen dos limpiezas. Si falla, se pierde
 * ese turno y lo hace el siguiente: liberar_cupos_expirados() es
 * idempotente y no pasa nada por saltarse una vuelta.
 * ------------------------------------------------------------------- */
const MINUTOS_ENTRE_LIMPIEZAS = 5;

async function soltarVencidos(env) {
  try {
    const cubo = Math.floor(Date.now() / (MINUTOS_ENTRE_LIMPIEZAS * 60000));
    const llave = new Request(`https://tumbao.caja/__limpieza/${cubo}`);
    const cache = caches.default;
    if (await cache.match(llave)) return;

    await cache.put(llave, new Response('1', {
      headers: { 'Cache-Control': `max-age=${MINUTOS_ENTRE_LIMPIEZAS * 60}` },
    }));

    const r = await rpc(env, 'liberar_cupos_expirados', {});
    const n = typeof r === 'number' ? r
            : (typeof r?.liberar_cupos_expirados === 'number'
                ? r.liberar_cupos_expirados : 0);
    // Se deja constancia aunque no haya soltado nada. Un "0 cupos" cada
    // cinco minutos es la prueba de que la limpieza sigue corriendo; si
    // solo hablara cuando suelta algo, no habría forma de distinguir
    // "no había nada que soltar" de "esto lleva días sin ejecutarse".
    console.log(`liberar_cupos_expirados: ${n} cupo(s) · cubo ${cubo}`);
  } catch (e) {
    // Nunca puede tumbar la página. Que un cupo vencido siga tomado
    // cinco minutos más es un fastidio; que no se vean los horarios,
    // es que no se puede reservar.
    console.log('soltarVencidos falló (se sigue igual):', e && e.message);
  }
}

/* ---------------------------------------------------------------------
 * Leer la captura del comprobante
 *
 * Se copia el contrato del workflow de n8n "Tumbao · Leer comprobante",
 * campo por campo, para que la página no note el cambio: devuelve
 * { ok, hora, referencia, pagador, valor, leidos }.
 *
 * LA IMAGEN NO SE GUARDA. Entra en la petición, se lee y se suelta. No
 * va a Supabase, ni a Drive, ni a un log. Es lo que la página le promete
 * al cliente en letra pequeña, y aquí es literal: no hay ni una línea
 * que la escriba en ningún lado.
 *
 * ANTE LA DUDA, NULL
 * Esto alimenta los campos con los que después se cruza el pago. Una
 * hora inventada hace que el dinero se case con la reserva equivocada;
 * un null solo hace que la persona la escriba a mano, que es lo que
 * hacía antes de que existiera esto. Por eso todo lo que devuelve el
 * modelo se vuelve a validar aquí abajo.
 * ------------------------------------------------------------------- */
const MODELO_VISION = '@cf/meta/llama-3.2-11b-vision-instruct';

const LEER_COMPROBANTE =
  'Eres un lector de comprobantes de transferencia de bancos colombianos ' +
  '(Bancolombia, Nequi, Daviplata, Davivienda, Bre-B y otros). Devuelves ' +
  'SOLO un objeto JSON con estas cuatro claves: hora, referencia, pagador, valor.\n\n' +
  'hora: la hora de la transaccion en formato 24h HH:MM. Si el comprobante la ' +
  'muestra en 12h con a.m./p.m., conviertela. Si no la ves con claridad, null.\n' +
  'referencia: el numero de comprobante, referencia o CUS, tal cual, sin ' +
  'etiquetas. Si no hay, null.\n' +
  'pagador: el nombre de quien ENVIA el dinero, no de quien lo recibe. Si el ' +
  'comprobante solo muestra al destinatario, null.\n' +
  'valor: el monto en pesos, solo digitos, sin puntos ni simbolos. Si no lo ves, null.\n\n' +
  'Regla que manda sobre todas: ante la duda, null. Un dato inventado hace que ' +
  'el pago se cruce con el equivocado; un null solo hace que la persona lo ' +
  'escriba a mano.';

// El modelo puede devolver "6:31 p.m.", "18:31:07" o cualquier cosa.
// Aquí solo pasa lo que tenga forma de hora de verdad.
function hora24(v) {
  if (v == null) return null;
  const s = String(v).trim().toLowerCase().replace(/\./g, '');
  const m = /^(\d{1,2}):(\d{2})(?::\d{2})?\s*(am|pm)?$/.exec(s);
  if (!m) return null;
  let h = Number(m[1]);
  const min = Number(m[2]);
  if (min > 59) return null;
  if (m[3] === 'pm' && h < 12) h += 12;
  if (m[3] === 'am' && h === 12) h = 0;
  if (h > 23) return null;
  return String(h).padStart(2, '0') + ':' + String(min).padStart(2, '0');
}

function textoLimpio(v, max) {
  if (v == null) return null;
  const s = String(v).trim().replace(/\s+/g, ' ');
  if (!s || s.length > max) return null;
  if (/^(null|n\/a|no aparece|desconocido)$/i.test(s)) return null;
  return s;
}

function enteroPositivo(v) {
  if (v == null) return null;
  const s = String(v).replace(/[^\d]/g, '');
  if (!s) return null;
  const n = Number(s);
  return Number.isFinite(n) && n > 0 ? n : null;
}

// Los modelos abiertos envuelven el JSON en ```json o le anteponen
// "Aquí está el objeto:". Se busca del primer { al último }.
function soloJSON(crudo) {
  if (crudo && typeof crudo === 'object') return crudo;
  const s = String(crudo || '');
  const a = s.indexOf('{');
  const b = s.lastIndexOf('}');
  if (a < 0 || b <= a) return {};
  try { return JSON.parse(s.slice(a, b + 1)); } catch (_) { return {}; }
}

async function leerComprobante(env, imagen) {
  // Se filtra ANTES de llamar al modelo: una entrada basura no mejora
  // por mandarla, y cada llamada cuesta.
  if (!/^data:image\/(jpe?g|png|webp);base64,/.test(imagen)) {
    return { ok: false, error: 'no_es_imagen' };
  }
  // El data URL abulta ~4/3 de los bytes reales. 6 MB de texto son unos
  // 4,5 MB de imagen: de sobra para una captura de celular.
  if (imagen.length > 6 * 1024 * 1024) {
    return { ok: false, error: 'muy_grande' };
  }

  let crudo = '';
  let fiarseDelPagador = true;
  if (env.OPENAI_API_KEY) {
    // Con llave se usa el mismo modelo que usaba n8n, así que la calidad
    // de lectura es exactamente la de antes.
    const r = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: { Authorization: `Bearer ${env.OPENAI_API_KEY}`,
                 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model: env.MODELO_OCR || 'gpt-4o-mini',
        temperature: 0,
        max_tokens: 200,
        response_format: { type: 'json_object' },
        messages: [
          { role: 'system', content: LEER_COMPROBANTE },
          { role: 'user', content: [
            { type: 'text', text: 'Lee este comprobante y devuelve el JSON.' },
            { type: 'image_url', image_url: { url: imagen, detail: 'high' } },
          ] },
        ],
      }),
    });
    if (!r.ok) throw new Error(`OCR ${r.status}`);
    crudo = (await r.json()).choices?.[0]?.message?.content || '';
  } else {
    // SIN LLAVE DE OPENAI NO SE DEVUELVE EL PAGADOR.
    //
    // Probado con un comprobante de Bancolombia que decía Origen
    // MARIANA QUINTERO y Destino LUZ SANTIAGO: el modelo abierto
    // contestó "LUZ SANTIAGO" las tres veces. O sea que confunde a quien
    // manda con quien recibe, justo lo que el guion le pide no hacer.
    //
    // Y ese campo no es decorativo: la página, si viene, marca la
    // casilla de "paga otra persona" y escribe ese nombre. Rellenarlo
    // con el de la dueña de la cuenta es peor que dejarlo en blanco —
    // en blanco la persona lo escribe; relleno, lo da por bueno.
    //
    // Y no es solo el pagador. Medido sobre el mismo comprobante, seis
    // veces seguidas: la hora salió bien 2 de 6, y las otras 4 devolvió
    // todo vacío. Con gpt-4o-mini, 3 de 3 correctas.
    //
    // POR ESO LA PÁGINA TODAVÍA NO USA ESTA RUTA. Está lista y probada,
    // pero apuntarla aquí sin llave cambiaría "te autocompleto los
    // datos" por "te los autocompleto una de cada tres veces".
    //
    // Poniendo OPENAI_API_KEY como secreto del Worker se usa el mismo
    // modelo que usaba n8n, con el mismo guion: la calidad vuelve a ser
    // la de antes, y ahí sí la página puede apuntar aquí y n8n deja de
    // gastar una ejecución por cada comprobante.
    fiarseDelPagador = false;
    if (!env.AI) return { ok: false, error: 'sin_modelo' };
    const base64 = imagen.slice(imagen.indexOf(',') + 1);
    const bytes = Uint8Array.from(atob(base64), (c) => c.charCodeAt(0));
    const d = await env.AI.run(MODELO_VISION, {
      image: [...bytes],
      prompt: LEER_COMPROBANTE + '\n\nLee este comprobante y devuelve el JSON.',
      max_tokens: 300,
    });
    crudo = d.description || d.response || '';
  }

  const d = soloJSON(crudo);
  const hora = hora24(d.hora);
  const referencia = textoLimpio(d.referencia, 40);
  const pagador = fiarseDelPagador ? textoLimpio(d.pagador, 80) : null;
  const valor = enteroPositivo(d.valor);

  // ok:true aunque no se haya sacado nada: para la página eso no es un
  // error, es que hay que escribirlo a mano.
  return { ok: true, hora, referencia, pagador, valor,
           leidos: [hora, referencia, pagador].filter(Boolean).length };
}

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
// Avisarle a n8n que revise Gmail YA, en vez de esperar al sondeo de
// fondo. Nunca bloquea la respuesta al cliente ni la revienta: si el
// token no está puesto, si n8n está caído o si la llamada tarda, el
// sondeo de fondo igual va a cruzar el pago — esto solo lo adelanta.
//
// APAGADO EL 30 DE AGOSTO POR LA CUOTA DE n8n
// El plan son 2.500 ejecuciones al mes y se llegó a 2.494 faltando un
// día. Este aviso gastaba UNA ejecución por cada persona que dice "ya
// pagué", y el sondeo de Gmail gastaba otra por el correo del banco: dos
// por pago, cuando con una basta. Adelantar el cruce medio minuto no
// vale la mitad del plan.
//
// Lo que se pierde: el cruce automático tarda lo que tarde el sondeo de
// fondo en vez de ser inmediato. La barra de espera de la página ya
// aguanta eso —está hecha para el aviso del banco, que tarda de 1 a 2
// minutos— así que la persona no nota nada.
//
// Para volver a encenderlo basta con quitar el `return` de abajo. Se
// deja la función entera en vez de borrarla porque el día que el plan
// suba, esto se vuelve a querer.
function avisarRevisionInmediata(env, ctx) {
  if (!env.AVISAR_A_N8N) return;
  if (!env.N8N_REVISAR_URL || !env.N8N_REVISAR_TOKEN) return;
  const aviso = fetch(env.N8N_REVISAR_URL, {
    method: 'POST',
    headers: { 'x-tumbao-token': env.N8N_REVISAR_TOKEN, 'Content-Type': 'application/json' },
    body: '{}',
  }).catch(() => {});
  if (ctx && typeof ctx.waitUntil === 'function') ctx.waitUntil(aviso);
}

async function pagina(request, env, ruta, origen, ctx) {
  const url = new URL(request.url);
  const q = url.searchParams;
  const metodo = request.method;

  let b = {};
  if (metodo === 'POST') { try { b = await request.json(); } catch (_) {} }

  const txt = (v, max) => (v == null ? '' : String(v).trim().slice(0, max));

  try {
    // ── los horarios ──────────────────────────────────────────────
    if (ruta === '/tumbao/clases' && metodo === 'GET') {
      // Antes de leer, no después: así los cupos que se enseñan ya
      // tienen descontados los que acaban de vencer.
      await soltarVencidos(env);
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
    // ── leer la captura del pago (la imagen NO se guarda) ─────────
    if (ruta === '/tumbao/leer-comprobante' && metodo === 'POST') {
      try {
        const d = await leerComprobante(env, typeof b.imagen === 'string' ? b.imagen : '');
        // Siempre 200: para la página, "no se pudo leer" no es un fallo
        // de red sino una invitación a escribirlo a mano. Un 500 la haría
        // enseñar "se cayó la conexión", que es mentira y asusta.
        return json({ hora: null, referencia: null, pagador: null,
                      valor: null, leidos: 0, ...d }, 200, origen);
      } catch (e) {
        // Sin esta línea el fallo es mudo: la página enseña "escríbelo a
        // mano" —que es lo correcto para el cliente— y desde fuera no hay
        // forma de distinguir "la imagen no se dejó leer" de "el modelo
        // lleva dos días caído".
        console.log('leer-comprobante FALLÓ:', e && e.message);
        // `detalle` va en la respuesta a propósito. La página no lo
        // enseña —para el cliente el mensaje sigue siendo "escríbelo a
        // mano"— pero desde fuera es la única forma de saber POR QUÉ sin
        // pelearse con los logs. No lleva nada sensible: es el mensaje
        // de error, no la imagen ni la llave.
        return json({ ok: false, error: 'falla',
                      detalle: String((e && e.message) || e).slice(0, 200),
                      hora: null, referencia: null,
                      pagador: null, valor: null, leidos: 0 }, 200, origen);
      }
    }

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
        // La persona está a punto de entrar a la barra de espera. Que
        // n8n revise Gmail ya mismo, sin esperar al sondeo de fondo.
        avisarRevisionInmediata(env, ctx);
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
  async fetch(request, env, ctx) {
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
      return await pagina(request, env, ruta, origen, ctx);
    }

    // La revisión diaria. Sin token: no devuelve más que cuentas.
    if (ruta === '/salud') {
      return await salud(env, origen);
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

    /* ─────────────────────────────────────────────────────────────
     * Login del panel — correo y contraseña, sin token todavía
     *
     * La contraseña la valida Supabase Auth, no esta base: el Worker
     * se la pasa una sola vez para el intercambio y no la guarda en
     * ningún lado. Lo que devuelve es el mismo tipo de token opaco de
     * siempre —admin_token_para_usuario lo emite igual que
     * crear_token_admin— solo que ahora viene con el rol pegado.
     * ───────────────────────────────────────────────────────────── */
    const REDIRECT_ADMIN = 'https://tumbaobaila.com/admin';

    if (ruta === '/api/admin/login') {
      const email = String(b.email || '').trim();
      const clave = String(b.password || '');
      if (!email || !clave) {
        return json({ ok: false, error: 'FALTA_DATO',
          mensaje: 'Escribe el correo y la contraseña.' }, 400, origen);
      }
      const ses = await auth(env, 'token?grant_type=password', { email, password: clave });
      if (!ses.ok || !ses.datos.access_token) {
        return json({ ok: false, error: 'CREDENCIALES',
          mensaje: 'Correo o contraseña incorrectos.' }, 401, origen);
      }
      const r = await rpc(env, 'admin_token_para_usuario', {
        p_user_id: ses.datos.user.id, p_email: ses.datos.user.email,
      });
      return json(r, r && r.ok === false ? 403 : 200, origen);
    }

    // El primer propietario, cuando todavía no hay ningún usuario dado
    // de alta. La propia función de Postgres se cierra sola en cuanto
    // exista una fila, así que no queda una puerta abierta.
    if (ruta === '/api/admin/bootstrap-invite') {
      const email  = String(b.email || '').trim();
      const nombre = String(b.nombre || '').trim();
      if (!email || !nombre) {
        return json({ ok: false, error: 'FALTA_DATO' }, 400, origen);
      }
      const r = await rpc(env, 'admin_bootstrap_propietario', { p_email: email, p_nombre: nombre });
      if (!r.ok) return json(r, 400, origen);
      const inv = await auth(env, `invite?redirect_to=${encodeURIComponent(REDIRECT_ADMIN)}`, { email });
      return json({
        ok: true,
        mensaje: inv.ok
          ? 'Listo. Revisa el correo de ' + email + ' para poner la contraseña.'
          : 'El usuario quedó creado, pero no se pudo mandar el correo de invitación. ' +
            'Revisa el envío de correo en Supabase (Authentication → Email).',
      }, 200, origen);
    }

    // "Olvidé mi contraseña". Responde igual exista o no ese correo:
    // decir la diferencia sería enseñarle a cualquiera qué correos
    // tienen cuenta en el panel.
    if (ruta === '/api/admin/recuperar') {
      const email = String(b.email || '').trim();
      if (email) {
        try {
          await auth(env, `recover?redirect_to=${encodeURIComponent(REDIRECT_ADMIN)}`, { email });
        } catch (_) {}
      }
      return json({ ok: true,
        mensaje: 'Si ese correo tiene una cuenta, le llega un enlace para poner una contraseña nueva.',
      }, 200, origen);
    }

    // Poner contraseña — se llega aquí desde el enlace de invitación o
    // el de "olvidé mi contraseña". El access_token es el que Supabase
    // deja en la URL de ese enlace, no el token del panel.
    if (ruta === '/api/admin/definir-clave') {
      const clave = String(b.password || '');
      const accesoUsuario = String(b.access_token || '');
      if (!accesoUsuario) {
        return json({ ok: false, error: 'ENLACE_INVALIDO',
          mensaje: 'Ese enlace no sirve. Pide que te inviten de nuevo.' }, 400, origen);
      }
      if (clave.length < 8) {
        return json({ ok: false, error: 'CLAVE_CORTA',
          mensaje: 'La contraseña necesita al menos 8 caracteres.' }, 400, origen);
      }
      const r = await auth(env, 'user', { password: clave }, accesoUsuario, 'PUT');
      if (!r.ok) {
        return json({ ok: false, error: 'ENLACE_VENCIDO',
          mensaje: 'El enlace venció o ya se usó. Pide que te lo manden de nuevo.' }, 400, origen);
      }
      return json({ ok: true, mensaje: 'Contraseña puesta. Ya puedes entrar.' }, 200, origen);
    }

    const token = String(b.token || '');
    if (!token) return json({ ok: false, error: 'NO_AUTORIZADO' }, 401, origen);

    try {
      let r;

      // Dar de alta un usuario nuevo del panel. Aparte de la tabla ADMIN
      // porque además manda la invitación por Supabase Auth — eso no
      // encaja en "una función de Postgres y ya". Se crea PRIMERO el
      // puesto en admin_usuarios (ahí es donde Postgres exige que quien
      // llama sea propietario) y solo si eso queda bien se manda el
      // correo: así un token sin permiso no dispara invitaciones a
      // nombre de nadie.
      if (ruta === '/api/admin/usuarios-crear') {
        const nombre = TXT(b.nombre, 80);
        const email  = TXT(b.email, 120);
        if (!nombre || !email || !ROLES.has(b.rol)) {
          return json({ ok: false, error: 'DATO_INVALIDO',
            mensaje: 'Falta el nombre, el correo o el rol.' }, 400, origen);
        }
        r = await rpc(env, 'admin_crear_usuario', {
          p_token: token, p_nombre: nombre, p_email: email, p_rol: b.rol, p_user_id: null,
        });
        if (r.ok) {
          const inv = await auth(env, `invite?redirect_to=${encodeURIComponent(REDIRECT_ADMIN)}`, { email });
          r.mensaje = inv.ok
            ? 'Listo. Le llega un correo a ' + email + ' para poner su contraseña.'
            : 'El usuario quedó creado, pero no se pudo mandar el correo de invitación.';
        }
        return json(r, r && r.ok === false ? 400 : 200, origen);
      }

      // ── el panel de admin ──
      if (ruta.startsWith('/api/admin/')) {
        const cual = ADMIN[ruta.slice('/api/admin/'.length)];
        if (!cual) return json({ ok: false, error: 'NO_EXISTE' }, 404, origen);

        const args = cual.args(b);
        if (args._error) {
          return json({ ok: false, error: args._error,
            mensaje: 'Faltan datos o no se reconocen. Recarga la página.' }, 400, origen);
        }
        // El tablero es lo que mira recepción durante el turno: si ahí
        // los cupos están viejos, se le dice a alguien que no hay puesto
        // cuando sí lo hay. Comparte el freno de cinco minutos con la
        // página pública, así que entre las dos no se duplica.
        if (cual.fn === 'admin_tablero' || cual.fn === 'admin_lista_clase') {
          await soltarVencidos(env);
        }
        r = await rpc(env, cual.fn, { p_token: token, ...args });

      } else if (ruta === '/api/dia') {
        r = await rpc(env, 'caja_del_dia', {
          p_token: token,
          p_dia: /^\d{4}-\d{2}-\d{2}$/.test(b.dia || '') ? b.dia : null,
        });

      // Diagnóstico puntual: el detalle crudo de cada depósito que el
      // banco confirmó ese día, para cruzar contra AdminGym transacción
      // por transacción cuando un total no cuadra y hay que ver de
      // dónde sale la diferencia. Reusa verificar_token_admin —
      // cualquier token vivo puede pedirlo, como cualquier otra pantalla
      // de solo lectura del panel.
      } else if (ruta === '/api/pagos-del-dia') {
        const dia = /^\d{4}-\d{2}-\d{2}$/.test(b.dia || '') ? b.dia : null;
        if (!dia) return json({ ok: false, error: 'DIA_INVALIDO' }, 400, origen);
        const v = await rpc(env, 'verificar_token_admin', { p_token: token });
        if (!v) return json({ ok: false, error: 'NO_AUTORIZADO' }, 401, origen);
        const desde = `${dia}T00:00:00-05:00`;
        const hasta = `${dia}T23:59:59.999-05:00`;
        const pagos = await leer(env, 'pagos',
          `fecha_pago=gte.${encodeURIComponent(desde)}&fecha_pago=lte.${encodeURIComponent(hasta)}` +
          `&select=id,remitente,valor_cop,fecha_pago,referencia,consumido,banco&order=fecha_pago.asc`);
        return json({ ok: true, dia, pagos }, 200, origen);

      // Con qué reserva quedó un depósito, y para qué clase (fecha) es
      // esa reserva — para distinguir un pago que sí es de hoy de uno
      // adelantado para una clase futura.
      } else if (ruta === '/api/pago-reserva') {
        const pago = String(b.pago_id || '');
        if (!/^[0-9a-f-]{36}$/i.test(pago)) return json({ ok: false, error: 'PAGO_INVALIDO' }, 400, origen);
        const v = await rpc(env, 'verificar_token_admin', { p_token: token });
        if (!v) return json({ ok: false, error: 'NO_AUTORIZADO' }, 401, origen);
        const reservas = await leer(env, 'reservas',
          `pago_id=eq.${pago}&select=nombre,telefono,tipo,estado,clase_id`);
        for (const r of reservas) {
          const clases = await leer(env, 'clases', `id=eq.${r.clase_id}&select=fecha_hora,nombre`);
          r.clase = clases[0] || null;
        }
        return json({ ok: true, reservas }, 200, origen);

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
        // A cuánta gente cubre este cobro. Tres personas que llegan
        // juntas y pagan $45.000 son UN movimiento y TRES entradas; sin
        // esto el cierre contaba una sola y la cuenta de gente del día
        // no cuadraba nunca. El valor no se teclea aparte: es
        // cantidad × precio, así que los dos números no se pueden
        // contradecir. Se valida aquí y NO se confía en el navegador:
        // Postgres lo vuelve a comprobar, pero un "3 personas" que
        // llegue como texto raro no puede convertirse en un cobro.
        const cantidad = b.cantidad === undefined || b.cantidad === null || b.cantidad === ''
          ? 1
          : parseInt(String(b.cantidad).replace(/[^\d]/g, ''), 10);
        if (!Number.isFinite(cantidad) || cantidad < 1) {
          return json({ ok: false, error: 'CANTIDAD_INVALIDA',
            mensaje: 'La cantidad tiene que ser al menos 1.' }, 400, origen);
        }
        // El mismo criterio que el tope del valor: alto pero real. La
        // clase más grande tiene treinta cupos.
        if (cantidad > 50) {
          return json({ ok: false, error: 'CANTIDAD_SOSPECHOSA',
            mensaje: 'Cincuenta personas en un solo cobro no es un cobro, '
                   + 'es un error de tecleo. Revísalo.' }, 400, origen);
        }
        const args = {
          p_token: token, p_sentido: sentido, p_concepto: concepto,
          p_valor: valor,
          p_medio: b.medio === 'transferencia' ? 'transferencia' : 'efectivo',
          p_nota: b.nota ? String(b.nota).slice(0, 200) : null,
        };
        // Igual que con p_pago_id: solo se manda cuando de verdad hay
        // algo que decir. PostgREST resuelve la función por los
        // parámetros que recibe, así que mandar p_cantidad siempre
        // obligaría a tener ya aplicada la migración 0065 — y hasta
        // entonces no se podría ni cobrar.
        if (cantidad > 1) args.p_cantidad = cantidad;
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
          // Cómo pagó. De esto depende que el arqueo cuadre: si fue en
          // efectivo, admin_crear_reserva registra el movimiento de caja
          // en la misma llamada, y esa plata deja de depender de que
          // alguien se acuerde de apuntarla en otra pestaña.
          //
          // Se filtra a los dos valores válidos en vez de reenviar lo
          // que llegue: Postgres también lo valida, pero un 'Efectivo'
          // con mayúscula rebotaría allá y aquí se arregla solo.
          // 'en_puerta' = paga en efectivo cuando llegue. Esa no entra a
          // la caja al apuntar: entra al marcarle la entrada. Si no
          // viene, no se cobró nada y no hay nada que deshacer.
          p_medio: ['efectivo', 'transferencia', 'en_puerta']
            .includes(String(b.medio || '').toLowerCase())
            ? String(b.medio).toLowerCase() : null,
        });

      } else if (ruta === '/api/juntar-pagos') {
        // Varios depósitos que en realidad son un solo pago: alguien
        // consignó 85.000 y después 40.000 para completar la
        // mensualidad. Postgres valida que estén libres y que ninguno
        // venga ya de otro grupo; aquí solo se limpia la lista.
        const ids = Array.isArray(b.ids) ? b.ids.map(String) : [];
        if (ids.some(x => !/^[0-9a-f-]{36}$/i.test(x))) {
          return json({ ok: false, error: 'PAGO_INVALIDO',
            mensaje: 'No se reconoce alguno de esos depósitos. Recarga la lista.' }, 400, origen);
        }
        if (ids.length < 2) {
          return json({ ok: false, error: 'FALTAN_DEPOSITOS',
            mensaje: 'Escoge al menos dos depósitos para juntarlos.' }, 400, origen);
        }
        r = await rpc(env, 'caja_fusionar_pagos', { p_token: token, p_ids: ids });

      } else if (ruta === '/api/enlazar-deposito') {
        // El depósito que llegó tarde. La cajera cobró una mensualidad
        // por transferencia y la registró a mano con la clienta
        // delante; horas después llegó la alerta del banco y entró un
        // depósito sin dueño. Nadie los cruzaba, así que esa plata
        // quedaba contada en la Caja Y persiguiéndose en la tirilla:
        // es lo que más descuadraba las cuentas del día.
        //
        // Postgres decide todo lo que importa —que el movimiento sea de
        // hoy, que no esté ya enlazado, que no sea efectivo, que el
        // depósito esté libre y que alcance—; aquí solo se comprueba
        // que los dos ids tengan forma de uuid, para no mandar basura
        // a la RPC.
        const mov = String(b.mov_id || '');
        if (!/^[0-9a-f-]{36}$/i.test(mov)) {
          return json({ ok: false, error: 'ID_INVALIDO',
            mensaje: 'No se reconoce ese movimiento. Recarga la caja del día.' }, 400, origen);
        }
        const dep = String(b.pago_id || '');
        if (!/^[0-9a-f-]{36}$/i.test(dep)) {
          return json({ ok: false, error: 'PAGO_INVALIDO',
            mensaje: 'No se reconoce ese depósito. Recarga la lista.' }, 400, origen);
        }
        r = await rpc(env, 'caja_enlazar_deposito', {
          p_token: token, p_mov_id: mov, p_pago_id: dep,
        });

      } else if (ruta === '/api/separar-pago') {
        const id = String(b.id || '');
        if (!/^[0-9a-f-]{36}$/i.test(id)) {
          return json({ ok: false, error: 'ID_INVALIDO' }, 400, origen);
        }
        r = await rpc(env, 'caja_separar_pago', { p_token: token, p_id: id });

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
