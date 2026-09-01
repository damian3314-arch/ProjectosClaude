/* ---------------------------------------------------------------------
 * tumbao-correo — el buzón de pagos@tumbaobaila.com
 *
 * POR QUÉ EXISTE
 * n8n cobra por ejecución y la ingesta de pagos —leer las alertas de
 * Bancolombia del correo— se llevaba más de la mitad del plan ella sola:
 * n8n sondea Gmail y cada correo que encuentra es una ejecución.
 *
 * La idea es darle la vuelta: en vez de ir a buscar el correo, que el
 * correo llegue solo. Gmail reenvía las alertas del banco a
 * pagos@tumbaobaila.com, Cloudflare las entrega aquí, y aquí se
 * procesan. Cloudflare Email Routing no cobra por correo recibido.
 *
 * POR QUÉ UN WORKER APARTE Y NO DENTRO DE tumbao-caja
 * tumbao-caja es lo que mantiene viva la página: horarios, reservas,
 * comprobantes. Meterle un manejador de correo nuevo y a medio probar
 * arriesga lo único que no se puede caer. Cuando esto esté rodado se
 * puede juntar; hoy no.
 *
 * EN QUÉ VA — MODO ESPEJO
 * Hoy este Worker LEE Y ENTIENDE los correos pero NO escribe nada en
 * Supabase. Guarda lo que HABRÍA registrado, para poder compararlo con
 * lo que registró n8n sobre los mismos correos.
 *
 * No es prudencia de adorno, son dos razones concretas:
 *
 *   1. Mientras n8n también ingiere, escribir aquí duplicaría pagos. El
 *      índice único que protege la tabla es sobre `hoja_fila`, y ahí
 *      n8n guarda el id de la API de Gmail mientras que aquí solo se
 *      tiene el Message-ID del correo: son distintos, así que el índice
 *      NO los cruzaría. Los dos caminos no pueden estar vivos a la vez;
 *      el cambio tiene que ser un relevo, no una convivencia.
 *
 *   2. Falta cerrar quién puede escribir aquí. Esta dirección es
 *      adivinable y el parser solo mira el texto: cualquiera que mande
 *      un correo imitando una alerta del banco podría registrar un pago
 *      que no existe y confirmar una reserva que nadie pagó. El filtro
 *      de remitente hay que escribirlo contra las cabeceras REALES de un
 *      correo reenviado por el filtro de Gmail, no contra las que uno
 *      se imagina. Ver `remitenteDeFiar()`.
 *
 * Para el relevo (cuando ya se haya visto una alerta real llegar por el
 * filtro y esté cerrado el punto 2):
 *   1. escribir el filtro de remitente de verdad
 *   2. `npx wrangler secret put SUPABASE_SERVICE_KEY`
 *   3. poner la variable REGISTRAR = "1"
 *   4. apagar el disparador de Gmail del workflow "Tumbao · Ingesta de
 *      pagos" en n8n, en el mismo momento
 *
 * LO QUE SE GUARDA, Y POR QUÉ CADUCA
 * Aquí caen alertas del banco: montos, nombres de quien paga y los
 * últimos cuatro dígitos de la cuenta. Eso no puede quedarse en un KV
 * para siempre. Se guarda 7 días, que es de sobra para depurar, y se
 * borra solo.
 * ------------------------------------------------------------------- */

import { textoDelCorreo, remitenteReal, cabecera } from './mime.js';
// OJO: se importa el parser que ya vive en el repo, no una copia.
// Ese archivo es la fuente de verdad y lo cubren las 16 pruebas de
// tumbao-reservas/pruebas/parser.test.js. Copiarlo aquí sería garantizar
// que un día los dos digan cosas distintas.
import { parsearCorreoBancolombia } from '../../tumbao-reservas/n8n/parser-bancolombia.js';

const DIAS_QUE_SE_GUARDA = 7;

// De dónde salen de verdad las alertas. Bancolombia usa las dos según
// el tipo de aviso; con una sola se perdería la mitad.
const REMITENTES_DEL_BANCO = [
  'alertasynotificaciones@an.notificacionesbancolombia.com',
  'alertasynotificaciones@bancolombia.com.co',
];

/**
 * ¿Este correo se puede creer?
 *
 * POR QUÉ HACE FALTA
 * pagos@tumbaobaila.com es una dirección adivinable y el parser solo
 * mira el texto. Sin esta comprobación, cualquiera que mande un correo
 * imitando una alerta del banco registraría un pago que no existe y
 * confirmaría una reserva que nadie pagó. Hay una prueba que lo
 * demuestra a propósito en pruebas/mime.test.mjs.
 *
 * LAS DOS CONDICIONES, Y POR QUÉ LAS DOS
 *
 *   1. Que el From: sea una de las direcciones de alerta de
 *      Bancolombia. Gmail, al reenviar por filtro, conserva el From
 *      original — no lo envuelve como sí hace un reenvío a mano.
 *
 *   2. Que Cloudflare diga spf=pass. Esta es la que aguanta el peso:
 *      el From se escribe solo, lo pone quien manda. La cabecera
 *      Authentication-Results la escribe Cloudflare al recibir el
 *      correo, comprobando que el servidor que lo entrega esté
 *      autorizado por el dominio del remitente.
 *
 * Con la 1 sola, falsificar esto sería escribir una línea de texto. Con
 * las dos, hay que además controlar un servidor autorizado por el
 * dominio del banco o de Google.
 *
 * OJO CON DE DÓNDE SE LEEN
 * Se leen del bloque de cabeceras, nunca del correo entero. Ver
 * bloqueDeCabeceras() en mime.js: si se busca por expresión regular
 * sobre todo el texto, un correo puede escribir en su CUERPO su propia
 * línea "Authentication-Results: spf=pass" y firmarse el certificado a
 * sí mismo. Eso pasaba y está arreglado.
 *
 * X-Forwarded-For (que Gmail pone al reenviar) se anota pero NO cuenta:
 * cualquiera puede escribirla en un correo suyo.
 */
