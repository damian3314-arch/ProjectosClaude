/**
 * Las cifras de los informes y del asistente: el modelo redacta, el código calcula y revisa.
 *
 * Damián (5 oct): «el modelo de IA del bot que envía los reportes y al que se le hacen preguntas cambia el
 * valor de la mensualidad; OpenAI no es muy bueno en los cálculos y cambia los números».
 *
 * Qué pasaba (cierre del 5 oct): el informe dijo «valor típico de $118.333» y «renovaciones en juego cerca de
 * $2.722.000». La mensualidad vale $125.000. El $118.333 salía de la base como «lo recaudado en el mes ÷ número
 * de mensualidades», que mezcla planes completos y medias mensualidades, y el modelo lo tomó por el precio y lo
 * multiplicó por 23 de cabeza. Las cuentas correctas eran 21 planes completos × $125.000 = $2.625.000.
 *
 * Tres capas, que no dependen de que el modelo sea bueno en matemáticas:
 *   1. DATOS FIJOS: los precios oficiales salen de la base y se le entregan al modelo (nunca los deduce).
 *   2. CÁLCULOS HECHOS: diferencias, porcentajes, metas y renovaciones en juego los hace `derivar()`; el modelo
 *      los copia.
 *   3. REVISIÓN: `cifrasSospechosas()` compara cada monto del texto con los datos. Si hay uno que no sale de ahí
 *      (ni es una suma, resta o producto de dos datos), se le pide corregir una vez; si persiste, el mensaje
 *      lleva una línea «cifras por confirmar» en vez de dejar pasar un número inventado.
 */

const redondear = (n, d = 0) => { const f = 10 ** d; return Math.round(n * f) / f; };

/** Todos los números que aparecen como valor en un objeto o en un texto. */
export function numerosDe(fuente, salida = new Set()) {
  if (fuente == null) return salida;
  if (typeof fuente === 'number') { if (Number.isFinite(fuente)) salida.add(Math.abs(fuente)); return salida; }
  if (typeof fuente === 'string') {
    // 1.250.000 · 1,250,000 · 52000 · 3,6 (los decimales se dejan: sirven para %).
    for (const m of fuente.matchAll(/\d{1,3}(?:[.,]\d{3})+|\d+(?:[.,]\d+)?/g)) {
      const t = m[0];
      const entero = /^\d{1,3}(?:[.,]\d{3})+$/.test(t) ? Number(t.replace(/[.,]/g, '')) : Number(t.replace(',', '.'));
      if (Number.isFinite(entero)) salida.add(entero);
    }
    return salida;
  }
  if (Array.isArray(fuente)) { for (const x of fuente) numerosDe(x, salida); return salida; }
  if (typeof fuente === 'object') { for (const k of Object.keys(fuente)) numerosDe(fuente[k], salida); }
  return salida;
}

/** Montos en pesos de un texto: «$1.250.000», «$ 12.000», «$3,6 M», «355.000 pesos». */
export function montosEnTexto(texto) {
  const t = String(texto || '');
  const out = [];
  for (const m of t.matchAll(/\$\s?(\d{1,3}(?:[.,]\d{3})+|\d+)(?:\s?(?:M\b|millones))?/gi)) {
    const completo = m[0];
    const base = m[1];
    let n = /^\d{1,3}(?:[.,]\d{3})+$/.test(base) ? Number(base.replace(/[.,]/g, '')) : Number(base);
    if (/M\b|millones/i.test(completo.slice(1 + base.length))) n *= 1_000_000;
    if (n >= 1000) out.push(n);
  }
  // «$3,6 M» con decimal.
  for (const m of t.matchAll(/\$\s?(\d+),(\d+)\s?(?:M\b|millones)/gi)) out.push(Math.round(Number(`${m[1]}.${m[2]}`) * 1_000_000));
  for (const m of t.matchAll(/\b(\d{1,3}(?:[.,]\d{3})+)\s*pesos\b/gi)) out.push(Number(m[1].replace(/[.,]/g, '')));
  return out;
}

/**
 * Montos del texto que NO salen de los datos. Un monto es válido si es:
 *   · exactamente un dato (±$1);
 *   · un dato redondeado de forma clara (a mil, diez mil, cien mil o millón: «cerca de $2.600.000»);
 *   · una cuenta EXACTA de dos datos: suma o resta de dos montos, o un monto por una cantidad pequeña
 *     (2 mensualidades × $125.000).
 * Sin tolerancia en las cuentas: con tolerancia, casi cualquier número «coincide» por casualidad con alguna
 * combinación (p. ej. $120.000 = $96.000 + $24.000) y la revisión no serviría. Devuelve la lista de montos
 * sospechosos (vacía = todo bien).
 */
