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
 */
(function () {
  'use strict';

  var script = document.currentScript ||
    (function () { var s = document.getElementsByTagName('script'); return s[s.length - 1]; })();
  var cfg = (script && script.dataset) || {};

  var API = cfg.api || 'https://barragan.app.n8n.cloud/webhook';
  var MODO = cfg.modo === 'pagina' ? 'pagina' : 'widget';
  var URL_PAGINA = cfg.paginaCheo || '/cheo.html';
  var WHATSAPP = cfg.whatsapp || '';
  var ACENTO = cfg.acento || '#c2410c';

  var LS_SESION = 'cheo.sesion';
  var LS_VISTO = 'cheo.visto';

  /* ---------------------------------------------------------------- */
  /* Sesion                                                            */
  /* ---------------------------------------------------------------- */

  function nuevaSesion() {
    // crypto.randomUUID no existe en navegadores viejos; el respaldo no
    // necesita ser criptografico, solo dificil de adivinar por accidente.
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

  /* ---------------------------------------------------------------- */
  /* Estilos                                                           */
  /* ---------------------------------------------------------------- */

  var CSS = [
    '.cheo-raiz{--cheo-acento:' + ACENTO + ';--cheo-tinta:#1c1917;--cheo-suave:#78716c;',
    '--cheo-linea:#e7e5e4;--cheo-fondo:#fff;--cheo-burbuja-yo:' + ACENTO + ';--cheo-burbuja-el:#f5f5f4;',
    'font-family:system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;-webkit-font-smoothing:antialiased}',

    '@media (prefers-color-scheme:dark){.cheo-raiz{--cheo-tinta:#fafaf9;--cheo-suave:#a8a29e;',
    '--cheo-linea:#292524;--cheo-fondo:#1c1917;--cheo-burbuja-el:#292524}}',

    /* boton flotante */
    '.cheo-boton{position:fixed;right:20px;bottom:20px;z-index:2147483000;display:flex;align-items:center;',
    'gap:9px;border:0;cursor:pointer;background:var(--cheo-acento);color:#fff;padding:13px 18px 13px 15px;',
    'border-radius:999px;font-size:15px;font-weight:550;line-height:1;box-shadow:0 6px 24px rgba(0,0,0,.19);',
    'transition:transform .18s ease,box-shadow .18s ease;font-family:inherit}',
    '.cheo-boton:hover{transform:translateY(-2px);box-shadow:0 10px 30px rgba(0,0,0,.24)}',
    '.cheo-boton:focus-visible{outline:3px solid var(--cheo-acento);outline-offset:3px}',
    '.cheo-boton svg{width:21px;height:21px;flex:none}',
    '.cheo-punto{position:absolute;top:10px;right:14px;width:9px;height:9px;border-radius:50%;',
    'background:#22c55e;box-shadow:0 0 0 2.5px var(--cheo-acento)}',

    /* panel */
    '.cheo-panel{position:fixed;right:20px;bottom:20px;z-index:2147483001;width:388px;max-width:calc(100vw - 32px);',
    'height:min(620px,calc(100vh - 40px));background:var(--cheo-fondo);border-radius:18px;display:flex;',
    'flex-direction:column;overflow:hidden;box-shadow:0 18px 60px rgba(0,0,0,.26);',
    'border:1px solid var(--cheo-linea);opacity:0;transform:translateY(10px) scale(.985);',
    'transition:opacity .18s ease,transform .18s ease}',
    '.cheo-panel.cheo-abierto{opacity:1;transform:none}',
    '@media (max-width:520px){.cheo-panel{right:0;bottom:0;width:100vw;max-width:100vw;height:100dvh;border-radius:0;border:0}}',

    /* modo pagina: ocupa el contenedor, sin sombra ni posicion fija */
    '.cheo-raiz.cheo-modo-pagina .cheo-panel{position:static;width:100%;max-width:100%;height:100%;',
    'box-shadow:none;border-radius:14px;opacity:1;transform:none}',
    '.cheo-raiz.cheo-modo-pagina{height:100%}',

    /* cabecera */
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

    /* mensajes */
    '.cheo-hilo{flex:1;overflow-y:auto;padding:18px 16px 8px;display:flex;flex-direction:column;gap:11px;',
    'overscroll-behavior:contain;scrollbar-width:thin}',
    '.cheo-msg{max-width:85%;padding:10px 13px;border-radius:15px;font-size:14.5px;line-height:1.5;',
    'white-space:pre-wrap;word-wrap:break-word;overflow-wrap:anywhere;animation:cheo-entra .22s ease}',
    '@keyframes cheo-entra{from{opacity:0;transform:translateY(5px)}to{opacity:1;transform:none}}',
    '.cheo-msg.cheo-el{align-self:flex-start;background:var(--cheo-burbuja-el);color:var(--cheo-tinta);border-bottom-left-radius:5px}',
    '.cheo-msg.cheo-yo{align-self:flex-end;background:var(--cheo-burbuja-yo);color:#fff;border-bottom-right-radius:5px}',
    '.cheo-aviso{align-self:center;text-align:center;font-size:11.5px;color:var(--cheo-suave);',
    'line-height:1.5;padding:2px 10px;max-width:92%}',

    /* escribiendo */
    '.cheo-tres{align-self:flex-start;background:var(--cheo-burbuja-el);border-radius:15px;border-bottom-left-radius:5px;',
    'padding:13px 15px;display:flex;gap:4px}',
    '.cheo-tres span{width:6px;height:6px;border-radius:50%;background:var(--cheo-suave);animation:cheo-late 1.3s infinite}',
    '.cheo-tres span:nth-child(2){animation-delay:.18s}.cheo-tres span:nth-child(3){animation-delay:.36s}',
    '@keyframes cheo-late{0%,60%,100%{opacity:.28;transform:translateY(0)}30%{opacity:1;transform:translateY(-3px)}}',

    /* atajos */
    '.cheo-atajos{display:flex;flex-wrap:wrap;gap:7px;padding:4px 16px 10px}',
    '.cheo-atajo{border:1px solid var(--cheo-linea);background:transparent;color:var(--cheo-tinta);',
    'border-radius:999px;padding:7px 13px;font-size:13px;cursor:pointer;font-family:inherit;line-height:1.3;',
    'transition:border-color .15s ease}',
    '.cheo-atajo:hover{border-color:var(--cheo-acento);color:var(--cheo-acento)}',

    /* escribir */
    '.cheo-pie{border-top:1px solid var(--cheo-linea);padding:11px 12px 12px;flex:none;background:var(--cheo-fondo)}',
    '.cheo-caja{display:flex;align-items:flex-end;gap:8px;background:var(--cheo-burbuja-el);border-radius:14px;padding:6px 6px 6px 13px}',
    '.cheo-txt{flex:1;border:0;background:transparent;resize:none;font-family:inherit;font-size:14.5px;',
    'line-height:1.45;color:var(--cheo-tinta);max-height:110px;padding:7px 0;outline:0}',
    '.cheo-txt::placeholder{color:var(--cheo-suave)}',
    '.cheo-enviar{border:0;background:var(--cheo-acento);color:#fff;width:36px;height:36px;border-radius:11px;',
    'cursor:pointer;display:flex;align-items:center;justify-content:center;flex:none;transition:opacity .15s ease}',
    '.cheo-enviar:disabled{opacity:.34;cursor:default}',
    '.cheo-enviar svg{width:17px;height:17px}',
    '.cheo-legal{text-align:center;font-size:10.5px;color:var(--cheo-suave);margin:9px 2px 0;line-height:1.45}',
    '.cheo-legal a{color:inherit}',

    /* contacto */
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
  /* Construccion del DOM                                              */
  /* ---------------------------------------------------------------- */

  function el(tag, clase, texto) {
    var n = document.createElement(tag);
    if (clase) n.className = clase;
    if (texto != null) n.textContent = texto;
    return n;
  }

  var ICONO_CHAT = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" ' +
    'stroke-linecap="round" stroke-linejoin="round"><path d="M21 11.5a8.4 8.4 0 0 1-9 8.4 8.9 8.9 0 0 1-4-.9L3 21l1.9-4.9A8.4 8.4 0 0 1 12 3a8.4 8.4 0 0 1 9 8.5z"/></svg>';
  var ICONO_X = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" ' +
    'stroke-linecap="round"><path d="M18 6 6 18M6 6l12 12"/></svg>';
  var ICONO_ENVIAR = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" ' +
    'stroke-linecap="round" stroke-linejoin="round"><path d="M22 2 11 13M22 2l-7 20-4-9-9-4 20-7z"/></svg>';

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

    /* --- panel --- */
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

    /* --- contacto (aparece despues de conversar) --- */
    var contacto = el('div', 'cheo-contacto cheo-oculto');
    var pC = el('p', null, 'Si quieres que te contemos en que quedo, dejame tu nombre y tu WhatsApp. Es opcional.');
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
    contacto.appendChild(pC); contacto.appendChild(filaC);
    panel.appendChild(contacto);

    /* --- escribir --- */
    var pie = el('div', 'cheo-pie');
    var caja = el('div', 'cheo-caja');
    var txt = el('textarea', 'cheo-txt');
    txt.rows = 1;
    txt.placeholder = 'Cuentame...';
    txt.setAttribute('aria-label', 'Escribele a Cheo');
    var btnEnviar = el('button', 'cheo-enviar');
    btnEnviar.type = 'button';
    btnEnviar.innerHTML = ICONO_ENVIAR;
    btnEnviar.setAttribute('aria-label', 'Enviar');
    btnEnviar.disabled = true;
    caja.appendChild(txt); caja.appendChild(btnEnviar);
    pie.appendChild(caja);

    var legal = el('div', 'cheo-legal');
    legal.innerHTML = 'Cheo es una inteligencia artificial. Lo que escribas se guarda y lo lee el equipo de Tumbao.';
    pie.appendChild(legal);
    panel.appendChild(pie);

    raiz.appendChild(panel);

    /* --- boton flotante --- */
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
      raiz: raiz, panel: panel, hilo: hilo, atajos: atajos, txt: txt,
      enviar: btnEnviar, cerrar: btnCerrar, boton: boton,
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

    function pinta(rol, texto) {
      var m = el('div', 'cheo-msg ' + (rol === 'yo' ? 'cheo-yo' : 'cheo-el'), texto);
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
    }

    function habla(cuerpo) {
      return fetch(API + '/tumbao/cheo', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(cuerpo),
      }).then(function (r) { return r.json(); });
    }

    function manda(texto, esSaludo) {
      if (enVuelo || cerrada) return;
      if (!esSaludo) {
        texto = String(texto == null ? ui.txt.value : texto).trim();
        if (!texto) return;
        pinta('yo', texto);
        ui.txt.value = '';
        ui.txt.style.height = 'auto';
        pintaAtajos(false);
        turnos++;
      }

      bloquea(true);
      escribiendo(true);

      var cuerpo = { sesion_id: SESION, origen: MODO === 'pagina' ? 'pagina' : 'widget' };
      if (esSaludo) { cuerpo.saludo = true; cuerpo.pagina_url = location.href; }
      else { cuerpo.mensaje = texto; }

      habla(cuerpo).then(function (r) {
        escribiendo(false);
        if (r && r.respuesta) pinta('el', r.respuesta);
        else pinta('el', 'Se me enredo la respuesta. Escribeme otra vez y le seguimos.');

        if (r && r.cerrada) {
          cerrada = true;
          aviso('Esta conversacion ya quedo bien larga y la cerramos aca. Todo lo que contaste quedo guardado.');
        }
        // El pedido de contacto llega despues de conversar, no antes:
        // pedir el telefono de entrada espanta a quien viene a quejarse.
        if (turnos >= 2 && ui.contacto.classList.contains('cheo-oculto')) {
          ui.contacto.classList.remove('cheo-oculto');
          // Al aparecer, el formulario le quita alto al hilo y deja el
          // ultimo mensaje cortado. Hay que volver a bajar DESPUES de
          // que el navegador recalcule.
          requestAnimationFrame(abajo);
        }
        bloquea(false);
        if (!cerrada && MODO === 'pagina') ui.txt.focus();
      }).catch(function () {
        escribiendo(false);
        pinta('el', 'No pude conectarme. Revisa tu senal y escribeme de nuevo.' +
          (WHATSAPP ? ' Si es urgente, escribenos por WhatsApp.' : ''));
        bloquea(false);
      });
    }

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

      fetch(API + '/tumbao/cheo/historial', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ sesion_id: SESION }),
      }).then(function (r) { return r.json(); }).then(function (h) {
        escribiendo(false);
        var previos = (h && h.mensajes) || [];

        if (previos.length === 0) {
          // Primera vez: aqui si se gasta una llamada al modelo, y se
          // hace al ABRIR, no al cargar la pagina. Si fuera al cargar,
          // cada visita costaria plata aunque nadie pensara escribir.
          bloquea(false);
          manda(null, true);
          pintaAtajos(true);
          return;
        }

        previos.forEach(function (m) { pinta(m.rol === 'cheo' ? 'el' : 'yo', m.texto); });
        aviso('Aqui quedo nuestra conversacion anterior. Sigue cuando quieras.');
        turnos = previos.filter(function (m) { return m.rol === 'usuario'; }).length;
        if (h.dejo_contacto) ui.contacto.remove();
        else if (turnos >= 2) ui.contacto.classList.remove('cheo-oculto');
        requestAnimationFrame(abajo);
        if (h.cerrada) {
          cerrada = true;
          aviso('Esta conversacion ya quedo bien larga y la cerramos aca. Todo lo que contaste quedo guardado.');
        }
        bloquea(false);
      }).catch(function () {
        // Si el historial no carga, no se deja a la persona en blanco:
        // se arranca como si fuera nueva. Peor caso, Cheo se vuelve a
        // presentar.
        escribiendo(false);
        bloquea(false);
        manda(null, true);
        pintaAtajos(true);
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
      abierto = false;
      ui.panel.classList.remove('cheo-abierto');
      setTimeout(function () {
        ui.panel.classList.add('cheo-oculto');
        if (ui.boton) ui.boton.style.display = '';
        if (ui.boton) ui.boton.focus();
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
      // trae su propio salto de linea, asi que solo aplica en pantallas
      // donde de verdad hay un Enter comodo.
      if (e.key === 'Enter' && !e.shiftKey && window.innerWidth > 520) {
        e.preventDefault();
        manda();
      }
    });

    ui.enviar.addEventListener('click', function () { manda(); });

    ui.btnOk.addEventListener('click', function () {
      var nombre = ui.inNombre.value.trim();
      var tel = ui.inTel.value.trim();
      if (!nombre && !tel) return;
      ui.btnOk.disabled = true;
      fetch(API + '/tumbao/cheo/contacto', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ sesion_id: SESION, nombre: nombre, telefono: tel, habeas: true }),
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
