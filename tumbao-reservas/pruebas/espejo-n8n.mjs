/**
 * Servidor espejo de los workflows de n8n.
 * NO reimplementa la lógica: extrae el jsCode real de los .json de los
 * workflows y lo ejecuta, contra el Postgres real. Si esto pasa, n8n pasa.
 */
import { createServer } from 'node:http';
import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const RAIZ = join(dirname(fileURLToPath(import.meta.url)), '..');
const DIR  = join(RAIZ, 'n8n');

// Conexión al Postgres de pruebas. Ajusta a tu entorno.
const PG = (process.env.PG_ARGS || '-h /tmp -p 55432 -U postgres -d postgres').split(' ');
const wf = f => JSON.parse(readFileSync(`${DIR}/${f}`, 'utf8'));
const WF_DISP = wf('01-tumbao-disponibilidad.json');
const WF_RES  = wf('02-tumbao-reservar.json');

const codeOf = (w, nombre) => {
  const n = w.nodes.find(x => x.name === nombre);
  if (!n) throw new Error(`nodo no encontrado: ${nombre}`);
  return n.parameters.jsCode;
};

/** Ejecuta un Code node de n8n con el shim mínimo de $input. */
function runCode(js, items) {
  const $input = { first: () => items[0], all: () => items };
  return new Function('$input', js)($input);
}

/** psql -> JSON. El payload va por :'payload', que psql escapa bien. */
function sql(query, payload) {
  const args = [...PG, '-X','-A','-t','-q'];
  if (payload !== undefined) args.push('-v', `payload=${JSON.stringify(payload)}`);
  // la query va por stdin: psql solo interpola :'var' fuera de -c
  const r = spawnSync('psql', args, { encoding: 'utf8', input: query });
  if (r.status !== 0) throw new Error(r.stderr || 'psql fallo');
  const out = r.stdout.trim();
  return out ? JSON.parse(out) : null;
}

const json = (res, code, obj) => {
  res.writeHead(code, {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': '*',
    'Access-Control-Allow-Methods': 'GET,POST,OPTIONS'
  });
  res.end(JSON.stringify(obj));
};

createServer(async (req, res) => {
  const url = new URL(req.url, 'http://x');

  if (req.method === 'OPTIONS') return json(res, 204, {});

  // ---- página estática ----
  if (url.pathname === '/' || url.pathname === '/index.html') {
    const html = readFileSync(join(RAIZ, 'web', 'index.html'), 'utf8')
      .replace('PEGA_AQUI_TU_URL_DE_N8N/webhook', 'http://localhost:8899/webhook');
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    return res.end(html);
  }

  try {
    // ---- workflow 1 ----
    if (url.pathname === '/webhook/tumbao/disponibilidad') {
      const query = Object.fromEntries(url.searchParams);
      const p = runCode(codeOf(WF_DISP, 'Parámetros'), [{ json: { query } }]);

      const filas = sql(
        `SELECT COALESCE(json_agg(x),'[]') FROM (
           SELECT sesion_id, clase, estilo, nivel, instructor, start_at, end_at,
                  cupo_total, cupos_disponibles, timezone
             FROM v_disponibilidad
            WHERE tenant_slug = (:'payload'::jsonb->>0)
              AND start_at < NOW() + ((:'payload'::jsonb->>1) || ' days')::INTERVAL
            ORDER BY start_at) x;`,
        [p[0].json.slug, p[0].json.dias]
      );

      const out = runCode(codeOf(WF_DISP, 'Agrupar por día'), filas.map(f => ({ json: f })));
      return json(res, 200, out[0].json);
    }

    // ---- workflow 2 ----
    if (url.pathname === '/webhook/tumbao/reservar' && req.method === 'POST') {
      const body = JSON.parse(await new Promise(ok => {
        let b = ''; req.on('data', c => b += c); req.on('end', () => ok(b || '{}'));
      }));

      const norm = runCode(codeOf(WF_RES, 'Normalizar entrada'), [{ json: { body } }]);
      const n = norm[0].json;

      if (n.es_bot) {                                    // rama "¿Es bot?" = true
        const s = runCode(codeOf(WF_RES, 'Señuelo'), norm);
        return json(res, s[0].json.http_status, s[0].json);
      }

      const r = sql(
        `SELECT json_build_object('r', crear_reserva(
            :'payload'::jsonb->>0, (:'payload'::jsonb->>1)::bigint,
            :'payload'::jsonb->>2, :'payload'::jsonb->>3, :'payload'::jsonb->>4,
            :'payload'::jsonb->>5, (:'payload'::jsonb->>6)::boolean, 'web'));`,
        [n.slug, n.sesion_id, n.first_name, n.last_name, n.phone, n.email, n.habeas_data]
      );

      if (r.r.ok) {                                      // rama "¿Quedó reservada?" = true
        const c = runCode(codeOf(WF_RES, 'Armar confirmación'), [{ json: r }]);
        // el nodo de WhatsApp está desactivado -> n8n deja pasar los datos
        return json(res, 200, c[0].json);
      }
      const e = runCode(codeOf(WF_RES, 'Mapear error'), [{ json: r }]);
      return json(res, e[0].json.http_status, e[0].json);
    }
  } catch (err) {
    console.error('[mock] ', err);
    return json(res, 500, { ok: false, error: 'mock_fallo', mensaje: String(err) });
  }

  json(res, 404, { ok: false, error: 'no_existe' });
}).listen(8899, () => console.log('espejo n8n en http://localhost:8899'));
