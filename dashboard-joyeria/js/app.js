import { CONFIG } from './config.js';
import { cargarFuentes, normalizar } from './data.js';
import * as M from './metrics.js';
import { progresoMes, planRecuperacion } from './goals.js';
import { generarInsights } from './insights.js';
import { cargarOro, senalOro, primaMercado, gramoCOP, leerHistorial, registrarLectura, leerMercado, guardarMercado } from './gold.js';
import { cop, copM, pct, num, variacion, fechaCorta, diaMes, rangoTexto, esc, mesCorto } from './fmt.js';

const $ = (s) => document.querySelector(s);
const MESES = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];
const DIAS_CORTO = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];

const PERIODOS = [
  { k: 'dia', t: 'Último día', previo: 'misma jornada, semana pasada', anio: 'mismo día, año pasado' },
  { k: 'semana', t: 'Semana', previo: 'semana anterior', anio: 'año pasado' },
  { k: 'mes', t: 'Mes', previo: 'mes anterior', anio: 'año pasado' },
  { k: 'trimestre', t: 'Trimestre', previo: 'trimestre anterior', anio: 'año pasado' },
  { k: 'semestre', t: 'Semestre', previo: 'semestre anterior', anio: 'año pasado' },
  { k: 'anio', t: 'Año', previo: null, anio: 'año pasado' },
];

const S = {
  medida: 'facturado',
  periodoCuentas: 'mes',
  R: null,
  hoy: null,
  maxFecha: null,
  minFecha: null,
  datos: null,
  diario: null,
  oro: null,
  oroError: null,
  det: { desde: '', hasta: '', cuenta: '', tipo: '', q: '', pag: 0 },
};

const hoyBogota = () => new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Bogota' }).format(new Date());

// ---------- Arranque ----------
async function init() {
  S.hoy = hoyBogota();
  try {
    const fuentes = await cargarFuentes(CONFIG.fuentesDatos);
    S.datos = normalizar(fuentes);
  } catch (e) {
    $('#avisos-datos').innerHTML = `<div class="banda banda-alerta"><b>No pude cargar los datos.</b> ${esc(e.message)}</div>`;
    return;
  }
  if (!S.datos.resumen.length) {
    $('#avisos-datos').innerHTML = '<div class="banda banda-alerta"><b>La fuente no trae filas de resumen diario.</b> Revisa la hoja o el endpoint.</div>';
    return;
  }
  S.diario = M.construirDiario(S.datos.resumen);
  const fechas = S.datos.resumen.map((r) => r.fecha);
  S.minFecha = fechas[0];
  S.maxFecha = fechas.filter((f) => f <= S.hoy).at(-1) ?? fechas.at(-1);
  S.R = S.maxFecha;

  const inp = $('#corte');
  inp.min = S.minFecha;
  inp.max = S.maxFecha;
  inp.value = S.R;
  inp.addEventListener('change', () => {
    const v = inp.value;
    if (!v || !S.diario) return;
    S.R = v < S.minFecha ? S.minFecha : v > S.maxFecha ? S.maxFecha : v;
    inp.value = S.R;
    resetDetalle();
    render();
  });

  document.querySelectorAll('[data-medida]').forEach((b) =>
    b.addEventListener('click', () => {
      S.medida = b.dataset.medida;
      document.querySelectorAll('[data-medida]').forEach((x) => x.setAttribute('aria-pressed', String(x === b)));
      render();
    }));
  document.querySelectorAll('#periodo-cuentas [data-p]').forEach((b) =>
    b.addEventListener('click', () => {
      S.periodoCuentas = b.dataset.p;
      document.querySelectorAll('#periodo-cuentas [data-p]').forEach((x) => x.setAttribute('aria-pressed', String(x === b)));
      renderCuentas();
    }));
  $('#oro-refrescar').addEventListener('click', refrescarOro);

  resetDetalle();
  render();
  refrescarOro();
}

function resetDetalle() {
  const { y, m } = M.partes(S.R);
  S.det = { desde: M.ymd(y, m, 1), hasta: S.R, cuenta: '', tipo: '', q: '', pag: 0 };
}

function render() {
  renderAvisos();
  renderKPIs();
  renderMeta();
  renderCurva();
  renderCuentas();
  renderTemporada();
  renderInsights();
  renderDetalle();
  renderCalidad();
  renderPie();
}

const cfgHoy = () => ({ ...CONFIG, hoy: S.hoy });
const etiquetaMedida = () => (S.medida === 'facturado' ? 'facturado' : 'recaudo');

// ---------- Avisos ----------
function renderAvisos() {
  const partes = [];
  if (S.datos.demo) {
    partes.push('<div class="banda banda-demo"><b>Datos de demostración.</b> Las cifras de este tablero son sintéticas, no son ventas reales. Conecta la hoja real en <code>js/config.js</code> (ver README).</div>');
  }
  const desdeV = M.sumarDias(S.hoy, -(CONFIG.ventanaHuecos - 1));
  const h = M.huecos(S.diario, desdeV, S.hoy, CONFIG.diasCerrados);
  if (h.dias.length) {
    const txt = h.rangos.map((r) => (r.desde === r.hasta ? diaMes(r.desde) : `${diaMes(r.desde)} al ${diaMes(r.hasta)}`)).join(' · ');
    partes.push(`<div class="banda banda-alerta"><b>Datos cargados hasta el ${fechaCorta(S.maxFecha)}; hoy es ${fechaCorta(S.hoy)}.</b> Faltan ${h.dias.length} días por cargar (${esc(txt)}). Hasta que estén, los totales del periodo en curso están subestimados.</div>`);
  }
  $('#avisos-datos').innerHTML = partes.join('');
}

