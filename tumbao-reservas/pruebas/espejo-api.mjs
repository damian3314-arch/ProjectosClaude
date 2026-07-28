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
const clases = [];
let seq = 1;
for (let n = 1; n <= 7; n++) {
  const dow = dowBogota(n);
  const horas = dow === 6 ? [[8, 'Clase 8:00 am'], [9, 'Clase 9:00 am']]
              : dow === 0 ? []
              : [[7, 'Clase 7:00 am'], [18, 'Clase 6:00 pm'], [19, 'Clase 7:00 pm']];
  for (const [h, nombre] of horas) {
    const libres = dow === 6 ? 30 : (h === 18 ? 4 : h === 7 ? 11 : 14);
    clases.push({
      clase_id: 'clase-' + (seq++),
      nombre, profesor: 'Kevin', lugar: 'Sede Tumbao',
      fecha_hora: enDias(n, h).toISOString(),
      duracion_min: 60, precio_cop: 15000,
      cupo_total: libres, cupos_disponibles: libres, agotada: libres <= 0,
      // Lo que ve el panel: los cupos salen de aforo − gente con plan.
      activa: true, aforo: 30, activos_plan: 30 - libres, cupo_manual: null,
      _dow: dow, _hora: h,
    });
  }
}
// Una agotada para comprobar que se deshabilita.
clases[1].cupos_disponibles = 0;
clases[1].agotada = true;

// Token del panel. En la vida real lo emite Supabase y se guarda hasheado;
// aqui es fijo para poder probar.
const TOKEN_ADMIN = process.env.TOKEN_ADMIN || 'token-de-prueba';

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

const MIEMBROS = { '3001111111': 18 };   // celular -> hora de su plan
const reservas = new Map();
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
    let html = readFileSync(join(WEB, 'index.html'), 'utf8')
      .replace(/N8N_BASE:\s*'[^']*'/, `N8N_BASE: 'http://localhost:${PUERTO}/webhook'`);
    if (MINUTOS_ESPERA) html = html.replace(/MINUTOS_ESPERA:\s*[\d.]+/, `MINUTOS_ESPERA: ${MINUTOS_ESPERA}`);
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    return res.end(html);
  }
  if (url.pathname === '/admin' || url.pathname === '/admin.html') {
    const html = readFileSync(join(WEB, 'admin.html'), 'utf8')
      .replace(/N8N_BASE:\s*'[^']*'/, `N8N_BASE: 'http://localhost:${PUERTO}/webhook'`);
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    return res.end(html);
  }
  if (url.pathname.startsWith('/js/')) {
    try {
      res.writeHead(200, { 'Content-Type': 'application/javascript; charset=utf-8' });
      return res.end(readFileSync(join(WEB, url.pathname)));
    } catch { res.writeHead(404); return res.end(); }
  }
  if (url.pathname.startsWith('/img/')) {
    try {
      res.writeHead(200, { 'Content-Type': 'image/png' });
      return res.end(readFileSync(join(WEB, url.pathname)));
    } catch { res.writeHead(404); return res.end(); }
  }

  // ---- panel de admin ----
  if (url.pathname.startsWith('/webhook/tumbao/admin/') && req.method === 'POST') {
    const b = await leerCuerpo(req);
    if (b.token !== TOKEN_ADMIN) {
      return json(res, 401, { ok: false, error: 'NO_AUTORIZADO' });
    }
    const que = url.pathname.split('/').pop();

    if (que === 'semana') {
      const dias = [];
      for (let i = 0; i < 7; i++) {
        const f = sumaDias(b.desde, i);
        dias.push({
          fecha: f,
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
        .map(r => {
          const c = clases.find(x => x.clase_id === r.clase_id) || {};
          return {
            codigo: r.codigo, nombre: r.nombre || 'Sin nombre',
            telefono: r.telefono || '3000000000', estado: r.estado,
            creada_at: r.creadaAt, clase: r.clase, fecha_hora: c.fecha_hora,
            precio_cop: c.precio_cop || 15000,
            pagos_sueltos: r.estado === 'pendiente_validacion'
              ? [{ pago_id: 'pago-1', valor_cop: 15000, fecha: new Date().toISOString(),
                   remitente: 'CAMILA ROJAS PEREZ', parecido: 0.67, minutos: 3 }]
              : []
          };
        });
      return json(res, 200, { ok: true, reservas: lista });
    }

    if (que === 'confirmar' || que === 'rechazar') {
      const r = reservas.get(String(b.codigo || '').toUpperCase());
      if (!r) return json(res, 400, { ok: false, error: 'NO_EXISTE' });
      if (que === 'confirmar') {
        r.estado = 'confirmada';
        return json(res, 200, { ok: true, estado: 'confirmada', codigo: r.codigo,
          nombre: r.nombre, telefono: r.telefono || '3001112233',
          mensaje: 'Confirmada a mano.' });
      }
      r.estado = 'rechazada';
      const c = clases.find(x => x.clase_id === r.clase_id);
      if (c) { c.cupos_disponibles++; c.agotada = false; }
      return json(res, 200, { ok: true, estado: 'rechazada', codigo: r.codigo,
        nombre: r.nombre, telefono: r.telefono || '3001112233',
        mensaje: 'Rechazada, el cupo quedo libre.' });
    }

    return json(res, 400, { ok: false, error: 'ruta_desconocida' });
  }

  // ---- GET /tumbao/clases ----
  if (url.pathname === '/webhook/tumbao/clases') {
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
      dias.get(clave).clases.push({ ...c, hora: hora12(c.fecha_hora) });
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

  // ---- POST /tumbao/comprobante ----
  if (url.pathname === '/webhook/tumbao/comprobante' && req.method === 'POST') {
    const b = await leerCuerpo(req);
    const r = reservas.get(String(b.codigo || '').toUpperCase());
    if (!r) return json(res, 404, { ok: false, error: 'no_encontrada' });
    r.estado = 'verificando';
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
      r.estado = 'confirmada';
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

  json(res, 404, { ok: false, error: 'no_existe' });
}).listen(PUERTO, () => console.log(`espejo api en http://localhost:${PUERTO}`));
