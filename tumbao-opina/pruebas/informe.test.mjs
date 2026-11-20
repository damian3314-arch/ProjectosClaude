/**
 * El informe de la encuesta (2 nov): de las conversaciones a un plan de acción, sin pasar nombres al modelo ni inflar números.
 *   node informe.test.mjs
 */
import { entorno } from './entorno-falso.mjs';

// Una caché que sí guarda, para probar el avance por tandas.
const memoria = new Map();
globalThis.caches = { default: {
  match: async (req) => { const v = memoria.get(req.url); return v ? new Response(v) : undefined; },
  put: async (req, res) => { memoria.set(req.url, await res.text()); },
} };
const worker = (await import('../src/index.js')).default;

let fallos = 0;
const ok = (n, c, extra = '') => { if (!c) fallos++; console.log(`${c ? '\x1b[32mv\x1b[0m' : '\x1b[31mx\x1b[0m'} ${n}${extra ? '  → ' + extra : ''}`); };
const titulo = (t) => console.log(`\n-- ${t} ${'-'.repeat(Math.max(0, 52 - t.length))}`);

const INFORME_FALSO = {
  resumen: 'La gente quiere más horarios.',
  ya: [{ que: 'Alguien se sintió expuesto', por_que: 'Trato', que_hacer: 'Hablar con los profes' }],
  aman: [{ tema: 'El ambiente', detalle: 'Confianza', cuantos: '999 de 12 personas', cita: 'Me siento bien' }],
  cambiar: [{ tema: 'Horarios', detalle: 'Más', cuantos: '3 de 12 personas', cita: '', gravedad: 'alta' }],
  fuga: [{ razon: 'Tiempo', cuantos: 'varias', cita: '' }],
  atencion: { hallazgos: ['Responden lento'], arreglos: ['Un mensaje claro'] },
  deseos: [{ idea: 'Domingo', cuantos: '2 de 12 personas', cita: '' }],
  acciones: [{ area: 'Operación', accion: 'Probar una clase más', por_que: 'La piden', plazo: '30 días', impacto: 'alto', esfuerzo: 'bajo', metrica: 'Asistencia', responsable: 'dueño' },
             { area: 'Inventada', accion: 'Algo', por_que: '', plazo: 'nunca', impacto: 'enorme', esfuerzo: 'x', metrica: '', responsable: '' }],
  estrategia: { tesis: 'Sin pena y más fácil', pilares: [{ titulo: 'Sin pena', detalle: 'x' }], mensajes: ['Tu hora para ti'] },
  limites: 'Son 12 personas.',
};

function montar(n) {
  const { base, env } = entorno({ conModelo: false });
  const vistos = { sistemas: [], datos: [] };
  env.AI = { run: async (_m, args) => {
    const sistema = String(args.messages[0].content);
    vistos.sistemas.push(sistema.slice(0, 40)); vistos.datos.push(String(args.messages[1].content));
    if (sistema.includes('hasta 40 conversaciones')) return { response: JSON.stringify({ personas: 40, temas: [{ categoria: 'cambiar', tema: 'Horarios', detalle: 'Más', personas: 9, gravedad: 'alta', citas: ['Un domingo'] }], urgentes: [] }) };
    return { response: JSON.stringify(INFORME_FALSO) };
  } };
  for (let i = 0; i < n; i++) {
    const id = `c${i}`;
    base.crudo.prepare(`insert into conversaciones (id, nombre, telefono, tipo, resumen, urgente, motivo_urgente, transcripcion, turnos, empezada_at, completa, tema)
      values (?, ?, ?, 'mixto', ?, ?, ?, '', 6, ?, 1, 'escuchamos')`)
      .run(id, i === 0 ? 'Marcela' : null, i === 0 ? '3001234567' : null, 'resumen ' + i, i === 0 ? 1 : 0, i === 0 ? 'Se sintió expuesta' : null, '2026-11-05T10:0' + (i % 10) + ':00.000Z');
    base.crudo.prepare("insert into mensajes (conversacion, de, texto, medio, creado_at) values (?, 'persona', ?, 'texto', ?)")
      .run(id, i === 0 ? 'Me llamo Marcela, mi cel es 300 123 4567 y quiero más horarios' : 'Quiero más horarios', '2026-11-05T10:00:00.000Z');
  }
  return { env, vistos };
}
const pedir = async (env, q) => {
  const r = await worker.fetch(new Request('https://opina.tumbao/informe?' + q), env, { waitUntil() {} });
  return { estado: r.status, html: await r.text() };
};

