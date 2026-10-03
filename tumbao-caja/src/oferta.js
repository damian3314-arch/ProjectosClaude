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

/**
 * ¿Toca pegarla? Solo en el PRIMER cierre de una conversación en la que la
 * persona elogió, y nunca con una queja ni con algo urgente: a quien vino
 * incómoda no se le vende.
 */
export function debeInvitarATiquetera({ estadoAntes, cerrar, tipo, urgente }) {
  return !!cerrar && estadoAntes !== 'cerrada' && tipo === 'elogio' && !urgente;
}