// ---------- KPIs ----------
function chipDelta(v, titulo) {
  if (v == null) return `<span class="chip nd" title="${esc(titulo)}">sin base</span>`;
  const cls = Math.abs(v) < 0.0005 ? 'igual' : v > 0 ? 'sube' : 'baja';
  const flecha = cls === 'sube' ? '▲' : cls === 'baja' ? '▼' : '■';
  return `<span class="chip ${cls}" title="${esc(titulo)}">${flecha} ${pct(Math.abs(v), 1)}</span>`;
}

function renderKPIs() {
  $('#nota-medida').textContent = S.medida === 'facturado'
    ? 'Facturado = ventas de contado + ventas a crédito del día, se hayan cobrado o no.'
    : 'Recaudo = ventas de contado + abonos a crédito: la plata que entró.';
  const campo = S.medida;
  $('#kpis').innerHTML = PERIODOS.map((p) => {
    const r = M.rangoAcumulado(p.k, S.R);
    const cur = M.datosRango(S.diario, r.desde, r.hasta);
    const filas = [];
    const fila = (etq, rango) => {
      const d = M.datosRango(S.diario, rango.desde, rango.hasta);
      const incompleta = d.diasConDatos < d.dias;
      const tit = `${etq}: ${cop(d[campo])} (${rangoTexto(rango)})` + (incompleta ? ` — base incompleta: ${d.diasConDatos} de ${d.dias} días con datos` : '');
      filas.push(`<div class="dl"><span>vs ${esc(etq)}${incompleta ? ' *' : ''}</span>${chipDelta(d[campo] > 0 ? variacion(cur[campo], d[campo]) : null, tit)}</div>`);
    };
    if (p.previo) fila(p.previo, M.rangoComparable(p.k, S.R, 'previo'));
    fila(p.anio, M.rangoComparable(p.k, S.R, 'anio'));
    const incompletoActual = cur.diasConDatos < cur.dias;
    return `<article class="kpi">
      <h3>${p.t}</h3>
      <p class="v">${copM(cur[campo])}</p>
      <p class="rango">${esc(rangoTexto(r))}${incompletoActual ? ` · <span style="color:var(--aviso)">${cur.diasConDatos}/${cur.dias} días con datos</span>` : ''}</p>
      ${filas.join('')}
    </article>`;
  }).join('');
}

// ---------- Meta ----------
function renderMeta() {
  const p = progresoMes(S.diario, S.R, CONFIG);
  const proy = p.proyEstacional ?? p.proyLineal;
  const base = p.proyEstacional != null ? 'según la forma del mismo mes del año pasado' : 'según el ritmo diario del mes';
  const estado = proy < p.equilibrio ? ['alerta', 'Por debajo del equilibrio'] : proy < p.meta ? ['aviso', 'Entre equilibrio y meta'] : ['ok', 'En camino a la meta'];
  const max = Math.max(p.meta * 1.15, p.acumulado * 1.05);
  const w = (v) => Math.min(100, (v / max) * 100);
  const nota = S.medida === 'recaudo' ? '<p class="nota" style="margin-top:6px">La meta se mide sobre lo facturado, sin importar la medida elegida arriba.</p>' : '';
  $('#meta').innerHTML = `<div class="meta-grid">
    <div>
      <span class="estado ${estado[0]}">${estado[1]}</span>
      <p class="meta-num">${copM(p.acumulado)}<small>facturado en ${MESES[M.partes(S.R).m - 1]} (día ${p.diaActual} de ${p.diasMes})</small></p>
      <div class="barra" role="img" aria-label="Avance: ${pct(p.pctMeta, 0)} de la meta">
        <div class="barra-llena" style="width:${w(p.acumulado)}%"></div>
        <div class="marca-t" style="left:${w(p.equilibrio)}%"><span>Equilibrio ${copM(p.equilibrio)}</span></div>
        <div class="marca-t m-arriba" style="left:${w(p.meta)}%"><span>Meta ${copM(p.meta)}</span></div>
      </div>
      ${nota}
    </div>
    <div class="cifras">
      <div class="cifra"><p class="t">Avance sobre la meta</p><p class="n">${pct(p.pctMeta, 1)}</p></div>
      <div class="cifra"><p class="t">Avance sobre el equilibrio</p><p class="n">${pct(p.pctEquilibrio, 1)}</p></div>
      <div class="cifra"><p class="t">Falta para el equilibrio</p><p class="n">${copM(p.faltaEquilibrio)}</p></div>
      <div class="cifra"><p class="t">Falta para la meta</p><p class="n">${copM(p.faltaMeta)}</p></div>
      <div class="cifra"><p class="t">Hay que vender por día (meta)</p><p class="n">${p.reqDiarioMeta == null ? '—' : copM(p.reqDiarioMeta)}</p></div>
      <div class="cifra"><p class="t">Ritmo actual por día</p><p class="n">${copM(p.ritmoDiario)}</p></div>
      <div class="cifra" style="grid-column:1/-1"><p class="t">Cierre proyectado ${base}</p><p class="n">${copM(proy)}</p>
        ${p.proyEstacional != null ? `<p class="sub">Con ritmo lineal sería ${copM(p.proyLineal)}.</p>` : '<p class="sub">No hay un mes del año pasado completo para comparar la forma de la curva.</p>'}</div>
    </div>
  </div>`;
}

