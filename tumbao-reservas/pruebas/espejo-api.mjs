/**
 * Espejo de "Tumbao · API de reservas" para probar la página sin tocar
 * n8n ni Supabase. Respeta el mismo contrato de request y respuesta.
 *
 * Simula el flujo completo, incluido el retardo del correo del banco:
 * la reserva pasa a 'confirmada' unos segundos después de que la
 * persona dice "ya pagué", igual que en la vida real.
 */
import { createServer } from 'node:http';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const RAIZ = join(dirname(fileURLToPath(import.meta.url)), '..');
// Las paginas viven en /docs del repo, no dentro del proyecto: es la
// carpeta que GitHub Pages sirve directamente desde la rama.
const WEB = join(RAIZ, '..', 'docs');
const PUERTO = 8899;

// Cuántos segundos tarda el "correo del banco" en llegar.
const RETARDO_BANCO = Number(process.env.RETARDO_BANCO ?? 6);
// Si es true, el pago nunca llega y la reserva cae a validación humana.
const NUNCA_LLEGA = process.env.NUNCA_LLEGA === '1';
// Permite acortar los 5 minutos de espera para poder probar en segundos
// el camino de validación humana sin esperar de verdad.
const MINUTOS_ESPERA = process.env.MINUTOS_ESPERA;

// Las horas se anclan a Bogotá (UTC-5, sin horario de verano). Si se
// usara la hora local del proceso, en un servidor en UTC las 7:00 am
// saldrían como 2:00 am.
const fechaBogota = n => {
  const d = new Date(Date.now() + n * 86400000);
  const [dd, mm, aa] = new Intl.DateTimeFormat('en-GB', {
    timeZone: 'America/Bogota', day: '2-digit', month: '2-digit', year: 'numeric',
  }).format(d).split('/');
  return `${aa}-${mm}-${dd}`;
};
const enDias = (n, h) => new Date(`${fechaBogota(n)}T${String(h).padStart(2, '0')}:00:00-05:00`);
const dowBogota = n => new Date(`${fechaBogota(n)}T12:00:00-05:00`).getUTCDay();

// Lun–vie 7am/6pm/7pm, sábado 8am/9am — el horario real de Tumbao.
//
// Va en una función y no suelto arriba porque el espejo guarda estado en
// memoria: las pruebas crean clases, reservan y marcan asistencias. Sin
// poder volver al principio, la segunda corrida de la misma suite
// arranca sobre los restos de la primera y falla por cosas que no tienen
// nada que ver con el código. Ese fue exactamente el sintoma.
const clases = [];
let seq = 1;
function sembrarClases() {
  clases.length = 0;
  seq = 1;
  for (let n = 1; n <= 7; n++) {
    const dow = dowBogota(n);
    const horas = dow === 6 ? [[8, 'Clase 8:00 am'], [9, 'Clase 9:00 am']]
                : dow === 0 ? []
                : [[7, 'Clase 7:00 am'], [18, 'Clase 6:00 pm'], [19, 'Clase 7:00 pm']];
    for (const [h, nombre] of horas) {
      // Los avisos del tablero se cuelgan de la PRIMERA y la ÚLTIMA
      // clase del día, no de una hora fija. Antes iban en la de las 7 am
      // y la de las 6 pm, que el sábado no existen: la prueba salta al
      // día siguiente, y todos los viernes eso caía en sábado y fallaba
      // sin que hubiera nada roto.
      const esPrimera = h === horas[0][0];
      const esUltima  = h === horas[horas.length - 1][0];
      // El sábado también tiene que quedar con gente de plan, o el aviso
      // de "vencen" no puede salir: nunca puede pasarse de con_plan.
      const libres = dow === 6 ? 25 : (h === 18 ? 4 : h === 7 ? 11 : 14);
      clases.push({
        clase_id: 'clase-' + (seq++),
        nombre, profesor: 'Kevin', lugar: 'Sede Tumbao',
        fecha_hora: enDias(n, h).toISOString(),
        duracion_min: 60, precio_cop: 15000,
        cupo_total: libres, cupos_disponibles: libres, agotada: libres <= 0,
        // Lo que ve el panel: los cupos salen de aforo − gente con plan.
        activa: true, aforo: 30, activos_plan: 30 - libres, cupo_manual: null,
        // A dos de la última clase del día se les acaba el plan. Sirve
        // para que el aviso punteado del tablero tenga algo que mostrar.
        _vencen: esUltima ? 2 : 0,
        _primera: esPrimera,
        // El sabado va partido: 15 para afiliados y 15 para sueltas.
        // Entre semana en null, que es "sin reparto".
        cupo_miembros: dow === 6 ? 15 : null,
        cupo_sueltas:  dow === 6 ? 15 : null,
        _dow: dow, _hora: h,
      });
    }
  }
  // Una agotada, para comprobar que se deshabilita.
  //
  // Va en el SEGUNDO sabado y se busca por hora, no por indice. Desde
  // que la pagina solo muestra la semana que corre, hay dias en que
  // queda un solo dia entre semana a la vista, y entonces agotar
  // cualquier clase de entre semana rompe alguna prueba:
  //
  //   7 am  -> el panel abre el dia siguiente y su primera tarjeta
  //            queda sin cupo: no se puede ni reservar ni bajar el
  //            cupo manual por debajo de lo ya tomado
  //   6 pm  -> es el horario del miembro de prueba, y necesita el
  //            suyo habilitado para que le diga "ya te cubre"
  //   7 pm  -> es la "otra hora" del mismo caso
  //
  // El sabado no estorba a ninguna: siempre esta dentro de la semana
  // visible, y al ser la segunda de ese dia la primera tarjeta del
  // sabado sigue libre.
  const agotada = clases.find(c => c._dow === 6 && c._hora === 9);
  if (agotada) { agotada.cupos_disponibles = 0; agotada.agotada = true; }
}
sembrarClases();

// Token del panel. En la vida real lo emite Supabase y se guarda hasheado;
// aqui es fijo para poder probar.
const TOKEN_ADMIN = process.env.TOKEN_ADMIN || 'token-de-prueba';

// token -> {rol, nombre}. El token de siempre (TOKEN_ADMIN) sigue vivo
// con rol null, que es como quedan los token de antes de que existieran
// los roles: acceso total, sin gestionar usuarios. Los que emite un
// login de verdad (admin_token_para_usuario en la vida real) se van
// agregando aqui con su rol.
let sesiones = new Map();
function sembrarSesiones() {
  sesiones = new Map([[TOKEN_ADMIN, { rol: null, nombre: 'Recepción' }]]);
}
sembrarSesiones();

// correo -> {password, nombre, rol, activo, id}. El reparto de quien
// puede entrar, para poder probar el login y las tres vistas por rol
// sin tocar Supabase.
let cuentas = new Map();
function sembrarCuentas() {
  cuentas = new Map([
    ['duena@tumbaobaila.com',  { id: 'u-1', password: 'clave1234', nombre: 'La Dueña',  rol: 'propietario',   activo: true }],
    ['admin@tumbaobaila.com',  { id: 'u-2', password: 'clave1234', nombre: 'El Admin',  rol: 'administrador', activo: true }],
    ['cajero@tumbaobaila.com', { id: 'u-3', password: 'clave1234', nombre: 'El Cajero', rol: 'cajero',        activo: true }],
  ]);
}
sembrarCuentas();
let seqUsuario = 4;

