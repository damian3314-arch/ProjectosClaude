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
 * EN QUÉ VA — EN PRODUCCIÓN DESDE EL 1 DE SEPTIEMBRE DE 2026
 * Este Worker es el que registra los pagos del banco. El disparador de
 * Gmail del workflow "Tumbao · Ingesta de pagos" quedó APAGADO en el
 * mismo movimiento, y tiene que seguir así.
 *
 * POR QUÉ NO PUEDEN CONVIVIR
 * El índice único que protege la tabla es sobre `hoja_fila`. n8n guarda
 * ahí el id de la API de Gmail; aquí va el Message-ID del correo. Son
 * valores distintos, así que el índice NO los cruza: con los dos
 * caminos vivos, el mismo pago entraría dos veces. Volver atrás es
 * quitar la variable REGISTRAR y reactivar aquel nodo, otra vez en un
 * solo movimiento.
 *
 * LO QUE SE COMPROBÓ ANTES DE DAR EL RELEVO
 *   · 3 de 3 alertas reales parseadas igual que n8n, campos idénticos,
 *     incluido el caso sin llave (referencia null en ambos)
 *   · el Worker las recibió antes que n8n las tres veces
 *   · el filtro de remitente acertó contra cabeceras reales de un
 *     correo reenviado por el filtro de Gmail
 *   · la llave de Supabase, con /salud?hondo=1 antes de apagar nada
 *
 * QUIÉN PUEDE ESCRIBIR AQUÍ
 * Esta dirección es adivinable y el parser solo mira el texto, así que
 * sin filtro cualquiera podría registrar un pago que no existe y
 * confirmar una reserva que nadie pagó. Lo cierra `remitenteDeFiar()`:
 * exige que el From sea del banco Y que Cloudflare haya dado spf=pass.
 *
 * SI ESTO SE MUERE
 * No falla nada visible: la página sigue tomando reservas y la gente
 * sigue pagando, simplemente nadie se confirma. Por eso el panel avisa
 * cuando alguien que ya dijo que pagó lleva más de 30 minutos esperando
 * (ver pintarPulso en docs/admin.html).
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

/**
 * Registrar el pago en Supabase y cruzarlo con la reserva que lo espera.
 *
 * Es lo mismo que hacen los nodos "Registrar y conciliar" y "Barrer lo
 * que quedó a medias" del workflow de n8n, con los mismos parámetros. La
 * decisión de confirmar NO vive aquí: vive dentro de
 * registrar_pago_y_conciliar() en Postgres, que bloquea la fila y, si
 * hay dos reservas que encajan con el mismo monto, no adivina — manda a
 * validación humana.
 *
 * p_hoja_fila es el Message-ID del correo, y es lo que hace que esto sea
 * repetible: la función hace `on conflict (hoja_fila) do nothing`, así
 * que si Cloudflare entrega el mismo correo dos veces, el pago se
 * registra una.
 *
 * OJO CON EL RELEVO: n8n manda ahí el id de la API de Gmail, que es OTRO
 * valor. Mientras los dos caminos estén vivos, el índice no los cruza y
 * el mismo pago entraría dos veces. Por eso encender esto y apagar el
 * disparador de Gmail de n8n es un solo movimiento, no dos.
 */