// ---------- Curva acumulada ----------
function ticksNice(max, n = 5) {
  const crudo = max / n;
  const mag = 10 ** Math.floor(Math.log10(crudo));
  const paso = [1, 2, 2.5, 5, 10].map((x) => x * mag).find((x) => x >= crudo) ?? 10 * mag;
  const out = [];
  for (let v = 0; v <= max + paso * 0.001; v += paso) out.push(v);
  return out;
}

function renderCurva() {
  const { y, m } = M.partes(S.R);
  const prev = M.partes(M.sumarMeses(S.R, -1));
  const ant = M.partes(M.sumarMeses(S.R, -12));
  const campo = S.medida;
  const n = M.diasDelMes(y, m);
  const series = [
    { id: 'act', nombre: `${MESES[m - 1]} ${y}`, color: 'var(--serie-1)', ancho: 3, valores: M.curvaMes(S.diario, y, m, campo, S.R) },
    { id: 'prev', nombre: `${MESES[prev.m - 1]} ${prev.y}`, color: 'var(--serie-2)', ancho: 2, valores: M.curvaMes(S.diario, prev.y, prev.m, campo) },
    { id: 'anio', nombre: `${MESES[ant.m - 1]} ${ant.y}`, color: 'var(--serie-3)', ancho: 2, dash: '6 5', valores: M.curvaMes(S.diario, ant.y, ant.m, campo) },
  ];
  const lineas = S.medida === 'facturado' ? [{ v: CONFIG.puntoEquilibrioMensual, t: 'Equilibrio' }, { v: CONFIG.metaMensual, t: 'Meta' }] : [];
  const W = 920, H = 320, L = 58, R = 18, T = 16, B = 32;
  const topVal = Math.max(...series.flatMap((s) => s.valores.filter((v) => v != null)), ...lineas.map((l) => l.v), 1) * 1.05;
  const ticks = ticksNice(topVal);
  const ymax = ticks.at(-1);
  const X = (d) => L + ((d - 1) / Math.max(1, n - 1)) * (W - L - R);
  const Y = (v) => T + (1 - v / ymax) * (H - T - B);

  const grid = ticks.map((v) => `<line x1="${L}" x2="${W - R}" y1="${Y(v)}" y2="${Y(v)}" stroke="var(--line)" stroke-width="1"/><text x="${L - 8}" y="${Y(v) + 4}" text-anchor="end" font-size="11" fill="var(--ink-3)">${v === 0 ? '0' : (v / 1e6).toLocaleString('es-CO', { maximumFractionDigits: 1 }) + ' M'}</text>`).join('');
  const xl = [];
  for (let d = 1; d <= n; d++) if (d === 1 || d % 5 === 0 || d === n) xl.push(`<text x="${X(d)}" y="${H - 10}" text-anchor="middle" font-size="11" fill="var(--ink-3)">${d}</text>`);
  const ref = lineas.map((l) => `<line x1="${L}" x2="${W - R}" y1="${Y(l.v)}" y2="${Y(l.v)}" stroke="var(--ink-3)" stroke-dasharray="3 4"/><text x="${W - R}" y="${Y(l.v) - 5}" text-anchor="end" font-size="11" fill="var(--ink-2)">${l.t} ${copM(l.v)}</text>`).join('');
  const trazos = series.map((s) => {
    let d = '';
    let lapiz = false;
    s.valores.forEach((v, i) => {
      if (v == null) { lapiz = false; return; }
      d += `${lapiz ? 'L' : 'M'}${X(i + 1).toFixed(1)} ${Y(v).toFixed(1)} `;
      lapiz = true;
    });
    return `<path d="${d}" fill="none" stroke="${s.color}" stroke-width="${s.ancho}" ${s.dash ? `stroke-dasharray="${s.dash}"` : ''} stroke-linecap="round" stroke-linejoin="round"/>`;
  }).join('');

  const hayAnt = series[2].valores.some((v) => v > 0);
  $('#curva').innerHTML = `
    <div class="leyenda">${series.map((s) => `<span><i style="background:${s.color}${s.dash ? ';opacity:.8' : ''}"></i>${esc(s.nombre)}${s.id === 'anio' && !hayAnt ? ' (sin datos)' : ''}</span>`).join('')}</div>
    <div class="chart">
      <svg viewBox="0 0 ${W} ${H}" role="img" aria-label="Venta acumulada del mes comparada con el mes anterior y el año pasado">
        ${grid}${xl.join('')}${ref}${trazos}
        <line id="guia" x1="0" x2="0" y1="${T}" y2="${H - B}" stroke="var(--ink-3)" stroke-width="1" visibility="hidden"/>
        <rect id="hit" x="${L}" y="${T}" width="${W - L - R}" height="${H - T - B}" fill="transparent"/>
      </svg>
    </div>`;

  const svg = $('#curva svg');
  const tip = $('#tip');
  const hit = $('#hit');
  const guia = $('#guia');
  const mover = (ev) => {
    const r = svg.getBoundingClientRect();
    const px = ((ev.clientX - r.left) / r.width) * W;
    const d = Math.min(n, Math.max(1, Math.round(((px - L) / (W - L - R)) * (n - 1)) + 1));
    guia.setAttribute('x1', X(d)); guia.setAttribute('x2', X(d)); guia.setAttribute('visibility', 'visible');
    tip.innerHTML = `<b>Día ${d}</b>` + series.map((s) => `<div><span>${esc(s.nombre)}</span><span>${s.valores[d - 1] == null ? '—' : copM(s.valores[d - 1])}</span></div>`).join('');
    tip.hidden = false;
    const ancho = tip.offsetWidth;
    tip.style.left = Math.min(window.innerWidth - ancho - 8, ev.clientX + 14) + 'px';
    tip.style.top = ev.clientY + 14 + 'px';
  };
  hit.addEventListener('pointermove', mover);
  hit.addEventListener('pointerleave', () => { tip.hidden = true; guia.setAttribute('visibility', 'hidden'); });
}