export function cifrasSospechosas(texto, ...fuentes) {
  const montos = [...new Set(montosEnTexto(texto))];
  if (!montos.length) return [];
  const base = new Set();
  for (const f of fuentes) numerosDe(f, base);
  const datos = [...base].filter((n) => n > 0 && n < 1e10);
  const grandes = datos.filter((n) => n >= 1000).slice(0, 400);
  const chicos = datos.filter((n) => Number.isInteger(n) && n >= 2 && n <= 100);
  const exacto = (v, m) => Math.abs(v - m) <= 1;
  const redondeos = [1000, 10000, 100000, 1000000];
  const ok = (m) => {
    for (const d of grandes) {
      if (exacto(d, m)) return true;
      for (const r of redondeos) if (exacto(Math.round(d / r) * r, m) && Math.abs(d - m) <= d * 0.03) return true;
    }
    for (let i = 0; i < grandes.length; i++) {
      for (let j = i; j < grandes.length; j++) {
        if (exacto(grandes[i] + grandes[j], m) || exacto(Math.abs(grandes[i] - grandes[j]), m)) return true;
      }
      for (const k of chicos) if (exacto(grandes[i] * k, m)) return true;
    }
    return false;
  };
  const sospechosos = new Set(montos.filter((m) => !ok(m)));

  // El precio de la mensualidad es lo que más importa. Junto a «mensualidad» o «plan», un monto solo vale si es un
  // múltiplo del precio oficial (2 mensualidades = $250.000) o un dato exacto de la base (lo cobrado en el mes);
  // una cuenta casual de dos datos NO alcanza (p. ej. $96.000 + $24.000 = $120.000 no es el precio).
  const precio = precioOficial(fuentes);
  if (precio) {
    const exactoDato = (m) => grandes.some((d) => exacto(d, m));
    const multiplo = (m) => { const k = m / precio; return Number.isInteger(Math.round(k * 1000) / 1000) && k >= 1 && k <= 120; };
    const cerca = [
      ...String(texto || '').matchAll(/\b(?:mensualidad(?:es)?|plan(?:es)?)\b[^$\n]{0,45}\$\s?(\d{1,3}(?:[.,]\d{3})+|\d{4,})/gi),
      ...String(texto || '').matchAll(/\$\s?(\d{1,3}(?:[.,]\d{3})+|\d{4,})[^$\n]{0,25}\b(?:mensualidad(?:es)?|plan(?:es)?)\b/gi),
    ];
    for (const x of cerca) {
      const m = Number(String(x[1]).replace(/[.,]/g, ''));
      if (m >= 1000 && !multiplo(m) && !exactoDato(m)) sospechosos.add(m);
    }
  }
  return [...sospechosos];
}

/** El precio oficial de la mensualidad, si viene en alguna de las fuentes (datos_fijos / precios_oficiales). */
function precioOficial(fuentes) {
  const buscar = (o) => {
    if (!o || typeof o !== 'object') return null;
    if (Number(o.mensualidad_plan_completo_cop) > 0) return Number(o.mensualidad_plan_completo_cop);
    for (const k of Object.keys(o)) { const r = buscar(o[k]); if (r) return r; }
    return null;
  };
  for (const f of fuentes) { const r = buscar(f); if (r) return r; }
  return null;
}

const pct = (actual, anterior) => (anterior > 0 ? redondear(((actual - anterior) / anterior) * 100, 1) : null);

/**
 * Las cuentas del informe, hechas. El modelo las copia y no calcula nada de cabeza.
 * @param {object} tablero  lo que devuelve tablero_tumbao()
 * @param {object} precios  precios_oficiales()
 * @param {object} renov    renovaciones_en_juego()
 */
