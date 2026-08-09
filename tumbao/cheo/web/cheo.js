/*
 * Cheo — el hijo de Tumbao.
 *
 * Un solo archivo, sin dependencias, sin build. Sirve para las dos cosas:
 *
 *   Burbuja en cualquier pagina:
 *     <script src="/cheo.js" defer></script>
 *
 *   Pagina propia de Cheo (cheo.html):
 *     <script src="/cheo.js" data-modo="pagina" defer></script>
 *
 * Habla directo con n8n. No necesita backend propio ni tocar Supabase
 * desde el navegador: la llave de la base nunca sale del servidor.
 *
 * Recibe texto, notas de voz y fotos. La foto no se guarda en ningun
 * lado: se mira, se saca una frase de lo que hay, y se suelta.
 */
(function () {
  'use strict';

  var script = document.currentScript ||
    (function () { var s = document.getElementsByTagName('script'); return s[s.length - 1]; })();
  var cfg = (script && script.dataset) || {};

  var API = cfg.api || 'https://barragan.app.n8n.cloud/webhook';
  var MODO = cfg.modo === 'pagina' ? 'pagina' : 'widget';
  var ACENTO = cfg.acento || '#c2410c';
  var CON_VOZ = cfg.voz !== '0';
  var CON_FOTO = cfg.foto !== '0';

  var LS_SESION = 'cheo.sesion';
  var LS_VISTO = 'cheo.visto';

  var MAX_SEG = 180;

  /* ---------------------------------------------------------------- */
  /* Sesion                                                            */
  /* ---------------------------------------------------------------- */

  function nuevaSesion() {
    try {
      if (window.crypto && window.crypto.randomUUID) return window.crypto.randomUUID();
    } catch (e) { /* sigue al respaldo */ }
    return 'cheo-' + Date.now().toString(36) + '-' +
      Math.random().toString(36).slice(2, 10) + Math.random().toString(36).slice(2, 10);
  }

  function sesion() {
    var v = null;
    try { v = localStorage.getItem(LS_SESION); } catch (e) { v = null; }
    if (!v) {
      v = nuevaSesion();
      try { localStorage.setItem(LS_SESION, v); } catch (e) { /* modo incognito */ }
    }
    return v;
  }

  var SESION = sesion();

  var puedeGrabar = CON_VOZ &&
    typeof MediaRecorder !== 'undefined' &&
    !!(navigator.mediaDevices && navigator.mediaDevices.getUserMedia);

  /* ---------------------------------------------------------------- */
  /* Estilos                                                           */
  /* ---------------------------------------------------------------- */

  var CSS = [
    '.cheo-raiz{--cheo-acento:' + ACENTO + ';--cheo-tinta:#1c1917;--cheo-suave:#78716c;',
    '--cheo-linea:#e7e5e4;--cheo-fondo:#fff;--cheo-burbuja-yo:' + ACENTO + ';--cheo-burbuja-el:#f5f5f4;',
    'font-family:system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;-webkit-font-smoothing:antialiased}',

    '@media (prefers-color-scheme:dark){.cheo-raiz{--cheo-tinta:#fafaf9;--cheo-suave:#a8a29e;',
    '--cheo-linea:#292524;--cheo-fondo:#1c1917;--cheo-burbuja-el:#292524}}',

    '.cheo-boton{position:fixed;right:20px;bottom:20px;z-index:2147483000;display:flex;align-items:center;',
    'gap:9px;border:0;cursor:pointer;background:var(--cheo-acento);color:#fff;padding:13px 18px 13px 15px;',
    'border-radius:999px;font-size:15px;font-weight:550;line-height:1;box-shadow:0 6px 24px rgba(0,0,0,.19);',
    'transition:transform .18s ease,box-shadow .18s ease;font-family:inherit}',
    '.cheo-boton:hover{transform:translateY(-2px);box-shadow:0 10px 30px rgba(0,0,0,.24)}',
    '.cheo-boton:focus-visible{outline:3px solid var(--cheo-acento);outline-offset:3px}',
    '.cheo-boton svg{width:21px;height:21px;flex:none}',
    '.cheo-punto{position:absolute;top:10px;right:14px;width:9px;height:9px;border-radius:50%;',
    'background:#22c55e;box-shadow:0 0 0 2.5px var(--cheo-acento)}',

    '.cheo-panel{position:fixed;right:20px;bottom:20px;z-index:2147483001;width:388px;max-width:calc(100vw - 32px);',
    'height:min(620px,calc(100vh - 40px));background:var(--cheo-fondo);border-radius:18px;display:flex;',
    'flex-direction:column;overflow:hidden;box-shadow:0 18px 60px rgba(0,0,0,.26);',
    'border:1px solid var(--cheo-linea);opacity:0;transform:translateY(10px) scale(.985);',
    'transition:opacity .18s ease,transform .18s ease}',
    '.cheo-panel.cheo-abierto{opacity:1;transform:none}',
    '@media (max-width:520px){.cheo-panel{right:0;bottom:0;width:100vw;max-width:100vw;height:100dvh;border-radius:0;border:0}}',

    '.cheo-raiz.cheo-modo-pagina .cheo-panel{position:static;width:100%;max-width:100%;height:100%;',
    'box-shadow:none;border-radius:14px;opacity:1;transform:none}',
    '.cheo-raiz.cheo-modo-pagina{height:100%}',

    '.cheo-cab{display:flex;align-items:center;gap:11px;padding:14px 14px 13px 16px;border-bottom:1px solid var(--cheo-linea);flex:none}',
    '.cheo-avatar{width:38px;height:38px;border-radius:50%;background:var(--cheo-acento);color:#fff;display:flex;',
    'align-items:center;justify-content:center;font-weight:600;font-size:15px;flex:none;letter-spacing:.02em}',
    '.cheo-quien{flex:1;min-width:0}',
    '.cheo-nombre{font-size:15px;font-weight:600;color:var(--cheo-tinta);line-height:1.25}',
    '.cheo-sub{font-size:12px;color:var(--cheo-suave);line-height:1.35;margin-top:1px}',
    '.cheo-cerrar{border:0;background:transparent;cursor:pointer;color:var(--cheo-suave);padding:7px;',
    'border-radius:9px;display:flex;line-height:0}',
    '.cheo-cerrar:hover{background:var(--cheo-burbuja-el);color:var(--cheo-tinta)}',
    '.cheo-cerrar svg{width:19px;height:19px}',

    '.cheo-hilo{flex:1;overflow-y:auto;padding:18px 16px 8px;display:flex;flex-direction:column;gap:8px;',
    'overscroll-behavior:contain;scrollbar-width:thin}',
    '.cheo-msg{max-width:85%;padding:9px 13px;border-radius:15px;font-size:14.5px;line-height:1.5;',
    'white-space:pre-wrap;word-wrap:break-word;overflow-wrap:anywhere;animation:cheo-entra .2s ease}',
    '@keyframes cheo-entra{from{opacity:0;transform:translateY(6px)}to{opacity:1;transform:none}}',
    '.cheo-msg.cheo-el{align-self:flex-start;background:var(--cheo-burbuja-el);color:var(--cheo-tinta);border-bottom-left-radius:5px}',
    '.cheo-msg.cheo-yo{align-self:flex-end;background:var(--cheo-burbuja-yo);color:#fff;border-bottom-right-radius:5px}',
    /* globos seguidos del mismo lado se pegan, como en un chat de verdad */
    '.cheo-msg.cheo-el + .cheo-msg.cheo-el{border-top-left-radius:6px;margin-top:-4px}',
    '.cheo-msg.cheo-yo + .cheo-msg.cheo-yo{border-top-right-radius:6px;margin-top:-4px}',
    '.cheo-aviso{align-self:center;text-align:center;font-size:11.5px;color:var(--cheo-suave);',
    'line-height:1.5;padding:4px 10px;max-width:92%}',

    '.cheo-marca{display:flex;align-items:center;gap:5px;font-size:11px;opacity:.75;margin:0 0 3px}',
    '.cheo-marca svg{width:12px;height:12px}',
    '.cheo-foto{display:block;max-width:190px;width:100%;border-radius:10px;margin:0 0 6px}',

    '.cheo-tres{align-self:flex-start;background:var(--cheo-burbuja-el);border-radius:15px;border-bottom-left-radius:5px;',
    'padding:13px 15px;display:flex;gap:4px}',
    '.cheo-tres span{width:6px;height:6px;border-radius:50%;background:var(--cheo-suave);animation:cheo-late 1.3s infinite}',
    '.cheo-tres span:nth-child(2){animation-delay:.18s}.cheo-tres span:nth-child(3){animation-delay:.36s}',
    '@keyframes cheo-late{0%,60%,100%{opacity:.28;transform:translateY(0)}30%{opacity:1;transform:translateY(-3px)}}',

    '.cheo-atajos{display:flex;flex-wrap:wrap;gap:7px;padding:8px 16px 10px}',
    '.cheo-atajo{border:1px solid var(--cheo-linea);background:transparent;color:var(--cheo-tinta);',
    'border-radius:999px;padding:7px 13px;font-size:13px;cursor:pointer;font-family:inherit;line-height:1.3;',
    'transition:border-color .15s ease}',
    '.cheo-atajo:hover{border-color:var(--cheo-acento);color:var(--cheo-acento)}',

    '.cheo-pie{border-top:1px solid var(--cheo-linea);padding:11px 12px 12px;flex:none;background:var(--cheo-fondo)}',
    '.cheo-caja{display:flex;align-items:flex-end;gap:6px;background:var(--cheo-burbuja-el);border-radius:14px;padding:6px 6px 6px 8px}',
    '.cheo-txt{flex:1;border:0;background:transparent;resize:none;font-family:inherit;font-size:14.5px;',
    'line-height:1.45;color:var(--cheo-tinta);max-height:110px;padding:7px 0;outline:0;min-width:0}',
    '.cheo-txt::placeholder{color:var(--cheo-suave)}',
    '.cheo-icono{border:0;background:transparent;color:var(--cheo-suave);width:34px;height:34px;border-radius:10px;',
    'cursor:pointer;display:flex;align-items:center;justify-content:center;flex:none;padding:0;',
    'transition:color .15s ease,background .15s ease}',
    '.cheo-icono:hover{color:var(--cheo-acento);background:rgba(0,0,0,.05)}',
    '.cheo-icono svg{width:19px;height:19px}',
    '.cheo-icono:disabled{opacity:.35;cursor:default}',
    '.cheo-enviar{border:0;background:var(--cheo-acento);color:#fff;width:36px;height:36px;border-radius:11px;',
    'cursor:pointer;display:flex;align-items:center;justify-content:center;flex:none;transition:opacity .15s ease}',
    '.cheo-enviar:disabled{opacity:.34;cursor:default}',
    '.cheo-enviar svg{width:17px;height:17px}',
    '.cheo-legal{text-align:center;font-size:10.5px;color:var(--cheo-suave);margin:9px 2px 0;line-height:1.45}',

    /* grabando */
    '.cheo-grabando{display:flex;align-items:center;gap:11px;background:var(--cheo-burbuja-el);',
    'border-radius:14px;padding:11px 12px}',
    '.cheo-rojo{width:10px;height:10px;border-radius:50%;background:#dc2626;flex:none;animation:cheo-pulso 1.1s infinite}',
    '@keyframes cheo-pulso{0%,100%{opacity:1}50%{opacity:.25}}',
    '.cheo-reloj{font-size:14px;color:var(--cheo-tinta);font-variant-numeric:tabular-nums;flex:none}',
    '.cheo-onda{flex:1;display:flex;align-items:center;gap:2px;height:20px;overflow:hidden}',
    '.cheo-onda i{display:block;width:3px;border-radius:2px;background:var(--cheo-suave);height:4px;',
    'animation:cheo-onda 1s infinite ease-in-out}',
    '@keyframes cheo-onda{0%,100%{height:4px}50%{height:16px}}',
    '.cheo-cancelar{border:0;background:transparent;color:var(--cheo-suave);font-size:13px;cursor:pointer;',
    'font-family:inherit;padding:6px 8px;flex:none}',
    '.cheo-cancelar:hover{color:#dc2626}',
    '.cheo-listo{border:0;background:var(--cheo-acento);color:#fff;width:36px;height:36px;border-radius:11px;',
    'cursor:pointer;display:flex;align-items:center;justify-content:center;flex:none}',
    '.cheo-listo svg{width:17px;height:17px}',

    '.cheo-contacto{padding:12px 16px 14px;border-top:1px solid var(--cheo-linea);background:var(--cheo-burbuja-el)}',
    '.cheo-contacto p{margin:0 0 9px;font-size:12.5px;color:var(--cheo-tinta);line-height:1.45}',
    '.cheo-fila{display:flex;gap:7px}',
    '.cheo-inp{flex:1;min-width:0;border:1px solid var(--cheo-linea);background:var(--cheo-fondo);border-radius:9px;',
    'padding:9px 11px;font-size:13.5px;font-family:inherit;color:var(--cheo-tinta);outline:0}',
    '.cheo-inp:focus{border-color:var(--cheo-acento)}',
    '.cheo-ok{border:0;background:var(--cheo-acento);color:#fff;border-radius:9px;padding:9px 15px;',
    'font-size:13.5px;font-family:inherit;cursor:pointer;font-weight:550;flex:none}',
    '.cheo-oculto{display:none!important}',
  ].join('');

  /* ---------------------------------------------------------------- */
  /* Iconos y DOM                                                      */
  /* ---------------------------------------------------------------- */

  function el(tag, clase, texto) {
    var n = document.createElement(tag);
    if (clase) n.className = clase;
    if (texto != null) n.textContent = texto;
    return n;
  }

  var SVG = 'viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"';
  var ICONO_CHAT = '<svg ' + SVG + '><path d="M21 11.5a8.4 8.4 0 0 1-9 8.4 8.9 8.9 0 0 1-4-.9L3 21l1.9-4.9A8.4 8.4 0 0 1 12 3a8.4 8.4 0 0 1 9 8.5z"/></svg>';
  var ICONO_X = '<svg ' + SVG + '><path d="M18 6 6 18M6 6l12 12"/></svg>';
  var ICONO_ENVIAR = '<svg ' + SVG + '><path d="M22 2 11 13M22 2l-7 20-4-9-9-4 20-7z"/></svg>';
  var ICONO_MIC = '<svg ' + SVG + '><path d="M12 2a3 3 0 0 0-3 3v7a3 3 0 0 0 6 0V5a3 3 0 0 0-3-3z"/><path d="M19 10v2a7 7 0 0 1-14 0v-2"/><path d="M12 19v3"/></svg>';
  var ICONO_FOTO = '<svg ' + SVG + '><path d="M23 19a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h4l2-3h6l2 3h4a2 2 0 0 1 2 2z"/><circle cx="12" cy="13" r="4"/></svg>';
  var ICONO_MIC_MINI = '<svg ' + SVG + '><path d="M12 2a3 3 0 0 0-3 3v7a3 3 0 0 0 6 0V5a3 3 0 0 0-3-3z"/><path d="M19 10v2a7 7 0 0 1-14 0v-2"/></svg>';

  var ATAJOS = [
    'Tengo una sugerencia',
    'Algo no me funciono',
    'Tengo una duda',
    'Una idea para Tumbao',
  ];

  function montar(contenedor) {
    var raiz = el('div', 'cheo-raiz' + (MODO === 'pagina' ? ' cheo-modo-pagina' : ''));

    var estilo = el('style');
    estilo.textContent = CSS;
    raiz.appendChild(estilo);

    var panel = el('div', 'cheo-panel');
    panel.setAttribute('role', 'dialog');
    panel.setAttribute('aria-label', 'Chat con Cheo, el asistente de Tumbao');
    if (MODO === 'widget') panel.classList.add('cheo-oculto');

    var cab = el('div', 'cheo-cab');
    var avatar = el('div', 'cheo-avatar', 'Ch');
    avatar.setAttribute('aria-hidden', 'true');
    var quien = el('div', 'cheo-quien');
    quien.appendChild(el('div', 'cheo-nombre', 'Cheo'));
    quien.appendChild(el('div', 'cheo-sub', 'El hijo de Tumbao · te lee y lo guarda'));
    cab.appendChild(avatar);
    cab.appendChild(quien);

    var btnCerrar = null;
    if (MODO === 'widget') {
      btnCerrar = el('button', 'cheo-cerrar');
      btnCerrar.type = 'button';
      btnCerrar.innerHTML = ICONO_X;
      btnCerrar.setAttribute('aria-label', 'Cerrar el chat');
      cab.appendChild(btnCerrar);
    }
    panel.appendChild(cab);

    var hilo = el('div', 'cheo-hilo');
    hilo.setAttribute('role', 'log');
    hilo.setAttribute('aria-live', 'polite');
    panel.appendChild(hilo);

    var atajos = el('div', 'cheo-atajos');
    panel.appendChild(atajos);

    var contacto = el('div', 'cheo-contacto cheo-oculto');
    contacto.appendChild(el('p', null,
      'Si quieres que te contemos en que quedo, dejame tu nombre y tu WhatsApp. Es opcional.'));
    var filaC = el('div', 'cheo-fila');
    var inNombre = el('input', 'cheo-inp');
    inNombre.type = 'text'; inNombre.placeholder = 'Tu nombre';
    inNombre.setAttribute('aria-label', 'Tu nombre');
    var inTel = el('input', 'cheo-inp');
    inTel.type = 'tel'; inTel.placeholder = 'WhatsApp';
    inTel.setAttribute('aria-label', 'Tu numero de WhatsApp');
    var btnOk = el('button', 'cheo-ok', 'Listo');
    btnOk.type = 'button';
    filaC.appendChild(inNombre); filaC.appendChild(inTel); filaC.appendChild(btnOk);
    contacto.appendChild(filaC);
    panel.appendChild(contacto);

    var pie = el('div', 'cheo-pie');

    var caja = el('div', 'cheo-caja');
    var btnFoto = null;
    if (CON_FOTO) {
      btnFoto = el('button', 'cheo-icono');
      btnFoto.type = 'button';
      btnFoto.innerHTML = ICONO_FOTO;
      btnFoto.setAttribute('aria-label', 'Mandar una foto');
      btnFoto.title = 'Mandar una foto';
      caja.appendChild(btnFoto);
    }
    var txt = el('textarea', 'cheo-txt');
    txt.rows = 1;
    txt.placeholder = 'Cuentame...';
    txt.setAttribute('aria-label', 'Escribele a Cheo');
    caja.appendChild(txt);

    var btnMic = null;
    if (puedeGrabar) {
      btnMic = el('button', 'cheo-icono');
      btnMic.type = 'button';
      btnMic.innerHTML = ICONO_MIC;
      btnMic.setAttribute('aria-label', 'Grabar una nota de voz');
      btnMic.title = 'Grabar una nota de voz';
      caja.appendChild(btnMic);
    }

    var btnEnviar = el('button', 'cheo-enviar');
    btnEnviar.type = 'button';
    btnEnviar.innerHTML = ICONO_ENVIAR;
    btnEnviar.setAttribute('aria-label', 'Enviar');
    btnEnviar.disabled = true;
    caja.appendChild(btnEnviar);
    pie.appendChild(caja);

    // Barra de grabacion, escondida hasta que se aprieta el microfono.
    var grabando = el('div', 'cheo-grabando cheo-oculto');
    grabando.appendChild(el('span', 'cheo-rojo'));
    var reloj = el('span', 'cheo-reloj', '0:00');
    grabando.appendChild(reloj);
    var onda = el('div', 'cheo-onda');
    for (var i = 0; i < 22; i++) {
      var barra = document.createElement('i');
      barra.style.animationDelay = (i * 0.07).toFixed(2) + 's';
      onda.appendChild(barra);
    }
    grabando.appendChild(onda);
    var btnCancelar = el('button', 'cheo-cancelar', 'Cancelar');
    btnCancelar.type = 'button';
    grabando.appendChild(btnCancelar);
    var btnListo = el('button', 'cheo-listo');
    btnListo.type = 'button';
    btnListo.innerHTML = ICONO_ENVIAR;
    btnListo.setAttribute('aria-label', 'Mandar la nota de voz');
    grabando.appendChild(btnListo);
    pie.appendChild(grabando);

    var legal = el('div', 'cheo-legal');
    legal.textContent = 'Cheo es una inteligencia artificial. Lo que escribas se guarda y lo lee el equipo de Tumbao.';
    pie.appendChild(legal);
    panel.appendChild(pie);

    var archivo = el('input');
    archivo.type = 'file';
    archivo.accept = 'image/*';
    archivo.className = 'cheo-oculto';
    panel.appendChild(archivo);

    raiz.appendChild(panel);

    var boton = null;
    if (MODO === 'widget') {
      boton = el('button', 'cheo-boton');
      boton.type = 'button';
      boton.innerHTML = ICONO_CHAT + '<span>Cuentanos</span>';
      boton.setAttribute('aria-label', 'Abrir el chat con Cheo');
      var visto = false;
      try { visto = localStorage.getItem(LS_VISTO) === '1'; } catch (e) { visto = false; }
      if (!visto) boton.appendChild(el('span', 'cheo-punto'));
      raiz.appendChild(boton);
    }

    (contenedor || document.body).appendChild(raiz);

    return {
      raiz: raiz, panel: panel, hilo: hilo, atajos: atajos, txt: txt, caja: caja,
      enviar: btnEnviar, cerrar: btnCerrar, boton: boton, mic: btnMic, foto: btnFoto,
      archivo: archivo, grabando: grabando, reloj: reloj, cancelar: btnCancelar, listo: btnListo,
      contacto: contacto, inNombre: inNombre, inTel: inTel, btnOk: btnOk,
    };
  }

  /* ---------------------------------------------------------------- */
  /* Comportamiento                                                    */
  /* ---------------------------------------------------------------- */

  function arranca() {
    var destino = MODO === 'pagina' ? document.getElementById('cheo-aqui') : null;
    var ui = montar(destino);

    var abierto = MODO === 'pagina';
    var saludado = false;
    var enVuelo = false;
    var cerrada = false;
    var turnos = 0;

    function abajo() { ui.hilo.scrollTop = ui.hilo.scrollHeight; }

    function pinta(rol, texto, medio, fotoUrl) {
      var m = el('div', 'cheo-msg ' + (rol === 'yo' ? 'cheo-yo' : 'cheo-el'));
      if (fotoUrl) {
        var img = el('img', 'cheo-foto');
        img.src = fotoUrl;
        img.alt = 'La foto que mandaste';
        m.appendChild(img);
      }
      if (medio === 'voz') {
        var marca = el('div', 'cheo-marca');
        marca.innerHTML = ICONO_MIC_MINI + '<span>nota de voz</span>';
        m.appendChild(marca);
      } else if (medio === 'foto' && !fotoUrl) {
        // Al retomar la conversacion la imagen ya no esta (no se guarda),
        // y sin esta marquita la descripcion se leeria como si la persona
        // hubiera escrito esa frase.
        var marcaF = el('div', 'cheo-marca');
        marcaF.innerHTML = ICONO_FOTO + '<span>foto que mandaste</span>';
        m.appendChild(marcaF);
      }
      m.appendChild(document.createTextNode(texto));
      ui.hilo.appendChild(m);
      abajo();
      return m;
    }

    function aviso(texto) {
      ui.hilo.appendChild(el('div', 'cheo-aviso', texto));
      abajo();
    }

    var puntos = null;
    function escribiendo(si) {
      if (si && !puntos) {
        puntos = el('div', 'cheo-tres');
        puntos.innerHTML = '<span></span><span></span><span></span>';
        puntos.setAttribute('aria-label', 'Cheo esta escribiendo');
        ui.hilo.appendChild(puntos);
        abajo();
      } else if (!si && puntos) {
        puntos.remove();
        puntos = null;
      }
    }

    // Cheo manda sus mensajitos uno por uno, con la pausa que tomaria
    // escribirlos. Verlos aparecer de golpe es lo que delata al bot.
    function pintaTanda(lista) {
      return new Promise(function (listoYa) {
        var i = 0;
        function siguiente() {
          if (i >= lista.length) { escribiendo(false); listoYa(); return; }
          var texto = lista[i++];
          var espera = Math.min(320 + texto.length * 16, 1500);
          escribiendo(true);
          setTimeout(function () {
            escribiendo(false);
            pinta('el', texto);
            if (i < lista.length) setTimeout(siguiente, 180);
            else listoYa();
          }, espera);
        }
        siguiente();
      });
    }

    function pintaAtajos(mostrar) {
      ui.atajos.textContent = '';
      if (!mostrar) return;
      ATAJOS.forEach(function (a) {
        var b = el('button', 'cheo-atajo', a);
        b.type = 'button';
        b.addEventListener('click', function () { manda(a); });
        ui.atajos.appendChild(b);
      });
    }

    function bloquea(si) {
      enVuelo = si;
      ui.txt.disabled = si || cerrada;
      ui.enviar.disabled = si || cerrada || ui.txt.value.trim() === '';
      if (ui.mic) ui.mic.disabled = si || cerrada;
      if (ui.foto) ui.foto.disabled = si || cerrada;
    }

    function post(ruta, cuerpo) {
      return fetch(API + ruta, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(cuerpo),
      }).then(function (r) { return r.json(); });
    }

    function trasResponder(r) {
      if (r && r.cerrada) {
        cerrada = true;
        aviso('Esta conversacion ya quedo bien larga y la cerramos aca. Todo lo que contaste quedo guardado.');
      }
      // El pedido de contacto llega despues de conversar, no antes:
      // pedir el telefono de entrada espanta a quien viene a quejarse.
      if (turnos >= 2 && ui.contacto.classList.contains('cheo-oculto')) {
        ui.contacto.classList.remove('cheo-oculto');
        requestAnimationFrame(abajo);
      }
    }

    // manda(texto, {saludo, medio, foto}) — el unico camino al chat.
    function manda(texto, op) {
      op = op || {};
      if (enVuelo || cerrada) return Promise.resolve();

      if (!op.saludo) {
        texto = String(texto == null ? ui.txt.value : texto).trim();
        if (!texto) return Promise.resolve();
        if (!op.yaPintado) pinta('yo', texto, op.medio, op.foto);
        if (texto === ui.txt.value.trim()) {
          ui.txt.value = '';
          ui.txt.style.height = 'auto';
        }
        pintaAtajos(false);
        turnos++;
      }

      bloquea(true);

      var cuerpo = { sesion_id: SESION, origen: MODO === 'pagina' ? 'pagina' : 'widget' };
      if (op.saludo) { cuerpo.saludo = true; cuerpo.pagina_url = location.href; }
      else { cuerpo.mensaje = texto; cuerpo.medio = op.medio || 'texto'; }

      escribiendo(true);

      return post('/tumbao/cheo', cuerpo).then(function (r) {
        escribiendo(false);
        var lista = (r && r.mensajes && r.mensajes.length) ? r.mensajes
                  : [(r && r.respuesta) || 'Se me enredo la respuesta. Escribeme otra vez y le seguimos.'];
        return pintaTanda(lista).then(function () {
          trasResponder(r);
          bloquea(false);
          if (!cerrada && MODO === 'pagina') ui.txt.focus();
        });
      }).catch(function () {
        escribiendo(false);
        pinta('el', 'No pude conectarme. Revisa tu senal y escribeme de nuevo.');
        bloquea(false);
      });
    }

    /* ---------------- notas de voz ---------------- */

    var grabadora = null;
    var pedazos = [];
    var cancelada = false;
    var tictac = null;

    function tipoAudio() {
      var opciones = ['audio/webm;codecs=opus', 'audio/webm', 'audio/mp4', 'audio/ogg;codecs=opus'];
      for (var i = 0; i < opciones.length; i++) {
        try { if (MediaRecorder.isTypeSupported(opciones[i])) return opciones[i]; } catch (e) { /* sigue */ }
      }
      return '';
    }

    function mostrarGrabacion(si) {
      ui.caja.classList.toggle('cheo-oculto', si);
      ui.grabando.classList.toggle('cheo-oculto', !si);
    }

    function empezarAGrabar() {
      if (enVuelo || cerrada || grabadora) return;
      navigator.mediaDevices.getUserMedia({ audio: true }).then(function (pista) {
        var tipo = tipoAudio();
        grabadora = tipo ? new MediaRecorder(pista, { mimeType: tipo }) : new MediaRecorder(pista);
        pedazos = [];
        cancelada = false;

        grabadora.ondataavailable = function (e) { if (e.data && e.data.size) pedazos.push(e.data); };
        grabadora.onstop = function () {
          // La pista se suelta SIEMPRE, se haya mandado la nota o no: si
          // no, el navegador deja el puntico rojo del microfono prendido
          // y la gente cree que la pagina la sigue oyendo.
          pista.getTracks().forEach(function (t) { t.stop(); });
          clearInterval(tictac);
          mostrarGrabacion(false);
          var blob = new Blob(pedazos, { type: grabadora.mimeType || 'audio/webm' });
          grabadora = null;
          if (!cancelada) mandarVoz(blob);
        };

        grabadora.start();
        mostrarGrabacion(true);

        var desde = Date.now();
        ui.reloj.textContent = '0:00';
        tictac = setInterval(function () {
          var s = Math.floor((Date.now() - desde) / 1000);
          ui.reloj.textContent = Math.floor(s / 60) + ':' + String(s % 60).padStart(2, '0');
          if (s >= MAX_SEG) pararGrabacion(false);
        }, 250);
      }).catch(function () {
        aviso('No pude prender el microfono. Revisa el permiso del navegador, o escribeme y ya.');
      });
    }

    function pararGrabacion(cancelar) {
      if (!grabadora) return;
      cancelada = !!cancelar;
      try { grabadora.stop(); } catch (e) { /* ya estaba parada */ }
    }

    function aBase64(blob) {
      return new Promise(function (ok, mal) {
        var fr = new FileReader();
        fr.onload = function () { ok(String(fr.result)); };
        fr.onerror = mal;
        fr.readAsDataURL(blob);
      });
    }

    function mandarVoz(blob) {
      if (!blob || blob.size < 2000) {
        aviso('Esa quedo muy cortica. Manten apretado un poquito mas.');
        return;
      }
      bloquea(true);
      escribiendo(true);

      aBase64(blob).then(function (dataUrl) {
        return post('/tumbao/cheo/voz', { audio: dataUrl });
      }).then(function (r) {
        escribiendo(false);
        if (!r || !r.ok) {
          bloquea(false);
          aviso((r && r.mensaje) || 'No alcance a oirte bien. Mandame otra nota o escribemelo.');
          return;
        }
        // Se pinta lo que se entendio ANTES de mandarlo: si Whisper se
        // equivoco, la persona lo ve y lo puede corregir escribiendo.
        pinta('yo', r.texto, 'voz');
        bloquea(false);
        return manda(r.texto, { medio: 'voz', yaPintado: true });
      }).catch(function () {
        escribiendo(false);
        bloquea(false);
        aviso('No pude mandar la nota. Revisa tu senal.');
      });
    }

    /* ---------------- fotos ---------------- */

    // Se encoge en el navegador antes de mandarla. Una foto de celular
    // pesa 4 MB; asi viaja como 150 KB y llega igual de entendible.
    function encoger(file) {
      return new Promise(function (ok, mal) {
        var lector = new FileReader();
        lector.onerror = mal;
        lector.onload = function () {
          var img = new Image();
          img.onerror = mal;
          img.onload = function () {
            var max = 1280;
            var w = img.width, h = img.height;
            if (w > max || h > max) {
              if (w > h) { h = Math.round(h * max / w); w = max; }
              else { w = Math.round(w * max / h); h = max; }
            }
            var lienzo = document.createElement('canvas');
            lienzo.width = w; lienzo.height = h;
            lienzo.getContext('2d').drawImage(img, 0, 0, w, h);
            try { ok(lienzo.toDataURL('image/jpeg', 0.72)); }
            catch (e) { ok(String(lector.result)); }
          };
          img.src = String(lector.result);
        };
        lector.readAsDataURL(file);
      });
    }

    function mandarFoto(file) {
      if (!file) return;
      bloquea(true);
      escribiendo(true);

      encoger(file).then(function (dataUrl) {
        return post('/tumbao/cheo/foto', { imagen: dataUrl }).then(function (r) {
          escribiendo(false);
          var desc = (r && r.descripcion) || 'Una foto';
          // La miniatura se ve en el chat, pero la foto NO se guarda en
          // ningun lado: al recargar queda solo lo que Cheo vio en ella.
          pinta('yo', ui.txt.value.trim() || '', 'foto', dataUrl);
          var pie = ui.txt.value.trim();
          ui.txt.value = '';
          ui.txt.style.height = 'auto';
          bloquea(false);
          return manda(pie ? desc + '. La persona escribio: ' + pie : desc,
                       { medio: 'foto', yaPintado: true });
        });
      }).catch(function () {
        escribiendo(false);
        bloquea(false);
        aviso('No pude leer esa foto. Intenta con otra.');
      });
    }

    /* ---------------- arranque ---------------- */

    function saluda() {
      if (saludado) return;
      saludado = true;
      try { localStorage.setItem(LS_VISTO, '1'); } catch (e) { /* da igual */ }
      var punto = ui.boton && ui.boton.querySelector('.cheo-punto');
      if (punto) punto.remove();

      // Primero se pregunta si esta sesion ya tiene conversacion. Ese
      // endpoint no llama al modelo, o sea que reabrir la burbuja no
      // cuesta nada, y la persona ve donde quedo en vez de una pantalla
      // en blanco que la obliga a repetir lo que ya conto.
      bloquea(true);
      escribiendo(true);

      post('/tumbao/cheo/historial', { sesion_id: SESION }).then(function (h) {
        escribiendo(false);
        var previos = (h && h.mensajes) || [];

        if (previos.length === 0) {
          // Primera vez: aqui si se gasta una llamada al modelo, y se
          // hace al ABRIR, no al cargar la pagina. Si fuera al cargar,
          // cada visita costaria plata aunque nadie pensara escribir.
          bloquea(false);
          pintaAtajos(true);
          manda(null, { saludo: true });
          return;
        }

        previos.forEach(function (m) {
          pinta(m.rol === 'cheo' ? 'el' : 'yo', m.texto, m.medio);
        });
        aviso('Aqui quedo nuestra conversacion anterior. Sigue cuando quieras.');
        turnos = previos.filter(function (m) { return m.rol === 'usuario'; }).length;
        if (h.dejo_contacto) ui.contacto.remove();
        else if (turnos >= 2) ui.contacto.classList.remove('cheo-oculto');
        if (h.cerrada) {
          cerrada = true;
          aviso('Esta conversacion ya quedo bien larga y la cerramos aca. Todo lo que contaste quedo guardado.');
        }
        bloquea(false);
        requestAnimationFrame(abajo);
      }).catch(function () {
        // Si el historial no carga, no se deja a la persona en blanco:
        // se arranca como si fuera nueva. Peor caso, Cheo se vuelve a
        // presentar.
        escribiendo(false);
        bloquea(false);
        pintaAtajos(true);
        manda(null, { saludo: true });
      });
    }

    function abre() {
      if (abierto) return;
      abierto = true;
      ui.panel.classList.remove('cheo-oculto');
      requestAnimationFrame(function () { ui.panel.classList.add('cheo-abierto'); });
      if (ui.boton) ui.boton.style.display = 'none';
      saluda();
      setTimeout(function () { ui.txt.focus(); }, 220);
    }

    function cierra() {
      if (!abierto || MODO === 'pagina') return;
      pararGrabacion(true);
      abierto = false;
      ui.panel.classList.remove('cheo-abierto');
      setTimeout(function () {
        ui.panel.classList.add('cheo-oculto');
        if (ui.boton) { ui.boton.style.display = ''; ui.boton.focus(); }
      }, 180);
    }

    if (ui.boton) ui.boton.addEventListener('click', abre);
    if (ui.cerrar) ui.cerrar.addEventListener('click', cierra);

    document.addEventListener('keydown', function (e) {
      if (e.key === 'Escape' && abierto && MODO === 'widget') cierra();
    });

    ui.txt.addEventListener('input', function () {
      ui.txt.style.height = 'auto';
      ui.txt.style.height = Math.min(ui.txt.scrollHeight, 110) + 'px';
      ui.enviar.disabled = enVuelo || cerrada || ui.txt.value.trim() === '';
    });

    ui.txt.addEventListener('keydown', function (e) {
      // Enter manda; Shift+Enter hace salto de linea. En movil el teclado
      // trae su propio salto de linea, asi que solo aplica donde de
      // verdad hay un Enter comodo.
      if (e.key === 'Enter' && !e.shiftKey && window.innerWidth > 520) {
        e.preventDefault();
        manda();
      }
    });

    ui.enviar.addEventListener('click', function () { manda(); });

    if (ui.mic) ui.mic.addEventListener('click', empezarAGrabar);
    ui.cancelar.addEventListener('click', function () { pararGrabacion(true); });
    ui.listo.addEventListener('click', function () { pararGrabacion(false); });

    if (ui.foto) {
      ui.foto.addEventListener('click', function () { ui.archivo.click(); });
      ui.archivo.addEventListener('change', function () {
        var f = ui.archivo.files && ui.archivo.files[0];
        ui.archivo.value = '';
        if (f) mandarFoto(f);
      });
    }

    ui.btnOk.addEventListener('click', function () {
      var nombre = ui.inNombre.value.trim();
      var tel = ui.inTel.value.trim();
      if (!nombre && !tel) return;
      ui.btnOk.disabled = true;
      post('/tumbao/cheo/contacto', {
        sesion_id: SESION, nombre: nombre, telefono: tel, habeas: true,
      }).then(function () {
        ui.contacto.classList.add('cheo-oculto');
        aviso('Listo, quedo anotado. Gracias por el tiempo.');
      }).catch(function () {
        ui.btnOk.disabled = false;
      });
    });

    if (MODO === 'pagina') saluda();

    // Para poder abrirlo desde un boton propio de la pagina:
    // <button onclick="Cheo.abrir()">Cuentanos</button>
    window.Cheo = { abrir: abre, cerrar: cierra, sesion: SESION };
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', arranca);
  } else {
    arranca();
  }
})();