// ---------- Cuentas ----------
function renderCuentas() {
  const tipo = S.periodoCuentas;
  const r = M.rangoAcumulado(tipo, S.R);
  const act = M.porCuenta(S.datos.movimientos, r.desde, r.hasta);
  const rp = M.rangoComparable(tipo, S.R, tipo === 'anio' ? 'anio' : 'previo');
  const prev = new Map(M.porCuenta(S.datos.movimientos, rp.desde, rp.hasta).map((c) => [c.clave, c]));
  const primero = M.primerMovimientoPorCuenta(S.datos.movimientos);
  const total = act.reduce((s, c) => s + c.total, 0);
  const tVenta = act.reduce((s, c) => s + c.venta, 0);
  const tAbono = act.reduce((s, c) => s + c.abono, 0);
  const tOtro = act.reduce((s, c) => s + c.otro, 0);
  const tN = act.reduce((s, c) => s + c.n, 0);
  const etqPrev = PERIODOS.find((p) => p.k === tipo);

  if (!act.length) {
    $('#cuentas').innerHTML = `<p class="vacio">No hay movimientos entre ${esc(rangoTexto(r))}.</p>`;
    return;
  }
  const filas = act.map((c) => {
    const pv = prev.get(c.clave);
    const f = primero.get(c.clave);
    const nueva = f && M.diasEntre(f, S.R) <= CONFIG.diasCuentaNueva && M.diasEntre(S.minFecha, f) > CONFIG.diasCuentaNueva;
    const v = pv && pv.total > 0 ? variacion(c.total, pv.total) : null;
    return `<tr>
      <td><span class="cta-nombre">${esc(c.nombre)}${nueva ? `<span class="etq" title="Primer movimiento: ${fechaCorta(f)}">nueva</span>` : ''}</span></td>
      <td class="n">${cop(c.venta)}</td>
      <td class="n">${cop(c.abono)}</td>
      <td class="n"><b>${cop(c.total)}</b></td>
      <td class="n" style="min-width:130px"><div style="display:flex;align-items:center;gap:8px;justify-content:flex-end"><span>${pct(c.pct, 1)}</span><div class="mini" style="width:70px"><i style="width:${(c.pct * 100).toFixed(1)}%"></i></div></div></td>
      <td class="n">${num(c.n)}</td>
      <td class="n">${v == null ? '<span class="chip nd">sin base</span>' : chipDelta(v, `${etqPrev.previo || etqPrev.anio}: ${cop(pv.total)}`)}</td>
    </tr>`;
  }).join('');
  $('#cuentas').innerHTML = `
    <p class="nota" style="margin-bottom:10px">${esc(rangoTexto(r))} · comparado con ${esc(rangoTexto(rp))}. “Ventas” son pagos de contado; “Abonos”, pagos a créditos.</p>
    <div class="tabla-wrap"><table>
      <thead><tr><th>Cuenta</th><th class="n">Ventas</th><th class="n">Abonos</th><th class="n">Total</th><th class="n">Participación</th><th class="n">Pagos</th><th class="n">Cambio</th></tr></thead>
      <tbody>${filas}</tbody>
      <tfoot><tr><td>Total</td><td class="n">${cop(tVenta)}</td><td class="n">${cop(tAbono)}</td><td class="n">${cop(total)}</td><td class="n">100%</td><td class="n">${num(tN)}</td><td></td></tr></tfoot>
    </table></div>
    ${tOtro ? `<p class="nota" style="margin-top:8px;color:var(--aviso)">Hay ${cop(tOtro)} en movimientos que no son ni VENTA ni ABONO; están dentro del total.</p>` : ''}`;
}