export function remitenteDeFiar(crudo, deSobre) {
  const from = remitenteReal(crudo, deSobre);
  const autor = String(cabecera(crudo, 'Authentication-Results') || '');
  const reenviadoPor = String(cabecera(crudo, 'X-Forwarded-For') || '');

  const delBanco = REMITENTES_DEL_BANCO.includes(from);
  const spf = /spf=pass/i.test(autor);
  const dkim = /dkim=pass/i.test(autor);

  return {
    from,
    del_banco: delBanco,
    spf,
    dkim,
    reenviado_por: reenviadoPor || null,
    // Ante la duda, no. Un falso positivo confirma una reserva que
    // nadie pagó; un falso negativo solo deja el pago en la cola de
    // validación humana, que es el camino de respaldo previsto.
    se_puede_creer: delBanco && spf,
    por_que: !delBanco
      ? 'el From no es una direccion de alerta de Bancolombia'
      : !spf
        ? 'Cloudflare no dio spf=pass'
        : 'ok',
  };
}

function json(datos, estado = 200) {
  return new Response(JSON.stringify(datos, null, 2), {
    status: estado,
    headers: {
      'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': 'no-store',
    },
  });
}

function conLlave(url, env) {
  return Boolean(env.LLAVE_BUZON) && url.searchParams.get('llave') === env.LLAVE_BUZON;
}

export default {
  /* ── llega un correo ─────────────────────────────────────────────
   * No se rechaza nada ni se responde: un rebote a Bancolombia no
   * sirve de nada y un rebote a Gmail podría hacer que Google apague
   * el reenvío. Lo que no se entienda se guarda igual y ya se mirará.
   *
   * Todo va dentro de un try: si el parser se cae con un correo raro,
   * lo que NO puede pasar es perder el correo. Se guarda el fallo y se
   * sigue.
   */
  async email(message, env, ctx) {
    let crudo = '';
    try {
      crudo = await new Response(message.raw).text();
    } catch (_) {
      crudo = '';
    }

    // El Message-ID es lo que evitará registrar dos veces el mismo pago:
    // si el correo se entrega dos veces, el identificador es el mismo.
    const idMensaje = message.headers.get('message-id') || null;

    let texto = '';
    let analisis = null;
    let procedencia = null;
    let fallo = null;
    try {
      texto = textoDelCorreo(crudo);
      analisis = parsearCorreoBancolombia(texto);
      procedencia = remitenteDeFiar(crudo, message.from);
    } catch (e) {
      fallo = String(e && e.message ? e.message : e).slice(0, 300);
    }

    const registro = {
      de: message.from,
      para: message.to,
      asunto: message.headers.get('subject') || '',
      message_id: idMensaje,
      recibido_at: new Date().toISOString(),
      // Recortado: una alerta del banco cabe de sobra, y así un correo
      // con adjuntos raros no llena el almacén.
      texto: crudo.slice(0, 60000),
      texto_limpio: texto.slice(0, 4000),
      procedencia,
      analisis,
      fallo,
      // Mientras esto diga "espejo", en Supabase no se tocó nada.
      modo: env.REGISTRAR === '1' ? 'registrando' : 'espejo',
    };

    await env.BUZON.put(
      `correo:${Date.now()}:${crypto.randomUUID().slice(0, 8)}`,
      JSON.stringify(registro),
      { expirationTtl: 60 * 60 * 24 * DIAS_QUE_SE_GUARDA }
    );

    // El relevo todavía no está dado. Cuando lo esté, aquí va la llamada
    // a registrar_pago_y_conciliar() — y no antes, por lo que dice la
    // cabecera de este archivo.
  },

  /* ── leer lo que llegó ───────────────────────────────────────────
   * Con llave, siempre. Aquí hay nombres de clientes y montos.
   */
  async fetch(request, env) {
    const url = new URL(request.url);

    if (url.pathname === '/salud') {
      return json({
        ok: true,
        buzon: 'pagos@tumbaobaila.com',
        modo: env.REGISTRAR === '1' ? 'registrando' : 'espejo',
      });
    }

    if (url.pathname === '/ultimos' || url.pathname === '/parseos') {
      if (!conLlave(url, env)) return json({ ok: false, error: 'no_autorizado' }, 401);

      const lista = await env.BUZON.list({ prefix: 'correo:' });
      const claves = lista.keys.map((k) => k.name).sort().reverse().slice(0, 20);
      const correos = [];
      for (const c of claves) {
        const v = await env.BUZON.get(c, 'json');
        if (v) correos.push({ clave: c, ...v });
      }

      // Lo que el Worker HABRÍA registrado, sin los cuerpos de los
      // correos. Es la vista para comparar contra lo que hizo n8n.
      if (url.pathname === '/parseos') {
        return json({
          ok: true,
          modo: env.REGISTRAR === '1' ? 'registrando' : 'espejo',
          correos: correos.map((c) => ({
            recibido_at: c.recibido_at,
            de: c.de,
            asunto: c.asunto,
            message_id: c.message_id,
            procedencia: c.procedencia,
            analisis: c.analisis,
            fallo: c.fallo,
          })),
        });
      }

      return json({ ok: true, cuantos: correos.length, correos });
    }

    return json({ ok: false, error: 'no_existe' }, 404);
  },
};
