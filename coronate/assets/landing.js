/* Landing de clientes, pensada para celular.
   General (cualquier persona): index.html  ·  Invitación premium (shampoo de regalo): index.html?n=Carlos&p=1  (también vale ?vip=1) */
(function () {
  var C = window.CORO, U = window.CoroUtil;
  var $ = function (id) { return document.getElementById(id); };
  var q = new URLSearchParams(window.CORO_DEMO || location.search); /* CORO_DEMO: solo para vistas previas sin parámetros en la URL */
  var nombre = (q.get('n') || '').trim().slice(0, 40);
  var vip = q.get('p') === '1' || q.get('vip') === '1';
  var P = C.precios || {};
  document.body.classList.toggle('vip', vip);

  Array.prototype.forEach.call(document.querySelectorAll('[data-c]'), function (el) {
    var v = el.getAttribute('data-c').split('.').reduce(function (o, k) { return o && o[k]; }, C);
    if (v != null) el.textContent = v;
  });

  /* ----- WhatsApp: todas las citas las agenda una asesora ----- */
  var msg = vip
    ? 'Hola, soy ' + (nombre || '[tu nombre]') + '. Recibí la invitación especial de Joyería Tanya Santiago y quiero agendar mi turno para el shampoo de brillo de regalo.'
    : 'Hola, quiero agendar mi turno para el shampoo de brillo de mis joyas en Joyería Tanya Santiago.';
  var wa = C.contacto.whatsapp ? U.waLink(C.contacto.whatsapp, msg) : '#';
  ['waTop', 'waHero', 'waEnd'].forEach(function (id) { $(id).href = wa; });

  /* ----- textos según el tipo de invitación ----- */
  if (vip) {
    /* Premium: primero la tarjeta personal y el test. El regalo se revela al terminarlo. */
    $('kicker').textContent = nombre ? 'Hola, ' + nombre : 'Una invitación para ti';
    $('h1').innerHTML = nombre ? 'Hola ' + U.esc(nombre) + ', <em>esto es para ti.</em>' : 'Esto es <em>para ti.</em>';
    $('lede').textContent = 'Esta Navidad tenemos una invitación especial para ti. Antes de contártela, cuéntanos cómo está tu oro: solo te tomará un parpadeo.';
    $('chip').hidden = true;
    $('ctaH').innerHTML = 'Tu turno te espera. <em>Escríbenos y lo apartamos.</em>';
    $('ctaP').textContent = 'Responde por WhatsApp y una asesora te agenda la hora, para tener todo listo cuando llegues. Puedes venir con alguien especial.';
  } else {
    $('chip').textContent = 'Shampoo de brillo ' + (P.shampoo || 'desde $20.000') + ' · hasta 3 joyas';
  }
  $('tk').textContent = (vip
    ? 'Una invitación especial para ti\u2003✦\u2003descubre si tu oro necesita un spa\u2003✦\u2003sábado 21 de noviembre\u2003✦\u2003la vitrina más linda de la Navidad\u2003✦\u2003'
    : 'Navidad es para brillar\u2003✦\u2003shampoo de brillo para tus joyas\u2003✦\u2003Corona bien fría\u2003✦\u2003sábado 21 de noviembre, de corrido\u2003✦\u2003oro 18k\u2003✦\u2003').repeat(4);

  /* ----- cuenta regresiva ----- */
  var faltan = U.daysUntil(C.campana.lanzamiento);
  if (faltan >= 0 && !vip) {
    $('count').hidden = false;
    $('countN').textContent = faltan === 0 ? 'Hoy' : faltan;
    $('countT').textContent = faltan === 0 ? 'se abre el telón' : (faltan === 1 ? 'día para el ' : 'días para el ') + 'sábado 21';
  }

  /* ----- nieve ----- */
  var snow = $('snow');
  for (var i = 0; i < 16; i++) {
    var d = document.createElement('i');
    d.style.left = (Math.random() * 100) + '%';
    d.style.animationDuration = (9 + Math.random() * 10) + 's';
    d.style.animationDelay = (-Math.random() * 12) + 's';
    d.style.opacity = (0.3 + Math.random() * 0.5).toFixed(2);
    snow.appendChild(d);
  }

  /* ----- test de la realeza ----- */
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
  var FLV = [
    'Los aretes que no te quitas desde la primera comunión… ¡tienen olor a tradición!',
    'Esa cadena opaca que se funde con el tono de tu piel porque ya perdió su brillo.',
    'Los anillos que todavía tienen jabón pegado desde el día del «sí».',
    'Los balines de esa manilla tejida que ya huelen a recuerdo.',
    'El broche flojo que te tiene rezando para no perder tu joya.'
  ];
  if (vip) {
    FL = FLV;
    var sh = $('test').querySelector('.sh');
    sh.innerHTML = '<p class="eyebrow">El test del spa dorado</p><h2>Tu oro pide auxilio <em>si…</em></h2><p>Un test de esos que te toman un parpadeo, sobre tus joyas de oro.</p>';
  }
  var on = {};
  var hecho = false;

  function renderFlags() {
    $('flags').innerHTML = FL.map(function (t, i) {
      return '<button type="button" class="fl" style="--i:' + i + '" data-i="' + i + '" aria-pressed="' + (!!on[i]) + '">' +
        '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 21V4M5 4h12l-2.5 4L17 12H5"/></svg><span>' + U.esc(t) + '</span></button>';
    }).join('');
    Array.prototype.forEach.call($('flags').querySelectorAll('button'), function (b) {
      b.onclick = function () { var i = +b.dataset.i; if (on[i]) delete on[i]; else on[i] = 1; document.body.classList.add('tocado'); renderFlags(); };
    });
    var n = Object.keys(on).length;
    var v = n === 0 ? ['Marca lo que te pasa.', 'Sé honesto: aquí nadie te juzga. Casi.']
      : n <= 2 ? ['Nada grave, pero tu oro pide brillo.', 'Mejor ahora que en plena Navidad.']
      : n <= 5 ? ['Tu oro necesita su día de realeza.', 'Tráelo todo: te apartamos turno.']
      : ['Alerta dorada.', 'Trae todo. La Corona la ponemos nosotros.'];
    if (vip) {
      $('verdict').innerHTML = '<div class="n num">' + n + '<span> / ' + FL.length + '</span></div>' +
        '<div><div class="t">' + (n ? 'Tu oro pide auxilio.' : 'Marca lo que te pasa.') + '</div><p>' + (n ? 'Toca «Ver mi resultado» y te contamos qué tenemos para ti.' : 'Toca al menos una bandera para ver tu resultado.') + '</p></div>' +
        '<button type="button" class="btn gold go" id="goRes"' + (n ? '' : ' disabled') + '>Ver mi resultado</button>';
      if ($('goRes')) $('goRes').onclick = terminar;
      return;
    }
    $('verdict').innerHTML = '<div class="n num">' + n + '<span> / ' + FL.length + '</span></div>' +
      '<div><div class="t">' + v[0] + '</div><p>' + v[1] + '</p></div>' +
      '<a class="btn wa" href="' + wa + '" target="_blank" rel="noopener">Agenda tu turno</a>';
  }
  /* ----- premium: resultado, regalo y aviso a las asesoras ----- */
  function revelar() {
    document.body.classList.add('done');
    var m = nombre ? 'Hola, soy ' + nombre + '. ' : 'Hola. ';
    $('premioH').innerHTML = (nombre ? U.esc(nombre) + ', tu oro pide ' : 'Tu oro pide ') + '<em>su día de brillo.</em>';
    $('premioP').textContent = 'Eres uno de nuestros clientes más especiales y queremos agradecer tu fidelidad. Trae hasta 3 de tus joyas favoritas el sábado 21 y te las dejamos brillando. Y mientras esperas, disfruta una Corona bien fría, cortesía de nuestra casa (solo mayores de 18).';
    if (C.contacto.whatsapp) {
      $('waConf').href = U.waLink(C.contacto.whatsapp, m + '¡Claro que sí, no me lo pierdo! Voy el sábado 21 de noviembre y me gustaría venir hacia las [hora]. ¿Me apartan el cupo?');
    }
  }
  function terminar() {
    if (!Object.keys(on).length) return;
    revelar();
    avisar();
    setTimeout(function () { $('premio').scrollIntoView({ behavior: 'smooth', block: 'start' }); }, 60);
  }
  /* Avisa al panel de las asesoras (Worker o Apps Script) que esta persona hizo el test. Sin dirección configurada no envía nada. */
  function avisar() {
    var url = C.avisos || '';
    if (!url) return;
    try {
      var body = JSON.stringify({ evento: 'test', k: q.get('k') || '', n: nombre, banderas: Object.keys(on).length, t: new Date().toISOString() });
      if (navigator.sendBeacon) navigator.sendBeacon(url, new Blob([body], { type: 'text/plain' }));
      else fetch(url, { method: 'POST', mode: 'no-cors', body: body, keepalive: true });
    } catch (e) {}
  }
  renderFlags();

  /* ----- lo que te espera ----- */
  var perks = [
    ['shampoo', vip ? 'Shampoo de brillo, de regalo' : 'Shampoo de brillo', vip ? 'Hasta 3 joyas de oro salen lavadas y brillando, sin ningún costo para ti.' : 'Hasta 3 joyas de oro salen lavadas y brillando.', vip ? 'De regalo' : (P.shampoo || 'Desde $20.000')],
    ['corona', 'Tu Corona bien fría', 'Mientras trabajamos, te atendemos con una Corona en un espacio de Navidad. Solo mayores de 18.', vip ? 'Por la casa' : 'Por la casa'],
    ['arreglo', 'Arreglos al momento', 'Puntos de soldadura, broches y piedras flojas. Te mostramos el valor y tú decides.', P.reparacion || 'Desde $30.000'],
    ['pulsera', 'Tu pulsera tejida', 'Escoges el hilo y el dije de oro, y la tejemos a tu medida.', P.pulsera || 'Desde $30.000'],
    ['vitrina', 'La vitrina de Navidad', 'Tréboles, corazones de esmeralda, candongas y argollas recién llegadas.', 'Oro 18k'],
    ['oro', 'Tu oro vale', 'El oro que ya no usas lo recibimos como parte de pago de tu próxima joya, al precio del día.', 'Parte de pago']
  ];
  var ICO = {
    shampoo: '<path d="M12 3c3 4 5 6.5 5 9a5 5 0 0 1-10 0c0-2.5 2-5 5-9Z"/>',
    corona: '<path d="M3 8l4 4 5-7 5 7 4-4-2 11H5Z"/>',
    arreglo: '<path d="M14 6a4 4 0 0 0 5 5L11 19l-4 1 1-4Z"/>',
    pulsera: '<path d="M4 12c4-6 12-6 16 0M4 12c4 6 12 6 16 0"/><circle cx="12" cy="12" r="2"/>',
    vitrina: '<path d="M12 3l2.6 5.6L20 9.3l-4 4 1 5.7-5-2.8-5 2.8 1-5.7-4-4 5.4-.7Z"/>',
    oro: '<circle cx="12" cy="12" r="8"/><path d="M9 12h6M12 9v6"/>'
  };
  if (vip) perks = [
    ['arreglo', 'Soldadura de cadenas en oro', 'Dejamos tu cadena entera otra vez.', '$40.000'],
    ['pulsera', 'Mantenimiento y tejido de pulseras', 'Renovamos tu pulsera o la tejemos a tu medida.', 'Desde $20.000'],
    ['oro', 'Valoramos tus joyas', 'Con el precio internacional del oro actualizado, para que conozcas el valor de tu inversión.', 'Sin compromiso'],
    ['vitrina', 'La vitrina de Navidad', 'Tréboles, corazones de esmeralda, candongas y argollas recién llegadas.', 'Oro 18k']
  ];
  $('perks').innerHTML = perks.map(function (p, i) {
    return '<div class="perk" style="--i:' + i + '"><div class="ic"><svg viewBox="0 0 24 24" aria-hidden="true">' + ICO[p[0]] + '</svg></div>' +
      '<div><h3>' + p[1] + '</h3><p>' + p[2] + '</p></div><span class="price">' + p[3] + '</span></div>';
  }).join('');


  /* ----- preguntas ----- */
  var faq = [
    ['¿Cuánto cuesta?', vip
      ? 'Para ti, el shampoo de brillo de hasta 3 joyas de oro es de regalo. Los arreglos y las pulseras tejidas tienen costo: ' + (P.reparacion || 'desde $30.000') + ' y ' + (P.pulsera || 'desde $30.000') + '.'
      : 'El shampoo de brillo de hasta 3 joyas cuesta ' + (P.shampoo || 'desde $20.000') + '. Los arreglos, ' + (P.reparacion || 'desde $30.000') + ', y la pulsera tejida, ' + (P.pulsera || 'desde $30.000') + '. La Corona va por la casa (+18).'],
    ['¿Tengo que agendar?', 'Sí, te lo recomendamos: los cupos son limitados. Escríbenos por WhatsApp y una asesora te aparta la hora.'],
    ['¿Puedo ir con alguien?', vip ? 'Claro, puedes venir con alguien especial.' : 'Claro. La cerveza es solo para mayores de 18, con documento.'],
    ['¿Reciben mi oro como parte de pago?', 'Sí, al precio del día, para tu próxima joya.'],
    ['¿Qué días atienden?', 'El lanzamiento es el sábado 21 de noviembre, de corrido. Después, todos los sábados hasta el 26 de diciembre y algunos domingos de diciembre con cita.']
  ];
  $('faqList').innerHTML = faq.map(function (f) { return '<details class="faq"><summary>' + f[0] + '</summary><p>' + f[1] + '</p></details>'; }).join('');
})();
