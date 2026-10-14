// Fecha de hoy en Bogota como medianoche UTC (ms), y su anio/mes.
// Se calcula siempre con zona America/Bogota: el Worker corre en UTC y a las
// 02:30 UTC todavia es "ayer" en Colombia.
const partes = (now) => {
  const s = new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Bogota", year: "numeric", month: "2-digit", day: "2-digit",
  }).format(now);
  const [a, m, d] = s.split("-").map(Number);
  return { a, m, d };
};

export const hoyBogota = (now = new Date()) => {
  const { a, m, d } = partes(now);
  return Date.UTC(a, m - 1, d);
};

export const anioMesBogota = (now = new Date()) => {
  const { a, m } = partes(now);
  return { anio: String(a), mes: m };
};

export const norm = (s) => String(s == null ? "" : s)
  .normalize("NFD").replace(/[̀-ͯ]/g, "")
  .trim().toLowerCase();