async function registrarPago(env, analisis, idMensaje, textoLimpio) {
  const llamar = async (funcion, cuerpo) => {
    const r = await fetch(`${env.SUPABASE_URL}/rest/v1/rpc/${funcion}`, {
      method: 'POST',
      headers: {
        apikey: env.SUPABASE_SERVICE_KEY,
        Authorization: `Bearer ${env.SUPABASE_SERVICE_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(cuerpo),
    });
    const texto = await r.text();
    if (!r.ok) throw new Error(`${funcion} ${r.status}: ${texto.slice(0, 200)}`);
    try { return JSON.parse(texto); } catch (_) { return {}; }
  };

  const resultado = await llamar('registrar_pago_y_conciliar', {
    p_banco: analisis.banco,
    p_valor_cop: analisis.valor_cop,
    p_fecha_pago: analisis.fecha_pago,
    p_referencia: analisis.llave,
    p_remitente: analisis.remitente,
    p_ultimos_4: analisis.ultimos_4,
    p_confianza: analisis.confianza,
    p_raw_email: String(textoLimpio || '').slice(0, 4000),
    p_hoja_fila: idMensaje,
  });

  // Reintenta cruzar las reservas que siguen esperando sin depósito. Si
  // falla, el pago ya quedó registrado y eso es lo que no se puede
  // perder, así que no se propaga el error.
  let barrido = null;
  try {
    barrido = await llamar('conciliar_pendientes', {});
  } catch (e) {
    barrido = { error: String(e && e.message ? e.message : e).slice(0, 200) };
  }

  return { resultado, barrido };
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

    // SOLO SE GUARDA EL CUERPO DE LO QUE VIENE DEL BANCO.
    //
    // De lo demás se deja una ficha sin cuerpo: de quién, qué asunto y
    // por qué se descartó. Suficiente para saber si el reenvío está
    // funcionando, sin quedarse con el correo de nadie.
    //
    // Esto es lo que hace viable reenviar TODO el correo de Tumbao aquí
    // en vez de depender de un filtro de Gmail. El filtro es un punto de
    // fallo silencioso —si se desconfigura no avisa, simplemente deja de
    // reenviar, que es exactamente lo que pasó el 31 de agosto—, y
    // ademas ya hay un filtro mejor de este lado: remitenteDeFiar()
    // exige que el From sea del banco Y que Cloudflare diera spf=pass.
    const delBanco = Boolean(procedencia && procedencia.se_puede_creer);

    const registro = {
      de: message.from,
      para: message.to,
      asunto: message.headers.get('subject') || '',
      message_id: idMensaje,
      recibido_at: new Date().toISOString(),
      procedencia,
      fallo,
      // Mientras esto diga "espejo", en Supabase no se tocó nada.
      modo: env.REGISTRAR === '1' ? 'registrando' : 'espejo',
      ...(delBanco
        ? {
            // Recortado: una alerta del banco cabe de sobra, y así un
            // correo con adjuntos raros no llena el almacén.
            texto: crudo.slice(0, 60000),
            texto_limpio: texto.slice(0, 4000),
            analisis,
          }
        : { descartado: true }),
    };

    const clave = `correo:${Date.now()}:${crypto.randomUUID().slice(0, 8)}`;
    await env.BUZON.put(clave, JSON.stringify(registro),
      { expirationTtl: 60 * 60 * 24 * DIAS_QUE_SE_GUARDA });

    // Registrar de verdad, solo si se dan LAS TRES:
    //   · el interruptor está puesto (relevo dado, n8n apagado)
    //   · el correo se puede creer (From del banco + spf=pass)
    //   · y es dinero ENTRANDO
    //
    // El orden importa: el correo se guarda ANTES de registrar. Si
    // Supabase estuviera caído, el correo ya está a salvo y se puede
    // reprocesar a mano; al revés se perdería. Por eso se guarda dos
    // veces: la primera para no perderlo, la segunda para dejar anotado
    // qué contestó Supabase.
    if (env.REGISTRAR === '1' && delBanco && analisis && analisis.es_ingreso) {
      try {
        registro.registrado = await registrarPago(
          env, analisis, idMensaje, texto);
      } catch (e) {
        registro.registrado = {
          error: String(e && e.message ? e.message : e).slice(0, 300),
        };
      }
      await env.BUZON.put(
        clave, JSON.stringify(registro),
        { expirationTtl: 60 * 60 * 24 * DIAS_QUE_SE_GUARDA });
    }
  },

  /* ── leer lo que llegó ───────────────────────────────────────────
   * Con llave, siempre. Aquí hay nombres de clientes y montos.
   */
  async fetch(request, env) {
    const url = new URL(request.url);

    if (url.pathname === '/salud') {
      const base = {
        ok: true,
        buzon: 'pagos@tumbaobaila.com',
        modo: env.REGISTRAR === '1' ? 'registrando' : 'espejo',
        tiene_llave_supabase: Boolean(env.SUPABASE_SERVICE_KEY),
      };

      // Con llave y ?hondo=1 se comprueba de verdad que la llave de
      // Supabase sirve, con una lectura que no cambia nada.
      //
      // Existe por una razón concreta: el relevo apaga n8n. Si la llave
      // estuviera mal, los pagos dejarían de registrarse y no se sabría
      // hasta que alguien reclamara. Esto permite comprobarlo ANTES de
      // apagar nada, y después sirve de chequeo cuando algo huela mal.
      if (url.searchParams.get('hondo') === '1') {
        if (!conLlave(url, env)) return json({ ok: false, error: 'no_autorizado' }, 401);
        try {
          const r = await fetch(
            `${env.SUPABASE_URL}/rest/v1/pagos?select=id&limit=1`,
            { headers: { apikey: env.SUPABASE_SERVICE_KEY,
                         Authorization: `Bearer ${env.SUPABASE_SERVICE_KEY}` } });
          const t = await r.text();
          return json({ ...base,
            supabase: r.ok ? 'responde' : `falla ${r.status}`,
            detalle: r.ok ? undefined : t.slice(0, 200) });
        } catch (e) {
          return json({ ...base, supabase: 'no_alcanzable',
            detalle: String(e && e.message ? e.message : e).slice(0, 200) });
        }
      }

      return json(base);
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

      // Qué entendió el Worker de cada correo y qué hizo con él, sin
      // los cuerpos. Es la vista de diagnóstico.
      //
      // OJO CON `registrado`: es el campo que dice si el pago llegó de
      // verdad a Supabase y qué contestó. Al principio no estaba en
      // esta lista, y el 1 de septiembre eso hizo perder un buen rato:
      // cinco pagos reales aparecían aquí como si no se hubieran
      // intentado registrar, cuando en realidad los cinco estaban en la
      // base. La vista de diagnóstico escondía justo el dato que hace
      // falta para diagnosticar. Si se añade un campo al registro,
      // añádelo también aquí.
      if (url.pathname === '/parseos') {
        return json({
          ok: true,
          modo: env.REGISTRAR === '1' ? 'registrando' : 'espejo',
          correos: correos.map((c) => ({
            recibido_at: c.recibido_at,
            de: c.de,
            asunto: c.asunto,
            message_id: c.message_id,
            modo: c.modo,
            descartado: c.descartado,
            procedencia: c.procedencia,
            analisis: c.analisis,
            registrado: c.registrado,
            fallo: c.fallo,
          })),
        });
      }

      return json({ ok: true, cuantos: correos.length, correos });
    }

    return json({ ok: false, error: 'no_existe' }, 404);
  },
};
