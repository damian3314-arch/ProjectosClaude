// La cabecera no esta siempre en la misma fila. Lo normal es que la 1
// sea el titulo fusionado y la 2 los encabezados, pero llegan archivos
// con filas de filtros, un logo o lineas en blanco encima, y entonces la
// cabecera baja. Por eso no se confia en NINGUNA posicion fija: se busca
// por contenido y se elige la fila que mas columnas conocidas trae.
//
// Se puntua en vez de tomar la primera que diga "Afiliado" porque el
// titulo fusionado a veces repite esa palabra en una celda suelta. Esa
// fila tiene una sola columna conocida; la cabecera de verdad tiene
// seis o siete, y gana.
const MESES = { ene:1, feb:2, mar:3, abr:4, may:5, jun:6, jul:7,
                ago:8, sep:9, sept:9, oct:10, nov:11, dic:12 };

const norm = (s) => String(s == null ? "" : s)
  .normalize("NFD").replace(/[\u0300-\u036f]/g, "")
  .trim().toLowerCase();

// El nodo "Extract From File" con headerRow:false devuelve cada fila como
// { row: [celda, celda, ...] } — un objeto con UNA llave. Con Object.values
// eso da [[...]], y al pasarlo por String() la fila entera se convierte en
// un solo texto pegado por comas, asi que nunca se encuentra la cabecera.
// Se acepta tambien la forma de objeto plano por si cambia el nodo.
const filas = $input.all().map(i => {
  const j = i.json || {};
  const celdas = Array.isArray(j.row) ? j.row : Object.values(j);
  return celdas.map(v => v == null ? "" : String(v));
});

// Hasta donde se busca. Cincuenta filas cubre de sobra cualquier
// encabezado corrido; mas abajo ya solo hay datos, y una celda de datos
// que dijera "Afiliado" seria un falso positivo.
const MAX_FILAS_CABECERA = 50;
// Minimo de columnas conocidas para creerse que una fila es la cabecera.
// Con "Afiliado" a secas no basta: eso lo cumple un titulo.
const MIN_COLUMNAS = 3;

const ETIQUETAS = [
  ["afiliado"], ["membresia"], ["# documento", "documento"], ["celular"],
  ["correo"], ["inicio membresia", "inicio"], ["final membresia", "final"],
];

const buscarCol = (cab, nombres) => {
  for (const n of nombres) {
    const i = cab.findIndex(c => c === norm(n) || c.startsWith(norm(n)));
    if (i >= 0) return i;
  }
  return -1;
};

// "afiliado" tiene que estar EXACTO. Los reportes de un solo horario
// traen "Afiliado Titular" y unas pocas filas: importarlos borraria a
// casi todos los afiliados, asi que se dejan fuera a proposito.
let iCab = -1, mejorPuntaje = 0;
for (let i = 0; i < filas.length && i < MAX_FILAS_CABECERA; i++) {
  const fila = filas[i].map(norm);
  if (!fila.some(c => c === "afiliado")) continue;
  const puntaje = ETIQUETAS.reduce((n, a) => n + (buscarCol(fila, a) >= 0 ? 1 : 0), 0);
  if (puntaje > mejorPuntaje) { mejorPuntaje = puntaje; iCab = i; }
}

if (iCab === -1 || mejorPuntaje < MIN_COLUMNAS) {
  const vistas = Math.min(filas.length, MAX_FILAS_CABECERA);
  return [{ json: { ok: false, error: "sin_cabecera",
    columnas_reconocidas: mejorPuntaje,
    mensaje: (iCab === -1
      ? "No se encontro la fila de encabezados: ninguna de las primeras " +
        vistas + " filas trae una columna llamada exactamente 'Afiliado'."
      : "Se encontro una fila con 'Afiliado' pero solo " + mejorPuntaje +
        " columnas reconocidas, y hacen falta " + MIN_COLUMNAS +
        ". Parece un titulo, no la cabecera.") +
      " Suele pasar cuando el archivo es la exportacion de un solo horario " +
      "—esas traen 'Afiliado Titular'— y no el listado completo." } }];
}

