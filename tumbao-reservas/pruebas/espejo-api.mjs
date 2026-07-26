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
      _dow: dow, _hora: h,
    });
  }
}
// Una agotada para comprobar que se deshabilita.
clases[1].cupos_disponibles = 0;
clases[1].agotada = true;

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
    let html = readFileSync(join(RAIZ, 'web', 'index.html'), 'utf8')
      .replace(/N8N_BASE:\s*'[^']*'/, `N8N_BASE: 'http://localhost:${PUERTO}/webhook'`);
    if (MINUTOS_ESPERA) html = html.replace(/MINUTOS_ESPERA:\s*[\d.]+/, `MINUTOS_ESPERA: ${MINUTOS_ESPERA}`);
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    return res.end(html);
  }
  if (url.pathname.startsWith('/img/')) {
    try {
      res.writeHead(200, { 'Content-Type': 'image/png' });
      return res.end(readFileSync(join(RAIZ, 'web', url.pathname)));
    } catch { res.writeHead(404); return res.end(); }
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

  json(res, 404, { ok: false, error: 'no_existe' });
}).listen(PUERTO, () => console.log(`espejo api en http://localhost:${PUERTO}`));
