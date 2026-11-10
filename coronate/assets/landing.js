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
  $('waTop').href = wa;

  /* ----- textos según el tipo de invitación ----- */
  /* Las dos versiones siguen el mismo camino: portada, test, resultado y carta de servicios.
     Premium: el resultado es la invitación sin costo. General: el resultado es la invitación con el valor del servicio. */
  $('kicker').textContent = 'Navidad 2026'; $('kicker').classList.add('mini');
  if (vip) {
    $('h1').innerHTML = nombre ? 'Hola ' + U.esc(nombre) + ', <em>tenemos algo para ti.</em>' : 'Tenemos <em>algo para ti.</em>';
    $('lede').textContent = 'Responde un breve test sobre tus joyas de oro y descubre de qué se trata.';
  } else {
    $('kicker').textContent = 'Tu oro, tu corona';
    $('h1').innerHTML = 'Navidad es para <em>brillar.</em>';
    $('lede').textContent = 'Responde un breve test y descubre si tus joyas de oro necesitan su día de spa.';
  }
  $('tk').textContent = (vip
    ? 'Tu invitación de Navidad\u2003✦\u2003descubre si tu oro necesita un spa\u2003✦\u2003sábado 21 de noviembre\u2003✦\u2003la vitrina más linda de la Navidad\u2003✦\u2003'
    : 'Navidad es para brillar\u2003✦\u2003descubre si tu oro necesita un spa\u2003✦\u2003todos los sábados hasta el 26 de diciembre\u2003✦\u2003oro 18k\u2003✦\u2003').repeat(4);

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
    'Los aretes que no te quitas desde la primera comunión… ¡tienen olor a tradición!',
    'Esa cadena opaca que se funde con el tono de tu piel porque ya perdió su brillo.',
    'Los anillos que todavía tienen jabón pegado desde el día del «sí».',
    'Los balines de esa manilla tejida que ya huelen a recuerdo.',
    'El broche flojo que te tiene rezando para no perder tu joya.'
  ];
  var on = {};

  function renderFlags() {
    $('flags').innerHTML = FL.map(function (t, i) {
      return '<button type="button" class="fl" style="--i:' + i + '" data-i="' + i + '" aria-pressed="' + (!!on[i]) + '">' +
        '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 21V4M5 4h12l-2.5 4L17 12H5"/></svg><span>' + U.esc(t) + '</span></button>';
    }).join('');
    Array.prototype.forEach.call($('flags').querySelectorAll('button'), function (b) {
      b.onclick = function () { var i = +b.dataset.i; if (on[i]) delete on[i]; else on[i] = 1; document.body.classList.add('tocado'); renderFlags(); };
    });
    var n = Object.keys(on).length;
    $('verdict').innerHTML = '<div class="n num">' + n + '<span> / ' + FL.length + '</span></div>' +
      '<div><div class="t">' + (n ? 'Tu oro pide auxilio.' : 'Marca lo que te pasa.') + '</div><p>' + (n ? 'Toca «Ver mi resultado» y te contamos qué tenemos para ti.' : 'Marca al menos una bandera para ver tu resultado.') + '</p></div>' +
      '<button type="button" class="btn gold shine go" id="goRes"' + (n ? '' : ' disabled') + '>Ver mi resultado</button>';
    $('goRes').onclick = terminar;
  }
  /* ----- resultado: la invitación (premium, sin costo) o la oferta (general, con valor) ----- */
  function revelar() {
    document.body.classList.add('done');
    var m = nombre ? 'Hola, soy ' + nombre + '. ' : 'Hola. ';
    $('premioH').innerHTML = (nombre ? U.esc(nombre) + ', tu oro pide ' : 'Tu oro pide ') + '<em>su día de brillo.</em>';
    var txt, boton, envio;
    if (vip) {
      txt = 'Hay clientes que ya son parte de la casa, y tú eres uno de ellos. El sábado 21 de noviembre queremos compartir un rato agradable contigo: trae hasta 3 de tus joyas favoritas y les devolvemos su brillo, sin ningún costo. Mientras tanto, disfrutas una Corona bien fría, cortesía de la casa.';
      boton = '¡Claro que sí, no me lo pierdo!';
      envio = m + '¡Claro que sí, no me lo pierdo! Voy el sábado 21 de noviembre y me gustaría venir hacia las [hora]. ¿Me apartan el cupo?';
    } else {
      txt = 'Tus joyas merecen volver a brillar como el primer día. Te esperamos este sábado: el shampoo de brillo para hasta 3 joyas de oro tiene un valor de ' + (P.shampoo || '$30.000') + '. Mientras tanto, disfrutas una Corona bien fría, cortesía de la casa.';
      boton = '¡Quiero que mi oro brille!';
      envio = m + 'Hice el test del spa dorado y quiero llevar mis joyas al shampoo de brillo. Me gustaría ir este sábado hacia las [hora]. ¿Me apartan el cupo?';
    }
    $('premioP').textContent = txt;
    $('waConfT').textContent = boton;
    if (C.contacto.whatsapp) $('waConf').href = U.waLink(C.contacto.whatsapp, envio);
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
    ['arreglo', 'Soldadura de cadenas en oro', 'Dejamos tu cadena entera otra vez.', '$40.000'],
    ['pulsera', 'Mantenimiento y tejido de pulseras', 'Renovamos tu pulsera o la tejemos a tu medida.', 'Desde $20.000'],
    ['oro', 'Valoramos tus joyas', 'Con el precio internacional del oro actualizado, para que conozcas el valor de tu inversión.', 'Sin compromiso'],
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
      ? 'Para ti, el shampoo de brillo de hasta 3 joyas de oro no tiene costo. Los demás servicios sí: soldadura de cadenas, $40.000; mantenimiento y tejido de pulseras, desde $20.000.'
      : 'El shampoo de brillo de hasta 3 joyas de oro tiene un valor de ' + (P.shampoo || '$30.000') + '. La soldadura de cadenas, $40.000; el mantenimiento y tejido de pulseras, desde $20.000. La Corona es cortesía de la casa (solo mayores de 18).'],
    ['¿Tengo que agendar?', 'Sí, te lo recomendamos: los cupos son limitados. Escríbenos por WhatsApp y una asesora te aparta la hora.'],
    ['¿Puedo ir con alguien?', vip ? 'Claro, puedes venir con alguien especial.' : 'Claro. La cerveza es solo para mayores de 18, con documento.'],
    ['¿Reciben mi oro como parte de pago?', 'Sí, al precio del día, para tu próxima joya.'],
    ['¿Qué días atienden?', vip
      ? 'Tu invitación es para el sábado 21 de noviembre, en jornada continua de 9:30 a. m. a 7:30 p. m.'
      : 'Todos los sábados hasta el 26 de diciembre, en jornada continua de 9:30 a. m. a 7:30 p. m.']
  ];
  $('faqList').innerHTML = faq.map(function (f) { return '<details class="faq"><summary>' + f[0] + '</summary><p>' + f[1] + '</p></details>'; }).join('');
})();
