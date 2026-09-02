/**
 * El gancho `window.__e2e`, en un solo sitio.
 *
 * POR QUÉ EXISTE ESTE ARCHIVO
 * Las siete pruebas de navegador del panel esperaban un `window.__e2e`
 * que `docs/admin.html` no tiene: se escribieron contra copias parcheadas
 * a mano que nadie versionó, y recibían la ruta por `process.argv[2]`.
 * Sin ese archivo —que no estaba en ninguna parte— ninguna de las siete
 * arrancaba: reventaban en `Cannot read properties of undefined`.
 *
 * Cada quien reinventaba el gancho y se equivocaba igual, porque los
 * nombres de dentro del panel no son los que uno supondría: la tirilla
 * se pinta en `#tirilla` (no `#tirilla-pagos`), los recuadros son `.ojo`
 * (no `.recuadro`), y `pintarTirillaPagos()` no recibe argumentos sino
 * que lee de la variable de módulo `cajaDatos`. Improvisar el gancho
 * hacía creer en regresiones que no existían.
 *
 * CÓMO FUNCIONA
 * `docs/admin.html` NO se toca: es la página que se despliega y el
 * gancho no puede viajar en ella. Se lee, se le inyecta el bloque justo
 * antes del cierre de su IIFE —ahí dentro están a la vista las variables
 * y funciones del módulo, que es lo que el gancho necesita— y se escribe
 * una copia en un temporal. Las pruebas cargan esa copia.
 *
 * REGLA DE ORO PARA QUIEN AÑADA GANCHOS
 * Mirar el código real del panel antes de escribir uno. El nombre exacto
 * de la función interna, el id del elemento y la clase CSS. Ahí es donde
 * se falla.
 */
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const AQUI = dirname(fileURLToPath(import.meta.url));

/** El panel de verdad, el que se despliega. Solo se lee. */
export const PANEL = join(AQUI, '..', '..', 'docs', 'admin.html');

/**
 * El cierre de la IIFE del panel. El gancho va JUSTO antes, dentro del
 * ámbito del módulo: fuera de ahí no vería `cajaDatos`, `pendientes` ni
 * `pintarTirillaPagos`, que es todo lo que necesita.
 */
const MARCA = '})();\n</script>';

/* El bloque que se inyecta. Va como texto y no como archivo aparte
   porque tiene que quedar DENTRO de la IIFE, no al lado. */