// Devuelve las fechas de la semana con hora y desfase pegados, como las
// devolvía admin_semana antes de la migración 0015. Sirve para correr la
// prueba del panel contra la forma que lo tumbó.
const FECHA_FEA = process.env.FECHA_FEA === '1';

// Fuerza el caso incomodo de deshacer: el cupo ya se vendio.
const SIN_CUPO_AL_DESHACER = process.env.SIN_CUPO_AL_DESHACER === '1';

// La lectura del comprobante no encuentra nada: la persona tiene que
// escribir los datos a mano. Es el camino que MAS se va a usar los
// primeros dias, asi que tiene prueba propia.
const LECTURA_VACIA = process.env.LECTURA_VACIA === '1';
// El comprobante sale a nombre de otra persona.
const LECTURA_OTRO  = process.env.LECTURA_OTRO === '1';
let ultimaLectura = null;

const soloFecha = v => String(v ?? '').slice(0, 10);
const diaDe = iso => new Intl.DateTimeFormat('en-CA', {
  timeZone: 'America/Bogota', year: 'numeric', month: '2-digit', day: '2-digit',
}).format(new Date(iso));
const sumaDias = (iso, n) => {
  const [a, m, d] = iso.split('-').map(Number);
  const f = new Date(Date.UTC(a, m - 1, d));
  f.setUTCDate(f.getUTCDate() + n);
  return f.toISOString().slice(0, 10);
};

// Lo ultimo que llego por /comprobante, para que la prueba lo pueda mirar.
let ultimoComprobante = null;

// celular -> hora de su plan. Varios a las 18 para que la lista de la
// puerta tenga los dos grupos y se note la diferencia.
const MIEMBROS = {
  '3001111111': 18, '3001111112': 18, '3001111113': 18,
  '3002222221': 7,  '3002222222': 7,
};
const reservas = new Map();
// Las reservas hechas de una sola vez y pagadas de un solo giro. Una
// reserva sola es su propio grupo.
const hermanas = (r) => [...reservas.values()]
  .filter(x => (x.grupo || x.codigo) === (r.grupo || r.codigo));
// "claseId|ref" de quien ya entro. Un Set, porque marcar dos veces no
// puede contar dos personas.
const asistencias = new Set();
let nCod = 0;
const codigo = () => 'AB' + String(++nCod).padStart(4, '0');

const fmt = (iso, o) => new Intl.DateTimeFormat('es-CO', { timeZone: 'America/Bogota', ...o }).format(new Date(iso));
const hora12 = iso => fmt(iso, { hour: 'numeric', minute: '2-digit', hour12: true })
  .replace(/ | /g, ' ').replace(/\s*a\.\s*m\./i, ' am').replace(/\s*p\.\s*m\./i, ' pm');

const json = (res, code, obj) => {
  res.writeHead(code, {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': '*',
    'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
  });
  res.end(JSON.stringify(obj));
};

const leerCuerpo = req => new Promise(ok => {
  let b = ''; req.on('data', c => b += c); req.on('end', () => { try { ok(JSON.parse(b || '{}')); } catch { ok({}); } });
});

