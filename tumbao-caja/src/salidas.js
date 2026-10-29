/**
 * 0190 · Timba le pregunta a Tania a qué corresponden las salidas del banco sin clasificar (Damián, 29 oct).
 *
 * El flujo, de punta a punta:
 *   1. Una vez al día (9:30 am, lunes a sábado) la base le deja a Tania una nota con la primera salida que lleve más de 16
 *      horas sin clasificar. Si la ventana de 24 h está cerrada, sale el aviso corto y la nota se abre con «Ver resumen».
 *   2. Tania contesta con lo que fue («clase de Nagle», «el arriendo», «no es del negocio»). Ese mensaje cae en /wa/agente
 *      —porque es una dueña— y, si hay una pregunta abierta, lo atiende este archivo en vez del agente general.
 *   3. El modelo SOLO interpreta la frase (categoría, concepto, a quién). El valor y el día salen del banco, nunca de lo que
 *      se escriba, y la base rechaza cualquier categoría fuera de su lista.
 *   4. Timba confirma lo que registró y, en la misma conversación, pregunta la siguiente. Sin respuesta, se queda pendiente.
 *
 * Nace APAGADO: ajustes.salidas_timba = 'apagado' hasta que Damián confirme el número de Tania.
 */

export const CATEGORIAS_SALIDA = {
  nomina: 'Nómina', profesores: 'Profesores', arriendo: 'Arriendo', sistema: 'Sistema', mercadeo: 'Mercadeo',
  talleres: 'Talleres', viaticos: 'Viáticos', mantenimiento: 'Mantenimiento', impuestos: 'Impuestos', otros: 'Otros',
};

export const INSTRUCCIONES_SALIDAS = `Eres Timba, la asistente de Tumbao. Le preguntaste a Tania (una de las dueñas) a qué corresponde una salida de plata del banco y ella te contesta. Tu trabajo es SOLO interpretar su respuesta.

Devuelve un JSON con esta forma exacta y nada más:
{"accion":"clasificar|descartar|luego|aclarar","categoria":"…","concepto":"…","a_quien":"…","mensaje":"…"}

- "clasificar": ella dice a qué corresponde. "categoria" es UNA de: ${Object.keys(CATEGORIAS_SALIDA).join(', ')}. "concepto" es una frase corta y clara que escribes tú con sus palabras (ej. «Clase profe Nagle», «Arriendo del salón»). "a_quien" es la persona o empresa si la dice; si no, vacío.
- "descartar": dice que NO es un gasto del negocio, que es un traslado entre cuentas o que ya estaba registrada. "mensaje" lleva el motivo con sus palabras.
- "luego": no sabe, lo dejará para después, o te pide saltarla.
- "aclarar": su respuesta no alcanza para clasificar. "mensaje" es UNA pregunta corta y concreta (en tuteo, amable, sin emojis de más).

Reglas:
- Usa «sugerencia» (lo que se anotó la última vez que salió plata a esa misma cuenta) SOLO si ella dice algo como «lo mismo de siempre», «igual que la otra vez» o «sí». Si dice otra cosa, manda lo que ella dice.
- NUNCA inventes una categoría, un nombre ni un motivo que ella no haya dicho. Ante la duda, "aclarar".
- NUNCA escribas montos ni fechas: el valor y el día salen del banco.
- No hables de ventas, clientes ni precios. Solo esta salida.`;

const norm = (t) => String(t || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().trim();

/** Lo que dice Tania cuando quiere dejarla para después. Se reconoce sin el modelo: no hace falta pagar una llamada. */
export function esLuego(texto) {
  return /^(luego|despues|mas tarde|ahora no|no se|nose|ni idea|no recuerdo|no la recuerdo|salta(r)?|siguiente|paso)\b/.test(norm(texto));
}

/** Valida lo que devolvió el modelo. Devuelve {accion, ...} o {accion:'aclarar'} si no sirve para registrar nada. */
export function interpretarSalida(j) {
  const aclarar = (mensaje) => ({ accion: 'aclarar', mensaje: mensaje || '¿Me cuentas un poco más a qué corresponde esa salida? Por ejemplo: «clase de Nagle» o «arriendo».' });
  if (!j || typeof j !== 'object') return aclarar();
  const accion = String(j.accion || '').toLowerCase();
  const limpio = (v, n) => String(v == null ? '' : v).replace(/\s+/g, ' ').trim().slice(0, n);
  if (accion === 'luego') return { accion: 'luego' };
  if (accion === 'descartar') {
    const motivo = limpio(j.mensaje, 160);
    return motivo ? { accion: 'descartar', motivo } : aclarar('¿Por qué no cuenta como gasto? Por ejemplo: «es un traslado» o «ya la había registrado».');
  }
  if (accion === 'clasificar') {
    const categoria = String(j.categoria || '').toLowerCase().trim();
    const concepto = limpio(j.concepto, 120);
    if (!CATEGORIAS_SALIDA[categoria] || !concepto) return aclarar(limpio(j.mensaje, 200) || undefined);
    // Un concepto que trae montos o fechas escritos por el modelo no se acepta: esos datos salen del banco.
    if (/\$\s?\d|\b\d{1,3}([.,]\d{3})+\b/.test(concepto)) return aclarar();
    return { accion: 'clasificar', categoria, concepto, a_quien: limpio(j.a_quien, 60) };
  }
  return aclarar(limpio(j.mensaje, 200) || undefined);
}

const pesos = (n) => '$' + Number(n || 0).toLocaleString('es-CO');

/** La pregunta de una salida. `sig` es lo que devuelve salida_siguiente_por_preguntar(). */
export function textoPreguntaSalida(sig, quedan) {
  const sug = sig && sig.sugerencia && sig.sugerencia.concepto
    ? `\nLa última vez que salió plata a esa cuenta la anotamos como «${sig.sugerencia.concepto}».` : '';
  const rep = sig && sig.quizas_repetida && sig.quizas_repetida.concepto
    ? `\nOjo: ya hay un gasto de ese mismo valor por esas fechas («${sig.quizas_repetida.concepto}»). Si es el mismo, dímelo.` : '';
  return `💸 *${pesos(sig.valor_cop)}* el ${sig.cuando}` +
    `${sig.cuenta_destino ? ` · cuenta ${sig.cuenta_destino}` : ''}${sug}${rep}\n¿A qué corresponde? (si no sabes, escribe «luego»)` +
    (quedan > 1 ? `\n\nQuedan ${quedan} por clasificar.` : '');
}

export function textoSalidaRegistrada(q, it, quedan) {
  return `✅ Anotado: ${pesos(q.valor_cop)} del ${q.cuando} como *${it.concepto}* (${CATEGORIAS_SALIDA[it.categoria]}${it.a_quien ? ` · ${it.a_quien}` : ''}).` +
    (quedan > 0 ? '' : '\n\n🎉 Ya no quedan salidas por clasificar.');
}

export function textoSalidaDescartada(q, it, quedan) {
  return `Listo, dejé esa salida (${pesos(q.valor_cop)} del ${q.cuando}) fuera de los gastos: ${it.motivo}.` +
    (quedan > 0 ? '' : '\n\n🎉 Ya no quedan salidas por clasificar.');
}

/** Cuántas veces ha contestado Timba desde la última pregunta de salida (las preguntas empiezan con 💸). */
export function aclaracionesSeguidas(historial) {
  const h = Array.isArray(historial) ? historial : [];
  let n = 0;
  for (let i = h.length - 1; i >= 0; i--) {
    if (h[i].direccion !== 'saliente') continue;
    if (String(h[i].texto || '').includes('💸')) break;
    n++;
  }
  return n;
}
