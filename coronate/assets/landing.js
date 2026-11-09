/* Landing pública (clientes). Personalización por link: index.html?n=Carlos  ·  día de prueba: ?p=1 */
(function () {
  var C = window.CORO, U = window.CoroUtil, S = U.S;
  var $ = function (id) { return document.getElementById(id); };
  var q = new URLSearchParams(location.search);
  var nombre = (q.get('n') || '').trim().slice(0, 40);
  var prueba = q.get('p') === '1';

  /* ----- textos desde config ----- */
  document.querySelectorAll('[data-c]').forEach(function (el) {
    var v = el.getAttribute('data-c').split('.').reduce(function (o, k) { return o && o[k]; }, C);
    if (v != null) el.textContent = v;
  });
  $('bebidas').textContent = C.bebidas;
  if (C.mostrarSnacks) { $('snacks').textContent = C.snacksTexto; $('snacks').hidden = false; }

  /* ----- nieve (se apaga sola con prefers-reduced-motion en CSS) ----- */
  var snow = $('snow');
  for (var i = 0; i < 18; i++) {
    var d = document.createElement('i');
    d.style.left = (Math.random() * 100) + '%';
    d.style.animationDuration = (8 + Math.random() * 10) + 's';
    d.style.animationDelay = (-Math.random() * 12) + 's';
    d.style.opacity = (0.3 + Math.random() * 0.6).toFixed(2);
    snow.appendChild(d);
  }

  /* ----- saludo y cuenta regresiva ----- */
  if (nombre) {
    $('kicker').textContent = (prueba ? 'Invitación selecta · ' : 'Invitación para ') + nombre;
    $('h1').innerHTML = U.esc(nombre) + ', tu oro, <em>tu corona.</em>';
    $('fNombre').value = nombre;
  } else if (prueba) {
    $('kicker').textContent = 'Invitación selecta · día de prueba';
  }
  var objetivo = prueba ? C.campana.prueba : C.campana.lanzamiento;
  var faltan = U.daysUntil(objetivo);
  if (faltan >= 0) {
    $('count').hidden = false;
    $('countN').textContent = faltan === 0 ? 'Hoy' : faltan;
    $('countT').textContent = faltan === 0 ? 'es el día' : (faltan === 1 ? 'día para el ' : 'días para el ') + U.fmtDate(objetivo, true);
  }

  /* ----- test de banderas rojas ----- */
  var FL = [
    'Los aretes que no te quitas ni para dormir.',
    'La manilla tejida, de cuero o neopreno que ya huele a recuerdo.',
    'La cadena que perdió el brillo y nadie te lo dijo.',
    'Las argollas que ya no brillan como el día del sí.',
    'El broche flojo que te tiene rezando.',
    'La piedra que baila cuando la tocas.',
    'El oro que se oscureció con el perfume y el sudor.',
    'No te acuerdas de la última vez que lo lavaste.'
  ];
  var on = {};
  function renderFlags() {
    $('flags').innerHTML = FL.map(function (t, i) {
      return '<button type="button" class="fl" data-i="' + i + '" aria-pressed="' + (!!on[i]) + '">' +
        '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 21V4M5 4h12l-2.5 4L17 12H5"/></svg><span>' + U.esc(t) + '</span></button>';
    }).join('');
    Array.prototype.forEach.call($('flags').querySelectorAll('button'), function (b) {
      b.onclick = function () { var i = +b.dataset.i; if (on[i]) delete on[i]; else on[i] = 1; renderFlags(); };
    });
    var n = Object.keys(on).length;
    var v = n === 0 ? ['Impecable. ¿Seguro?', 'Igual ven por tu Corona.']
      : n <= 2 ? ['Nada grave, pero tu oro pide spa.', 'Mejor ahora que en diciembre.']
      : n <= 5 ? ['Tu oro necesita un shampoo este sábado.', 'Tráelo todo, te apartamos turno.']
      : ['Alerta dorada.', 'Trae todo. La Corona la ponemos nosotros.'];
    $('verdict').innerHTML = '<div class="n num">' + n + '<span style="font-size:32px"> / ' + FL.length + '</span></div>' +
      '<div><div class="t">' + v[0] + '</div><p>' + v[1] + '</p></div>' +
      '<a class="btn gold" href="#agenda">Agenda tu turno</a>';
  }
  renderFlags();

  /* ----- fechas ----- */
  var fechas = U.fechasPublicas(prueba);
  $('datesList').innerHTML = fechas.length ? fechas.map(function (x) {
    return '<div><b>' + U.esc(U.fmtDate(x.f)) + '</b><span>' + U.esc(x.etiqueta) + '</span></div>';
  }).join('') : '<p class="muted">Las próximas fechas se anuncian muy pronto.</p>';

  /* ----- agenda ----- */
  var fFecha = $('fFecha'), fHora = $('fHora'), fJoyas = $('fJoyas');
  fFecha.innerHTML = fechas.map(function (x) {
    return '<option value="' + x.f + '">' + U.esc(U.fmtDate(x.f, true)) + '</option>';
  }).join('');
  var j = ''; for (var n = 1; n <= C.agenda.maxJoyas; n++) j += '<option value="' + n + '">' + n + (n === 1 ? ' joya' : ' joyas') + '</option>';
  fJoyas.innerHTML = j;

  function takenLocal(f) {
    var t = {};
    (S.get('citas', []) || []).forEach(function (c) { if (c.f === f) t[c.h] = (t[c.h] || 0) + 1; });
    return t;
  }

  function pintarHoras(taken) {
    var f = fFecha.value;
    var local = takenLocal(f);
    fHora.innerHTML = U.slots().map(function (h) {
      var usados = Math.max(local[h] || 0, (taken && taken[h]) || 0);
      var quedan = C.agenda.cuposPorBloque - usados;
      return '<option value="' + h + '"' + (quedan <= 0 ? ' disabled' : '') + '>' + h + (quedan <= 0 ? ' · lleno' : ' · quedan ' + quedan) + '</option>';
    }).join('');
  }

  function cargarHoras() {
    pintarHoras(null);
    if (C.agenda.endpoint && fFecha.value) {
      fetch(C.agenda.endpoint + '?fecha=' + encodeURIComponent(fFecha.value))
        .then(function (r) { return r.json(); })
        .then(function (d) { pintarHoras(d && d.taken); })
        .catch(function () { /* sin red: se queda con lo local */ });
    }
  }
  fFecha.addEventListener('change', cargarHoras);
  cargarHoras();

  function evento(c) {
    return {
      titulo: 'Sábado de Realeza · ' + C.campana.marca, f: c.f, ini: c.h, fin: U.addMin(c.h, C.agenda.bloqueMin),
      detalle: 'Shampoo de brillo para hasta ' + C.agenda.maxJoyas + ' joyas. Cita a nombre de ' + c.nombre + '.', lugar: C.contacto.direccion
    };
  }

  $('form').addEventListener('submit', function (e) {
    e.preventDefault();
    var err = $('fErr'); err.hidden = true;
    var tel = U.normPhone($('fTel').value);
    var c = {
      id: U.uid(), nombre: $('fNombre').value.trim(), tel: tel.num, f: fFecha.value, h: fHora.value,
      joyas: +fJoyas.value, acomp: +$('fAcomp').value, nota: $('fNota').value.trim(), creada: new Date().toISOString(), origen: 'web'
    };
    var msg = '';
    if (c.nombre.length < 2) msg = 'Escribe tu nombre.';
    else if (!tel.ok) msg = 'Revisa tu WhatsApp: son 10 dígitos y empieza por 3.';
    else if (!c.f || !c.h) msg = 'Elige día y hora disponibles.';
    else if (!$('fOk').checked) msg = 'Necesitamos tu autorización para confirmar la cita.';
    if (msg) { err.textContent = msg; err.hidden = false; return; }

    var citas = S.get('citas', []) || [];
    citas.push(c); S.set('citas', citas);
    if (C.agenda.endpoint) {
      try { fetch(C.agenda.endpoint, { method: 'POST', mode: 'no-cors', body: JSON.stringify(c) }); } catch (x) { /* se reintenta desde WhatsApp */ }
    }

    var ev = evento(c);
    $('okP').textContent = c.nombre + ', te esperamos el ' + U.fmtDate(c.f, true) + ' a las ' + c.h + '. ' +
      (C.contacto.whatsapp ? 'Confirma por WhatsApp para que la asesora vea tu cita.' : 'Una asesora te escribirá para confirmar.');
    var act = $('okAct'); act.innerHTML = '';
    if (C.contacto.whatsapp) {
      var texto = 'Hola, soy ' + c.nombre + '. Aparté mi turno para el ' + U.fmtDate(c.f, true) + ' a las ' + c.h + ' (' + c.joyas + ' joya(s)).';
      act.insertAdjacentHTML('beforeend', '<a class="btn wa" target="_blank" rel="noopener" href="' + U.esc(U.waLink(C.contacto.whatsapp, texto)) + '">Confirmar por WhatsApp</a>');
    }
    act.insertAdjacentHTML('beforeend', '<a class="btn line" target="_blank" rel="noopener" href="' + U.esc(U.gcalLink(ev)) + '">Agregar a Google Calendar</a>');
    var ics = document.createElement('button'); ics.type = 'button'; ics.className = 'btn line'; ics.textContent = 'Descargar para otro calendario';
    ics.onclick = function () { U.download('sabado-de-realeza.ics', 'text/calendar', U.makeICS([ev])); };
    act.appendChild(ics);
    $('okNote').textContent = C.agenda.endpoint ? '' : 'Modo prueba: esta cita solo se guardó en este dispositivo.';
    $('form').hidden = true; $('okBox').hidden = false;
    $('okBox').scrollIntoView({ behavior: 'smooth', block: 'center' });
  });
})();
