/**
 * Parser de correos de alerta de Bancolombia.
 *
 * Este archivo es la FUENTE DE VERDAD del parser: el mismo código va
 * dentro del nodo Code del workflow "Tumbao · Ingesta de pagos".
 * Si se cambia aquí, se cambia allá (y se vuelve a correr parser.test.js).
 *
 * Regla de oro: ante la duda, NO es un ingreso. Un falso positivo
 * confirma una reserva que nadie pagó; un falso negativo solo manda la
 * reserva a validación humana, que es el camino de respaldo previsto.
 */

// Verbos que significan que el dinero SALIÓ. Si aparece alguno, se
// descarta el correo aunque también diga "recibiste" en otra parte.
const VERBOS_SALIDA = [
  /\btransferiste\b/i,
  /\bpagaste\b/i,
  /\bcompraste\b/i,
  /\bretiraste\b/i,
  /\bavance\b/i,
  /\bpago (?:programado|automatico|automático) por\b/i,
];

// Estructuras de ingreso observadas en correos reales de Bancolombia.
// El orden importa: se prueba de la más específica a la más general.
const PATRONES_ENTRADA = [
  {
    // "Damian, recibiste una transferencia de JUAN PEREZ por $100000.00
    //  en tu cuenta *8621 conectada a la llave 3015373964 el 17/07/26 a las 17:02"
    id: 'transferencia_llave',
    re: /recibiste una transferencia de\s+(?<remitente>.+?)\s+por\s+\$\s*(?<monto>[\d.,]+)\s+en tu cuenta\s+\*+(?<cuenta>\d+)\s+conectada a la llave\s+(?<llave>\d+)\s+el\s+(?<fecha>\d{1,2}\/\d{1,2}\/\d{2,4})\s+a las\s+(?<hora>\d{1,2}:\d{2})/i,
    confianza: 1.0,
  },
  {
    // "Recibiste una transferencia por $650000 de JUAN PEREZ
    //  en tu cuenta **8621, el 10/07/2026 a las 10:10."
    id: 'transferencia_simple',
    re: /recibiste una transferencia por\s+\$\s*(?<monto>[\d.,]+)\s+de\s+(?<remitente>.+?)\s+en tu cuenta\s+\*+(?<cuenta>\d+)\s*,?\s*el\s+(?<fecha>\d{1,2}\/\d{1,2}\/\d{2,4})\s+a las\s+(?<hora>\d{1,2}:\d{2})/i,
    confianza: 1.0,
  },
  {
    // "Recibiste un pago por codigo QR de JUAN PEREZ por $15000.00
    //  en tu cuenta *8621 el 26/07/2026 a las 19:05"
    // Variante esperada para cobros por QR Bre-B. Pendiente de confirmar
    // con un correo real de la cuenta de Tumbao (ver LEEME).
    id: 'pago_qr',
    re: /recibiste un pago(?:\s+por\s+c[oó]digo\s+QR)?\s+de\s+(?<remitente>.+?)\s+por\s+\$\s*(?<monto>[\d.,]+)\s+en tu cuenta[^.]*?\s+el\s+(?<fecha>\d{1,2}\/\d{1,2}\/\d{2,4})\s+a las\s+(?<hora>\d{1,2}:\d{2})/i,
    confianza: 0.9,
  },
  {
    // Red de seguridad: dice "recibiste", trae monto y fecha, pero la
    // estructura no coincide con nada conocido. Se registra con
    // confianza baja para que NO confirme sola.
    id: 'generico',
    re: /recibiste[^$]*\$\s*(?<monto>[\d.,]+)[\s\S]*?(?<fecha>\d{1,2}\/\d{1,2}\/\d{2,4})[^\d]{0,12}(?<hora>\d{1,2}:\d{2})?/i,
    confianza: 0.4,
  },
];


/**
 * Montos colombianos en dos notaciones distintas, en el mismo banco:
 *   $14.000,00  → punto = miles, coma = decimales
 *   $100000.00  → punto = decimales
 *   $650000     → sin separadores
 *   $1.500.000  → punto = miles
 */
