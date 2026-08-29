/**
 * Un Cloudflare de mentiras, para poder probar el Worker de verdad.
 *
 * POR QUÉ EXISTE
 * Las otras pruebas llaman funciones sueltas (`limpiarFicha`,
 * `loQueSeAnaliza`). Eso no alcanza para lo que se rompió el 21 de
 * agosto: ahí no falló ninguna función, falló que /api/cerrar nunca se
 * llamó. Para probar eso hay que hacer lo mismo que hace la persona
 * —abrir el chat, contestar, cerrar la pestaña— y después pedir el
 * reporte. O sea, hay que correr el Worker entero.
 *
 * La base es SQLite de verdad (node:sqlite, viene con Node) con el
 * schema.sql de verdad. Si el SQL que se escribe en src/index.js está
 * mal, aquí revienta igual que reventaría en D1. Un mapa en memoria
 * fingiendo ser una base habría dado pruebas verdes con SQL roto.
 *
 * Esto NO es una prueba: es el andamio de las que sí lo son.
 */
import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';

// node:sqlite todavía avisa de que es experimental en cada arranque. El
// aviso no le dice nada a quien corre las pruebas y tapa el resultado.
process.removeAllListeners('warning');
process.on('warning', (w) => { if (w.name !== 'ExperimentalWarning') console.warn(w); });

const SCHEMA = readFileSync(new URL('../schema.sql', import.meta.url), 'utf8');

/* La cara de D1 que usa el Worker: prepare().bind().run() / .all().
 * Nada más, porque nada más se usa. */
export function abrirBase() {
  const db = new DatabaseSync(':memory:');
  db.exec(SCHEMA);

  return {
    crudo: db,
    prepare(sql) {
      const st = db.prepare(sql);
      let args = [];
      const api = {
        bind(...a) { args = a; return api; },
        async run() { st.run(...args); return { success: true }; },
        async all() { return { results: st.all(...args) }; },
        async first() { return st.get(...args) ?? null; },
      };
      return api;
    },
  };
}

/* Envejecer los mensajes para simular "esta persona cerró la pestaña
 * hace rato". El barrido solo toca conversaciones calladas hace 30
 * minutos, justamente para no sacarle la ficha a alguien que todavía
 * está escribiendo. */
export function callarHace(base, minutos) {
  const cuando = new Date(Date.now() - minutos * 60000).toISOString();
  base.crudo.prepare('update mensajes set creado_at = ?1').run(cuando);
}

/* El modelo, fingido. Devuelve lo mismo que Workers AI: un objeto con
 * `response`. Distingue por el system con el que se le llama, que es
 * como el Worker distingue sus tres usos. */
export function modeloFalso(opciones = {}) {
  const llamadas = [];
  const run = async (modelo, args) => {
    const system = String(args.messages?.[0]?.content || '');
    const ultimo = String(args.messages?.[args.messages.length - 1]?.content || '');
    llamadas.push({ modelo, system, ultimo });

    if (system.startsWith('Te paso una conversación')) {
      const suyas = ultimo.split('\n').filter((l) => l.startsWith('CLIENTE: '))
        .map((l) => l.slice(9));
      return { response: JSON.stringify({
        nombre: opciones.nombre ?? null,
        telefono: null,
        tipo: opciones.tipo || 'elogio',
        resumen: `Ficha del modelo: «${suyas.join(' / ')}»`,
        urgente: Boolean(opciones.urgente),
        motivo: opciones.urgente ? 'algo grave' : null,
      }) };
    }

    if (system.startsWith('Eres el analista')) {
      return { response: JSON.stringify({
        titular: 'La gente extraña las clases entre semana',
        claves: [{ titulo: 'Horario', detalle: 'Piden más días.', cuantos: '2 de 2' }],
        critico: null, cita: 'Los extraño muchoooo',
      }) };
    }

    return { response: opciones.respuesta || 'Qué bueno leer eso. ¿Y qué más?' };
  };

  return { AI: { run }, llamadas };
}

/* El entorno del Worker. `conModelo: false` es el caso que más importa
 * probar: sin modelo no hay ficha, y aun así lo que la persona escribió
 * tiene que llegar al reporte del lunes. */
export function entorno({ conModelo = true, ...resto } = {}) {
  const base = abrirBase();
  const modelo = conModelo ? modeloFalso(resto) : null;
  return {
    base,
    modelo,
    env: {
      DB: base,
      TOKEN_REPORTE: 'llave-de-prueba',
      ...(modelo ? { AI: modelo.AI } : {}),
    },
  };
}

// El Worker guarda el análisis de la semana en la caché de Cloudflare.
// Aquí se finge una que nunca acierta, para que cada prueba salga de
// cero y no herede el resultado de la anterior.
globalThis.caches = globalThis.caches || {
  default: { match: async () => undefined, put: async () => {} },
};

/* ── mandarle cosas al Worker como lo hace la página ── */

export const CONV = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';

export async function postear(worker, env, ruta, cuerpo) {
  const r = await worker.fetch(new Request(`https://opina.tumbao${ruta}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(cuerpo),
  }), env, { waitUntil() {} });
  return { estado: r.status, cuerpo: await r.json() };
}

export async function abrirLeer(worker, env, token) {
  const r = await worker.fetch(
    new Request(`https://opina.tumbao/leer?token=${token}`), env, { waitUntil() {} });
  return { estado: r.status, html: await r.text() };
}

/* Una conversación como la vive la página: mantiene su propia `historia`
 * en memoria y se la manda al Worker en cada turno, igual que el
 * navegador. Lo importante es lo que NO hace: no llama a /api/cerrar
 * salvo que se le pida. Cerrar la pestaña es, exactamente, dejar de
 * llamar. */
export function chat(worker, env, id = CONV) {
  const historia = [];
  return {
    id,
    historia,
    async abrir() {
      const d = await postear(worker, env, '/api/mensaje',
        { conversacion: id, historia, texto: '' });
      historia.push({ role: 'assistant', content: d.cuerpo.respuesta });
      return d.cuerpo;
    },
    async escribir(texto) {
      const d = await postear(worker, env, '/api/mensaje',
        { conversacion: id, historia, texto, medio: 'texto' });
      historia.push({ role: 'user', content: texto });
      historia.push({ role: 'assistant', content: d.cuerpo.respuesta });
      return d.cuerpo;
    },
    // La pestaña se recarga: la página pierde la historia y vuelve a
    // pedir el saludo con el mismo id de conversación.
    recargar() { historia.length = 0; },
    async cerrarBien() {
      return postear(worker, env, '/api/cerrar', { conversacion: id, historia });
    },
  };
}

export async function reporte(worker, env) {
  const d = await postear(worker, env, '/api/pendientes', { token: env.TOKEN_REPORTE });
  return d.cuerpo.conversaciones || [];
}
