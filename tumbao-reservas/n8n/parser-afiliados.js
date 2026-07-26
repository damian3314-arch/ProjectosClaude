// El archivo trae el titulo en la fila 1 y los encabezados en la 2, asi
// que no se puede confiar en la primera fila. Se busca la cabecera por
// contenido; asi tampoco importa si reordenan columnas.
const MESES = { ene:1, feb:2, mar:3, abr:4, may:5, jun:6, jul:7,
                ago:8, sep:9, sept:9, oct:10, nov:11, dic:12 };

const norm = (s) => String(s == null ? "" : s)
  .normalize("NFD").replace(/[\u0300-\u036f]/g, "")
  .trim().toLowerCase();

const filas = $input.all().map(i => Object.values(i.json).map(v => v == null ? "" : String(v)));

let iCab = -1;
for (let i = 0; i < filas.length && i < 10; i++) {
  if (filas[i].some(c => norm(c) === "afiliado")) { iCab = i; break; }
}
if (iCab === -1) {
  return [{ json: { ok: false, error: "sin_cabecera",
    mensaje: "No se encontro la fila de encabezados (se buscaba la columna 'Afiliado')." } }];
}

const cab = filas[iCab].map(norm);
const col = (...nombres) => {
  for (const n of nombres) {
    const i = cab.findIndex(c => c === norm(n) || c.startsWith(norm(n)));
    if (i >= 0) return i;
  }
  return -1;
};
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
 * El reporte real trae:
 *   fila 1  título fusionado "Reporte Afiliados con Membresía Activa"
 *   fila 2  encabezados
 *   fila 3+ los afiliados
 *
 * Por eso NO se puede usar la primera fila como cabecera. Se busca la
 * fila que contenga "Afiliado" y se mapean las columnas por nombre, así
 * que reordenarlas tampoco rompe nada.
 *
 * La hora sale del texto de la membresía:
 *   "PLAN MENSUALIDAD 7:00AM"   -> 07:00:00, tipo plan
 *   "MEDIA MENSUALIDAD 6:00PM"  -> 18:00:00, tipo media
 * Ojo con el mediodía: 12:00PM es 12:00, no 24:00; 12:00AM es 00:00.
 *
 * Las fechas vienen como "30/jun./2026", con mes abreviado en español.
 */
