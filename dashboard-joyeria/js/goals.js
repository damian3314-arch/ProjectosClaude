import * as M from './metrics.js';

// Avance del mes en curso contra equilibrio y meta, con dos proyecciones:
//  - lineal: ritmo diario promedio del mes
//  - estacional: cuánto del mes ya se había vendido, a esta misma altura, el año anterior
export function progresoMes(diario, R, cfg) {
  const { y, m, d } = M.partes(R);
  const dim = M.diasDelMes(y, m);
  const inicio = M.ymd(y, m, 1);
  const acum = M.datosRango(diario, inicio, R).facturado;
  const restantes = dim - d;
  const req = (obj) => (restantes > 0 ? Math.max(0, obj - acum) / restantes : null);

  const hPrev = M.sumarMeses(R, -12);
  const pp = M.partes(hPrev);
  const iniPrev = M.ymd(pp.y, pp.m, 1);
  const finPrev = M.ymd(pp.y, pp.m, M.diasDelMes(pp.y, pp.m));
  const totPrev = M.datosRango(diario, iniPrev, finPrev);
  const parcPrev = M.datosRango(diario, iniPrev, hPrev).facturado;
  // Sólo confiamos en el año anterior si ese mes tiene (casi) todos sus días cargados.
  const cobertura = totPrev.diasConDatos / totPrev.dias;
  const share = totPrev.facturado > 0 && cobertura >= 0.8 ? parcPrev / totPrev.facturado : null;

  return {
    desde: inicio,
    hasta: R,
    diasMes: dim,
    diaActual: d,
    restantes,
    acumulado: acum,
    equilibrio: cfg.puntoEquilibrioMensual,
    meta: cfg.metaMensual,
    pctEquilibrio: acum / cfg.puntoEquilibrioMensual,
    pctMeta: acum / cfg.metaMensual,
    faltaEquilibrio: Math.max(0, cfg.puntoEquilibrioMensual - acum),
    faltaMeta: Math.max(0, cfg.metaMensual - acum),
    reqDiarioEquilibrio: req(cfg.puntoEquilibrioMensual),
    reqDiarioMeta: req(cfg.metaMensual),
    ritmoDiario: acum / d,
    proyLineal: (acum / d) * dim,
    proyEstacional: share && share >= 0.1 ? acum / share : null,
    shareAnioAnterior: share,
  };
}

// Qué hay que vender de aquí a fin de año para cerrarlo en equilibrio o en meta,
// repartido por fecha pico. El reparto sigue la forma del año anterior si hay datos; si no, los multiplicadores de config.
export function planRecuperacion(diario, R, cfg) {
  const { y } = M.partes(R);
  const ytd = M.datosRango(diario, M.ymd(y, 1, 1), R).facturado;
  const finAnio = M.ymd(y, 12, 31);

  const dias = [];
  for (let f = M.sumarDias(R, 1); f <= finAnio; f = M.sumarDias(f, 1)) dias.push(f);

  const prevDe = (f) => diario.get(M.sumarMeses(f, -12))?.facturado;
  const conPrev = dias.filter((f) => prevDe(f) != null).length;
  const cobertura = dias.length ? conPrev / dias.length : 0;
  const sumaPrev = dias.reduce((s, f) => s + (prevDe(f) || 0), 0);
  const usaAnioAnterior = cobertura >= 0.8 && sumaPrev > 0;

  const multDe = (f) => cfg.eventos.find((e) => f >= e.desde && f <= e.hasta)?.mult ?? 1;
  const peso = (f) => (usaAnioAnterior ? prevDe(f) || 0 : multDe(f));
  const sumaPesos = dias.reduce((s, f) => s + peso(f), 0);

  const mk = (objetivo) => {
    const necesario = Math.max(0, objetivo - ytd);
    const porDia = new Map(dias.map((f) => [f, sumaPesos ? (necesario * peso(f)) / sumaPesos : 0]));
    return { objetivo, necesario, porDia };
  };
  const equilibrio = mk(cfg.puntoEquilibrioMensual * 12);
  const meta = mk(cfg.metaMensual * 12);

  const sumaRango = (porDia, desde, hasta) => {
    let s = 0;
    for (const [f, v] of porDia) if (f >= desde && f <= hasta) s += v;
    return s;
  };
  const anioPasadoRango = (desde, hasta) => {
    let s = 0;
    for (let f = desde; f <= hasta; f = M.sumarDias(f, 1)) s += prevDe(f) || 0;
    return s;
  };

  const ventanas = cfg.eventos
    .filter((e) => e.hasta > R)
    .map((e) => {
      const d0 = e.desde > R ? e.desde : M.sumarDias(R, 1);
      const nDias = M.diasEntre(d0, e.hasta) + 1;
      return {
        id: e.id,
        nombre: e.nombre,
        desde: d0,
        hasta: e.hasta,
        dias: nDias,
        equilibrio: sumaRango(equilibrio.porDia, d0, e.hasta),
        meta: sumaRango(meta.porDia, d0, e.hasta),
        anioPasado: anioPasadoRango(d0, e.hasta),
      };
    });

  const meses = [];
  for (let mm = M.partes(M.sumarDias(R, 1)).m; mm <= 12; mm++) {
    const ini = M.ymd(y, mm, 1) > R ? M.ymd(y, mm, 1) : M.sumarDias(R, 1);
    const fin = M.ymd(y, mm, M.diasDelMes(y, mm));
    meses.push({
      mes: mm,
      desde: ini,
      hasta: fin,
      equilibrio: sumaRango(equilibrio.porDia, ini, fin),
      meta: sumaRango(meta.porDia, ini, fin),
      anioPasado: anioPasadoRango(ini, fin),
    });
  }

  const anioPasadoTotal = anioPasadoRango(dias[0] ?? finAnio, finAnio);
  const dNov = M.ymd(y, 11, 1);
  return {
    ytd,
    diasRestantes: dias.length,
    desdeRestante: dias[0] ?? null,
    usaAnioAnterior,
    cobertura,
    equilibrio: { objetivo: equilibrio.objetivo, necesario: equilibrio.necesario },
    meta: { objetivo: meta.objetivo, necesario: meta.necesario },
    anioPasadoTotal,
    ventanas,
    meses,
    // Contraste con la intuición: lo necesario sólo de Nov+Dic (si el corte está en octubre).
    novDic: {
      equilibrio: sumaRango(equilibrio.porDia, dNov, finAnio),
      meta: sumaRango(meta.porDia, dNov, finAnio),
      anioPasado: anioPasadoRango(dNov > R ? dNov : M.sumarDias(R, 1), finAnio),
    },
  };
}
