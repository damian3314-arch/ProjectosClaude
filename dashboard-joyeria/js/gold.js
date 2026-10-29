// Oro: precio internacional (spot) convertido a pesos por gramo, más el registro propio del precio de mercado local.
// Fuentes públicas, sin llave: gold-api.com (XAU/USD) y datos.gov.co (TRM oficial).
const OZ_TROY_G = 31.1034768;
const URL_SPOT = 'https://api.gold-api.com/price/XAU';
const URL_TRM = 'https://www.datos.gov.co/resource/32sa-8pi3.json?$select=valor,vigenciadesde&$order=vigenciadesde%20DESC&$limit=5';
const LS_HIST = 'oro_hist_v1';
const LS_MERCADO = 'oro_mercado_v1';

export const gramoCOP = (usdOz, trm) => (usdOz / OZ_TROY_G) * trm;

export async function cargarOro() {
  const [s, t] = await Promise.all([fetch(URL_SPOT), fetch(URL_TRM)]);
  if (!s.ok) throw new Error(`Precio internacional no disponible (HTTP ${s.status}).`);
  if (!t.ok) throw new Error(`TRM no disponible (HTTP ${t.status}).`);
  const spot = await s.json();
  const trmRows = await t.json();
  const usdOz = Number(spot.price);
  const trm = Number(trmRows[0]?.valor);
  if (!Number.isFinite(usdOz) || !Number.isFinite(trm)) throw new Error('Respuesta de oro/TRM con formato inesperado.');
  return {
    usdOz,
    trm,
    trmFecha: String(trmRows[0].vigenciadesde).slice(0, 10),
    spotActualizado: spot.updatedAt,
    cop24: gramoCOP(usdOz, trm),
  };
}

// Señal: compara el precio de hoy con el promedio de las lecturas guardadas (excluyendo hoy).
// Es una referencia mecánica, no una recomendación de inversión.
export function senalOro(hist, hoyFecha, hoyCop, { umbral, minLecturas }) {
  const previas = Object.entries(hist).filter(([f]) => f < hoyFecha).map(([, v]) => v);
  if (previas.length < minLecturas) {
    return { estado: 'sin-datos', lecturas: previas.length, faltan: minLecturas - previas.length };
  }
  const prom = previas.reduce((a, b) => a + b, 0) / previas.length;
  const desv = hoyCop / prom - 1;
  const estado = desv >= umbral ? 'alto' : desv <= -umbral ? 'bajo' : 'neutral';
  return { estado, promedio: prom, desviacion: desv, lecturas: previas.length };
}

// Prima o descuento del precio local contra el internacional convertido (misma pureza).
export function primaMercado(precioLocal, spotCopPureza) {
  return spotCopPureza > 0 && precioLocal > 0 ? precioLocal / spotCopPureza - 1 : null;
}

const leer = (k, def) => { try { return JSON.parse(localStorage.getItem(k)) ?? def; } catch { return def; } };
const guardar = (k, v) => { try { localStorage.setItem(k, JSON.stringify(v)); } catch { /* modo privado: se ignora */ } };

export const leerHistorial = () => leer(LS_HIST, {});
export function registrarLectura(fecha, cop24) {
  const h = leerHistorial();
  h[fecha] = Math.round(cop24);
  const fechas = Object.keys(h).sort();
  for (const f of fechas.slice(0, Math.max(0, fechas.length - 400))) delete h[f];
  guardar(LS_HIST, h);
  return h;
}
export const leerMercado = () => leer(LS_MERCADO, null);
export const guardarMercado = (v) => guardar(LS_MERCADO, v);