export function derivar(tablero, precios, renov) {
  const t = tablero || {};
  const v = (t.ventas && t.ventas.hoy) || {};
  const m = (t.ventas && t.ventas.mes) || {};
  const c = t.cruce_banco || {};
  const out = {};

  if (v.total_cop != null) {
    out.hoy = {
      total_cop: v.total_cop,
      suma_de_las_partes_cop: (v.sueltas_cop || 0) + (v.mensualidades_cop || 0) + (v.tiqueteras_cop || 0) + (v.otros_cop || 0),
    };
    if (v.promedio_mismo_dia_4_semanas_cop > 0) {
      out.hoy.contra_promedio_cop = v.total_cop - v.promedio_mismo_dia_4_semanas_cop;
      out.hoy.contra_promedio_pct = pct(v.total_cop, v.promedio_mismo_dia_4_semanas_cop);
    }
  }
  if (m.total_cop != null) {
    out.mes = { total_cop: m.total_cop };
    if (m.mes_anterior_mismo_tramo_cop > 0) {
      out.mes.contra_mes_anterior_cop = m.total_cop - m.mes_anterior_mismo_tramo_cop;
      out.mes.contra_mes_anterior_pct = pct(m.total_cop, m.mes_anterior_mismo_tramo_cop);
    }
    if (m.meta_cop > 0) {
      out.mes.falta_para_meta_cop = Math.max(m.meta_cop - m.total_cop, 0);
      const dias = Number(m.dias_con_clase_que_quedan);
      if (dias > 0) out.mes.necesario_por_dia_cop = Math.ceil(out.mes.falta_para_meta_cop / dias);
    }
  }
  if (c.entro_al_banco_hoy_cop != null) {
    out.banco = {
      entro_cop: c.entro_al_banco_hoy_cop, cruzado_cop: c.cruzado_cop, pendiente_cop: c.pendiente_por_cruzar_cop,
      entro_menos_cruzado_cop: c.entro_al_banco_hoy_cop - (c.cruzado_cop || 0),
    };
  }
  if (renov) out.renovaciones_en_juego = renov;
  if (precios) {
    out.tiquetera_por_clase_cop = (precios.tiquetera_paquetes || []).map((p) => ({
      clases: p.clases, precio_cop: p.precio_cop, por_clase_cop: redondear(p.precio_cop / p.clases),
      ahorro_contra_sueltas_cop: p.clases * (precios.clase_suelta_cop || 0) - p.precio_cop,
    }));
  }
  return out;
}

/** Lo que se le agrega al tablero antes de pasárselo al modelo: datos fijos y cálculos hechos. */
export function prepararTablero(tablero, precios, renov) {
  const t = JSON.parse(JSON.stringify(tablero || {}));
  // «Valor típico de la mensualidad» (lo recaudado ÷ número de mensualidades) NO es el precio: confunde.
  if (t.para_insights && t.para_insights.renovaciones_7_dias) delete t.para_insights.renovaciones_7_dias.valor_tipico_mensualidad_cop;
  t.datos_fijos = precios || {};
  t.calculos_hechos = derivar(t, precios, renov);
  return t;
}

export const REGLAS_DE_CIFRAS = `CIFRAS (lo más importante del informe)
- "datos_fijos" trae los precios OFICIALES: la mensualidad vale "mensualidad_plan_completo_cop"; una clase suelta, "clase_suelta_cop"; las tiqueteras, "tiquetera_paquetes". Esos números NUNCA cambian ni se promedian ni se redondean. Jamás uses como precio el promedio de lo cobrado en el mes.
- "calculos_hechos" trae las cuentas ya hechas (diferencias, porcentajes, lo que falta para la meta, renovaciones en juego en plata). CÓPIALAS tal cual. No hagas cuentas de cabeza: ni sumas, ni multiplicaciones, ni porcentajes. Si una cifra que necesitas no está en el JSON, no la calcules: dilo ("no tengo ese dato") o habla sin cifra.
- Las "medias mensualidades" no valen lo mismo que un plan completo: no las sumes a ningún total.`;

export const REGLAS_DE_CIFRAS_AGENTE = `CIFRAS (reglas que no se rompen)
- Los precios oficiales están arriba en "DATOS FIJOS DEL NEGOCIO". La mensualidad vale lo que ahí dice. Jamás la cambies, la promedies ni la reemplaces por un promedio de pagos ("valor típico", "ticket promedio" o lo cobrado dividido entre mensualidades): eso NO es el precio.
- Nada de cuentas de cabeza. Toda suma, promedio, porcentaje, diferencia o multiplicación se hace en SQL con la herramienta (sum, avg, round, count) y copias el resultado. Para "cuánto representan N renovaciones" usa select renovaciones_en_juego(7) (ya trae el valor en plata).
- Si el resultado de la base no trae una cifra, no la inventes ni la estimes: dilo.
- MENSUALIDADES (cuántas hay, activas, vigentes, cupos, ocupación por horario): usa SIEMPRE select mensualidades_resumen() y copia sus campos con su nombre. Tiene tres números que NO son lo mismo y nunca se mezclan: "vigentes" (personas con el plan al día), "en_gracia" (vencieron hace pocos días y se les guarda el cupo) y "ocupan_cupo" (vigentes + en gracia: lo que cuenta la página contra el tope). Los totales ya vienen sumados (total_vigentes, total_en_gracia, total_ocupan_cupo): no los sumes ni los restes tú. Si en una misma respuesta pones un número por horario y un total, el total tiene que ser el de la MISMA columna. Si te dicen que la página muestra otro número, explica con esas tres columnas cuál es cuál, sin inventar.`;