function parsearMonto(txt) {
  if (!txt) return null;
  let s = String(txt).trim();

  if (s.includes(',')) {
    // Hay coma: es el separador decimal. Los puntos son de miles.
    s = s.replace(/\./g, '').replace(',', '.');
  } else if (/\.\d{2}$/.test(s)) {
    // Termina en punto + exactamente 2 dígitos: son decimales.
    s = s.replace(/\.(?=.*\.)/g, '');
  } else {
    // Cualquier otro punto es separador de miles.
    s = s.replace(/\./g, '');
  }

  const n = parseFloat(s);
  if (!Number.isFinite(n) || n <= 0) return null;
  // Los pesos colombianos no llevan centavos en la práctica.
  return Math.round(n);
}


/**
 * "17/07/26" y "10/07/2026" conviven. Siempre DD/MM.
 * Devuelve ISO 8601 con el offset de Bogotá (-05:00, sin horario de verano).
 */
function parsearFecha(fecha, hora) {
  if (!fecha) return null;
  const m = /^(\d{1,2})\/(\d{1,2})\/(\d{2,4})$/.exec(fecha.trim());
  if (!m) return null;

  const dia = parseInt(m[1], 10);
  const mes = parseInt(m[2], 10);
  let anio = parseInt(m[3], 10);
  if (anio < 100) anio += 2000;

  if (dia < 1 || dia > 31 || mes < 1 || mes > 12) return null;

  let hh = 0, mm = 0;
  if (hora) {
    const h = /^(\d{1,2}):(\d{2})$/.exec(hora.trim());
    if (h) {
      hh = parseInt(h[1], 10);
      mm = parseInt(h[2], 10);
      if (hh > 23 || mm > 59) return null;
    }
  }

  const p = (n, w = 2) => String(n).padStart(w, '0');
  return `${anio}-${p(mes)}-${p(dia)}T${p(hh)}:${p(mm)}:00-05:00`;
}


/**
 * Limpia el cuerpo del correo: quita el envoltorio de marketing que
 * Bancolombia mete alrededor del mensaje real.
 */
function limpiar(texto) {
  return String(texto || '')
    .replace(/\s+/g, ' ')
    .replace(/¡Listo!\s*Todo sali[oó] bien con tus movimientos\s*/i, '')
    .trim();
}


/**
 * @returns {{es_ingreso: boolean, motivo?: string, ...}}
 */
function parsearCorreoBancolombia(texto) {
  const cuerpo = limpiar(texto);

  if (!cuerpo) {
    return { es_ingreso: false, motivo: 'cuerpo_vacio' };
  }

  const salida = VERBOS_SALIDA.find((re) => re.test(cuerpo));
  if (salida) {
    return { es_ingreso: false, motivo: 'movimiento_de_salida' };
  }

  if (!/recibiste/i.test(cuerpo)) {
    return { es_ingreso: false, motivo: 'no_es_movimiento_de_entrada' };
  }

  for (const patron of PATRONES_ENTRADA) {
    const m = patron.re.exec(cuerpo);
    if (!m || !m.groups) continue;

    const monto = parsearMonto(m.groups.monto);
    const fecha = parsearFecha(m.groups.fecha, m.groups.hora);
    if (monto === null || fecha === null) continue;

    return {
      es_ingreso: true,
      patron: patron.id,
      confianza: patron.confianza,
      banco: 'bancolombia',
      valor_cop: monto,
      fecha_pago: fecha,
      remitente: (m.groups.remitente || '').trim().replace(/\s+/g, ' ') || null,
      ultimos_4: m.groups.cuenta ? m.groups.cuenta.slice(-4) : null,
      llave: m.groups.llave || null,
    };
  }

  return { es_ingreso: false, motivo: 'estructura_no_reconocida' };
}

module.exports = {
  parsearCorreoBancolombia,
  parsearMonto,
  parsearFecha,
};