// ---------- Temporada ----------
function renderTemporada() {
  const p = planRecuperacion(S.diario, S.R, CONFIG);
  if (!p.diasRestantes) {
    $('#temporada').innerHTML = '<p class="vacio">El corte está en el último día del año; no queda nada por proyectar.</p>';
    return;
  }
  const mult = p.usaAnioAnterior
    ? `El reparto sigue la forma de ventas del año pasado (${pct(p.cobertura, 0)} de los días restantes tienen dato).`
    : 'No hay suficiente historia del año pasado: el reparto usa multiplicadores por fecha pico definidos en config.js. Son supuestos, no mediciones.';
  const intu = CONFIG.intuicionNovDic;
  const cubre = p.novDic.meta > 0 ? intu / p.novDic.meta : null;
  const filasMes = p.meses.map((x) => `<tr>
    <td>${MESES[x.mes - 1]}<br><span class="nota">${esc(rangoTexto(x))}</span></td>
    <td class="n">${cop(x.equilibrio)}</td><td class="n"><b>${cop(x.meta)}</b></td><td class="n">${x.anioPasado ? cop(x.anioPasado) : '—'}</td>
    <td class="n">${x.anioPasado ? chipDelta(variacion(x.meta, x.anioPasado), 'Meta necesaria frente a lo vendido en esas fechas el año pasado') : '—'}</td></tr>`).join('');
  const filasEv = p.ventanas.map((v) => `<tr>
    <td>${esc(v.nombre)}<br><span class="nota">${esc(rangoTexto(v))} · ${v.dias} ${v.dias === 1 ? 'día' : 'días'}</span></td>
    <td class="n">${cop(v.equilibrio)}</td><td class="n"><b>${cop(v.meta)}</b></td>
    <td class="n">${cop(v.meta / v.dias)}</td><td class="n">${v.anioPasado ? cop(v.anioPasado) : '—'}</td></tr>`).join('');

  $('#temporada').innerHTML = `
    <div class="res3">
      <div class="cifra"><p class="t">Vendido en el año hasta el corte</p><p class="n">${copM(p.ytd)}</p><p class="sub">${esc(rangoTexto({ desde: M.ymd(M.partes(S.R).y, 1, 1), hasta: S.R }))}</p></div>
      <div class="cifra"><p class="t">Falta para cerrar el año en equilibrio</p><p class="n">${copM(p.equilibrio.necesario)}</p><p class="sub">Equilibrio anual ${copM(p.equilibrio.objetivo)} (12 × ${copM(CONFIG.puntoEquilibrioMensual)})</p></div>
      <div class="cifra"><p class="t">Falta para cerrar el año en meta</p><p class="n">${copM(p.meta.necesario)}</p><p class="sub">Meta anual ${copM(p.meta.objetivo)} (12 × ${copM(CONFIG.metaMensual)})</p></div>
    </div>
    <div class="callout"><b>Contraste con tu cálculo:</b> pensabas en ${copM(intu)} para noviembre y diciembre. Para cerrar el año en meta, esos dos meses tendrían que aportar ${copM(p.novDic.meta)}${cubre != null ? `; tu cifra cubre el ${pct(cubre, 0)}` : ''}.
      ${p.novDic.anioPasado ? ` El año pasado, Nov+Dic vendieron ${copM(p.novDic.anioPasado)}.` : ' No hay Nov+Dic del año pasado cargados para comparar.'}
      ${p.desdeRestante && p.desdeRestante <= S.hoy ? `<br><span class="nota">Ojo: los días ${esc(diaMes(p.desdeRestante))} a ${esc(diaMes(S.hoy))} aún no tienen datos y cuentan como pendientes; cuando se carguen, lo necesario bajará.</span>` : ''}</div>
    <p class="nota" style="margin-bottom:12px">${esc(mult)}</p>
    <div class="tabla-wrap"><table>
      <thead><tr><th>Mes (lo que queda)</th><th class="n">Para equilibrio anual</th><th class="n">Para meta anual</th><th class="n">Mismas fechas, año pasado</th><th class="n">Meta vs año pasado</th></tr></thead>
      <tbody>${filasMes}</tbody></table></div>
    ${filasEv ? `<h3 style="font-size:16px;margin:22px 0 8px">Fechas pico</h3>
    <div class="tabla-wrap"><table>
      <thead><tr><th>Ventana</th><th class="n">Para equilibrio</th><th class="n">Para meta</th><th class="n">Meta por día</th><th class="n">Año pasado, mismas fechas</th></tr></thead>
      <tbody>${filasEv}</tbody></table></div>` : ''}`;
}

