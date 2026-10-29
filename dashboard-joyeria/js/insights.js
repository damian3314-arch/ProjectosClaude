import * as M from './metrics.js';
import { copM, pct, variacion, rangoTexto, diaMes } from './fmt.js';

const DIAS = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];

// Hallazgos por reglas, todos con los números que los sustentan. Nada de texto genérico:
// si la regla no tiene datos suficientes, no habla.
export function generarInsights({ diario, movs, R, meta, plan, cfg, cuentas1stSeen }) {
  const out = [];
  const add = (nivel, titulo, detalle) => out.push({ nivel, titulo, detalle });

  // 1. Ritmo contra equilibrio y meta
  if (meta) {
    const p = meta.proyEstacional ?? meta.proyLineal;
    const base = meta.proyEstacional != null ? 'con la forma del año pasado' : 'con el ritmo actual';
    if (p < meta.equilibrio) {
      add('alerta', `A este ritmo el mes cierra por debajo del equilibrio`,
        `Proyección ${copM(p)} (${base}) contra equilibrio ${copM(meta.equilibrio)}. Hay que vender ${copM(meta.reqDiarioEquilibrio)} por día en los ${meta.restantes} días que quedan para alcanzarlo.`);
    } else if (p < meta.meta) {
      add('aviso', `El mes cubre el equilibrio pero no llega a la meta`,
        `Proyección ${copM(p)} (${base}). Para llegar a ${copM(meta.meta)} faltan ${copM(meta.faltaMeta)}: ${copM(meta.reqDiarioMeta)} por día.`);
    } else {
      add('ok', `El mes va en camino de cumplir la meta`, `Proyección ${copM(p)} (${base}) contra meta ${copM(meta.meta)}.`);
    }
  }

  // 2. Cuánto se necesita en lo que queda del año
  if (plan && plan.equilibrio.necesario > 0) {
    const ratio = plan.anioPasadoTotal > 0 ? plan.meta.necesario / plan.anioPasadoTotal : null;
    add(ratio && ratio > 1.15 ? 'alerta' : 'aviso',
      `Para cerrar el año en meta faltan ${copM(plan.meta.necesario)}`,
      `Equilibrio anual: faltan ${copM(plan.equilibrio.necesario)}. ` +
        (ratio ? `Esa meta equivale a ${ratio.toFixed(2).replace('.', ',')}× lo vendido en las mismas fechas del año pasado (${copM(plan.anioPasadoTotal)}).` : 'No hay datos del año pasado para comparar.'));
  }

  // 3. Concentración por cuenta (mes en curso)
  const { y, m } = M.partes(R);
  const iniMes = M.ymd(y, m, 1);
  const ctas = M.porCuenta(movs, iniMes, R);
  if (ctas.length >= 2 && ctas[0].pct >= 0.6) {
    add('aviso', `${ctas[0].nombre} concentra ${pct(ctas[0].pct, 0)} del recaudo del mes`,
      `Si esa cuenta tiene un bloqueo o un límite, más de la mitad del flujo queda expuesto. Segunda cuenta: ${ctas[1].nombre} con ${pct(ctas[1].pct, 0)}.`);
  }

  // 4. Cuentas nuevas
  for (const c of ctas) {
    const primero = cuentas1stSeen.get(c.clave);
    if (primero && M.diasEntre(primero, R) <= cfg.diasCuentaNueva) {
      add('info', `Cuenta nueva con movimiento: ${c.nombre}`,
        `Primer movimiento el ${diaMes(primero)}. Lleva ${copM(c.total)} en el mes (${pct(c.pct, 1)} del recaudo).`);
    }
  }

  // 5. Contado vs crédito
  const mesAct = M.datosRango(diario, iniMes, R);
  const compMes = M.rangoComparable('mes', R, 'previo');
  const mesPrev = M.datosRango(diario, compMes.desde, compMes.hasta);
  if (mesAct.facturado > 0 && mesPrev.facturado > 0) {
    const shAct = mesAct.credito / mesAct.facturado;
    const shPrev = mesPrev.credito / mesPrev.facturado;
    if (Math.abs(shAct - shPrev) >= 0.05) {
      add('info', `La venta a crédito ${shAct > shPrev ? 'pesa más' : 'pesa menos'} que el mes pasado`,
        `Crédito = ${pct(shAct, 0)} de lo facturado en ${rangoTexto({ desde: iniMes, hasta: R })}, contra ${pct(shPrev, 0)} en ${rangoTexto(compMes)}. ` +
          (shAct > shPrev ? 'Más venta sin caja inmediata: vigilar abonos.' : 'Más venta con caja inmediata.'));
    }
  }

  // 6. Pago promedio por transacción de contado
  const ventasAct = movs.filter((x) => x.tipo === 'VENTA' && x.fecha >= iniMes && x.fecha <= R);
  const ventasPrev = movs.filter((x) => x.tipo === 'VENTA' && x.fecha >= compMes.desde && x.fecha <= compMes.hasta);
  if (ventasAct.length >= 10 && ventasPrev.length >= 10) {
    const tAct = ventasAct.reduce((s, x) => s + x.valor, 0) / ventasAct.length;
    const tPrev = ventasPrev.reduce((s, x) => s + x.valor, 0) / ventasPrev.length;
    const v = variacion(tAct, tPrev);
    if (v != null && Math.abs(v) >= 0.1) {
      add('info', `El pago promedio de contado ${v > 0 ? 'subió' : 'bajó'} ${pct(Math.abs(v), 0)}`,
        `${copM(tAct)} por pago este mes (${ventasAct.length} pagos) contra ${copM(tPrev)} en el periodo comparable (${ventasPrev.length} pagos). ` +
          (v < 0 ? 'Si el número de pagos no subió, se está vendiendo más barato.' : ''));
    }
  }

  // 7. Mejor y peor día de la semana (últimos 91 días)
  const perfil = M.perfilSemana(diario, R, 91).filter((p) => p.promedio != null && p.n >= 4);
  if (perfil.length >= 5) {
    const ord = [...perfil].sort((a, b) => b.promedio - a.promedio);
    const mejor = ord[0];
    const peor = ord[ord.length - 1];
    add('info', `El ${DIAS[mejor.dia]} es el día más fuerte; el ${DIAS[peor.dia]}, el más flojo`,
      `Promedio facturado en los últimos 91 días: ${DIAS[mejor.dia]} ${copM(mejor.promedio)} vs ${DIAS[peor.dia]} ${copM(peor.promedio)}. Útil para ubicar pauta y turnos.`);
  }

  // 8. Concentración de clientes
  const tc = M.topClientes(movs, iniMes, R, 5);
  if (tc.clientes >= 6 && tc.total > 0) {
    const top5 = tc.lista.reduce((s, c) => s + c.valor, 0) / tc.total;
    if (top5 >= 0.5) {
      add('aviso', `5 clientes aportan ${pct(top5, 0)} del recaudo del mes`,
        `${tc.lista.map((c) => c.cliente).join(', ')}. Una demora de pago de uno de ellos mueve la caja.`);
    }
  }

  // 9. Huecos de carga
  const hoy = cfg.hoy || R;
  const desdeV = M.sumarDias(hoy, -(cfg.ventanaHuecos - 1));
  const h = M.huecos(diario, desdeV, hoy, cfg.diasCerrados);
  if (h.dias.length) {
    add('alerta', `Faltan ${h.dias.length} días por cargar en las últimas ${cfg.ventanaHuecos} jornadas`,
      `Sin registro: ${h.rangos.map((r) => (r.desde === r.hasta ? diaMes(r.desde) : `${diaMes(r.desde)} a ${diaMes(r.hasta)}`)).join('; ')}. Mientras no estén, los totales del periodo están subestimados.`);
  }

  const orden = { alerta: 0, aviso: 1, info: 2, ok: 3 };
  return out.sort((a, b) => orden[a.nivel] - orden[b.nivel]);
}