createServer(async (req, res) => {
  const url = new URL(req.url, 'http://x');
  if (req.method === 'OPTIONS') return json(res, 204, {});

  if (url.pathname === '/' || url.pathname === '/index.html') {
    // Desde que se pueden reservar varios cupos, la pagina publica
    // tambien llama al Worker. Se reescriben las tres bases al espejo.
    //
    // API_BASE son las cuatro llamadas de la reserva, que desde el 17
    // de agosto las atiende el Worker y ya no n8n. El espejo las sigue
    // sirviendo en /webhook/tumbao/... porque el contrato es el mismo:
    // lo que cambio fue quien contesta, no que contesta.
    let html = readFileSync(join(WEB, 'index.html'), 'utf8')
      .replace(/API_BASE:\s*'[^']*'/, `API_BASE: 'http://localhost:${PUERTO}/webhook/tumbao'`)
      .replace(/N8N_BASE:\s*'[^']*'/, `N8N_BASE: 'http://localhost:${PUERTO}/webhook'`)
      .replace(/CAJA_BASE:\s*'[^']*'/, `CAJA_BASE: 'http://localhost:${PUERTO}'`)
      // El chat de opiniones vive en otro Worker. Aqui se apunta al
      // propio espejo, que sirve una pagina de mentiras: lo que se
      // prueba es la burbuja, no el chat.
      .replace(/OPINA:\s*'[^']*'/, `OPINA: 'http://localhost:${PUERTO}/opina-falso'`);
    if (MINUTOS_ESPERA) html = html.replace(/MINUTOS_ESPERA:\s*[\d.]+/, `MINUTOS_ESPERA: ${MINUTOS_ESPERA}`);
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    return res.end(html);
  }
  // Un chat de mentiras para poder probar la burbuja sin salir a
  // internet. Solo tiene que responder algo dentro de un iframe.
  if (url.pathname === '/opina-falso' || url.pathname.startsWith('/opina-falso/')) {
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    return res.end('<!doctype html><meta charset="utf-8">' +
      '<body style="background:#0d0b0f;color:#f2eef5;font:15px system-ui;padding:1rem">' +
      '<p id="saludo">Un gusto. Cuéntame: ¿Qué te hizo volver la segunda vez?</p></body>');
  }

  if (url.pathname === '/admin' || url.pathname === '/admin.html') {
    // Desde el 11 de agosto el panel llama al Worker (/api/admin/...) y
    // no a n8n. El espejo atiende las dos formas, así que aquí se
    // reescriben las dos bases al mismo sitio.
    const html = readFileSync(join(WEB, 'admin.html'), 'utf8')
      .replace(/N8N_BASE:\s*'[^']*'/, `N8N_BASE: 'http://localhost:${PUERTO}/webhook'`)
      .replace(/CAJA_BASE:\s*'[^']*'/, `CAJA_BASE: 'http://localhost:${PUERTO}'`)
      // El chat de opiniones vive en otro Worker. Aqui se apunta al
      // propio espejo, que sirve una pagina de mentiras: lo que se
      // prueba es la burbuja, no el chat.
      .replace(/OPINA:\s*'[^']*'/, `OPINA: 'http://localhost:${PUERTO}/opina-falso'`);
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    return res.end(html);
  }
  if (url.pathname.startsWith('/img/')) {
    try {
      res.writeHead(200, { 'Content-Type': 'image/png' });
      return res.end(readFileSync(join(WEB, url.pathname)));
    } catch { res.writeHead(404); return res.end(); }
  }

  // ---- login con correo y contraseña ----
  if (url.pathname === '/api/admin/login' && req.method === 'POST') {
    const b = await leerCuerpo(req);
    const cuenta = cuentas.get(String(b.email || '').trim().toLowerCase());
    if (!cuenta || cuenta.password !== b.password) {
      return json(res, 401, { ok: false, error: 'CREDENCIALES', mensaje: 'Correo o contraseña incorrectos.' });
    }
    if (!cuenta.activo) {
      return json(res, 403, { ok: false, error: 'inactivo', mensaje: 'Tu acceso está desactivado.' });
    }
    const tk = 'tk-' + cuenta.id + '-' + Math.random().toString(36).slice(2);
    sesiones.set(tk, { rol: cuenta.rol, nombre: cuenta.nombre });
    return json(res, 200, { ok: true, token: tk, rol: cuenta.rol, nombre: cuenta.nombre });
  }

  if (url.pathname === '/api/admin/recuperar' && req.method === 'POST') {
    return json(res, 200, { ok: true,
      mensaje: 'Si ese correo tiene una cuenta, le llega un enlace para poner una contraseña nueva.' });
  }

  if (url.pathname === '/api/admin/definir-clave' && req.method === 'POST') {
    const b = await leerCuerpo(req);
    if (!b.access_token) {
      return json(res, 400, { ok: false, error: 'ENLACE_INVALIDO', mensaje: 'Ese enlace no sirve.' });
    }
    if (String(b.password || '').length < 8) {
      return json(res, 400, { ok: false, error: 'CLAVE_CORTA', mensaje: 'Al menos 8 caracteres.' });
    }
    return json(res, 200, { ok: true, mensaje: 'Contraseña puesta. Ya puedes entrar.' });
  }

  // ---- panel de admin ----
  // El panel ahora pega en /api/admin/<ruta> (Worker). Se acepta también
  // la forma vieja de n8n para no romper nada que todavía la use.
  if ((url.pathname.startsWith('/webhook/tumbao/admin/') ||
       url.pathname.startsWith('/api/admin/')) && req.method === 'POST') {
    const b = await leerCuerpo(req);
    const sesion = sesiones.get(b.token);
    if (!sesion) {
      return json(res, 401, { ok: false, error: 'NO_AUTORIZADO' });
    }
    const que = url.pathname.split('/').pop();

    // El cajero no toca el horario — mismo candado que en Postgres.
    if (que === 'guardar' && sesion.rol === 'cajero') {
      return json(res, 200, { ok: false, error: 'SIN_PERMISO',
        mensaje: 'El cajero no puede tocar el horario. Pide a un administrador.' });
    }

    if (que === 'usuarios-listar' || que === 'usuarios-crear' ||
        que === 'usuarios-estado' || que === 'usuarios-rol') {
      if (sesion.rol !== 'propietario') {
        return json(res, 200, { ok: false, error: 'SIN_PERMISO',
          mensaje: 'Solo el propietario ve y gestiona los usuarios.' });
      }
      if (que === 'usuarios-listar') {
        const lista = [...cuentas.entries()].map(([email, c]) => ({
          id: c.id, nombre: c.nombre, email, rol: c.rol, activo: c.activo, tiene_acceso: true,
        })).sort((a, b2) => a.nombre.localeCompare(b2.nombre));
        return json(res, 200, { ok: true, usuarios: lista });
      }
      if (que === 'usuarios-crear') {
        const email = String(b.email || '').trim().toLowerCase();
        if (cuentas.has(email)) {
          return json(res, 200, { ok: false, error: 'YA_EXISTE', mensaje: 'Ese correo ya tiene un perfil.' });
        }
        cuentas.set(email, { id: 'u-' + (seqUsuario++), password: 'sin-definir',
          nombre: b.nombre, rol: b.rol, activo: true });
        return json(res, 200, { ok: true, mensaje: 'Le llega un correo a ' + email + ' para poner su contraseña.' });
      }
      if (que === 'usuarios-estado') {
        const par = [...cuentas.entries()].find(([, c]) => c.id === b.id);
        if (!par) return json(res, 200, { ok: false, error: 'NO_EXISTE' });
        par[1].activo = b.activo === true;
        if (!par[1].activo) {
          for (const [tk, ses] of sesiones) if (ses.nombre === par[1].nombre) sesiones.delete(tk);
        }
        return json(res, 200, { ok: true });
      }
      if (que === 'usuarios-rol') {
        const par = [...cuentas.entries()].find(([, c]) => c.id === b.id);
        if (!par) return json(res, 200, { ok: false, error: 'NO_EXISTE' });
        par[1].rol = b.rol;
        return json(res, 200, { ok: true });
      }
    }

    if (que === 'semana') {
      const dias = [];
      for (let i = 0; i < 7; i++) {
        const f = sumaDias(b.desde, i);
        dias.push({
          // FECHA_FEA repite la forma con la que Postgres tumbó el panel
          // ("2026-07-28T00:00:00+00:00" en vez de "2026-07-28"). El
          // espejo devolvía la fecha ya limpia, así que la prueba pasaba
          // en verde mientras producción se caía. Con la bandera puesta
          // la suite entera se corre contra el contrato feo.
          fecha: FECHA_FEA ? `${f}T00:00:00+00:00` : f,
          dow: new Date(`${f}T12:00:00-05:00`).getUTCDay(),
          clases: clases.filter(c => diaDe(c.fecha_hora) === f).map(c => ({
            clase_id: c.clase_id, nombre: c.nombre,
            hora: String(c._hora).padStart(2, '0') + ':00',
            profesor: c.profesor, activa: c.activa !== false,
            aforo: c.aforo ?? 30, activos_plan: c.activos_plan ?? 0,
            cupo_total: c.cupo_total, cupo_tomado: c.cupo_total - c.cupos_disponibles,
            cupo_manual: c.cupo_manual ?? null,
            ya_paso: new Date(c.fecha_hora) <= new Date()
          }))
        });
      }
      return json(res, 200, { ok: true, desde: b.desde, hasta: sumaDias(b.desde, 6), dias });
    }

    if (que === 'guardar') {
      let creadas = 0, editadas = 0, apagadas = 0;
      const avisos = [];
      for (const cel of (b.celdas || [])) {
        const h = Number(cel.hora.split(':')[0]);
        let c = clases.find(x => diaDe(x.fecha_hora) === cel.fecha && x._hora === h);
        if (!c) {
          if (cel.activa === false) continue;
          c = {
            clase_id: 'clase-' + (seq++), nombre: 'Clase ' + cel.hora,
            profesor: 'Por asignar', lugar: 'Sede Tumbao',
            fecha_hora: new Date(`${cel.fecha}T${cel.hora}:00-05:00`).toISOString(),
            duracion_min: 60, precio_cop: 15000, aforo: cel.aforo ?? 30,
            activos_plan: 0, cupo_manual: cel.cupo_manual ?? null,
            cupo_total: cel.cupo_manual ?? cel.aforo ?? 30,
            activa: true,
            _dow: new Date(`${cel.fecha}T12:00:00-05:00`).getUTCDay(), _hora: h
          };
          c.cupos_disponibles = c.cupo_total;
          clases.push(c);
          creadas++;
          continue;
        }
        const tomado = c.cupo_total - c.cupos_disponibles;
        if (cel.activa === false && tomado > 0) {
          avisos.push({ fecha: cel.fecha, hora: cel.hora,
            aviso: `no se apago: ya tiene ${tomado} reserva(s)` });
          continue;
        }
        let manual = cel.cupo_manual;
        if (manual != null && manual < tomado) {
          avisos.push({ fecha: cel.fecha, hora: cel.hora,
            aviso: `se dejo en ${tomado}: ya hay esas reservas, no se puede bajar mas` });
          manual = tomado;
        }
        c.cupo_manual = manual ?? null;
        c.aforo = cel.aforo ?? c.aforo ?? 30;
        c.cupo_total = Math.max(tomado, manual ?? Math.max(c.aforo - (c.activos_plan || 0), 0));
        c.cupos_disponibles = c.cupo_total - tomado;
        c.agotada = c.cupos_disponibles <= 0;
        if (cel.activa === false) { c.activa = false; apagadas++; }
        else { c.activa = true; editadas++; }
      }
      return json(res, 200, { ok: true, creadas, editadas, apagadas, avisos });
    }

    if (que === 'pendientes') {
      const lista = [...reservas.values()]
        .filter(r => r.estado === 'pendiente_validacion' || r.estado === 'verificando')
        // Solo el lider del grupo: las hermanas se resuelven con el.
        .filter(r => !r.grupo || r.grupo === r.codigo)
        .map(r => {
          const c = clases.find(x => x.clase_id === r.clase_id) || {};
          return {
            codigo: r.codigo, nombre: r.nombre || 'Sin nombre',
            telefono: r.telefono || '3000000000', estado: r.estado,
            tipo: r.tipo || 'suelta',
            creada_at: r.creadaAt, clase: r.clase, fecha_hora: c.fecha_hora,
            // Con que agrupar por horario en el panel.
            clase_id: r.clase_id,
            // Lo que declaro quien paga. Sin esto el espejo escondia el
            // "pago otra persona", que es justo lo que explica que el
            // nombre del banco no cuadre con el de la reserva.
            pagado_en:  (r.recibido || {}).pagado_en  || null,
            pagador:    (r.recibido || {}).pagador    || null,
            referencia: (r.recibido || {}).referencia || null,
            precio_cop: c.precio_cop || 15000,
            // Un grupo es UNA tarjeta, con el precio del grupo y los
            // nombres de los demas. Seis tarjetas iguales con el mismo
            // comprobante no son seis decisiones, son una.
            cupos: hermanas(r).length,
            acompanantes: hermanas(r).filter(h => h.codigo !== r.codigo).map(h => h.nombre),
            // Para los DOS estados, como en produccion: admin_pendientes
            // calcula pagos_sueltos por valor y hora, sin mirar el estado
            // de la reserva. Restringirlo a pendiente_validacion escondia
            // el boton "Es este" en la mitad de los casos — y con el
            // escondido, su bug vivio meses sin que ninguna prueba lo
            // tocara.
            // Desde 0032 la lista ya no exige que el valor cuadre: se
            // ofrece lo que haya cerca en el tiempo, marcado. El segundo
            // es el caso real de quien paga dos puestos con un solo
            // giro, que antes no aparecia nunca.
            pagos_sueltos: [{ pago_id: 'pago-1', valor_cop: 15000,
                              fecha: new Date().toISOString(),
                              remitente: 'CAMILA ROJAS PEREZ',
                              cuadra: true, parecido: 0.67, minutos: 3 },
                            { pago_id: 'pago-2', valor_cop: 30000,
                              fecha: new Date().toISOString(),
                              remitente: 'MARTA NIETO',
                              cuadra: false, parecido: 0, minutos: 12 }]
          };
        });
      // La plata que entro al banco y no caso con nadie. Va aparte de la
      // cola: se ve aunque no haya ni una reserva por validar, que es
      // justo el caso que se perdia.
      return json(res, 200, { ok: true, reservas: lista,
        pagos_libres: [{ pago_id: 'pago-suelto-1', valor_cop: 60000,
                         fecha_pago: new Date().toISOString(),
                         remitente: 'Elayne Leonor Jiménez Becerra',
                         cuando: '11/08 15:57' }] });
    }

    if (que === 'tablero') {
      const dia = soloFecha(b.dia) || diaDe(new Date().toISOString());
      const delDia = clases.filter(c => diaDe(c.fecha_hora) === dia);
      const tarjetas = delDia.map(c => {
        const deLaClase = [...reservas.values()].filter(r => r.clase_id === c.clase_id);
        const cuenta = e => deLaClase.filter(r => e.includes(r.estado)).length;
        const confirmadas = cuenta(['confirmada']);
        // El miembro no paga la clase: su plan ya la cubre. Contar todas
        // las confirmadas como plata invento 180.000 el sabado 22.
        const confirmadasDe = t =>
          deLaClase.filter(r => r.estado === 'confirmada' && r.tipo === t).length;
        const porValidar  = cuenta(['pendiente_validacion']);
        const esperando   = cuenta(['pendiente_pago', 'verificando']);
        const aforo    = c.aforo ?? 30;
        const conPlan  = c.activos_plan ?? 0;
        const tomadas  = c.cupo_total - c.cupos_disponibles;
        return {
          clase_id: c.clase_id, nombre: c.nombre,
          hora: String(c._hora).padStart(2, '0') + ':00',
          activa: c.activa !== false,
          ya_paso: new Date(c.fecha_hora) <= new Date(),
          aforo, con_plan: conPlan, a_la_venta: c.cupo_total,
          // Los del plan a los que se les acaba ESE dia. Nunca puede
          // pasarse de con_plan: es un subconjunto.
          vencen: Math.min(c._vencen ?? 0, conPlan),
          reparto: c.cupo_miembros == null ? null : (() => {
            const vivas = t => [...reservas.values()].filter(r =>
              r.clase_id === c.clase_id && r.tipo === t &&
              !['rechazada', 'expirada'].includes(r.estado)).length;
            const m = vivas('miembro'), s = vivas('suelta');
            return {
              miembros_tope: c.cupo_miembros, miembros_tomados: m,
              miembros_libres: Math.max(c.cupo_miembros - m, 0),
              sueltas_tope: c.cupo_sueltas, sueltas_tomadas: s,
              sueltas_libres: Math.max(c.cupo_sueltas - s, 0),
            };
          })(),
          cupo_manual: c.cupo_manual ?? null,
          reservadas: tomadas, libres: Math.max(c.cupos_disponibles, 0),
          confirmadas, por_validar: porValidar, esperando,
          // Cupos apartados sin pagar que ya se pasaron del tiempo y se
          // van a soltar solos. Dos en la de las 7 am, para que la
          // etiqueta tenga algo que enseñar.
          por_soltar: c._primera ? 2 : 0,
          en_sala: conPlan + tomadas,
          // Partidas: el miembro no paga la clase, su plan ya la cubre.
          // Multiplicar TODAS las confirmadas por el precio inventaba
          // 180.000 el sabado 22 de agosto.
          confirmadas_suelta: confirmadasDe('suelta'),
          confirmadas_miembro: confirmadasDe('miembro'),
          ingreso_cop: confirmadasDe('suelta') * (c.precio_cop || 15000)
        };
      }).sort((a, z) => a.hora.localeCompare(z.hora));

      const suma = k => tarjetas.reduce((t, c) => t + (c[k] || 0), 0);
      return json(res, 200, {
        ok: true, dia, es_hoy: dia === diaDe(new Date().toISOString()),
        clases: tarjetas,
        resumen: {
          clases: tarjetas.length, aforo: suma('aforo'), con_plan: suma('con_plan'),
          vencen: suma('vencen'),
          a_la_venta: suma('a_la_venta'), reservadas: suma('reservadas'),
          libres: suma('libres'), confirmadas: suma('confirmadas'),
          confirmadas_suelta: suma('confirmadas_suelta'),
          confirmadas_miembro: suma('confirmadas_miembro'),
          por_validar: suma('por_validar'), esperando: suma('esperando'),
          en_sala: suma('en_sala'), ingreso_cop: suma('ingreso_cop')
        }
      });
    }

    if (que === 'no_vino') {
      const cod = String(b.ref || '').split(':')[1] || '';
      const r = reservas.get(cod.toUpperCase());
      if (!r) return json(res, 400, { ok: false, error: 'NO_EXISTE' });
      if (b.no_vino === false) {
        r.noVino = false; r.venceCredito = null;
        return json(res, 200, { ok: true, no_vino: false, codigo: r.codigo, nombre: r.nombre });
      }
      if (r.estado !== 'confirmada') {
        return json(res, 400, { ok: false, error: 'NO_PAGO',
          mensaje: 'Esa reserva no esta confirmada: no hay clase pagada que guardarle.' });
      }
      if (r.tipo !== 'suelta') {
        return json(res, 400, { ok: false, error: 'ES_MIEMBRO',
          mensaje: 'Quien viene por mensualidad no pierde una clase pagada.' });
      }
      const c0 = clases.find(x => x.clase_id === r.clase_id) || {};
      const vence = new Date(new Date(c0.fecha_hora || Date.now()).getTime() + 3 * 86400000);
      r.noVino = true;
      r.venceCredito = vence.toISOString().slice(0, 10);
      asistencias.delete(r.clase_id + '|r:' + r.codigo);
      return json(res, 200, { ok: true, no_vino: true, codigo: r.codigo,
        nombre: r.nombre, vence: r.venceCredito });
    }

    if (que === 'disfrutar') {
      const hoy = new Date().toISOString().slice(0, 10);
      const gente = [...reservas.values()]
        .filter(r => r.noVino && !r.reprogramadaA && r.estado === 'confirmada'
                     && (r.venceCredito || '') >= hoy)
        .map(r => {
          const c0 = clases.find(x => x.clase_id === r.clase_id) || {};
          return { codigo: r.codigo, nombre: r.nombre, telefono: r.telefono,
                   clase: c0.nombre, clase_id: r.clase_id, fecha_hora: c0.fecha_hora,
                   precio_cop: c0.precio_cop, vence: r.venceCredito,
                   dias: Math.round((new Date(r.venceCredito + 'T12:00:00Z') -
                                     new Date(hoy + 'T12:00:00Z')) / 86400000) };
        })
        .sort((a, z) => String(a.vence).localeCompare(String(z.vence)));
      // Las clases a las que se puede mover a alguien, en la misma
      // respuesta: quien pinta el desplegable no deberia tener que
      // saber como se llaman los campos de otra pantalla.
      const destino = clases
        .filter(c => c.activa !== false && new Date(c.fecha_hora) > new Date()
                     && c.cupos_disponibles > 0)
        .map(c => ({ clase_id: c.clase_id, nombre: c.nombre,
                     fecha_hora: c.fecha_hora, libres: c.cupos_disponibles }))
        .sort((a, z) => new Date(a.fecha_hora) - new Date(z.fecha_hora))
        .slice(0, 40);
      return json(res, 200, { ok: true, gente, clases: destino, hoy });
    }

    if (que === 'reprogramar') {
      const r = reservas.get(String(b.codigo || '').toUpperCase());
      if (!r) return json(res, 400, { ok: false, error: 'NO_EXISTE' });
      if (!r.noVino) return json(res, 400, { ok: false, error: 'NO_TIENE_CREDITO' });
      if (r.reprogramadaA) return json(res, 400, { ok: false, error: 'YA_REPROGRAMADA' });
      const c1 = clases.find(x => x.clase_id === b.clase_id);
      if (!c1) return json(res, 400, { ok: false, error: 'CLASE_INVALIDA' });
      if (c1.clase_id === r.clase_id) return json(res, 400, { ok: false, error: 'MISMA_CLASE' });
      // Un credito no es un pase por encima del aforo.
      if (c1.cupos_disponibles <= 0) {
        return json(res, 400, { ok: false, error: 'SIN_CUPO',
          mensaje: 'Esa clase se lleno. Elige otro horario.' });
      }
      c1.cupos_disponibles--;
      const cod = codigo();
      reservas.set(cod, {
        codigo: cod, tipo: 'suelta', clase: c1.nombre, clase_id: c1.clase_id,
        nombre: r.nombre, telefono: r.telefono, creadaAt: new Date().toISOString(),
        estado: 'confirmada', vieneDe: r.codigo,
        fecha: fmt(c1.fecha_hora, { weekday: 'long', day: 'numeric', month: 'long' }),
        hora: hora12(c1.fecha_hora), pagoEn: null,
      });
      r.reprogramadaA = cod;
      return json(res, 200, { ok: true, codigo: cod, codigo_viejo: r.codigo,
        nombre: r.nombre, clase: c1.nombre });
    }

    if (que === 'lista') {
      const c = clases.find(x => x.clase_id === b.clase_id);
      if (!c) return json(res, 400, { ok: false, error: 'NO_EXISTE' });

      const reservadas = [...reservas.values()]
        .filter(r => r.clase_id === c.clase_id &&
                     !['expirada', 'rechazada'].includes(r.estado))
        .map(r => ({
          ref: 'r:' + r.codigo, codigo: r.codigo,
          nombre: r.nombre, telefono: r.telefono, tipo: r.tipo,
          estado: r.estado, confirmada: r.estado === 'confirmada',
          asistio: asistencias.has(c.clase_id + '|r:' + r.codigo),
          // Pago y no vino: un tercer estado, distinto de "sin marcar".
          no_vino: !!r.noVino, credito_vence: r.venceCredito || null,
          // Apuntada desde el panel. Solo estas se pueden liberar
          // estando ya confirmadas; las de la pagina traen deposito.
          a_mano: r.origen === 'recepcion',
          // Lo que sale de la caja al liberarla, si se cobro en efectivo.
          cobrado_cop: r.cobradoCop || null
        }))
        .sort((a, z) => a.nombre.localeCompare(z.nombre));

      // Entre semana el miembro no reserva: su puesto ya salio del
      // aforo. El sabado no hay planes de esa hora, asi que va vacio.
      const tels = new Set(reservadas.map(r => String(r.telefono || '').replace(/\D/g, '')));
      const conPlan = c._dow === 6 ? [] : Object.entries(MIEMBROS)
        .filter(([tel, hora]) => hora === c._hora && !tels.has(tel))
        .map(([tel]) => ({
          ref: 'p:' + tel, nombre: 'Afiliada ' + tel.slice(-4), telefono: tel,
          membresia: 'PLAN MENSUALIDAD',
          // Una de las de las 6pm vence hoy, para que la etiqueta de la
          // puerta tenga algo que mostrar.
          vence_hoy: c._hora === 18 && tel === '3001111111',
          asistio: asistencias.has(c.clase_id + '|p:' + tel)
        }))
        .sort((a, z) => a.nombre.localeCompare(z.nombre));

      const entraron = [...asistencias].filter(k => k.startsWith(c.clase_id + '|')).length;
      return json(res, 200, {
        ok: true,
        clase: { clase_id: c.clase_id, nombre: c.nombre, fecha: diaDe(c.fecha_hora),
                 hora: String(c._hora).padStart(2, '0') + ':00',
                 aforo: c.aforo ?? 30, ya_paso: new Date(c.fecha_hora) <= new Date() },
        reservas: reservadas, con_plan: conPlan,
        resumen: {
          reservas: reservadas.length, con_plan: conPlan.length,
          esperados: reservadas.length + conPlan.length, entraron,
          sin_confirmar: reservadas.filter(r => !r.confirmada).length
        }
      });
    }

    if (que === 'asistencia') {
      const c = clases.find(x => x.clase_id === b.clase_id);
      if (!c) return json(res, 400, { ok: false, error: 'CLASE_NO_EXISTE' });
      const ref = String(b.ref || '');
      if (!/^[rp]:.+/.test(ref)) return json(res, 400, { ok: false, error: 'REF_INVALIDA' });
      if (ref.startsWith('r:')) {
        const r = reservas.get(ref.slice(2).toUpperCase());
        if (!r || r.clase_id !== c.clase_id) {
          return json(res, 400, { ok: false, error: 'NO_EXISTE',
            mensaje: 'Esa reserva no es de esta clase.' });
        }
      }
      const llave = c.clase_id + '|' + ref;
      // Idempotente: en la puerta se dan clics repetidos y con prisa.
      if (b.asistio !== false) asistencias.add(llave); else asistencias.delete(llave);
      const entraron = [...asistencias].filter(k => k.startsWith(c.clase_id + '|')).length;
      return json(res, 200, { ok: true, ref, asistio: b.asistio !== false, entraron });
    }

    if (que === 'confirmar' || que === 'rechazar') {
      const r = reservas.get(String(b.codigo || '').toUpperCase());
      if (!r) return json(res, 400, { ok: false, error: 'NO_EXISTE' });
      // El rastro para deshacer: de donde venia y cuando se resolvio.
      r.estadoAntes = r.estado;
      r.resueltaAt = Date.now();
      if (que === 'confirmar') {
        r.estado = 'confirmada';
        return json(res, 200, { ok: true, estado: 'confirmada', codigo: r.codigo,
          nombre: r.nombre, telefono: r.telefono || '3001112233',
          se_puede_deshacer: true,
          mensaje: 'Confirmada a mano.' });
      }
      // Una confirmada solo se libera si se apunto a mano. La que cruzo
      // la pagina tiene un deposito detras y se deshace desde la cola.
      if (r.estado === 'confirmada' && r.origen !== 'recepcion') {
        return json(res, 400, { ok: false, error: 'YA_CONFIRMADA',
          mensaje: 'Esa reserva ya esta confirmada y entro por la pagina.' });
      }
      r.estado = 'rechazada';
      asistencias.delete(r.clase_id + '|r:' + r.codigo);
      const c = clases.find(x => x.clase_id === r.clase_id);
      if (c) { c.cupos_disponibles++; c.agotada = false; }
      const devuelto = r.cobradoCop || null;
      r.cobradoCop = null;
      return json(res, 200, { ok: true, estado: 'rechazada', codigo: r.codigo,
        nombre: r.nombre, telefono: r.telefono || '3001112233',
        se_puede_deshacer: true, devuelto_cop: devuelto, aviso_caja: null,
        mensaje: 'Rechazada, el cupo quedo libre.' });
    }

    if (que === 'deshacer') {
      const r = reservas.get(String(b.codigo || '').toUpperCase());
      if (!r) return json(res, 400, { ok: false, error: 'NO_EXISTE' });
      if (r.estado !== 'confirmada' && r.estado !== 'rechazada') {
        return json(res, 400, { ok: false, error: 'NADA_QUE_DESHACER',
          mensaje: 'Esa reserva no esta confirmada ni rechazada.' });
      }
      if (!r.estadoAntes) {
        return json(res, 400, { ok: false, error: 'NO_FUE_A_MANO',
          mensaje: 'Esta se resolvio sola, no desde el panel. No se deshace desde aqui.' });
      }
      const min = Math.floor((Date.now() - r.resueltaAt) / 60000);
      if (min > 15) {
        return json(res, 400, { ok: false, error: 'FUERA_DE_TIEMPO', minutos: min,
          mensaje: `Ya pasaron ${min} minutos. Deshacer solo sirve en los primeros 15.` });
      }
      const c = clases.find(x => x.clase_id === r.clase_id);
      if (r.estado === 'rechazada') {
        // SIN_CUPO_AL_DESHACER=1 fuerza el caso incomodo: mientras se
        // dudaba, alguien compro ese cupo.
        if (SIN_CUPO_AL_DESHACER || (c && c.cupos_disponibles <= 0)) {
          return json(res, 409, { ok: false, error: 'SIN_CUPO',
            mensaje: 'Mientras tanto se vendio ese cupo y la clase quedo llena. '
                   + 'Si hay que meter a esta persona, primero sube el cupo a mano '
                   + 'en la pestana Horario.' });
        }
        if (c) { c.cupos_disponibles--; c.agotada = c.cupos_disponibles <= 0; }
      }
      const volvio = r.estadoAntes;
      r.estado = volvio;
      r.estadoAntes = null;
      r.resueltaAt = null;
      return json(res, 200, { ok: true, codigo: r.codigo, nombre: r.nombre,
        estado: volvio, mensaje: 'Deshecho. Vuelve a la cola tal como estaba.' });
    }

    return json(res, 400, { ok: false, error: 'ruta_desconocida' });
  }

  // ---- GET /tumbao/clases ----
  if (url.pathname === '/webhook/tumbao/clases') {
    const tipo = url.searchParams.get('tipo') === 'miembro' ? 'miembro' : 'suelta';
    const dias = new Map();
    for (const c of clases) {
      const clave = new Intl.DateTimeFormat('en-CA', {
        timeZone: 'America/Bogota', year: 'numeric', month: '2-digit', day: '2-digit',
      }).format(new Date(c.fecha_hora));
      if (!dias.has(clave)) dias.set(clave, {
        fecha: clave,
        etiqueta: fmt(c.fecha_hora, { weekday: 'long', day: 'numeric', month: 'long' }),
        clases: [],
      });
      // El sabado va partido: a cada quien se le muestran los cupos de
      // SU lado, y los del otro ni salen. Asi el reparto es invisible.
      const tope = tipo === 'miembro' ? c.cupo_miembros : c.cupo_sueltas;
      let total = c.cupo_total, libres = c.cupos_disponibles;
      if (tope != null) {
        const tomadas = [...reservas.values()].filter(r =>
          r.clase_id === c.clase_id && r.tipo === tipo &&
          !['rechazada', 'expirada'].includes(r.estado)).length;
        total  = tope;
        libres = Math.max(Math.min(c.cupos_disponibles, tope - tomadas), 0);
      }
      dias.get(clave).clases.push({
        ...c, hora: hora12(c.fecha_hora),
        cupo_total: total, cupos_disponibles: libres, agotada: libres <= 0,
        // Que no se escapen ni por descuido.
        cupo_miembros: undefined, cupo_sueltas: undefined,
      });
    }
    return json(res, 200, { ok: true, timezone: 'America/Bogota', dias: [...dias.values()] });
  }

  // ---- POST /tumbao/reservar ----
  if (url.pathname === '/webhook/tumbao/reservar' && req.method === 'POST') {
    const b = await leerCuerpo(req);
    if ((b.apellido2 || '').trim() !== '') return json(res, 200, { ok: true, codigo: 'OK' });

    const c = clases.find(x => x.clase_id === b.clase_id);
    if (!c) return json(res, 404, { ok: false, error: 'CLASE_NO_EXISTE', mensaje: 'Esa clase ya no está disponible.' });

    const tel = String(b.telefono || '').replace(/\D/g, '');
    const tipo = b.tipo === 'miembro' ? 'miembro' : 'suelta';

    if (tipo === 'miembro') {
      const horaPlan = MIEMBROS[tel];
      if (horaPlan === undefined) {
        return json(res, 404, { ok: false, error: 'MEMBRESIA_NO_ENCONTRADA',
          mensaje: 'No encontramos una mensualidad activa con ese celular. Si crees que es un error escríbenos por WhatsApp; si vienes por clase suelta, elige esa opción.' });
      }
      if (c._dow !== 6) {
        return json(res, 409, horaPlan === c._hora
          ? { ok: false, error: 'PLAN_YA_CUBRE', mensaje: 'Tu plan ya te cubre esta clase, no necesitas reservar. Solo llega 10 minutos antes.' }
          : { ok: false, error: 'OTRO_HORARIO', mensaje: 'Tu plan es de las 6:00 pm. Venir a otra hora entre semana es clase suelta: elige esa opción.' });
      }
    }

    if (c.cupos_disponibles <= 0) {
      return json(res, 409, { ok: false, error: 'SIN_CUPO', mensaje: 'Esa clase se llenó. Elige otro horario.' });
    }
    // El tope de su lado, cuando la clase esta partida. El mensaje es el
    // mismo de siempre a proposito: decir "se acabaron los de afiliados"
    // le contaria al cliente que hay un reparto.
    const tope = tipo === 'miembro' ? c.cupo_miembros : c.cupo_sueltas;
    if (tope != null) {
      const tomadas = [...reservas.values()].filter(r =>
        r.clase_id === c.clase_id && r.tipo === tipo &&
        !['rechazada', 'expirada'].includes(r.estado)).length;
      if (tomadas >= tope) {
        return json(res, 409, { ok: false, error: 'SIN_CUPO',
          mensaje: 'Esa clase se llenó. Elige otro horario.' });
      }
    }
    c.cupos_disponibles--;
    c.agotada = c.cupos_disponibles <= 0;

    const cod = codigo();
    const requierePago = tipo === 'suelta';
    reservas.set(cod, {
      codigo: cod, tipo, clase: c.nombre, clase_id: c.clase_id,
      nombre: String(b.nombre || '').trim(), telefono: tel,
      creadaAt: new Date().toISOString(),
      estado: requierePago ? 'pendiente_pago' : 'confirmada',
      fecha: fmt(c.fecha_hora, { weekday: 'long', day: 'numeric', month: 'long' }),
      hora: hora12(c.fecha_hora), pagoEn: null,
    });
    return json(res, 200, {
      ok: true, tipo, requiere_pago: requierePago,
      estado: requierePago ? 'pendiente_pago' : 'confirmada',
      codigo: cod, clase: c.nombre, profesor: c.profesor, lugar: c.lugar,
      fecha: fmt(c.fecha_hora, { weekday: 'long', day: 'numeric', month: 'long' }),
      hora: hora12(c.fecha_hora), precio_cop: c.precio_cop,
    });
  }

  // ---- POST /api/reservar-varios ----
  // Varios cupos con un solo pago. Cada persona es una fila, todas del
  // mismo grupo, y el total es lo que hay que buscar en el banco.
  if (url.pathname === '/api/reservar-varios' && req.method === 'POST') {
    const b = await leerCuerpo(req);
    if ((b.apellido2 || '').trim() !== '') return json(res, 200, { ok: true, codigo: 'OK' });

    const c = clases.find(x => x.clase_id === b.clase_id);
    if (!c) return json(res, 400, { ok: false, error: 'CLASE_INVALIDA',
      mensaje: 'No se reconoce la clase. Vuelve a elegir el horario.' });

    const nombres = (Array.isArray(b.nombres) ? b.nombres : [])
      .map(n => String(n || '').trim()).filter(Boolean);
    if (nombres.length < 1 || nombres.length > 8) {
      return json(res, 400, { ok: false, error: 'CANTIDAD_INVALIDA',
        mensaje: 'Se pueden reservar entre 1 y 8 cupos a la vez.' });
    }
    // O caben todos o no entra ninguno: medio grupo es lo peor posible.
    if (c.cupos_disponibles < nombres.length) {
      return json(res, 400, { ok: false, error: 'NO_CABEN_TANTOS',
        libres: Math.max(c.cupos_disponibles, 0), pedidos: nombres.length,
        mensaje: `En esa clase solo quedan ${Math.max(c.cupos_disponibles, 0)} cupos, y estás pidiendo ${nombres.length}.` });
    }

    const tel = String(b.telefono || '').replace(/\D/g, '');
    const cods = [];
    for (const nombre of nombres) {
      const cod = codigo();
      cods.push(cod);
      reservas.set(cod, {
        codigo: cod, tipo: 'suelta', clase: c.nombre, clase_id: c.clase_id,
        nombre, telefono: tel, creadaAt: new Date().toISOString(),
        estado: 'pendiente_pago', grupo: cods[0],
        fecha: fmt(c.fecha_hora, { weekday: 'long', day: 'numeric', month: 'long' }),
        hora: hora12(c.fecha_hora), pagoEn: null,
      });
      c.cupos_disponibles--;
    }
    c.agotada = c.cupos_disponibles <= 0;

    return json(res, 200, {
      ok: true, cupos: nombres.length, grupo: nombres.length > 1,
      requiere_pago: true, estado: 'pendiente_pago',
      codigo: cods[0], codigos: cods, nombres,
      clase: c.nombre, profesor: c.profesor, lugar: c.lugar,
      fecha: fmt(c.fecha_hora, { weekday: 'long', day: 'numeric', month: 'long' }),
      hora: hora12(c.fecha_hora),
      precio_cop: c.precio_cop, total_cop: c.precio_cop * nombres.length,
    });
  }

  // ---- POST /tumbao/leer-comprobante ----
  // Imita la lectura de la captura. LECTURA_VACIA=1 fuerza el caso de
  // "no le saco nada", que es el que tiene que dejar a la persona
  // escribiendo los datos a mano sin que se rompa nada.
  if (url.pathname === '/webhook/tumbao/leer-comprobante' && req.method === 'POST') {
    const b = await leerCuerpo(req);
    const img = typeof b.imagen === 'string' ? b.imagen : '';
    if (!/^data:image\/(jpe?g|png|webp);base64,/.test(img)) {
      return json(res, 200, { ok: false, error: 'no_es_imagen',
        hora: null, referencia: null, pagador: null, valor: null, leidos: 0 });
    }
    ultimaLectura = { bytes: img.length };
    if (LECTURA_VACIA) {
      return json(res, 200, { ok: true, hora: null, referencia: null,
        pagador: null, valor: null, leidos: 0 });
    }
    return json(res, 200, {
      ok: true, hora: '18:31', referencia: 'M25418019',
      pagador: LECTURA_OTRO ? 'LUISA GOMEZ MORA' : null,
      valor: 15000, leidos: LECTURA_OTRO ? 3 : 2
    });
  }

  // ---- POST /tumbao/comprobante ----
  if (url.pathname === '/webhook/tumbao/comprobante' && req.method === 'POST') {
    const b = await leerCuerpo(req);
    const r = reservas.get(String(b.codigo || '').toUpperCase());
    if (!r) return json(res, 404, { ok: false, error: 'no_encontrada' });
    // El grupo entero: la persona tiene UN codigo y con el dice que pago
    // por los seis. Si solo se moviera su fila, las otras cinco seguirian
    // esperando pago y se soltarian solas.
    for (const h of hermanas(r)) { h.estado = 'verificando'; h.pagoEn = Date.now(); }
    r.pagoEn = Date.now();
    r.recibido = {
      referencia: b.referencia || null,
      qr: b.qr || null,
      pagado_en: b.pagado_en || null,
      pagador: b.pagador || null,
      archivo: b.archivo ? { nombre: b.archivo.nombre, tipo: b.archivo.tipo,
                             bytes: (b.archivo.base64 || '').length } : null,
    };
    ultimoComprobante = r.recibido;
    return json(res, 200, { ok: true, estado: 'verificando', codigo: r.codigo });
  }

  // ---- GET /tumbao/estado ----
  if (url.pathname === '/webhook/tumbao/estado') {
    const r = reservas.get(String(url.searchParams.get('codigo') || '').toUpperCase());
    if (!r) return json(res, 404, { ok: false, error: 'no_encontrada' });

    if (r.estado === 'verificando' && !NUNCA_LLEGA && r.pagoEn
        && Date.now() - r.pagoEn > RETARDO_BANCO * 1000) {
      for (const h of hermanas(r)) h.estado = 'confirmada';
    }
    if (url.searchParams.get('vencido') === '1' && r.estado === 'verificando') {
      r.estado = 'pendiente_validacion';
    }
    const mensajes = {
      confirmada: 'Pago confirmado. Tu cupo está asegurado.',
      verificando: 'Estamos esperando la confirmación del banco.',
      pendiente_validacion: 'Recibimos tu comprobante. Alguien del equipo lo valida y te escribimos por WhatsApp.',
    };
    return json(res, 200, { ok: true, estado: r.estado, codigo: r.codigo,
      clase: r.clase, fecha: r.fecha, hora: r.hora, mensaje: mensajes[r.estado] || '' });
  }

  if (url.pathname === '/_prueba/ultimo-comprobante') {
    return json(res, 200, { ok: true, ultimo: ultimoComprobante });
  }

  // Vuelve al estado del arranque. Sin esto, correr la misma suite dos
  // veces seguidas falla por los restos de la primera, y el fallo no se
  // parece en nada a su causa.
  // Siembra una reserva apuntada a mano y ya cobrada en efectivo. Es la
  // unica forma de tener una en el espejo: el panel apunta contra
  // /api/reserva, que vive en el Worker y aqui no se imita.
  //
  // Existe para poder probar en un navegador algo que solo se ve alli:
  // que el boton "Liberar" SI salga en las de mostrador aunque esten
  // confirmadas, y NO en las que entraron por la pagina.
  // Un sabado con las dos cosas: miembros que reservan —solo pasa ese
  // dia, porque el aforo va partido en dos mitades— y sueltas que si
  // pagan. Es el caso donde el tablero decia COBRADO 285.000 cuando lo
  // cobrado eran 105.000.
  if (url.pathname === '/_prueba/sabado-mixto') {
    const c = clases.find(x => x._dow === 6 && x._hora === 8);
    if (!c) return json(res, 400, { ok: false, error: 'sin_sabado' });
    for (const [t, n] of [['miembro', 12], ['suelta', 7]]) {
      for (let i = 0; i < n; i++) {
        const cod = codigo();
        reservas.set(cod, {
          codigo: cod, tipo: t, clase: c.nombre, clase_id: c.clase_id,
          nombre: `${t === 'miembro' ? 'Afiliada' : 'Suelta'} ${i + 1}`,
          telefono: '30099900' + String(i).padStart(2, '0'),
          creadaAt: new Date().toISOString(), estado: 'confirmada',
          origen: 'formulario',
          fecha: fmt(c.fecha_hora, { weekday: 'long', day: 'numeric', month: 'long' }),
          hora: hora12(c.fecha_hora), pagoEn: null,
        });
      }
    }
    c.cupos_disponibles = Math.max(c.cupo_total - 19, 0);
    return json(res, 200, { ok: true, dia: diaDe(c.fecha_hora),
                            clase_id: c.clase_id });
  }

  if (url.pathname === '/_prueba/apuntar-a-mano') {
    const c = clases.find(x => x.clase_id === url.searchParams.get('clase'))
           || clases[0];
    const cod = codigo();
    reservas.set(cod, {
      codigo: cod, tipo: 'suelta', clase: c.nombre, clase_id: c.clase_id,
      nombre: url.searchParams.get('nombre') || 'Mostrador Efectivo',
      telefono: '3007770000', creadaAt: new Date().toISOString(),
      estado: 'confirmada', origen: 'recepcion',
      cobradoCop: Number(url.searchParams.get('cobrado') ?? 15000) || null,
      fecha: fmt(c.fecha_hora, { weekday: 'long', day: 'numeric', month: 'long' }),
      hora: hora12(c.fecha_hora), pagoEn: null,
    });
    c.cupos_disponibles--;
    return json(res, 200, { ok: true, codigo: cod, clase_id: c.clase_id });
  }

  if (url.pathname === '/_prueba/reiniciar') {
    sembrarClases();
    reservas.clear();
    asistencias.clear();
    ultimoComprobante = null;
    sembrarSesiones();
    sembrarCuentas();
    seqUsuario = 4;
    return json(res, 200, { ok: true, clases: clases.length });
  }

  json(res, 404, { ok: false, error: 'no_existe' });
}).listen(PUERTO, () => console.log(`espejo api en http://localhost:${PUERTO}`));
