/**
 * La opinión que se cierra la pestaña — prueba
 *
 * EL CASO
 * El 21 de agosto una clienta contestó las tres preguntas —«Los extraño
 * muchoooo de lunes a viernes 😭», «Trabajooo», «Que es lo mejor de lo
 * mejor 😃»— y cerró la pestaña. /api/cerrar, que era el único sitio
 * donde se escribía el resumen, no se llamó nunca. En el correo del
 * lunes salió como «Sin nombre · (sin resumen)»: la dueña vio una fila
 * vacía donde había una clienta contenta.
 *
 * LO QUE SE MIDE
 * Que eso no pueda volver a pasar. La prueba hace lo que hizo ella
 * —abrir, contestar, irse— y después pide el reporte del lunes. Si sus
 * palabras no están ahí, falla.
 *
 * Se corre contra el Worker de verdad y una SQLite de verdad con el
 * schema.sql de verdad; ver pruebas/entorno-falso.mjs.
 *
 *   node pruebas/no-se-pierde.test.mjs
 */
import worker from '../src/index.js';
import {
  entorno, chat, reporte, callarHace, abrirLeer, postear, CONV,
} from './entorno-falso.mjs';

let fallos = 0;
const ok = (n, c, extra = '') => {
  console.log(`  ${c ? '\x1b[32mv\x1b[0m' : '\x1b[31mx\x1b[0m'} ${n}${extra ? '  → ' + extra : ''}`);
  if (!c) fallos++;
};

const ELLA = 'Los extraño muchoooo de lunes a viernes 😭';

console.log('\n-- 1. Contesta una pregunta y cierra la pestaña -------------');
{
  const { env } = entorno();
  const c = chat(worker, env);
  await c.abrir();
  await c.escribir(ELLA);
  // Y aquí se va. No hay /api/cerrar. Nunca lo hubo.

  const filas = await reporte(worker, env);
  ok('la conversación llega al reporte', filas.length === 1, `${filas.length} filas`);
  ok('con lo que dijo, legible', String(filas[0]?.resumen || '').includes('Los extraño muchoooo'),
     JSON.stringify(filas[0]?.resumen));
  ok('y no como "(sin resumen)"', !/sin resumen/i.test(String(filas[0]?.resumen)));
}

console.log('\n-- 2. Aunque el modelo esté caído ---------------------------');
// El requisito duro no puede depender de que Workers AI conteste. Sin
// modelo no hay ficha, pero las palabras de la persona son suyas y ya
// están escritas.
{
  const { env } = entorno({ conModelo: false });
  const c = chat(worker, env);
  await c.abrir();
  await c.escribir(ELLA);

  const filas = await reporte(worker, env);
  ok('sigue llegando sin modelo de por medio', filas.length === 1);
  ok('con su frase entera', String(filas[0]?.resumen).includes('de lunes a viernes'),
     JSON.stringify(filas[0]?.resumen));
}

console.log('\n-- 3. Las tres respuestas, sin cerrar -----------------------');
{
  const { env } = entorno();
  const c = chat(worker, env);
  await c.abrir();
  await c.escribir(ELLA);
  await c.escribir('Trabajooo');
  await c.escribir('Que es lo mejor de lo mejor 😃');

  const filas = await reporte(worker, env);
  const r = String(filas[0]?.resumen || '');
  ok('no se pierde ninguna de las tres',
     r.includes('Los extraño') && r.includes('Trabajooo') && r.includes('lo mejor de lo mejor'),
     JSON.stringify(r.slice(0, 90)));
  ok('la conversación entera queda guardada',
     String(filas[0]?.turnos) === '4', `turnos=${filas[0]?.turnos}`);
}

console.log('\n-- 4. El barrido le saca ficha de verdad --------------------');
// La capa 1 deja las palabras crudas. Cuando ya está claro que nadie va
// a escribir más, el barrido las convierte en ficha: tipo, nombre, si es
// urgente. Eso es lo que se lee el lunes de un vistazo.
{
  const { env, base } = entorno({ tipo: 'elogio', nombre: 'Marcela' });
  const c = chat(worker, env);
  await c.abrir();
  await c.escribir(ELLA);
  callarHace(base, 45);            // se fue hace tres cuartos de hora

  const filas = await reporte(worker, env);
  ok('el resumen pasa a ser el del modelo',
     String(filas[0]?.resumen).startsWith('Ficha del modelo'), filas[0]?.resumen);
  ok('sin perder lo que dijo', String(filas[0]?.resumen).includes('Los extraño muchoooo'));
  ok('y ya tiene tipo', filas[0]?.tipo === 'elogio', String(filas[0]?.tipo));
  ok('y nombre, si lo dio', filas[0]?.nombre === 'Marcela', String(filas[0]?.nombre));
  ok('pero NO se marca como completa: no lo está',
     Number(filas[0]?.completa) === 0, `completa=${filas[0]?.completa}`);
}

console.log('\n-- 5. Una queja abandonada sí levanta la alerta -------------');
// Antes, quien contaba algo grave y cerraba la pestaña no aparecía como
// urgente en ninguna parte: no había ficha, y sin ficha no hay alerta.
{
  const { env, base } = entorno({ tipo: 'queja', urgente: true });
  const c = chat(worker, env);
  await c.abrir();
  await c.escribir('Un profesor me hizo sentir mal delante de toda la clase');
  callarHace(base, 45);

  const filas = await reporte(worker, env);
  ok('queda marcada para mirar hoy', Number(filas[0]?.urgente) === 1,
     `urgente=${filas[0]?.urgente}`);
  ok('con su motivo', Boolean(filas[0]?.motivo_urgente), String(filas[0]?.motivo_urgente));
}