// ---------- Insights ----------
function renderInsights() {
  const meta = progresoMes(S.diario, S.R, CONFIG);
  const plan = planRecuperacion(S.diario, S.R, CONFIG);
  const lista = generarInsights({
    diario: S.diario, movs: S.datos.movimientos, R: S.R, meta, plan, cfg: cfgHoy(),
    cuentas1stSeen: M.primerMovimientoPorCuenta(S.datos.movimientos),
  });
  $('#insights').innerHTML = lista.length
    ? lista.map((i) => `<article class="ins ${i.nivel}"><h3>${esc(i.titulo)}</h3><p>${esc(i.detalle)}</p></article>`).join('')
    : '<p class="vacio">Aún no hay datos suficientes para sacar hallazgos.</p>';
}

// ---------- Oro ----------
async function refrescarOro() {
  const btn = $('#oro-refrescar');
  btn.disabled = true;
  btn.textContent = 'Actualizando…';
  try {
    S.oro = await cargarOro();
    S.oroError = null;
    registrarLectura(S.hoy, S.oro.cop24);
  } catch (e) {
    S.oroError = e.message;
  }
  btn.disabled = false;
  btn.textContent = 'Actualizar';
  renderOro();
}

function renderOro() {
  const caja = $('#oro');
  if (!S.oro) {
    caja.innerHTML = `<p class="vacio">${S.oroError ? `No pude traer el precio: ${esc(S.oroError)}` : 'Cargando precio…'}</p>`;
    return;
  }
  const o = S.oro;
  const hist = leerHistorial();
  const senal = senalOro(hist, S.hoy, Math.round(o.cop24), CONFIG.oro);
  const mercado = leerMercado();
  const k18 = o.cop24 * 0.75;
  const filasK = CONFIG.oro.quilates.map((q) => `<tr><td>${q.k}k</td><td class="n">${cop(o.cop24 * q.pureza)}</td></tr>`).join('');

  let txtSenal;
  if (senal.estado === 'sin-datos') {
    txtSenal = `<b>Sin señal todavía.</b> Hay ${senal.lecturas} lecturas guardadas en este navegador y se necesitan ${CONFIG.oro.minLecturas}. Se guarda una por día al abrir el tablero. Para no depender del navegador, conviene registrar el precio a diario en la hoja con n8n.`;
  } else {
    const d = pct(Math.abs(senal.desviacion), 1);
    const m = {
      alto: `<b>Precio alto:</b> hoy está ${d} por encima de su promedio de ${senal.lecturas} lecturas (${cop(senal.promedio)}/g 24k). Como referencia: momento favorable para vender oro o inventario, y menos favorable para comprar.`,
      bajo: `<b>Precio bajo:</b> hoy está ${d} por debajo de su promedio de ${senal.lecturas} lecturas (${cop(senal.promedio)}/g 24k). Como referencia: momento favorable para comprar oro, y menos favorable para vender.`,
      neutral: `<b>Sin desviación relevante:</b> hoy está a ${d} de su promedio de ${senal.lecturas} lecturas (${cop(senal.promedio)}/g 24k).`,
    };
    txtSenal = m[senal.estado];
  }

  let txtMercado = '<p class="nota">Aún no has registrado el precio de mercado de hoy.</p>';
  if (mercado && mercado.fecha) {
    const c = mercado.compra18 ? primaMercado(mercado.compra18, k18) : null;
    const v = mercado.venta18 ? primaMercado(mercado.venta18, k18) : null;
    txtMercado = `<p class="nota">Último registro: ${fechaCorta(mercado.fecha)}.</p>
      <div class="cifras" style="margin-top:8px">
        <div class="cifra"><p class="t">Compra 18k (lo que pagan)</p><p class="n">${mercado.compra18 ? cop(mercado.compra18) : '—'}</p><p class="sub">${c == null ? '' : `${c >= 0 ? '+' : '−'}${pct(Math.abs(c), 1)} vs bolsa 18k`}</p></div>
        <div class="cifra"><p class="t">Venta 18k (lo que cobran)</p><p class="n">${mercado.venta18 ? cop(mercado.venta18) : '—'}</p><p class="sub">${v == null ? '' : `${v >= 0 ? '+' : '−'}${pct(Math.abs(v), 1)} vs bolsa 18k`}</p></div>
      </div>`;
  }

  caja.innerHTML = `<div class="oro-grid">
    <div>
      <p class="nota">Bolsa (precio internacional convertido a pesos)</p>
      <p class="oro-precio">${cop(o.cop24)} <small style="font:400 14px var(--f-texto);color:var(--ink-3)">/ gramo 24k</small></p>
      <p class="sub">${o.usdOz.toLocaleString('es-CO', { minimumFractionDigits: 2 })} USD por onza troy × TRM ${o.trm.toLocaleString('es-CO', { minimumFractionDigits: 2 })} (${fechaCorta(o.trmFecha)}) ÷ 31,1035 g</p>
      <div class="tabla-wrap" style="margin-top:12px"><table style="max-width:300px"><thead><tr><th>Quilates</th><th class="n">COP / gramo</th></tr></thead><tbody>${filasK}</tbody></table></div>
      <div class="senal ${senal.estado}">${txtSenal}</div>
      <p class="nota" style="margin-top:8px">Es una referencia mecánica contra el promedio de lecturas propias, no una recomendación de inversión.</p>
    </div>
    <div>
      <h3 style="font-size:16px">Mercado (compraventas)</h3>
      <p class="nota">No existe una fuente pública confiable del precio de mercado local, así que lo registras tú una vez al día.</p>
      <form id="form-mercado" class="form-fila" autocomplete="off">
        <label>Compra 18k, $/g<input name="compra18" inputmode="numeric" placeholder="ej. 290000" value="${mercado?.compra18 ?? ''}"></label>
        <label>Venta 18k, $/g<input name="venta18" inputmode="numeric" placeholder="ej. 330000" value="${mercado?.venta18 ?? ''}"></label>
        <div style="grid-column:1/-1"><button class="btn btn-oro" type="submit">Guardar precio de hoy</button></div>
      </form>
      ${txtMercado}
    </div>
  </div>`;

  $('#form-mercado').addEventListener('submit', (ev) => {
    ev.preventDefault();
    const f = new FormData(ev.target);
    const lee = (k) => { const n = Number(String(f.get(k)).replace(/[^\d]/g, '')); return n > 0 ? n : null; };
    guardarMercado({ fecha: S.hoy, compra18: lee('compra18'), venta18: lee('venta18') });
    renderOro();
  });
}