const GANCHO = `
  /* ─────────────────────────────────────────────────────────────
     GANCHO DE PRUEBAS — lo inyecta pruebas/instrumentar.mjs sobre una
     copia temporal. No viaja en el archivo que se despliega.
     ───────────────────────────────────────────────────────────── */
  (function () {
    const $$ = s => Array.from(document.querySelectorAll(s));
    const txt = el => (el ? el.textContent : '');
    const seVe = el => !!el && !el.hidden;

    // El panel arranca en la pantalla de entrar y con \`#app\` oculto. Las
    // pruebas que miden anchos o hacen clic de verdad (Playwright exige
    // que el elemento se vea) necesitan el panel pintado, así que se
    // salta el login sin fingir sesión: no hace falta token para nada
    // de lo que se comprueba.
    const mostrar = cual => {
      $('#entrar').hidden = true;
      $('#app').hidden = false;
      verPanel(cual);
    };

    // La referencia del comprobante vive en la tarjeta de la cola.
    const refComp = () =>
      document.querySelector('#lista-pend .pend-card .ref-comp');

    // "✓ Confirmar igual". Se busca por el texto y no por posición
    // porque al lado está "✕ Rechazar", que también es un .btn.
    const btnConfirmar = () => {
      const acc = document.querySelector('#lista-pend .pend-card .acciones');
      if (!acc) return null;
      return Array.from(acc.querySelectorAll('button'))
        .find(b => /Confirmar/.test(b.textContent)) || null;
    };

    // El aviso de "cobrando el depósito de…" que pone pintarDepPendiente.
    const avisoDeposito = () => {
      const c = $('#dep-pendiente');
      return { avisoVisible: seVe(c), aviso: txt(c) };
    };

    window.__e2e = {

      /* ── la tirilla de pagos ──────────────────────────────────── */

      // pintarTirillaPagos() NO recibe argumentos: lee de la variable de
      // módulo cajaDatos, y escribe en #tirilla (no #tirilla-pagos).
      // Los recuadros son .ojo (no .recuadro).
      tirillaPagos(d) {
        cajaDatos = d;
        pintarTirillaPagos();
        const t = document.querySelector('#tirilla');
        return {
          texto: t ? t.innerText : '',
          recuadros: t ? t.querySelectorAll('.ojo').length : 0,
        };
      },

      /* ── el aviso de ingesta caída ────────────────────────────── */

      // pulso: pone la cola en \`pendientes\`, llama a pintarPulso() y lee
      // #pulso-ingesta. La caja la crea pintarPulso si no existe.
      pulso(cola) {
        pendientes = cola;
        pintarPulso();
        const c = document.querySelector('#pulso-ingesta');
        return { visible: !!c && !c.hidden, texto: c ? c.textContent : '' };
      },

      /* ── la cola de por validar ───────────────────────────────── */

      // La cola cruda entra en \`pendientes\`; pintarPendientes reparte al
      // resto (pintarSinDueno, pintarPulso y las tarjetas).
      sembrarPendientes(lista) {
        mostrar('pendientes');
        pendientes = lista || [];
        pintarPendientes();
      },

      // ¿Hay dónde escribir la referencia, y se ve? getClientRects vacío
      // es justo el caso que se quiere cazar: el input existe pero se
      // encogió hasta desaparecer dentro de la fila flex.
      hayCaja() {
        const r = refComp();
        return !!r && r.getClientRects().length > 0;
      },

      // Las tres medidas de que el CSS de .ref-comp llegó.
      anchoRef() {
        const r = refComp();
        if (!r) return null;
        const c = r.getBoundingClientRect();
        return {
          ancho: c.width,
          alto: c.height,
          borde: getComputedStyle(r).borderTopWidth,
        };
      },

      boton() {
        const b = btnConfirmar();
        return { existe: !!b, apagado: !b || b.disabled };
      },

      // Se dispara 'input' a mano: el panel enciende el botón desde ese
      // evento, y asignar .value no lo lanza solo.
      teclear(t) {
        const r = refComp();
        if (!r) return false;
        r.value = t;
        r.dispatchEvent(new Event('input', { bubbles: true }));
        return true;
      },

      clic() {
        const b = btnConfirmar();
        if (!b) return false;
        b.click();
        return true;
      },

      // "Es este" cuelga de cada depósito candidato de la tarjeta.
      clicEsEste() {
        const b = document.querySelector(
          '#lista-pend .pend-card .pagos .pago button');
        if (!b) return false;
        b.click();
        return true;
      },

      /* ── los depósitos sin dueño ──────────────────────────────── */

      // Para la prueba del depósito que se cobra en la Caja: la lista de
      // sin dueño y el día de la caja, los dos a la vez.
      //
      // \`traido\` se marca a propósito: tocar un depósito llama a
      // cargarCaja() sin forzar, y sin esto saldría a la red a pedir el
      // día y pisaría el que acaba de sembrar la prueba.
      sembrar(libres, dia) {
        mostrar('pendientes');
        pendientes = [];
        pagosLibres = libres || [];
        cajaDatos = dia || null;
        traido.set('caja', Date.now());
        pintarPendientes();
        pintarCaja();
      },

      // Solo la lista de sin dueño. Se vuelve al estado de reposo: fuera
      // del modo juntar y sin nada escogido.
      sembrarLibres(lista) {
        mostrar('pendientes');
        pagosLibres = lista || [];
        juntando = false;
        escogidos.clear();
        pintarSinDueno();
      },

      // Todo lo que se puede leer de la lista de sin dueño de una vez.
      libres() {
        const caja = $('#sin-dueno');
        const filas = $$('#sin-dueno .pago');
        // El de "Juntar en uno", que solo existe dentro del modo. El de
        // entrar al modo es #modo-juntar y está siempre que haya más de
        // un depósito.
        const hacer = $('#hacer-juntar');
        return {
          filas: filas.length,
          tics: $$('#sin-dueno .pago .tic').length,
          marcados: $$('#sin-dueno .pago.marcado').length,
          hayBotonJuntar: !!hacer,
          confirmarApagado: !hacer || hacer.disabled,
          cuenta: txt(caja.querySelector('.juntar-barra .cuenta')),
          textoPrimera: filas.length ? filas[0].textContent : '',
          // Los <span> de las partes; el botón "Separar" no cuenta.
          partesVisibles: $$('#sin-dueno .partes span').length,
          haySeparar: !!caja.querySelector('[data-separar]'),
        };
      },

      // Un clic de verdad: el panel escucha por delegación en #sin-dueno,
      // así que tocar la fila es lo único que reproduce lo que hace una
      // persona. Fuera del modo juntar lleva el depósito a la Caja;
      // dentro, lo tilda.
      tocarPago(i) {
        const b = $$('#sin-dueno .pago')[i];
        if (!b) return false;
        b.click();
        return true;
      },

      modoJuntar() {
        const b = $('#modo-juntar');
        if (!b) return false;
        b.click();
        return true;
      },

      confirmarJuntar() {
        const b = $('#hacer-juntar');
        if (!b) return false;
        b.click();
        return true;
      },

      // El aviso de "cobrando el depósito de…", sin lo del modal.
      estadoDep() {
        return avisoDeposito();
      },

      // Lo mismo más el modal de la Caja. \`cajaMedio\` y \`cajaPago\` son
      // variables de módulo: lo que de verdad se va a mandar al Worker,
      // no lo que se ve pintado.
      estado() {
        return Object.assign(avisoDeposito(), {
          modalAbierto: seVe($('#modal-caja')),
          texto: txt($('#modal-texto')),
          valor: $('#modal-valor').value,
          medio: cajaMedio,
          pagoElegido: cajaPago,
        });
      },

      /* ── las tarjetas de clase del tablero ────────────────────── */

      // tarjetaClase(c) devuelve HTML suelto; pintarTablero lo mete en
      // #clases-tab. Se pinta solo eso y no el tablero entero porque el
      // resto pide un resumen que la prueba no tiene por qué inventar.
      pintarSabado(lista) {
        mostrar('tablero');
        $('#clases-tab').innerHTML = (lista || []).map(tarjetaClase).join('');
        return $$('#clases-tab .clase-card').length;
      },

      leerTarjeta(i) {
        const c = $$('#clases-tab .clase-card')[i];
        if (!c) return null;
        const mini = c.querySelector('.mini');
        const rep = c.querySelector('.reparto');
        return {
          // El número grande de arriba a la derecha: "13 sueltas" el
          // sábado, "2 libres" entre semana.
          badge: txt(c.querySelector('.quedan')),
          partido: !!mini && mini.classList.contains('partido'),
          mini: mini
            ? Array.from(mini.children).map(d => ({
                v: txt(d.querySelector('.v')),
                e: txt(d.querySelector('.e')),
              }))
            : [],
          sala: txt(c.querySelector('.sala')),
          // null y no '' cuando no hay: entre semana la línea no existe,
          // y eso es distinto de existir vacía.
          reparto: rep ? rep.textContent : null,
          texto: c.textContent,
        };
      },
    };
  })();
`;

