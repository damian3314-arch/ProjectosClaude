/* ---------------------------------------------------------------------
 * tumbao-correo — el buzón de pagos@tumbaobaila.com
 *
 * POR QUÉ EXISTE
 * n8n cobra por ejecución. El plan son 2.500 al mes y el 30 de agosto se
 * llegó a 2.494 faltando un día. La ingesta de pagos —leer las alertas
 * de Bancolombia del correo— se lleva el 56% de ese gasto ella sola:
 * n8n sondea Gmail y cada correo que encuentra es una ejecución.
 *
 * La idea es darle la vuelta: en vez de que alguien vaya a buscar el
 * correo, que el correo llegue solo. Gmail reenvía las alertas del banco
 * a pagos@tumbaobaila.com, Cloudflare las entrega aquí, y aquí se
 * procesan. Cloudflare Email Routing no cobra por correo recibido.
 *
 * POR QUÉ UN WORKER APARTE Y NO DENTRO DE tumbao-caja
 * tumbao-caja es lo que mantiene viva la página: horarios, reservas,
 * comprobantes. Meterle un manejador de correo nuevo y a medio probar
 * arriesga lo único que no se puede caer. Cuando esto esté rodado se
 * puede juntar; hoy no.
 *
 * EN QUÉ VA
 * Paso 1 (hecho): recibir. Guarda lo que llegue para poder leer el
 * código con el que Gmail confirma la dirección de reenvío — sin eso no
 * se puede terminar de configurar el reenvío del otro lado.
 *
 * Paso 2 (pendiente, para el 1 de septiembre): parsear la alerta del
 * banco y llamar a registrar_pago_y_conciliar() en Supabase, que es lo
 * que hoy hace el nodo "Registrar y conciliar" de n8n. El parser ya
 * existe y está probado —vive en el nodo "Parsear correo" del workflow
 * "Tumbao · Ingesta de pagos"— y es JavaScript puro, sin nada de n8n
 * dentro, así que se mueve tal cual.
 *
 * LO QUE SE GUARDA, Y POR QUÉ CADUCA
 * Aquí van a caer alertas del banco: montos, nombres de quien paga y los
 * últimos cuatro dígitos de la cuenta. Eso no puede quedarse en un KV
 * para siempre. Se guarda 7 días, que es de sobra para depurar, y se
 * borra solo.
 * ------------------------------------------------------------------- */

const DIAS_QUE_SE_GUARDA = 7;

// El código de confirmación de Gmail. Cuando se añade una dirección de
// reenvío, Google manda un correo con un número de 9 dígitos y un
// enlace; con cualquiera de los dos se confirma.
function codigoDeGmail(texto) {
  const m = /Confirmation code:?\s*([0-9]{6,12})/i.exec(texto)
         || /c[oó]digo de confirmaci[oó]n:?\s*([0-9]{6,12})/i.exec(texto);
  const enlace = /(https:\/\/mail\.google\.com\/[^\s"'<>\]]+)/i.exec(texto);
  if (!m && !enlace) return null;
  return { codigo: m ? m[1] : null, enlace: enlace ? enlace[1] : null };
}

function json(datos, estado = 200) {
  return new Response(JSON.stringify(datos, null, 2), {
    status: estado,
    headers: { 'Content-Type': 'application/json; charset=utf-8',
               'Cache-Control': 'no-store' },
  });
}

export default {
  /* ── llega un correo ─────────────────────────────────────────────
   * No se rechaza nada ni se responde: un rebote a Bancolombia no
   * sirve de nada y un rebote a Gmail podría hacer que Google apague
   * el reenvío. Lo que no se entienda se guarda igual y ya se mirará.
   */
  async email(message, env, ctx) {
    let crudo = '';
    try {
      crudo = await new Response(message.raw).text();
    } catch (_) {
      crudo = '(no se pudo leer el cuerpo)';
    }

    const asunto = message.headers.get('subject') || '';
    // El Message-ID es lo que va a evitar registrar dos veces el mismo
    // pago cuando esto procese de verdad: si el correo se entrega dos
    // veces, el identificador es el mismo. Hoy solo se guarda.
    const idMensaje = message.headers.get('message-id') || null;

    const registro = {
      de: message.from,
      para: message.to,
      asunto,
      message_id: idMensaje,
      recibido_at: new Date().toISOString(),
      // Recortado: una alerta del banco cabe de sobra, y así un correo
      // con adjuntos raros no llena el almacén.
      texto: crudo.slice(0, 60000),
      gmail: codigoDeGmail(crudo),
    };

    await env.BUZON.put(
      `correo:${Date.now()}:${crypto.randomUUID().slice(0, 8)}`,
      JSON.stringify(registro),
      { expirationTtl: 60 * 60 * 24 * DIAS_QUE_SE_GUARDA }
    );
  },

  /* ── leer lo que llegó ───────────────────────────────────────────
   * Con llave, siempre. Aquí hay nombres de clientes y montos.
   */
  async fetch(request, env) {
    const url = new URL(request.url);

    if (url.pathname === '/salud') {
      return json({ ok: true, buzon: 'pagos@tumbaobaila.com' });
    }

    if (url.pathname === '/ultimos') {
      if (!env.LLAVE_BUZON || url.searchParams.get('llave') !== env.LLAVE_BUZON) {
        return json({ ok: false, error: 'no_autorizado' }, 401);
      }
      const lista = await env.BUZON.list({ prefix: 'correo:' });
      const claves = lista.keys.map((k) => k.name).sort().reverse().slice(0, 20);
      const correos = [];
      for (const c of claves) {
        const v = await env.BUZON.get(c, 'json');
        if (v) correos.push({ clave: c, ...v });
      }
      // Solo lo del código de Gmail si se pide así: es lo que se
      // necesita para terminar de configurar el reenvío, y evita
      // andar paseando cuerpos de correos por pantalla.
      if (url.searchParams.get('solo') === 'codigo') {
        return json({ ok: true, correos: correos
          .filter((c) => c.gmail)
          .map((c) => ({ de: c.de, asunto: c.asunto,
                         recibido_at: c.recibido_at, gmail: c.gmail })) });
      }
      return json({ ok: true, cuantos: correos.length, correos });
    }

    return json({ ok: false, error: 'no_existe' }, 404);
  },
};