titulo('1. Acceso');
{
  const { env } = montar(0);
  const sin = await pedir(env, 'token=mala');
  ok('sin la llave de verdad no abre', sin.estado === 401);
  const demo = await pedir(env, 'token=llave-de-prueba&demo=1');
  ok('con demo=1 se ve el informe de ejemplo, marcado como ejemplo', demo.estado === 200 && /EJEMPLO/.test(demo.html) && /Plan de acción/.test(demo.html));
  const pocas = await pedir(env, 'token=llave-de-prueba');
  ok('con muy pocas respuestas dice que todavía no hay suficientes', /Todavía no hay suficientes respuestas/.test(pocas.html));
}

titulo('2. Con respuestas');
{
  const { env, vistos } = montar(12);
  const r = await pedir(env, 'token=llave-de-prueba');
  ok('arma el informe con todas sus secciones', r.estado === 200 && ['Lo urgente', 'Lo que más aman', 'Plan de acción', 'Estrategia 2027', 'Casos para atender'].every((t) => r.html.includes(t)));
  ok('baja a 12 el «999 de 12 personas» que se inventó el modelo', /12 de 12 personas/.test(r.html) && !/999/.test(r.html));
  ok('un área o un plazo inventados caen en uno válido', !/Inventada/.test(r.html) && !/nunca/.test(r.html));
  ok('al modelo no le viajan nombres ni teléfonos', !vistos.datos.some((d) => /Marcela|3001234567|300 123/.test(d)) && vistos.datos.some((d) => /\[número\]/.test(d)));
  ok('el caso urgente sí enseña el contacto que la persona dejó, para atenderla', /Marcela/.test(r.html) && /3001234567/.test(r.html));
  ok('trae la matriz de impacto y esfuerzo', /Hacer primero/.test(r.html) && /Pensarlo bien/.test(r.html));
  ok('con pocas respuestas avisa que hay que leerlo con cuidado', /hay que leerlo con cuidado/.test(r.html));
  const antes = vistos.datos.length;
  await pedir(env, 'token=llave-de-prueba');
  ok('abrir otra vez no vuelve a llamar al modelo (caché)', vistos.datos.length === antes);
}

titulo('3. Muchas respuestas: por tandas, sin pasarse');
{
  memoria.clear();
  const { env, vistos } = montar(85);
  const uno = await pedir(env, 'token=llave-de-prueba');
  ok('la primera visita resume una tanda y se recarga sola', /Analizando… 1 de 4/.test(uno.html) && /http-equiv="refresh"/.test(uno.html), uno.html.match(/Analizando[^<]*/)?.[0]);
  await pedir(env, 'token=llave-de-prueba');
  await pedir(env, 'token=llave-de-prueba');
  const fin = await pedir(env, 'token=llave-de-prueba');
  ok('al terminar las tandas, escribe el informe', /Plan de acción/.test(fin.html), fin.html.match(/<h1>[^<]*/)?.[0]);
  ok('el final recibe resúmenes de tandas, no las 85 conversaciones', vistos.datos.at(-1).includes('"modo":"parciales"') && vistos.datos.at(-1).length < 6000);
}

console.log(`\n${fallos ? '\x1b[31m' + fallos + ' fallo(s)\x1b[0m' : '\x1b[32mtodo en verde\x1b[0m'}`);
process.exit(fallos ? 1 : 0);
