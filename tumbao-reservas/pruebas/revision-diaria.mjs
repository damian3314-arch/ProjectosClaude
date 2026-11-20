/**
 * ¿Está bien tumbaobaila.com? — la revisión de todos los días.
 *
 * PARA QUÉ
 * Todo lo que se ha roto en este proyecto se rompió en silencio, y nos
 * enteramos tarde y de casualidad: la semana que no abrió, los cupos
 * ofrecidos que ya tenían dueño, el reporte del lunes que llevaba cinco
 * días sin salir. Esto pregunta por esas cosas antes de que la gente
 * empiece a reservar.
 *
 * SIN LLAVES
 * Ninguna comprobación necesita token. El grueso lo calcula el propio
 * Worker en /salud, que solo devuelve cuentas: ni un nombre, ni un
 * teléfono, ni una cifra de caja. Así esto se puede correr desde
 * cualquier sitio sin cargar con un secreto.
 *
 *   node pruebas/revision-diaria.mjs
 *
 * Sale con código 0 si todo está bien y 1 si algo falla, para que quien
 * lo dispare pueda distinguirlo sin leer el texto.
 */

// Se pueden apuntar a otro sitio con variables de entorno. No es por
// flexibilidad: es para poder comprobar que esta revisión sabe ponerse
// en ROJO. Una que solo ha dado verde no ha demostrado nada.
const PAGINA = process.env.TUMBAO_PAGINA || 'https://tumbaobaila.com/';
const WORKER = process.env.TUMBAO_WORKER || 'https://tumbao-caja.damian3314.workers.dev';
const OPINA  = process.env.TUMBAO_OPINA  || 'https://opina.tumbaobaila.com/';

const mal = [];
const bien = [];

const apunta = (ok, que, detalle) => {
  (ok ? bien : mal).push({ que, detalle });
  console.log(`${ok ? '✓' : '✗'} ${que}${detalle ? '  → ' + detalle : ''}`);
};

/* Se pide con curl y no con fetch a propósito.
 *
 * En entornos con proxy de salida —el contenedor donde corre esto es
 * uno— el fetch de Node lo ignora y devuelve 403 en todo. La primera
 * vez que se corrió esta revisión dio las cinco comprobaciones en rojo
 * con la página perfectamente sana: exactamente la falsa alarma que
 * hace que una revisión diaria se deje de mirar. curl respeta las
 * variables de proxy sin configurar nada.
 *
 * Una caída de red tampoco es lo mismo que una página rota, así que
 * cuando no se puede ni preguntar se dice con esas palabras.
 */
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
const correr = promisify(execFile);

const SEPARADOR = '<<<CUERPO>>>';

const pedir = async (url, opciones = {}) => {
  const args = ['-s', '-m', '30', '-w', `\n${SEPARADOR}%{http_code}`, url];
  for (const [k, v] of Object.entries(opciones.headers || {})) {
    args.push('-H', `${k}: ${v}`);
  }
  // Solo hacen falta las cabeceras cuando se pregunta por el CORS.
  if (opciones.cabeceras) args.push('-D', '-');
  try {
    const { stdout } = await correr('curl', args, { maxBuffer: 20 * 1024 * 1024 });
    const corte = stdout.lastIndexOf(SEPARADOR);
    const status = Number(stdout.slice(corte + SEPARADOR.length).trim());
    const cuerpo = stdout.slice(0, corte);
    if (!status) return { error: 'no hubo respuesta' };
    return { status, texto: cuerpo, crudo: stdout };
  } catch (e) {
    return { error: String((e && e.message) || e).split('\n')[0] };
  }
};

console.log('\n── La página ──');

{
  const { status, texto, error } = await pedir(PAGINA);
  if (error) apunta(false, 'la página carga', `no se pudo preguntar: ${error}`);
  else {
    apunta(status === 200, 'la página carga', `HTTP ${status}`);

    // Si alguien revierte esta línea, las reservas vuelven a gastar plan
    // de n8n sin que nada se rompa a la vista. Es justo el tipo de cosa
    // que solo se descubre cuando llega el correo del límite.
    const alWorker = texto.includes(`API_BASE:  '${WORKER}/tumbao'`);
    apunta(alWorker, 'las reservas van por el Worker, no por n8n',
           alWorker ? 'API_BASE apunta al Worker'
                    : 'API_BASE ya NO apunta al Worker — revisa docs/index.html');
  }
}

console.log('\n── El fondo ──');

{
  const { status, texto, error } = await pedir(`${WORKER}/salud`);
  if (error) {
    apunta(false, 'el Worker responde', `no se pudo preguntar: ${error}`);
  } else if (status !== 200) {
    apunta(false, 'el Worker responde', `HTTP ${status}`);
  } else {
    let d = {};
    try { d = JSON.parse(texto); } catch (_) { d = {}; }
    if (!Array.isArray(d.revisiones)) {
      apunta(false, 'el Worker responde', 'contestó algo que no se entiende');
    } else {
      for (const v of d.revisiones) apunta(v.ok, v.que, v.detalle);
    }
  }
}

console.log('\n── Lo de al lado ──');

{
  // El CORS es el fallo más difícil de ver desde fuera: la página carga
  // perfecta y sale vacía, porque el navegador tira la respuesta y quien
  // mira desde la terminal no se entera de nada.
  const { status, crudo, error } = await pedir(`${WORKER}/tumbao/clases?tipo=suelta`,
    { headers: { Origin: 'https://tumbaobaila.com' }, cabeceras: true });
  if (error) apunta(false, 'el horario se puede pedir desde la página', error);
  else {
    const m = /access-control-allow-origin:\s*(\S+)/i.exec(crudo || '');
    const permiso = m ? m[1] : null;
    apunta(status === 200 && !!permiso,
           'el horario se puede pedir desde la página',
           `HTTP ${status} · permiso: ${permiso || 'NINGUNO'}`);
  }
}

{
  const { status, error } = await pedir(OPINA);
  if (error) apunta(false, 'el bot de opiniones responde', error);
  else apunta(status === 200, 'el bot de opiniones responde', `HTTP ${status}`);
}

console.log('');
if (!mal.length) {
  // Una sola línea cuando no pasa nada. Una revisión que escribe tres
  // párrafos todos los días se deja de leer, y entonces no sirve el día
  // que sí pasa algo.
  const clases = bien.find((b) => /clases que reservar/.test(b.que));
  const semana = bien.find((b) => /semana entrante/.test(b.que));
  console.log('TODO BIEN' +
    (clases ? ` · ${clases.detalle}` : '') +
    (semana ? ` · ${semana.detalle}` : ''));
  process.exit(0);
}

console.log(`${mal.length} COSA(S) MAL:`);
for (const m of mal) console.log(`  · ${m.que} — ${m.detalle}`);
process.exit(1);
