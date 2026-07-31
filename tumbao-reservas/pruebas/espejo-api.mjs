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
      const libres = dow === 6 ? 30 : (h === 18 ? 4 : h === 7 ? 11 : 14);
      clases.push({
        clase_id: 'clase-' + (seq++),
        nombre, profesor: 'Kevin', lugar: 'Sede Tumbao',
        fecha_hora: enDias(n, h).toISOString(),
        duracion_min: 60, precio_cop: 15000,
        cupo_total: libres, cupos_disponibles: libres, agotada: libres <= 0,
        // Lo que ve el panel: los cupos salen de aforo − gente con plan.
        activa: true, aforo: 30, activos_plan: 30 - libres, cupo_manual: null,
        // A dos de las 6pm se les acaba el plan ese dia. Sirve para que
        // el aviso punteado del tablero tenga algo que mostrar.
        _vencen: h === 18 ? 2 : 0,
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
            pagos_sueltos: r.estado === 'pendiente_validacion'
              ? [{ pago_id: 'pago-1', valor_cop: 15000, fecha: new Date().toISOString(),
                   remitente: 'CAMILA ROJAS PEREZ', parecido: 0.67, minutos: 3 }]
              : []
          };
        });
      return json(res, 200, { ok: true, reservas: lista });
    }

    if (que === 'tablero') {
      const dia = soloFecha(b.dia) || diaDe(new Date().toISOString());
      const delDia = clases.filter(c => diaDe(c.fecha_hora) === dia);
      const tarjetas = delDia.map(c => {
        const deLaClase = [...reservas.values()].filter(r => r.clase_id === c.clase_id);
        const cuenta = e => deLaClase.filter(r => e.includes(r.estado)).length;
        const confirmadas = cuenta(['confirmada']);
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
          en_sala: conPlan + tomadas,
          ingreso_cop: confirmadas * (c.precio_cop || 15000)
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
          por_validar: suma('por_validar'), esperando: suma('esperando'),
          en_sala: suma('en_sala'), ingreso_cop: suma('ingreso_cop')
        }
      });
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
          asistio: asistencias.has(c.clase_id + '|r:' + r.codigo)
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
      r.estado = 'rechazada';
      const c = clases.find(x => x.clase_id === r.clase_id);
      if (c) { c.cupos_disponibles++; c.agotada = false; }
      return json(res, 200, { ok: true, estado: 'rechazada', codigo: r.codigo,
        nombre: r.nombre, telefono: r.telefono || '3001112233',
        se_puede_deshacer: true,
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

  // Vuelve al estado del arranque. Sin esto, correr la misma suite dos
  // veces seguidas falla por los restos de la primera, y el fallo no se
  // parece en nada a su causa.
  if (url.pathname === '/_prueba/reiniciar') {
    sembrarClases();
    reservas.clear();
    asistencias.clear();
    ultimoComprobante = null;
    return json(res, 200, { ok: true, clases: clases.length });
  }

  json(res, 404, { ok: false, error: 'no_existe' });
}).listen(PUERTO, () => console.log(`espejo api en http://localhost:${PUERTO}`));
