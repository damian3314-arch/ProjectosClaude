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
    $('kicker').textContent = nombre ? 'Invitación especial para ' + nombre : 'Invitación especial';
    $('h1').innerHTML = nombre ? U.esc(nombre) + ', esta Navidad <em>brillas tú.</em>' : 'Esta Navidad <em>brillas tú.</em>';
    $('lede').textContent = 'Eres uno de nuestros clientes más especiales y queremos agradecértelo. Trae hasta 3 joyas de oro y te las dejamos brillando, sin ningún costo. Mientras tanto, compartes con nosotros un rato agradable con una Corona bien fría.';
    $('chip').textContent = 'De regalo para ti · hasta 3 joyas · sin costo';
    $('ctaH').innerHTML = 'Tu turno te espera. <em>Escríbenos y lo apartamos.</em>';
    $('ctaP').textContent = 'Responde por WhatsApp y una asesora te agenda la hora, para tener todo listo cuando llegues. Puedes venir con alguien especial.';
  } else {
    $('chip').textContent = 'Shampoo de brillo ' + (P.shampoo || 'desde $20.000') + ' · hasta 3 joyas';
  }
  $('tk').textContent = (vip
    ? 'Tu invitación especial ✦ shampoo de brillo de regalo ✦ Corona bien fría ✦ sábado 21 de noviembre ✦ la vitrina más linda de la Navidad ✦ '
    : 'Navidad es para brillar ✦ shampoo de brillo para tus joyas ✦ Corona bien fría ✦ sábado 21 de noviembre, de corrido ✦ oro 18k ✦ ').repeat(4);

  /* ----- cuenta regresiva ----- */
  var faltan = U.daysUntil(C.campana.lanzamiento);
  if (faltan >= 0) {
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
  var on = {};
  function renderFlags() {
    $('flags').innerHTML = FL.map(function (t, i) {
      return '<button type="button" class="fl" style="--i:' + i + '" data-i="' + i + '" aria-pressed="' + (!!on[i]) + '">' +
        '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 21V4M5 4h12l-2.5 4L17 12H5"/></svg><span>' + U.esc(t) + '</span></button>';
    }).join('');
    Array.prototype.forEach.call($('flags').querySelectorAll('button'), function (b) {
      b.onclick = function () { var i = +b.dataset.i; if (on[i]) delete on[i]; else on[i] = 1; renderFlags(); };
    });
    var n = Object.keys(on).length;
    var v = n === 0 ? ['Marca lo que te pasa.', 'Sé honesto: aquí nadie te juzga. Casi.']
      : n <= 2 ? ['Nada grave, pero tu oro pide brillo.', 'Mejor ahora que en plena Navidad.']
      : n <= 5 ? ['Tu oro necesita su día de realeza.', 'Tráelo todo: te apartamos turno.']
      : ['Alerta dorada.', 'Trae todo. La Corona la ponemos nosotros.'];
    $('verdict').innerHTML = '<div class="n num">' + n + '<span> / ' + FL.length + '</span></div>' +
      '<div><div class="t">' + v[0] + '</div><p>' + v[1] + '</p></div>' +
      '<a class="btn wa" href="' + wa + '" target="_blank" rel="noopener">Agenda tu turno</a>';
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
