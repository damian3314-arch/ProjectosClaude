// Formato es-CO. Todos los montos son pesos colombianos enteros.
const nf = new Intl.NumberFormat('es-CO', { maximumFractionDigits: 0 });
const nf1 = new Intl.NumberFormat('es-CO', { minimumFractionDigits: 1, maximumFractionDigits: 1 });

export const cop = (n) => (n == null || Number.isNaN(n) ? '—' : '$ ' + nf.format(Math.round(n)));

export const copM = (n) => {
  if (n == null || Number.isNaN(n)) return '—';
  const abs = Math.abs(n);
  if (abs >= 1e6) return (n < 0 ? '-' : '') + '$ ' + nf1.format(abs / 1e6) + ' M';
  return cop(n);
};

export const pct = (n, dec = 1) =>
  n == null || Number.isNaN(n)
    ? '—'
    : (n * 100).toLocaleString('es-CO', { minimumFractionDigits: dec, maximumFractionDigits: dec }) + '%';

export const num = (n) => (n == null || Number.isNaN(n) ? '—' : nf.format(Math.round(n)));

// Variación relativa. Sin base de comparación (cero o ausente) devuelve null, nunca infinito.
export const variacion = (actual, previo) => (previo > 0 ? (actual - previo) / previo : null);

const MESES = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
export const mesCorto = (m) => MESES[m - 1];

export const fechaCorta = (s) => {
  const [y, m, d] = s.split('-').map(Number);
  return `${d} ${MESES[m - 1]} ${y}`;
};

export const diaMes = (s) => {
  const [, m, d] = s.split('-').map(Number);
  return `${d} ${MESES[m - 1]}`;
};

export const rangoTexto = ({ desde, hasta }) =>
  desde === hasta ? fechaCorta(hasta) : `${diaMes(desde)} – ${fechaCorta(hasta)}`;

export const esc = (s) =>
  String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
