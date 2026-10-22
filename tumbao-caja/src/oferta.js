/**
 * La invitación a la tiquetera que se le pega al cierre de la conversación
 * de «¿cómo te fue?» cuando la persona contó que le encantó.
 *
 * Damián (29 sep): «los que contestaron "me encantó" son los ideales para
 * invitarles a que compren tiquetera». El asistente ya la mencionaba al
 * despedirse, pero la escribía el modelo: con una de siete personas se le
 * olvidó por completo, y en las demás decía «la tiquetera de 4 clases» sin
 * precio ni enlace. Aquí se arma con código, para que salga siempre igual
 * y con el precio de verdad.
 *
 * Los paquetes vienen de `tiquetera_paquetes()` (ajustes.tiquetera_paquetes):
 * si Damián cambia un precio, el mensaje cambia solo. Nada se inventa.
 *
 * No dice nada del pase de regalo por constancia: eso es a propósito
 * silencioso hasta ver cómo reacciona la gente.
 */

const ENLACE_COMPRA = 'https://tumbaobaila.com/mensualidad';

const miles = (n) => String(Math.round(n)).replace(/\B(?=(\d{3})+(?!\d))/g, '.');

/**
 * @param {Array<{clases:number, precio_cop:number, vigencia_dias:number}>} paquetes
 * @returns {string} el párrafo, o '' si no hay un paquete que ofrecer.
 */
export function invitacionTiquetera(paquetes) {
  const lista = (Array.isArray(paquetes) ? paquetes : [])
    .filter((p) => p && Number(p.clases) > 0 && Number(p.precio_cop) > 0);
  if (!lista.length) return '';
  // El paquete chico: es el primer paso, el que no asusta.
  const p = lista.slice().sort((a, b) => Number(a.clases) - Number(b.clases))[0];
  const clases = Number(p.clases);
  const precio = Number(p.precio_cop);
  const porClase = Math.round(precio / clases / 100) * 100;
  const dias = Number(p.vigencia_dias) > 0 ? ` dura ${Number(p.vigencia_dias)} días y` : '';
  return `Si quieres seguir bailando, la tiquetera de ${clases} clases sale a $${miles(precio)} ` +
    `($${miles(porClase)} por clase),${dias} la usas cuando quieras. La compras aquí: ${ENLACE_COMPRA}`;
}

// «7 am», «6 pm», «6:30 pm» a partir de «07:00», «18:00», «18:30».
function horaCorta(hhmm) {
  const m = /^(\d{1,2}):(\d{2})/.exec(String(hhmm || ''));
  if (!m) return String(hhmm || '');
  const h = Number(m[1]);
  const min = m[2] === '00' ? '' : ':' + m[2];
  return `${h % 12 === 0 ? 12 : h % 12}${min} ${h < 12 ? 'am' : 'pm'}`;
}

/**
 * La invitación del cierre de «¿cómo te fue?» (10 oct, Damián: «trabajar fuerte en vender mensualidad y tiquetera»).
 *
 * Quien acaba de vivir su PRIMERA clase y contó que le encantó es la sangre nueva que reemplaza a quien no renueva, y
 * la mensualidad ($5.000 la clase) vale 2,4 veces la tiquetera chica. Por eso, si hay cupo real de mensualidad, va
 * primero; la tiquetera queda como la forma suave de empezar. Todo sale del sistema (`ventas_perfil`): el precio, el
 * costo por clase y los cupos libres por horario. Nada se inventa, y sin cupos no se promete ninguno.
 *
 *   · ya tiene plan, o una tiquetera con clases: no se le vende;
 *   · sin perfil (la consulta falló): queda la invitación de siempre, la de la tiquetera;
 *   · sin cupos libres en ningún horario: también la de la tiquetera.
 *
 * @param {{paquetes?: Array, perfil?: object|null}} datos
 * @returns {string} el párrafo, o '' si no toca ofrecer nada.
 */
export function invitacionPlanes({ paquetes, perfil } = {}) {
  const p = perfil && typeof perfil === 'object' && !Array.isArray(perfil) ? perfil : null;
  if (!p) return invitacionTiquetera(paquetes);
  if (p.plan_vigente) return '';
  if (p.tiquetera_vigente && Number(p.tiquetera_vigente.clases_restantes) > 0) return '';

  const valor = Number(p.valor_mensualidad);
  const libres = Object.entries(p.cupos_mensualidad || {})
    .filter(([, n]) => Number(n) > 0)
    .sort(([a], [b]) => String(a).localeCompare(String(b)));
  if (!(valor > 0) || !libres.length) return invitacionTiquetera(paquetes);

  const porClase = Number(p.mensualidad_por_clase) > 0
    ? Number(p.mensualidad_por_clase) : Math.round(valor / 25 / 100) * 100;
  const cupos = libres.map(([h, n]) => `${Number(n)} ${Number(n) === 1 ? 'cupo' : 'cupos'} a las ${horaCorta(h)}`);
  const lista = cupos.length > 1 ? cupos.slice(0, -1).join(', ') + ' y ' + cupos[cupos.length - 1] : cupos[0];

  const chica = (Array.isArray(paquetes) ? paquetes : [])
    .filter((q) => q && Number(q.clases) > 0 && Number(q.precio_cop) > 0)
    .sort((a, b) => Number(a.clases) - Number(b.clases))[0];
  const suave = chica
    ? ` Y si prefieres empezar más suave, la tiquetera de ${Number(chica.clases)} clases cuesta $${miles(chica.precio_cop)}.`
    : '';
  return `Si quieres bailar todo el mes, la mensualidad sale a $${miles(valor)} (a $${miles(porClase)} la clase) ` +
    `y todavía quedan ${lista}.${suave} ${chica ? 'Las dos opciones' : 'La compras'} aquí: ${ENLACE_COMPRA}`;
}

/**
 * ¿Toca pegarla? Solo en el PRIMER cierre de una conversación en la que la
 * persona elogió, y nunca con una queja ni con algo urgente: a quien vino
 * incómoda no se le vende.
 */
export function debeInvitarATiquetera({ estadoAntes, cerrar, tipo, urgente }) {
  return !!cerrar && estadoAntes !== 'cerrada' && tipo === 'elogio' && !urgente;
}