// ---------- Detalle ----------
const POR_PAG = 40;
function movsFiltrados() {
  const { desde, hasta, cuenta, tipo, q } = S.det;
  const qq = q.trim().toLowerCase();
  return S.datos.movimientos.filter((x) =>
    (!desde || x.fecha >= desde) && (!hasta || x.fecha <= hasta) &&
    (!cuenta || x.cuentaClave === cuenta) && (!tipo || x.tipo === tipo) &&
    (!qq || x.cliente.toLowerCase().includes(qq)));
}

function renderDetalle() {
  const cuentas = [...new Map(S.datos.movimientos.map((x) => [x.cuentaClave, x.cuenta])).entries()].sort((a, b) => a[1].localeCompare(b[1], 'es'));
  const d = S.det;
  $('#detalle').innerHTML = `
    <div class="filtros">
      <label>Desde<input type="date" id="f-desde" value="${d.desde}"></label>
      <label>Hasta<input type="date" id="f-hasta" value="${d.hasta}"></label>
      <label>Cuenta<select id="f-cuenta"><option value="">Todas</option>${cuentas.map(([k, n]) => `<option value="${esc(k)}" ${d.cuenta === k ? 'selected' : ''}>${esc(n)}</option>`).join('')}</select></label>
      <label>Tipo<select id="f-tipo"><option value="">Todos</option><option value="VENTA" ${d.tipo === 'VENTA' ? 'selected' : ''}>Venta</option><option value="ABONO" ${d.tipo === 'ABONO' ? 'selected' : ''}>Abono</option><option value="OTRO" ${d.tipo === 'OTRO' ? 'selected' : ''}>Otro</option></select></label>
      <label>Cliente<input type="search" id="f-q" placeholder="Buscar…" value="${esc(d.q)}"></label>
      <button class="btn" type="button" id="f-csv">Descargar CSV</button>
    </div>
    <div id="detalle-tabla"></div>`;
  const act = (id, k) => $(id).addEventListener('input', (e) => { S.det[k] = e.target.value; S.det.pag = 0; pintarTablaDetalle(); });
  act('#f-desde', 'desde'); act('#f-hasta', 'hasta'); act('#f-cuenta', 'cuenta'); act('#f-tipo', 'tipo'); act('#f-q', 'q');
  $('#f-csv').addEventListener('click', descargarCSV);
  pintarTablaDetalle();
}

function pintarTablaDetalle() {
  const lista = movsFiltrados();
  const total = lista.reduce((s, x) => s + x.valor, 0);
  const paginas = Math.max(1, Math.ceil(lista.length / POR_PAG));
  S.det.pag = Math.min(S.det.pag, paginas - 1);
  const trozo = [...lista].reverse().slice(S.det.pag * POR_PAG, (S.det.pag + 1) * POR_PAG);
  const dow = (f) => DIAS_CORTO[M.diaSemana(f)];
  $('#detalle-tabla').innerHTML = lista.length ? `
    <div class="tabla-wrap"><table>
      <thead><tr><th>Fecha</th><th>Cliente</th><th>Cuenta</th><th>Tipo</th><th class="n">Valor</th></tr></thead>
      <tbody>${trozo.map((x) => `<tr><td>${dow(x.fecha)} ${fechaCorta(x.fecha)}</td><td>${esc(x.cliente)}</td><td>${esc(x.cuenta)}</td><td><span class="tipo ${esc(x.tipo)}">${esc(x.tipo)}</span></td><td class="n">${cop(x.valor)}</td></tr>`).join('')}</tbody>
    </table></div>
    <div class="pag"><span>${num(lista.length)} movimientos · total <b>${cop(total)}</b></span>
      <span><button class="btn" type="button" id="p-ant" ${S.det.pag === 0 ? 'disabled' : ''}>←</button> Página ${S.det.pag + 1} de ${paginas} <button class="btn" type="button" id="p-sig" ${S.det.pag >= paginas - 1 ? 'disabled' : ''}>→</button></span></div>`
    : '<p class="vacio">Ningún movimiento con esos filtros.</p>';
  $('#p-ant')?.addEventListener('click', () => { S.det.pag--; pintarTablaDetalle(); });
  $('#p-sig')?.addEventListener('click', () => { S.det.pag++; pintarTablaDetalle(); });
}

