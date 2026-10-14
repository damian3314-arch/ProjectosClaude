// Convierte las filas del xlsx (arrays de texto) en membresias.
//
// La cabecera no esta siempre en la misma fila: se buscan hasta 50 filas y gana
// la que mas columnas conocidas trae (un titulo fusionado que diga "Afiliado"
// tiene una sola; la cabecera real tiene seis o siete).
// "Afiliado" se exige EXACTO: los exports de un solo horario traen
// "Afiliado Titular" y se rechazan a proposito (importarlos borraria a casi todos).
import { norm } from "./fechas.js";

const MESES = { ene: 1, feb: 2, mar: 3, abr: 4, may: 5, jun: 6, jul: 7,
  ago: 8, sep: 9, sept: 9, oct: 10, nov: 11, dic: 12 };

const MAX_FILAS_CABECERA = 50;
const MIN_COLUMNAS = 3;

const ETIQUETAS = [
  ["afiliado"], ["membresia"], ["# documento", "documento"], ["celular"],
  ["correo"], ["inicio membresia", "inicio"], ["final membresia", "final"],
];

const buscarCol = (cab, nombres) => {
  for (const n of nombres) {
    const i = cab.findIndex((c) => c === norm(n) || c.startsWith(norm(n)));
    if (i >= 0) return i;
  }
  return -1;
};

const hora24 = (txt) => {
  const m = /(\d{1,2}):(\d{2})\s*(a\.?m\.?|p\.?m\.?)/i.exec(String(txt || ""));
  if (!m) return null;
  let h = parseInt(m[1], 10);
  const pm = /p/i.test(m[3]);
  if (pm && h !== 12) h += 12;
  if (!pm && h === 12) h = 0;
  return String(h).padStart(2, "0") + ":" + m[2] + ":00";
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

export function parsearAfiliados(filasCrudas, archivo = null) {
  const filas = filasCrudas.map((r) => r.map((v) => (v == null ? "" : String(v))));

  let iCab = -1, mejorPuntaje = 0;
  for (let i = 0; i < filas.length && i < MAX_FILAS_CABECERA; i++) {
    const fila = filas[i].map(norm);
    if (!fila.some((c) => c === "afiliado")) continue;
    const puntaje = ETIQUETAS.reduce((n, a) => n + (buscarCol(fila, a) >= 0 ? 1 : 0), 0);
    if (puntaje > mejorPuntaje) { mejorPuntaje = puntaje; iCab = i; }
  }

  if (iCab === -1 || mejorPuntaje < MIN_COLUMNAS) {
    const vistas = Math.min(filas.length, MAX_FILAS_CABECERA);
    return { ok: false, error: "sin_cabecera", archivo, columnas_reconocidas: mejorPuntaje,
      mensaje: (iCab === -1
        ? "No se encontro la fila de encabezados: ninguna de las primeras " + vistas +
          " filas trae una columna llamada exactamente 'Afiliado'"
        : "Se encontro una fila con 'Afiliado' pero solo " + mejorPuntaje +
          " columnas reconocidas, y hacen falta " + MIN_COLUMNAS + ". Parece un titulo, no la cabecera") +
        (archivo ? " en " + archivo : "") +
        ". Suele pasar cuando el archivo es la exportacion de un solo horario " +
        "—esas traen 'Afiliado Titular'— y no el listado completo." };
  }

  const cab = filas[iCab].map(norm);
  const col = (...n) => buscarCol(cab, n);
  const cAfil = col("afiliado"), cMemb = col("membresia"), cDoc = col("# documento", "documento"),
    cCel = col("celular"), cMail = col("correo"), cIni = col("inicio membresia", "inicio"),
    cFin = col("final membresia", "final");

  const salida = [], descartes = [];
  for (let i = iCab + 1; i < filas.length; i++) {
    const f = filas[i];
    const afiliado = (f[cAfil] || "").trim();
    const memb = (f[cMemb] || "").trim();
    if (!afiliado && !memb) continue;

    const hora = hora24(memb), inicio = fechaISO(f[cIni]), fin = fechaISO(f[cFin]);
    if (!hora || !inicio || !fin) {
      descartes.push({ fila: i + 1, afiliado, membresia: memb,
        falta: [!hora && "hora", !inicio && "inicio", !fin && "fin"].filter(Boolean).join(", ") });
      continue;
    }
    salida.push({
      afiliado, membresia: memb, hora,
      tipo: /^media/i.test(memb) ? "media" : (/^plan/i.test(memb) ? "plan" : "otro"),
      documento: (f[cDoc] || "").trim() || null,
      celular: (f[cCel] || "").trim() || null,
      correo: (f[cMail] || "").trim() || null,
      inicio, fin,
    });
  }

  const porHora = {};
  for (const m of salida) porHora[m.hora] = (porHora[m.hora] || 0) + 1;

  return { ok: true, archivo, fila_cabecera: iCab + 1, total: salida.length,
    por_hora: porHora, descartados: descartes.length,
    detalle_descartes: descartes.slice(0, 10), filas: salida };
}