const cab = filas[iCab].map(norm);
const col = (...nombres) => buscarCol(cab, nombres);
const cAfil = col("afiliado");
const cMemb = col("membresia");
const cDoc  = col("# documento", "documento");
const cCel  = col("celular");
const cMail = col("correo");
const cIni  = col("inicio membresia", "inicio");
const cFin  = col("final membresia", "final");

const hora24 = (txt) => {
  const m = /(\d{1,2}):(\d{2})\s*(a\.?m\.?|p\.?m\.?)/i.exec(String(txt || ""));
  if (!m) return null;
  let h = parseInt(m[1], 10);
  const min = m[2];
  const pm = /p/i.test(m[3]);
  if (pm && h !== 12) h += 12;
  if (!pm && h === 12) h = 0;
  return String(h).padStart(2, "0") + ":" + min + ":00";
};

const fechaISO = (txt) => {
  const m = /(\d{1,2})\s*\/\s*([a-zA-Z]+)\.?\s*\/\s*(\d{4})/.exec(String(txt || ""));
  if (!m) return null;
  const mes = MESES[norm(m[2]).replace(/\.$/, "")];
  if (!mes) return null;
  const d = parseInt(m[1], 10);
  if (d < 1 || d > 31) return null;
  return m[3] + "-" + String(mes).padStart(2, "0") + "-" + String(d).padStart(2, "0");
};

const salida = [];
const descartes = [];
for (let i = iCab + 1; i < filas.length; i++) {
  const f = filas[i];
  const afiliado = (f[cAfil] || "").trim();
  const memb = (f[cMemb] || "").trim();
  if (!afiliado && !memb) continue;

  const hora   = hora24(memb);
  const inicio = fechaISO(f[cIni]);
  const fin    = fechaISO(f[cFin]);

  if (!hora || !inicio || !fin) {
    descartes.push({ fila: i + 1, afiliado, membresia: memb,
      falta: [!hora && "hora", !inicio && "inicio", !fin && "fin"].filter(Boolean).join(", ") });
    continue;
  }
  salida.push({
    afiliado, membresia: memb, hora,
    tipo: /^media/i.test(memb) ? "media" : (/^plan/i.test(memb) ? "plan" : "otro"),
    documento: (f[cDoc] || "").trim() || null,
    celular:   (f[cCel] || "").trim() || null,
    correo:    (f[cMail] || "").trim() || null,
    inicio, fin
  });
}

const porHora = {};
for (const m of salida) porHora[m.hora] = (porHora[m.hora] || 0) + 1;

return [{ json: { ok: true, total: salida.length, por_hora: porHora,
  descartados: descartes.length, detalle_descartes: descartes.slice(0, 10),
  filas: salida } }];

/*
 * Este archivo es la fuente de verdad del nodo "Parsear afiliados" del
 * workflow "Tumbao · Importar afiliados y recalcular cupos".
 * Si se cambia aquí, se cambia allá.
 *
 * El reporte real suele traer:
 *   fila 1  título fusionado "Reporte Afiliados con Membresía Activa"
 *   fila 2  encabezados
 *   fila 3+ los afiliados
 *
 * Pero "suele" no es "siempre": llegan archivos con filas de filtros, un
 * logo o líneas en blanco encima, y la cabecera baja. Por eso no se usa
 * ninguna posición fija. Se recorren hasta 50 filas, se puntúa cada una
 * por cuántas columnas conocidas trae, y gana la mejor. Reordenar las
 * columnas tampoco rompe nada, porque se mapean por nombre.
 *
 * "Afiliado" se exige EXACTO. Los reportes de un solo horario traen
 * "Afiliado Titular" y unas pocas filas; se rechazan a propósito, porque
 * importarlos borraría a casi todos los afiliados.
 *
 * La hora sale del texto de la membresía:
 *   "PLAN MENSUALIDAD 7:00AM"   -> 07:00:00, tipo plan
 *   "MEDIA MENSUALIDAD 6:00PM"  -> 18:00:00, tipo media
 * Ojo con el mediodía: 12:00PM es 12:00, no 24:00; 12:00AM es 00:00.
 *
 * Las fechas vienen como "30/jun./2026", con mes abreviado en español.
 */