/**
 * Devuelve la ruta a una copia de docs/admin.html con window.__e2e puesto.
 *
 * `origen` solo se cambia para comprobar el propio guardián de abajo; en
 * las pruebas siempre es el panel de verdad.
 *
 * Si el marcador del cierre de la IIFE deja de aparecer exactamente una
 * vez, falla aquí y con nombre propio. El día que alguien reordene el
 * final del panel hay que enterarse en este punto, y no con siete
 * pruebas rotas por un `__e2e` que se quedó fuera del ámbito.
 */
export function panelInstrumentado(origen = PANEL) {
  const fuente = readFileSync(origen, 'utf8');

  const veces = fuente.split(MARCA).length - 1;
  if (veces !== 1) {
    throw new Error(
      `instrumentar.mjs: el marcador ${JSON.stringify(MARCA)} aparece ` +
      `${veces} veces en ${origen}, y tiene que aparecer exactamente una. ` +
      `El gancho __e2e va justo antes del cierre de la IIFE del panel; ` +
      `si el final del archivo cambió, hay que actualizar MARCA en ` +
      `pruebas/instrumentar.mjs — no las pruebas.`
    );
  }

  // El reemplazo va como función a propósito. Con la forma de texto,
  // String.replace interpreta `$$`, `$&` y compañía como patrones: el
  // `$$` del ayudante del gancho se convertía en `$` y tapaba el `$` del
  // panel, así que `$('#app')` devolvía un array y todo lo que tocaba el
  // DOM dejaba de hacer nada — sin lanzar ningún error.
  const salida = fuente.replace(MARCA, () => GANCHO + MARCA);

  // Ruta fija: el contenido es determinista (mismo panel + mismo gancho),
  // así que reescribirla no sorprende a nadie y no deja un temporal nuevo
  // por cada corrida.
  const carpeta = join(tmpdir(), 'tumbao-pruebas');
  mkdirSync(carpeta, { recursive: true });
  const destino = join(carpeta, 'admin-instrumentado.html');
  writeFileSync(destino, salida);
  return destino;
}

/**
 * Lo que llama cada suite: la ruta que le pasen por argumento si viene
 * (para poder apuntar a una copia de otro sitio), y si no, la copia
 * instrumentada. Que corran sin argumentos es el objetivo.
 */
export function rutaDelPanel(argv = process.argv) {
  return argv[2] || panelInstrumentado();
}