// Celdas que empiezan con = + - @ se neutralizan para que Excel/Sheets no las ejecute como fórmula.
const celdaCSV = (v) => {
  let s = String(v ?? '');
  if (/^[=+\-@\t\r]/.test(s)) s = "'" + s;
  return /[",\n\r]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s;
};
function descargarCSV() {
  const filas = [['Fecha', 'Cliente', 'Valor', 'Cuenta_Destino', 'Tipo'], ...movsFiltrados().map((x) => [x.fecha, x.cliente, x.valor, x.cuenta, x.tipo])];
  const blob = new Blob(['﻿' + filas.map((f) => f.map(celdaCSV).join(',')).join('\n')], { type: 'text/csv;charset=utf-8' });
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = `movimientos_${S.det.desde || 'inicio'}_${S.det.hasta || 'fin'}.csv`;
  a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 1000);
}

// ---------- Calidad ----------
function renderCalidad() {
  const desdeV = M.sumarDias(S.hoy, -(CONFIG.ventanaHuecos - 1));
  const h = M.huecos(S.diario, desdeV, S.hoy, CONFIG.diasCerrados);
  const dif = M.cuadre(S.datos.movimientos, S.diario, CONFIG.toleranciaCuadre);
  const sinResumen = dif.filter((x) => x.motivo === 'sin resumen');
  const noCuadra = dif.filter((x) => x.motivo === 'no cuadra');
  const errores = S.datos.avisos.filter((a) => a.nivel === 'error');
  const cuentas = M.porCuenta(S.datos.movimientos, S.minFecha, S.maxFecha);

  $('#calidad').innerHTML = `
    <div class="cal-grid">
      <div class="cifra"><p class="t">Días con resumen</p><p class="n">${num(S.datos.resumen.length)}</p><p class="sub">${fechaCorta(S.minFecha)} a ${fechaCorta(S.maxFecha)}</p></div>
      <div class="cifra"><p class="t">Movimientos leídos</p><p class="n">${num(S.datos.movimientos.length)}</p><p class="sub">${cuentas.length} cuentas detectadas</p></div>
      <div class="cifra"><p class="t">Días sin cargar (últimos ${CONFIG.ventanaHuecos})</p><p class="n" style="color:${h.dias.length ? 'var(--mal)' : 'var(--ok)'}">${h.dias.length}</p></div>
      <div class="cifra"><p class="t">Días que no cuadran</p><p class="n" style="color:${noCuadra.length ? 'var(--aviso)' : 'var(--ok)'}">${noCuadra.length}</p><p class="sub">Σ movimientos ≠ contado + abonos del resumen</p></div>
      <div class="cifra"><p class="t">Movimientos sin resumen</p><p class="n" style="color:${sinResumen.length ? 'var(--aviso)' : 'var(--ok)'}">${sinResumen.length}</p><p class="sub">Días con pagos pero sin fila diaria</p></div>
      <div class="cifra"><p class="t">Filas ilegibles</p><p class="n" style="color:${errores.length ? 'var(--mal)' : 'var(--ok)'}">${errores.length}</p><p class="sub">Ignoradas, con aviso</p></div>
    </div>
    ${noCuadra.length ? `<details><summary>Días que no cuadran (${noCuadra.length})</summary><div class="tabla-wrap"><table>
      <thead><tr><th>Fecha</th><th class="n">Σ movimientos</th><th class="n">Resumen</th><th class="n">Diferencia</th></tr></thead>
      <tbody>${noCuadra.slice(0, 40).map((x) => `<tr><td>${fechaCorta(x.fecha)}</td><td class="n">${cop(x.movimientos)}</td><td class="n">${cop(x.resumen)}</td><td class="n">${cop(x.dif)}</td></tr>`).join('')}</tbody></table></div></details>` : ''}
    ${S.datos.avisos.length ? `<details><summary>Avisos de lectura (${S.datos.avisos.length})</summary><ul class="lista">${S.datos.avisos.slice(0, 40).map((a) => `<li>${esc(a.texto)}</li>`).join('')}</ul></details>` : ''}
    <details><summary>Cuentas detectadas</summary><ul class="lista">${cuentas.map((c) => `<li>${esc(c.nombre)} · ${num(c.n)} pagos</li>`).join('')}</ul>
      <p class="nota" style="margin-top:6px">Una cuenta nueva aparece sola en cuanto llega su primer movimiento; no hay que configurarla.</p></details>`;
}

function renderPie() {
  const meta = S.datos.demo ? 'Datos de demostración' : 'Fuente: hoja de Google Sheets';
  $('#pie').textContent = `${meta} · Corte ${fechaCorta(S.R)} · Hoy ${fechaCorta(S.hoy)} (hora de Bogotá) · Montos en pesos colombianos.`;
}

init();