/* ── 0159 · mensualidades: una sola verdad ───────────────────────────────────────────────────────────────
 * Damián (8 oct): «¿cuántos activos en mensualidad hay?» → «58»; «¿en cada horario?» → 26 / 20 / 23 y «Total: 58».
 * Eran dos cuentas distintas (vigentes y los que ocupan cupo) con un total de la otra columna: la suma real era 69.
 * Tres defensas: (1) las preguntas de conteo se contestan SIN modelo, con el texto armado de mensualidades_resumen();
 * (2) las reglas de arriba obligan al modelo a copiar esa función en lo demás; (3) si aun así una lista trae un
 * «Total» que no es la suma de sus renglones, no se envía.
 */

/** ¿Es una pregunta directa por cuántas mensualidades hay vigentes/activas? Solo estas se contestan sin modelo. */
export function esConteoDeMensualidades(texto) {
  const t = String(texto || '').toLowerCase();
  if (!t || t.length > 160) return false;
  if (/vend|ingres|plata|\$|pes[oa]s|mes\b|semana|ayer|venc|renov|precio|cuest|valor|lista de espera|cupos?\b|clase|suelta|tiquet/.test(t)) return false;
  const cuantos = /(cu[aá]nt[oa]s\b|cantidad|n[uú]mero|total)/.test(t);
  const sujeto = /(mensualidad|afiliad|activ[oa]s?|vigentes?|inscrit|plan(es)?\b)/.test(t);
  return cuantos && sujeto;
}

const AM = { '07:00': '7 am', '18:00': '6 pm', '19:00': '7 pm' };
const num = (n) => `*${Number(n) || 0}*`;

/** El texto exacto, armado solo con lo que trae mensualidades_resumen(): nadie suma ni redondea. */
export function textoMensualidades(r) {
  if (!r || !Array.isArray(r.por_horario)) return null;
  const hs = r.por_horario;
  const et = (h) => h.etiqueta ? String(h.etiqueta).replace(/^(\d{1,2}):00\s*(am|pm)$/i, '$1 $2').toLowerCase() : (AM[h.hora] || h.hora);
  const lin = (campo) => hs.map((h) => `${et(h)}: ${num(h[campo])}`).join(' · ');
  const libres = hs.filter((h) => h.libres_pagina != null).map((h) => `${et(h)}: ${num(h.libres_pagina)}`).join(' · ');
  return [
    '*Mensualidades hoy*',
    '',
    `• *Activas* (plan al día): ${num(r.total_vigentes)} → ${lin('vigentes')}`,
    `• *En gracia* (vencieron hace ${r.dias_de_gracia} días o menos y se les guarda el cupo): ${num(r.total_en_gracia)} → ${lin('en_gracia')}`,
    `• *Ocupan cupo* (activas + en gracia; es lo que cuenta la página): ${num(r.total_ocupan_cupo)} → ${lin('ocupan_cupo')}`,
    libres ? `• *Cupos que la página puede vender hoy*: ${libres}` : null,
  ].filter((x) => x !== null).join('\n');
}

/**
 * ¿Hay una lista de renglones con número y debajo un «Total» que no es la suma? Devuelve la lista de desajustes.
 * Lee renglones del estilo «• 7 am: *26*» o «- 6 pm: 20» y un «Total: 58» (con o sin asteriscos, punto o «en total»).
 */
export function totalesNoCuadran(texto) {
  const lineas = String(texto || '').split(/\r?\n/);
  const malos = [];
  for (let i = 0; i < lineas.length; i++) {
    const m = /^\W*(?:en\s+)?total\b[^0-9\n]{0,40}\*?(\d[\d.]*)\*?/i.exec(lineas[i].replace(/\*/g, ''));
    if (!m) continue;
    const total = Number(m[1].replace(/\./g, ''));
    const suma = [];
    for (let j = i - 1; j >= 0; j--) {
      if (!lineas[j].trim()) { if (suma.length) break; continue; }
      const r = /^\s*[•\-*·]\s*.*?(\d[\d.]*)\s*[.)]?\s*$/.exec(lineas[j].replace(/\*/g, ''));
      if (!r) break;
      suma.push(Number(r[1].replace(/\./g, '')));
    }
    if (suma.length >= 2 && suma.reduce((a, b) => a + b, 0) !== total) malos.push({ total, suma: suma.reduce((a, b) => a + b, 0) });
  }
  return malos;
}