console.log('\n-- 6. Quien solo abrió y se fue no ensucia el reporte -------');
{
  const { env, base } = entorno();
  const c = chat(worker, env);
  await c.abrir();                 // solo el saludo del bot
  callarHace(base, 45);

  const filas = await reporte(worker, env);
  ok('no aparece', filas.length === 0, `${filas.length} filas`);
}

console.log('\n-- 7. Al que sigue escribiendo no se le corta la ficha ------');
// Si Tania abre /leer mientras alguien está contestando, el barrido no
// puede darle esa conversación por terminada.
{
  const { env } = entorno();
  const c = chat(worker, env);
  await c.abrir();
  await c.escribir(ELLA);          // hace un segundo, no 30 minutos

  const filas = await reporte(worker, env);
  ok('todavía no se le saca ficha', filas[0]?.tipo === null, String(filas[0]?.tipo));
  ok('pero lo que dijo ya está guardado',
     String(filas[0]?.resumen).includes('Los extraño'));
}

console.log('\n-- 8. Recargar la pestaña no borra lo ya contado ------------');
// La página guarda la historia en memoria: al recargar, vuelve a empezar
// con el mismo id de conversación pero sin nada. Si el Worker escribiera
// esa historia corta encima de la larga, la primera mitad se perdería.
{
  const { env } = entorno({ conModelo: false });
  const c = chat(worker, env);
  await c.abrir();
  await c.escribir(ELLA);
  c.recargar();
  await c.abrir();
  await c.escribir('Trabajooo');

  const filas = await reporte(worker, env);
  ok('lo de antes de recargar sigue ahí',
     String(filas[0]?.resumen).includes('Los extraño'), JSON.stringify(filas[0]?.resumen));
}

console.log('\n-- 9. Rescatar lo que ya estaba perdido ---------------------');
// Las conversaciones de antes de este arreglo tienen resumen, tipo y
// transcripción en NULL, pero sus mensajes sí están en `mensajes`. El
// barrido las lee de ahí: es la clienta del 21 de agosto.
{
  const { env, base } = entorno();
  const viejo = new Date(Date.now() - 8 * 86400000).toISOString();
  base.crudo.prepare(
    `insert into conversaciones (id, empezada_at, turnos) values (?1, ?2, 4)`
  ).run(CONV, viejo);
  for (const [de, texto] of [
    ['bot', '¡Hola! Somos Tumbao'], ['persona', ELLA],
    ['bot', '¿Y si dejaras de venir?'], ['persona', 'Trabajooo'],
  ]) {
    base.crudo.prepare(
      `insert into mensajes (conversacion, de, texto, medio, creado_at)
       values (?1, ?2, ?3, 'texto', ?4)`
    ).run(CONV, de, texto, viejo);
  }

  const filas = await reporte(worker, env);
  ok('la fila vacía se llena sola', Boolean(filas[0]?.resumen), String(filas[0]?.resumen));
  ok('con sus dos respuestas',
     String(filas[0]?.resumen).includes('Los extraño') &&
     String(filas[0]?.resumen).includes('Trabajooo'));
  // El reporte del lunes no se lleva la transcripción a propósito —son
  // ladrillos de texto dentro del correo—, pero tiene que quedar
  // guardada para poder abrirla en /leer.
  const guardada = base.crudo.prepare(
    'select transcripcion from conversaciones where id = ?1').get(CONV);
  ok('y con la conversación entera para leerla',
     String(guardada?.transcripcion || '').includes('> Trabajooo'),
     JSON.stringify(String(guardada?.transcripcion || '').slice(0, 60)));
}

console.log('\n-- 10. Y se lee en /leer, no solo en el correo --------------');
{
  const { env, base } = entorno({ conModelo: false });
  const c = chat(worker, env);
  await c.abrir();
  await c.escribir(ELLA);
  callarHace(base, 45);

  const { estado, html } = await abrirLeer(worker, env, env.TOKEN_REPORTE);
  ok('la página abre', estado === 200, String(estado));
  ok('y enseña lo que dijo', html.includes('Los extraño muchoooo'));
  ok('marcada como cortada', html.includes('se cortó'));
}

console.log('\n-- 11. El camino de siempre no se rompió --------------------');
// Quien sí llega al final tiene que seguir quedando como completa.
{
  const { env } = entorno({ tipo: 'elogio', nombre: 'Marcela' });
  const c = chat(worker, env);
  await c.abrir();
  await c.escribir(ELLA);
  await c.escribir('Trabajooo');
  await c.escribir('Que es lo mejor de lo mejor 😃');
  await c.escribir('Marcela, 3001234567');
  await c.cerrarBien();

  const filas = await reporte(worker, env);
  ok('queda marcada como completa', Number(filas[0]?.completa) === 1);
  ok('con la ficha del modelo', String(filas[0]?.resumen).startsWith('Ficha del modelo'));
  ok('y el barrido no la vuelve a tocar', filas[0]?.nombre === 'Marcela');
}

console.log('\n-- 12. Nadie sin llave ve nada de esto ----------------------');
{
  const { env } = entorno();
  const c = chat(worker, env);
  await c.abrir();
  await c.escribir(ELLA);
  const d = await postear(worker, env, '/api/pendientes', { token: 'la-que-no-es' });
  ok('el reporte pide su llave', d.estado === 401, String(d.estado));
  const { estado } = await abrirLeer(worker, env, 'la-que-no-es');
  ok('y la pantalla también', estado === 401, String(estado));
}

console.log(`\n${fallos === 0 ? '\x1b[32mtodo en verde\x1b[0m' : `\x1b[31m${fallos} FALLOS\x1b[0m`}\n`);
process.exit(fallos ? 1 : 0);
