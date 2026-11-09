/* Pestaña de asesoras: lista de clientes cargada, mensajes por paso (invitación, seguimiento, confirmación,
   recordatorio, gracias) con botón directo a WhatsApp, piezas para copiar y pegar, agenda con cupos y respuestas rápidas.
   La base viene de assets/clientes.js (fuera del repositorio). El avance de cada cliente se guarda en este navegador. */
(function () {
  var C = window.CORO, U = window.CoroUtil, S = U.S, esc = U.esc;
  var $ = function (id) { return document.getElementById(id); };

  /* ---------------- base de clientes ---------------- */
  function siNo(v) { return /^(s[ií]|x|1|true|premium|vip)$/i.test(String(v == null ? '' : v).trim()); }
  function titulo(s) { return String(s || '').toLowerCase().replace(/(^|\s)(\S)/g, function (m, a, b) { return a + b.toUpperCase(); }); }
  function normaliza(arr) {
    var vistos = {}, out = [];
    (arr || []).forEach(function (r) {
      var tel = U.normPhone(r.t || r.tel || r.celular || '');
      if (!tel.num || vistos[tel.num]) return;
      vistos[tel.num] = 1;
      out.push({ id: tel.num, nombre: titulo(r.n || r.nombre || 'Cliente'), tel: tel.num, ok: tel.ok, premium: r.premium === true || siNo(r.premium), asesora: String(r.asesora || '').trim() });
    });
    return out;
  }
  var local = S.get('base', null);
  var ORIGEN = local && local.length ? 'local' : (window.CORO_CLIENTES_EJEMPLO ? 'ejemplo' : 'archivo');
  var BASE = normaliza(local && local.length ? local : window.CORO_CLIENTES);

  /* seguimiento de cada cliente, por número */
  var SEG = S.get('seg', {}) || {};
  function seg(id) { if (!SEG[id]) SEG[id] = { estado: 'porinvitar', hist: [], cita: null, monto: 0, nota: '' }; return SEG[id]; }
  function guardar() { S.set('seg', SEG); }

  var ESTADOS = {
    porinvitar: 'Por invitar', invitado: 'Invitación enviada', seguimiento: 'Seguimiento enviado', interesado: 'Interesado',
    agendado: 'Agendado', recordado: 'Recordatorio enviado', llego: 'Llegó', compro: 'Compró', nointeresa: 'No le interesa', baja: 'No volver a escribir'
  };
  var AGENDADOS = ['agendado', 'recordado'];

  /* ---------------- mensajes ---------------- */
  var lanz = C.campana.lanzamiento;
  var PASOS = {
    invitacion: {
      nombre: 'Invitación', icono: '✉️',
      ayuda: 'Primer mensaje. Aparecen los clientes a los que aún no se les ha escrito.',
      cola: function (c, s) { return s.estado === 'porinvitar'; },
      despues: 'invitado', pieza: 'invitacion',
      premium: 'Hola {nombre} ✨ Soy {asesora}, de Joyería Tanya Santiago.\n\nTú eres de nuestros clientes más especiales y esta Navidad queremos consentirte: trae hasta 3 joyas de oro y te las dejamos brillando con un shampoo de brillo, *de regalo*. Mientras tanto disfrutas una Corona bien fría y conoces la vitrina más linda de la Navidad.\n\n📅 Desde el sábado 21 de noviembre, todos los sábados hasta el 26 de diciembre.{link}\n\n¿Te aparto un turno? Respóndeme con el día que te queda mejor.',
      general: 'Hola {nombre} ✨ Soy {asesora}, de Joyería Tanya Santiago.\n\nEsta Navidad llegan los *Sábados de Realeza*: dejamos tus joyas de oro como nuevas con un shampoo de brillo (hasta 3 joyas, desde $20.000), hacemos arreglos al momento y, mientras esperas, te atendemos con una Corona bien fría.\n\n📅 Desde el sábado 21 de noviembre, todos los sábados hasta el 26 de diciembre.{link}\n\n¿Te aparto un turno? Respóndeme con el día que te queda mejor.'
    },
    seguimiento: {
      nombre: 'Seguimiento', icono: '🔁',
      ayuda: 'Para quien no respondió. Primero salen los que llevan más días sin contestar.',
      cola: function (c, s) { return s.estado === 'invitado' || s.estado === 'seguimiento'; },
      despues: 'seguimiento', pieza: 'invitacion',
      premium: 'Hola {nombre}, soy {asesora} de Joyería Tanya Santiago 😊 Te escribo por si se te pasó la invitación: tu shampoo de brillo para hasta 3 joyas de oro es *de regalo* y los turnos de los sábados se están llenando.\n\n¿Qué día te aparto? Tengo espacio el {proximo}.',
      general: 'Hola {nombre}, soy {asesora} de Joyería Tanya Santiago 😊 Te escribo por si se te pasó el mensaje: los Sábados de Realeza ya empiezan y los turnos se están llenando. Shampoo de brillo desde $20.000 y una Corona bien fría mientras esperas.\n\n¿Qué día te aparto? Tengo espacio el {proximo}.'
    },
    confirmar: {
      nombre: 'Confirmar turno', icono: '📅',
      ayuda: 'Cuando el cliente dice que sí: primero agéndalo con el botón "Agendar" y luego envía la confirmación.',
      cola: function (c, s) { return s.estado === 'interesado' || (s.estado === 'agendado' && !enviado(s, 'confirmar')); },
      despues: null, pieza: 'turno',
      premium: '¡Listo, {nombre}! 👑 Tu turno quedó para el *{dia}* a las *{hora}*.\n\nTrae hasta 3 joyas de oro: el shampoo de brillo es de regalo. Te esperamos con una Corona bien fría.\n\n📍 {direccion}\n\nSi necesitas cambiar la hora, respóndeme por aquí. {asesora}',
      general: '¡Listo, {nombre}! 👑 Tu turno quedó para el *{dia}* a las *{hora}*.\n\nTrae tus joyas de oro (el shampoo de brillo es desde $20.000 por hasta 3 joyas). Te esperamos con una Corona bien fría.\n\n📍 {direccion}\n\nSi necesitas cambiar la hora, respóndeme por aquí. {asesora}'
    },
    recordatorio: {
      nombre: 'Recordatorio', icono: '⏰',
      ayuda: 'Un día antes del turno. Primero salen los turnos de mañana.',
      cola: function (c, s) { return s.estado === 'agendado' && s.cita && s.cita.f >= U.today(); },
      despues: 'recordado', pieza: 'turno',
      premium: 'Hola {nombre} ✨ Te recuerdo que mañana, *{dia}*, a las *{hora}*, te esperamos en Joyería Tanya Santiago para tu shampoo de brillo de regalo. Trae hasta 3 joyas de oro.\n\n📍 {direccion}\n\n¿Me confirmas que vienes? {asesora}',
      general: 'Hola {nombre} ✨ Te recuerdo que mañana, *{dia}*, a las *{hora}*, te esperamos en Joyería Tanya Santiago. Trae tus joyas de oro para el shampoo de brillo.\n\n📍 {direccion}\n\n¿Me confirmas que vienes? {asesora}'
    },
    gracias: {
      nombre: 'Gracias', icono: '💛',
      ayuda: 'Después de la visita. Aparecen los que llegaron.',
      cola: function (c, s) { return (s.estado === 'llego' || s.estado === 'compro') && !enviado(s, 'gracias'); },
      despues: null, pieza: 'gracias',
      premium: 'Gracias por venir, {nombre} 💛 Fue un gusto consentir tu oro. Tu oro, tu corona 👑\n\nAquí estamos para lo que necesites esta Navidad. {asesora}, Joyería Tanya Santiago',
      general: 'Gracias por venir, {nombre} 💛 Fue un gusto dejar tus joyas brillando. Tu oro, tu corona 👑\n\nAquí estamos para lo que necesites esta Navidad. {asesora}, Joyería Tanya Santiago'
    }
  };
  var ORDEN = ['invitacion', 'seguimiento', 'confirmar', 'recordatorio', 'gracias'];
  function enviado(s, paso) { return s.hist.some(function (h) { return h[0] === paso; }); }
  function ultimo(s) { return s.hist.length ? s.hist[s.hist.length - 1] : null; }
  function diasDesde(iso) { return iso ? -U.daysUntil(iso.slice(0, 10)) : 0; }

  function textoPaso(paso, tipo) {
    var o = S.get('tpl2', {}) || {};
    return o[paso + '.' + tipo] != null ? o[paso + '.' + tipo] : PASOS[paso][tipo];
  }
  function primerNombre(n) { return String(n || '').trim().split(/\s+/)[0] || ''; }
  function horaBonita(h) { if (!h) return '[hora]'; var p = h.split(':'), H = +p[0]; return (H > 12 ? H - 12 : H) + ':' + p[1] + (H >= 12 ? ' p. m.' : ' a. m.'); }
  function horaCorta(h) { var p = h.split(':'), H = +p[0]; return (H > 12 ? H - 12 : H) + ':' + p[1] + (H >= 12 ? ' pm' : ' am'); }
  function proximasFechas(c) { var t = U.today(); return C.fechas.filter(function (x) { return x.f >= t && x.tipo !== 'ensayo' && (x.publico || c.premium); }); }
  function mensaje(paso, c) {
    var s = seg(c.id), fs = proximasFechas(c);
    var link = C.baseUrl ? '\n\nTu invitación: ' + C.baseUrl.replace(/\/$/, '') + '/?n=' + encodeURIComponent(primerNombre(c.nombre)) + (c.premium ? '&p=1' : '') : '';
    var dir = /\[/.test(C.contacto.direccion) ? '[dirección de la joyería]' : C.contacto.direccion;
    return textoPaso(paso, c.premium ? 'premium' : 'general')
      .replace(/\{nombre\}/g, primerNombre(c.nombre))
      .replace(/\{asesora\}/g, ($('aseNombre').value || '').trim() || 'tu asesora')
      .replace(/\{link\}/g, link)
      .replace(/\{dia\}/g, s.cita ? U.fmtDate(s.cita.f, true) : '[día]')
      .replace(/\{hora\}/g, s.cita ? horaBonita(s.cita.h) : '[hora]')
      .replace(/\{proximo\}/g, fs.length ? fs.slice(0, 2).map(function (x) { return U.fmtDate(x.f, true); }).join(' o el ') : 'próximo sábado')
      .replace(/\{direccion\}/g, dir);
  }

  /* ---------------- piezas (imágenes para pegar en el chat) ---------------- */
  function rr(g, x, y, w, h, r) { g.beginPath(); g.moveTo(x + r, y); g.arcTo(x + w, y, x + w, y + h, r); g.arcTo(x + w, y + h, x, y + h, r); g.arcTo(x, y + h, x, y, r); g.arcTo(x, y, x + w, y, r); g.closePath(); }
  function fitText(g, t, max, size, pre, fam) { var f = function () { g.font = (pre ? pre + ' ' : '') + size + 'px ' + fam; }; f(); while (g.measureText(t).width > max && size > 30) { size -= 4; f(); } }
  function pieza(cv, o) {
    var g = cv.getContext('2d'), W = cv.width, H = cv.height, serif = '"Instrument Serif", Georgia, serif', sans = '"Hanken Grotesk", system-ui, sans-serif';
    var grad = g.createLinearGradient(0, 0, W, H); grad.addColorStop(0, '#24451F'); grad.addColorStop(1, '#0F2412');
    g.fillStyle = grad; g.fillRect(0, 0, W, H);
    var glow = g.createRadialGradient(W * .85, 0, 10, W * .85, 0, W * .8); glow.addColorStop(0, 'rgba(201,164,74,.45)'); glow.addColorStop(1, 'rgba(201,164,74,0)');
    g.fillStyle = glow; g.fillRect(0, 0, W, H);
    var seed = 11; function rnd() { seed = (seed * 9301 + 49297) % 233280; return seed / 233280; }
    for (var i = 0; i < 80; i++) { g.fillStyle = 'rgba(255,255,255,' + (0.12 + rnd() * 0.45).toFixed(2) + ')'; g.beginPath(); g.arc(rnd() * W, rnd() * H, 2 + rnd() * 5, 0, 7); g.fill(); }
    g.strokeStyle = '#C9A44A'; g.lineWidth = 4; rr(g, 44, 44, W - 88, H - 88, 36); g.stroke();
    g.textAlign = 'center';
    g.fillStyle = '#C9A44A'; g.font = '700 30px ' + sans; if ('letterSpacing' in g) g.letterSpacing = '8px';
    g.fillText(o.kicker, W / 2 + 4, 160); if ('letterSpacing' in g) g.letterSpacing = '0px';
    g.fillStyle = '#F7F2E8'; fitText(g, o.titulo, W - 200, 150, '', serif); g.fillText(o.titulo, W / 2, 360);
    g.fillStyle = '#E2C878'; fitText(g, o.sub, W - 200, 96, 'italic', serif); g.fillText(o.sub, W / 2, 470);
    if (o.destacado) {
      g.fillStyle = 'rgba(247,242,232,.1)'; rr(g, 140, 540, W - 280, 150, 30); g.fill();
      g.strokeStyle = 'rgba(201,164,74,.7)'; g.lineWidth = 2; rr(g, 140, 540, W - 280, 150, 30); g.stroke();
      g.fillStyle = '#F7F2E8'; g.font = '800 46px ' + sans; g.fillText(o.destacado[0], W / 2, 605);
      g.fillStyle = '#D9E3D6'; g.font = '500 34px ' + sans; g.fillText(o.destacado[1], W / 2, 660);
    }
    g.font = '500 38px ' + sans; g.fillStyle = '#D9E3D6';
    o.lineas.forEach(function (t, i) { g.fillText(t, W / 2, 800 + i * 66); });
    g.fillStyle = '#C9A44A'; rr(g, 150, 1110, W - 300, 100, 50); g.fill();
    g.fillStyle = '#2A1D00'; fitText(g, o.boton, W - 360, 40, '800', sans); g.fillText(o.boton, W / 2, 1174);
    g.fillStyle = '#B3261E'; g.beginPath(); g.moveTo(W - 230, 44); g.lineTo(W - 150, 44); g.lineTo(W - 150, 240); g.lineTo(W - 190, 206); g.lineTo(W - 230, 240); g.closePath(); g.fill();
  }
  function datosPieza(tipo, c) {
    var nom = c ? primerNombre(c.nombre) : '', s = c ? seg(c.id) : null, prem = c ? c.premium : false;
    var fechaLanz = U.fmtDate(lanz, true);
    if (tipo === 'invitacion' && prem) return { kicker: 'INVITACIÓN ESPECIAL', titulo: (nom || 'Para ti') + ',', sub: 'esta Navidad brillas tú', destacado: ['Shampoo de brillo DE REGALO', 'para hasta 3 joyas de oro'], lineas: ['Una Corona bien fría mientras esperas', 'La vitrina más linda de la Navidad', 'Desde el ' + fechaLanz], boton: 'Responde y te apartamos tu turno' };
    if (tipo === 'invitacion') return { kicker: 'SÁBADOS DE REALEZA', titulo: 'Navidad es para brillar', sub: 'tu oro, tu corona', destacado: ['Shampoo de brillo desde $20.000', 'hasta 3 joyas de oro'], lineas: ['Arreglos al momento desde $30.000', 'Una Corona bien fría mientras esperas', 'Todos los sábados desde el ' + fechaLanz], boton: 'Agenda tu turno por WhatsApp' };
    if (tipo === 'turno') return { kicker: 'TU TURNO ESTÁ LISTO', titulo: (nom || 'Te esperamos') + (nom ? ',' : ''), sub: 'te esperamos', destacado: s && s.cita ? [U.fmtDate(s.cita.f, true), horaBonita(s.cita.h)] : ['Sábado de Realeza', 'jornada continua'], lineas: [prem ? 'Shampoo de brillo de regalo' : 'Shampoo de brillo desde $20.000', 'Trae hasta 3 joyas de oro', 'Una Corona bien fría te espera'], boton: 'Joyería Tanya Santiago' };
    return { kicker: 'GRACIAS POR VENIR', titulo: nom ? 'Gracias, ' + nom : 'Gracias', sub: 'tu oro, tu corona', destacado: null, lineas: ['Fue un gusto consentir tu oro', 'Aquí estamos para lo que necesites', 'esta Navidad'], boton: 'Joyería Tanya Santiago' };
  }
  function lienzo(tipo, c) {
    var cv = document.createElement('canvas'); cv.width = 1080; cv.height = 1350;
    pieza(cv, datosPieza(tipo, c)); return cv;
  }
  function listoFuentes() { return document.fonts && document.fonts.ready ? document.fonts.ready : Promise.resolve(); }
  function copiarImagen(cvPromesa, nombreArchivo, btn) {
    var fin = function (t) { if (!btn) return; var o = btn.getAttribute('data-txt') || btn.textContent; btn.setAttribute('data-txt', o); btn.textContent = t; setTimeout(function () { btn.textContent = o; }, 1800); };
    var blobP = cvPromesa.then(function (cv) { return new Promise(function (r) { cv.toBlob(r, 'image/png'); }); });
    try {
      if (!navigator.clipboard || !window.ClipboardItem) throw new Error('sin portapapeles');
      navigator.clipboard.write([new ClipboardItem({ 'image/png': blobP })]).then(function () { fin('Imagen copiada ✓ pégala en el chat'); }, function () {
        blobP.then(function (b) { U.download(nombreArchivo, 'image/png', b); fin('Descargada ✓ adjúntala'); });
      });
    } catch (e) { blobP.then(function (b) { U.download(nombreArchivo, 'image/png', b); fin('Descargada ✓ adjúntala'); }); }
  }

  /* ---------------- interfaz ---------------- */
  var paso = S.get('paso', 'invitacion') || 'invitacion';
  if (!PASOS[paso]) paso = 'invitacion';
  $('aseNombre').value = S.get('asesora', '') || '';
  var asesorasBase = BASE.map(function (c) { return c.asesora; }).filter(function (a, i, arr) { return a && arr.indexOf(a) === i; });
  $('aseMias').parentNode.hidden = !asesorasBase.length;

  function aviso() {
    var a = $('aseBase');
    if (ORIGEN === 'ejemplo') { a.hidden = false; a.className = 'warn-box'; a.innerHTML = '<b>Lista de ejemplo.</b> Los nombres y números son inventados para que veas cómo funciona. Cuando se cargue la base real de la joyería, aparecerá aquí sola.'; }
    else if (!BASE.length) { a.hidden = false; a.className = 'warn-box'; a.innerHTML = '<b>No hay clientes cargados.</b> La propietaria carga la base en la pestaña Propietaria.'; }
    else a.hidden = true;
  }

  function cuenta(p) { return BASE.filter(function (c) { var s = seg(c.id); return s.estado !== 'baja' && s.estado !== 'nointeresa' && PASOS[p].cola(c, s); }).length; }

  function renderPasos() {
    $('pasos').innerHTML = ORDEN.map(function (k) {
      var n = cuenta(k);
      return '<button type="button" role="tab" aria-selected="' + (k === paso) + '" data-paso="' + k + '"><span class="ic">' + PASOS[k].icono + '</span><b>' + PASOS[k].nombre + '</b><em class="num">' + n + '</em></button>';
    }).join('');
    $('pasoAyuda').textContent = PASOS[paso].ayuda;
    $('msgPrem').textContent = mensaje(paso, { id: '_demo', nombre: 'Carlos Pérez', premium: true });
    $('msgGen').textContent = mensaje(paso, { id: '_demo2', nombre: 'Carlos Pérez', premium: false });
    $('tplEdP').value = textoPaso(paso, 'premium'); $('tplEdG').value = textoPaso(paso, 'general');
    delete SEG._demo; delete SEG._demo2;
  }

  function kpis() {
    var hoy = U.today(), n = function (f) { return BASE.filter(function (c) { return f(seg(c.id)); }).length; };
    var hoyInv = n(function (s) { return s.hist.some(function (h) { return h[0] === 'invitacion' && h[1].slice(0, 10) === hoy; }); });
    var pf = proximasFechas({ premium: true }), prox = pf.filter(function (x) { return x.f >= lanz; })[0] || pf[0];
    $('aseKpis').innerHTML = [
      ['Clientes', BASE.length, BASE.filter(function (c) { return c.premium; }).length + ' premium'],
      ['Invitaciones hoy', hoyInv, 'de ' + n(function (s) { return s.estado === 'porinvitar'; }) + ' por invitar'],
      ['Esperando respuesta', n(function (s) { return s.estado === 'invitado' || s.estado === 'seguimiento'; }), ''],
      ['Agendados', n(function (s) { return AGENDADOS.indexOf(s.estado) >= 0; }), ''],
      ['Turnos ' + (prox ? U.fmtDate(prox.f) : ''), prox ? n(function (s) { return s.cita && s.cita.f === prox.f && AGENDADOS.indexOf(s.estado) >= 0; }) : 0, 'de ' + cupoDia() + ' cupos']
    ].map(function (k) { return '<div class="kpi"><small>' + esc(k[0]) + '</small><b class="num">' + k[1] + '</b><em>' + esc(k[2]) + '</em></div>'; }).join('');
  }

  function estadoTexto(c, s) {
    var u = ultimo(s), t = ESTADOS[s.estado];
    if (s.cita && AGENDADOS.indexOf(s.estado) >= 0) t += ' · ' + U.fmtDate(s.cita.f) + ' ' + horaBonita(s.cita.h);
    if (u) { var d = diasDesde(u[1]); t += ' · último mensaje ' + (d === 0 ? 'hoy' : d === 1 ? 'ayer' : 'hace ' + d + ' días'); }
    return t;
  }
  function prioridad(c, s) {
    if (paso === 'seguimiento') { var u = ultimo(s); return u ? -diasDesde(u[1]) : 0; }
    if (paso === 'recordatorio' || paso === 'confirmar') return s.cita ? s.cita.f + s.cita.h : 'z';
    return (c.premium ? '0' : '1') + c.nombre;
  }

  function renderLista() {
    var bq = $('aseBusq').value.trim().toLowerCase(), tipo = $('aseTipo').value, todos = $('aseTodos').checked;
    var mias = $('aseMias').checked && ($('aseNombre').value || '').trim();
    var lista = BASE.filter(function (c) {
      var s = seg(c.id);
      if (!todos && (s.estado === 'baja' || s.estado === 'nointeresa' || !PASOS[paso].cola(c, s))) return false;
      if (tipo === 'p' && !c.premium) return false;
      if (tipo === 'g' && c.premium) return false;
      if (mias && c.asesora && c.asesora.toLowerCase() !== mias.toLowerCase()) return false;
      if (bq && c.nombre.toLowerCase().indexOf(bq) < 0 && c.tel.indexOf(bq.replace(/\D/g, '') || '§') < 0) return false;
      return true;
    });
    lista.sort(function (a, b) { var x = prioridad(a, seg(a.id)), y = prioridad(b, seg(b.id)); return x < y ? -1 : x > y ? 1 : 0; });
    $('aseConteo').textContent = lista.length + (lista.length === 1 ? ' cliente' : ' clientes') + (todos ? ' en total' : ' para ' + PASOS[paso].nombre.toLowerCase());
    if (!lista.length) { $('aseLista').innerHTML = '<p class="vacio">' + (todos ? 'Nadie con ese filtro.' : 'Nadie pendiente en este paso. ¡Buen trabajo!') + '</p>'; return; }
    var MAX = 120;
    $('aseLista').innerHTML = lista.slice(0, MAX).map(function (c) {
      var s = seg(c.id), bloqueado = s.estado === 'baja' || !c.ok;
      var faltaCita = (paso === 'confirmar' || paso === 'recordatorio') && !s.cita;
      var chips = [];
      if (['porinvitar', 'invitado', 'seguimiento', 'interesado', 'nointeresa'].indexOf(s.estado) >= 0) chips.push(['agendar', '📅 Agendar']);
      if (AGENDADOS.indexOf(s.estado) >= 0) { chips.push(['agendar', 'Cambiar turno'], ['llego', '✅ Llegó']); }
      if (s.estado === 'llego') chips.push(['compro', '💰 Compró']);
      if (['invitado', 'seguimiento'].indexOf(s.estado) >= 0) chips.push(['interesado', '🙂 Respondió']);
      if (['porinvitar', 'invitado', 'seguimiento', 'interesado'].indexOf(s.estado) >= 0) chips.push(['nointeresa', 'No le interesa']);
      if (s.estado !== 'baja') chips.push(['baja', 'No escribir más']); else chips.push(['reactivar', 'Volver a activar']);
      return '<article class="cl' + (c.premium ? ' prem' : '') + (bloqueado ? ' off' : '') + '" data-id="' + c.id + '">' +
        '<div class="cl-h"><div><h4>' + esc(c.nombre) + '</h4><span class="tel num">' + esc(fmtTel(c.tel)) + '</span>' + (c.ok ? '' : ' <span class="pill bad">revisar número</span>') + '</div>' +
        (c.premium ? '<span class="tag gold">👑 Premium · shampoo de regalo</span>' : '<span class="tag">General · desde $20.000</span>') + '</div>' +
        '<p class="cl-s">' + esc(estadoTexto(c, s)) + (c.asesora ? ' · ' + esc(c.asesora) : '') + (s.nota ? ' · ' + esc(s.nota) : '') + '</p>' +
        '<div class="cl-a">' +
        (faltaCita ? '<button class="btn fill" data-a="agendar">📅 Primero agenda el turno</button>'
          : '<a class="btn wa" data-a="wa" href="' + (bloqueado ? '#' : esc(U.waLink(c.tel, mensaje(paso, c)))) + '" target="_blank" rel="noopener"' + (bloqueado ? ' aria-disabled="true"' : '') + '>' + waIco + ' ' + esc(PASOS[paso].nombre) + '</a>') +
        '<button class="btn line" data-a="img" title="Copiar imagen para pegar en el chat">🖼️ <span class="lg">Copiar imagen</span><span class="sm">Imagen</span></button></div>' +
        '<div class="cl-c">' + chips.map(function (x) { return '<button type="button" data-a="' + x[0] + '">' + x[1] + '</button>'; }).join('') + '</div></article>';
    }).join('') + (lista.length > MAX ? '<p class="vacio">Mostrando ' + MAX + ' de ' + lista.length + '. Usa el buscador para encontrar a alguien.</p>' : '');
  }
  var waIco = '<svg viewBox="0 0 24 24" aria-hidden="true"><path fill="currentColor" d="M12 2a10 10 0 0 0-8.6 15.1L2 22l5-1.3A10 10 0 1 0 12 2zm0 18.2a8.2 8.2 0 0 1-4.2-1.2l-.3-.2-3 .8.8-2.9-.2-.3A8.2 8.2 0 1 1 12 20.2zm4.5-6.1c-.2-.1-1.5-.7-1.7-.8s-.4-.1-.6.1-.7.8-.8 1-.3.2-.5.1a6.7 6.7 0 0 1-3.3-2.9c-.3-.4.3-.4.7-1.3.1-.2 0-.3 0-.4l-.8-1.8c-.2-.5-.4-.4-.6-.4h-.5a1 1 0 0 0-.7.3 3 3 0 0 0-.9 2.2 5.2 5.2 0 0 0 1.1 2.7 11.8 11.8 0 0 0 4.5 4c1.7.7 2.3.8 3.2.6a2.7 2.7 0 0 0 1.8-1.3 2.2 2.2 0 0 0 .2-1.3c-.1-.1-.3-.2-.6-.3z"/></svg>';
  function fmtTel(t) { var d = t.replace(/^57/, ''); return d.length === 10 ? d.slice(0, 3) + ' ' + d.slice(3, 6) + ' ' + d.slice(6) : t; }

  function render() { renderPasos(); kpis(); renderLista(); renderAgenda(); }
  function porId(id) { return BASE.filter(function (c) { return c.id === id; })[0]; }

  $('pasos').addEventListener('click', function (e) {
    var b = e.target.closest('button[data-paso]'); if (!b) return;
    paso = b.dataset.paso; S.set('paso', paso); render();
  });
  ['aseBusq', 'aseTipo', 'aseTodos', 'aseMias'].forEach(function (id) { $(id).addEventListener(id === 'aseBusq' ? 'input' : 'change', renderLista); });
  $('aseNombre').addEventListener('input', function () { S.set('asesora', this.value); renderPasos(); renderLista(); });

  $('aseLista').addEventListener('click', function (e) {
    var b = e.target.closest('[data-a]'); if (!b) return;
    var c = porId(b.closest('.cl').dataset.id); if (!c) return;
    var s = seg(c.id), a = b.dataset.a;
    if (a === 'wa') {
      if (b.getAttribute('aria-disabled')) { e.preventDefault(); return; }
      if (!($('aseNombre').value || '').trim()) { e.preventDefault(); $('aseNombre').focus(); $('aseNombre').classList.add('pide'); setTimeout(function () { $('aseNombre').classList.remove('pide'); }, 1600); return; }
      s.hist.push([paso, new Date().toISOString()]);
      if (PASOS[paso].despues && !(paso === 'seguimiento' && s.estado !== 'invitado' && s.estado !== 'seguimiento')) s.estado = PASOS[paso].despues;
      guardar(); setTimeout(render, 400);
      return;
    }
    if (a === 'img') { copiarImagen(listoFuentes().then(function () { return lienzo(PASOS[paso].pieza, c); }), PASOS[paso].pieza + '-' + primerNombre(c.nombre).toLowerCase() + '.png', b); return; }
    if (a === 'agendar') { agendar(c); return; }
    if (a === 'compro') { var m = prompt('¿Cuánto compró ' + primerNombre(c.nombre) + '? (solo números)', s.monto || ''); if (m === null) return; s.monto = +String(m).replace(/\D/g, '') || 0; s.estado = 'compro'; }
    else if (a === 'reactivar') { s.estado = s.hist.length ? 'invitado' : 'porinvitar'; }
    else if (a === 'nointeresa' || a === 'baja') { var nota = prompt(a === 'baja' ? '¿Pidió no recibir más mensajes? Puedes anotar el motivo (opcional):' : '¿Por qué no le interesa? (opcional, nos ayuda a mejorar)', ''); if (nota === null) return; s.estado = a; if (nota) s.nota = nota; }
    else s.estado = a;
    guardar(); render();
  });

  /* ---------------- agenda con cupos ---------------- */
  function cupoDia() { return U.slots().length * (C.agenda.cuposPorBloque || 1); }
  function ocupados(f, h, excepto) {
    return BASE.filter(function (c) { var s = seg(c.id); return c.id !== excepto && s.cita && s.cita.f === f && (!h || s.cita.h === h) && AGENDADOS.indexOf(s.estado) >= 0; }).length;
  }
  function agendar(c) {
    var d = $('dlg'), body = $('dlgBody'), s = seg(c.id), fs = proximasFechas(c);
    var def = fs.filter(function (x) { return x.f >= lanz; })[0] || fs[0];
    var sel = { f: s.cita ? s.cita.f : (def && def.f), h: s.cita ? s.cita.h : '' };
    var cupo = C.agenda.cuposPorBloque || 1;
    function pinta() {
      body.innerHTML = '<h3>Turno para ' + esc(primerNombre(c.nombre)) + '</h3>' +
        '<p class="note">' + (c.premium ? '👑 Premium: shampoo de regalo.' : 'General: shampoo desde $20.000.') + ' Cupo: ' + cupo + ' personas cada ' + C.agenda.bloqueMin + ' min.</p>' +
        '<div class="ag-d">' + fs.map(function (x) { var oc = ocupados(x.f, '', c.id), tot = cupoDia(); return '<button type="button" data-f="' + x.f + '" aria-pressed="' + (x.f === sel.f) + '"><b>' + esc(U.fmtDate(x.f)) + '</b><small>' + (tot - oc) + ' libres</small></button>'; }).join('') + '</div>' +
        '<div class="ag-h">' + U.slots().map(function (h) { var oc = ocupados(sel.f, h, c.id), lleno = oc >= cupo; return '<button type="button" data-h="' + h + '" aria-pressed="' + (h === sel.h) + '"' + (lleno ? ' disabled' : '') + '>' + esc(horaCorta(h)) + '<small>' + (lleno ? 'lleno' : (cupo - oc) + ' libre' + (cupo - oc > 1 ? 's' : '')) + '</small></button>'; }).join('') + '</div>' +
        '<label style="margin-top:10px">Nota (opcional)<input id="agNota" value="' + esc(s.nota || '') + '" placeholder="Ej. trae 2 cadenas y una argolla"></label>' +
        '<div class="actions" style="margin-top:12px"><button class="btn fill" id="agOk"' + (sel.f && sel.h ? '' : ' disabled') + '>Guardar turno</button>' +
        (s.cita ? '<button class="btn line small" id="agQuitar">Quitar turno</button>' : '') + '<button class="btn line small" id="agX">Cancelar</button></div>';
    }
    pinta();
    body.onclick = function (e) {
      var b = e.target.closest('button'); if (!b) return;
      if (b.dataset.f) { sel.f = b.dataset.f; sel.h = ''; pinta(); }
      else if (b.dataset.h) { sel.h = b.dataset.h; var n = $('agNota').value; pinta(); $('agNota').value = n; }
      else if (b.id === 'agX') d.close();
      else if (b.id === 'agQuitar') { s.cita = null; s.estado = 'interesado'; guardar(); d.close(); render(); }
      else if (b.id === 'agOk') {
        s.cita = { f: sel.f, h: sel.h }; s.estado = 'agendado'; s.nota = $('agNota').value.trim();
        s.hist = s.hist.filter(function (h) { return h[0] !== 'confirmar'; });
        guardar();
        body.innerHTML = '<h3>Turno guardado ✓</h3><p>' + esc(primerNombre(c.nombre)) + ': <b>' + esc(U.fmtDate(sel.f, true)) + '</b> a las <b>' + esc(horaBonita(sel.h)) + '</b>.</p>' +
          '<div class="actions" style="margin-top:12px"><a class="btn wa" id="agWa" target="_blank" rel="noopener" href="' + esc(U.waLink(c.tel, mensaje('confirmar', c))) + '">' + waIco + ' Enviar confirmación</a><button class="btn line small" id="agX">Listo</button></div>';
        $('agWa').onclick = function () { s.hist.push(['confirmar', new Date().toISOString()]); guardar(); setTimeout(function () { d.close(); render(); }, 300); };
        render();
      }
    };
    if (d.showModal) d.showModal(); else d.setAttribute('open', '');
  }

  /* agenda del día para las asesoras */
  function renderAgenda() {
    var fs = proximasFechas({ premium: true });
    var f = $('agDia').value || ((fs.filter(function (x) { return x.f >= lanz; })[0] || fs[0] || {}).f);
    $('agDia').innerHTML = fs.map(function (x) { return '<option value="' + x.f + '"' + (x.f === f ? ' selected' : '') + '>' + esc(U.fmtDate(x.f, true)) + ' · ' + ocupados(x.f) + ' turnos</option>'; }).join('');
    var cupo = C.agenda.cuposPorBloque || 1;
    $('agTabla').innerHTML = U.slots().map(function (h) {
      var gente = BASE.filter(function (c) { var s = seg(c.id); return s.cita && s.cita.f === f && s.cita.h === h && AGENDADOS.indexOf(s.estado) >= 0; });
      return '<div class="ag-r' + (gente.length >= cupo ? ' lleno' : '') + '"><b class="num">' + esc(horaBonita(h)) + '</b><span>' + (gente.length ? gente.map(function (c) { return esc(c.nombre) + (c.premium ? ' 👑' : ''); }).join(' · ') : '<span class="note">libre</span>') + '</span><em>' + gente.length + '/' + cupo + '</em></div>';
    }).join('');
  }
  $('agDia').addEventListener('change', renderAgenda);

  /* ---------------- piezas fijas ---------------- */
  var FIJAS = [
    ['invitacion-premium', 'Invitación premium (con el nombre del cliente)', 'Se genera sola desde el botón "Copiar imagen" de cada cliente premium.', function () { return lienzo('invitacion', { id: '_x', nombre: 'Carlos', premium: true }); }],
    ['flyer-general', 'Flyer general · Sábados de Realeza', 'Para clientes generales, estados y grupos.', function () { return lienzo('invitacion', null); }],
    ['turno', 'Tu turno está listo', 'Acompaña la confirmación y el recordatorio.', function () { return lienzo('turno', null); }],
    ['gracias', 'Gracias · tu oro, tu corona', 'Después de la visita.', function () { return lienzo('gracias', null); }]
  ];
  function renderPiezas() {
    var finales = (C.piezasFinales || []).map(function (p) { return '<figure class="pz"><img src="' + esc(p.archivo) + '" alt="' + esc(p.titulo) + '" loading="lazy"><figcaption><b>' + esc(p.titulo) + '</b><span>' + esc(p.uso || '') + '</span></figcaption><div class="actions"><button class="btn fill small" data-img="' + esc(p.archivo) + '">Copiar imagen</button><a class="btn line small" href="' + esc(p.archivo) + '" download>Descargar</a></div></figure>'; }).join('');
    $('piezasAse').innerHTML = finales + FIJAS.map(function (p, i) {
      return '<figure class="pz"><canvas width="1080" height="1350" data-pz="' + i + '"></canvas><figcaption><b>' + esc(p[1]) + '</b><span>' + esc(p[2]) + '</span></figcaption><div class="actions"><button class="btn fill small" data-cp="' + i + '">Copiar imagen</button><button class="btn line small" data-dl="' + i + '">Descargar</button></div></figure>';
    }).join('');
    listoFuentes().then(function () {
      Array.prototype.forEach.call($('piezasAse').querySelectorAll('canvas[data-pz]'), function (cv) { var src = FIJAS[+cv.dataset.pz][3](); cv.getContext('2d').drawImage(src, 0, 0); });
    });
    delete SEG._x;
  }
  $('piezasAse').addEventListener('click', function (e) {
    var b = e.target.closest('button'); if (!b) return;
    if (b.dataset.cp != null) copiarImagen(listoFuentes().then(function () { return FIJAS[+b.dataset.cp][3](); }), FIJAS[+b.dataset.cp][0] + '.png', b);
    if (b.dataset.dl != null) FIJAS[+b.dataset.dl][3]().toBlob(function (bl) { U.download(FIJAS[+b.dataset.dl][0] + '.png', 'image/png', bl); });
    if (b.dataset.img) {
      var img = b.closest('figure').querySelector('img');
      copiarImagen(Promise.resolve().then(function () { var cv = document.createElement('canvas'); cv.width = img.naturalWidth; cv.height = img.naturalHeight; cv.getContext('2d').drawImage(img, 0, 0); return cv; }), b.dataset.img.split('/').pop().replace(/\.\w+$/, '.png'), b);
    }
  });

  /* ---------------- respuestas rápidas ---------------- */
  var dirTxt = /\[/.test(C.contacto.direccion) ? '[DIRECCIÓN]' : C.contacto.direccion;
  var horTxt = /\[/.test(C.contacto.horario) ? '[HORARIO]' : C.contacto.horario;
  var RESP = [
    ['¿Cuánto cuesta?', 'Si recibiste la invitación especial, el shampoo de brillo para hasta 3 joyas de oro es de regalo 🎁. Para los demás clientes es desde $20.000 por hasta 3 joyas. Los arreglos son desde $30.000 y siempre te decimos el valor antes de hacer cualquier cosa.'],
    ['¿Qué es el shampoo de brillo?', 'Es una limpieza profunda para tus joyas de oro: les quitamos la suciedad del día a día (perfume, crema, sudor) y les devolvemos el brillo. Y de paso revisamos broches y piedras para que no se te pierda nada.'],
    ['¿Cuánto se demora?', 'Unos [CONFIRMAR: 20 a 30] minutos. Mientras tanto te atendemos con una Corona bien fría y puedes ver la vitrina de Navidad.'],
    ['¿Qué días y a qué hora?', 'Todos los sábados desde el 21 de noviembre hasta el 26 de diciembre, de corrido (' + horTxt + '). En diciembre también hay domingos con cita. ¿Qué día te aparto?'],
    ['¿Dónde quedan?', 'Estamos en ' + dirTxt + ', Barrancabermeja. Cuando llegues, di tu nombre y te atendemos de una.'],
    ['¿Tengo que agendar?', 'Te recomiendo agendar para que no tengas que esperar: tenemos pocos puestos por hora. Dime qué día y a qué hora te queda mejor y te lo aparto.'],
    ['¿Puedo llevar más de 3 joyas?', 'Claro que sí. Las 3 primeras van con el servicio y las adicionales tienen un valor de [CONFIRMAR] cada una. Igual te decimos antes de empezar.'],
    ['¿Solo joyas de oro?', 'El shampoo de brillo es para joyas de oro. Si tienes otra pieza, tráela y la revisamos: te decimos qué se le puede hacer.'],
    ['¿Puedo ir con alguien?', '¡Claro! Ven con quien quieras. La Corona es solo para mayores de 18 (con documento); también tenemos bebidas sin alcohol.'],
    ['¿Se me puede dañar la joya?', 'Tranquila, antes de empezar revisamos cada pieza contigo. Si vemos algo delicado (una piedra floja, un broche gastado) te lo mostramos y tú decides.'],
    ['Arreglos y pulsera tejida', 'Hacemos arreglos al momento (soldadura, broches, piedras flojas) desde $30.000, y pulseras tejidas a tu medida desde $30.000: escoges el hilo y el dije de oro.'],
    ['"Después te digo"', '¡Perfecto! Te cuento que los turnos de los sábados se están llenando. ¿Te parece si te aparto uno provisional el {dia} y si no puedes me avisas y lo cambiamos?'],
    ['"No puedo el sábado"', 'No te preocupes. En diciembre también abrimos domingos con cita (6, 13, 20 y 27). ¿Alguno de esos te sirve?'],
    ['Pidió no recibir más mensajes', 'Entendido, {nombre}. No te volveremos a escribir por aquí. Gracias por tu tiempo y feliz Navidad 🎄']
  ];
  $('respAse').innerHTML = RESP.map(function (r, i) { return '<details class="rq"><summary>' + esc(r[0]) + '</summary><div class="cpy">' + esc(r[1]) + '</div><button class="btn line small" data-r="' + i + '">Copiar respuesta</button></details>'; }).join('');
  $('respAse').addEventListener('click', function (e) {
    var b = e.target.closest('button[data-r]'); if (!b) return;
    U.copy(RESP[+b.dataset.r][1].replace(/\{dia\}/g, 'sábado').replace(/\{nombre\}/g, ''), function () { var o = b.textContent; b.textContent = 'Copiada ✓ pégala en el chat'; setTimeout(function () { b.textContent = o; }, 1500); });
  });

  /* ---------------- editar textos (solo si hace falta) ---------------- */
  function guardaTpl(tipo, v) { var o = S.get('tpl2', {}) || {}; o[paso + '.' + tipo] = v; S.set('tpl2', o); renderPasos(); renderLista(); }
  $('tplEdP').addEventListener('change', function () { guardaTpl('premium', this.value); });
  $('tplEdG').addEventListener('change', function () { guardaTpl('general', this.value); });
  $('tplRes').onclick = function () { var o = S.get('tpl2', {}) || {}; delete o[paso + '.premium']; delete o[paso + '.general']; S.set('tpl2', o); render(); };

  /* ---------------- carga de la base (propietaria) ---------------- */
  function parseCSV(txt) {
    var filas = txt.replace(/\r/g, '').split('\n').filter(function (l) { return l.trim(); });
    if (!filas.length) return [];
    var sep = (filas[0].match(/;/g) || []).length > (filas[0].match(/,/g) || []).length ? ';' : (filas[0].indexOf('\t') >= 0 ? '\t' : ',');
    var cols = function (l) { return l.split(sep).map(function (x) { return x.replace(/^"|"$/g, '').trim(); }); };
    var h = cols(filas[0]).map(function (x) { return x.toLowerCase(); });
    var idx = function (re) { for (var i = 0; i < h.length; i++) if (re.test(h[i])) return i; return -1; };
    var iN = idx(/nombre|cliente/), iT = idx(/cel|tel|whats|n[uú]mero|movil|móvil/), iP = idx(/premium|vip|regalo|tipo/), iA = idx(/asesora|vendedor/);
    var conCab = iN >= 0 && iT >= 0;
    if (!conCab) { iN = 0; iT = 1; iP = 2; iA = 3; }
    return filas.slice(conCab ? 1 : 0).map(function (l) { var c = cols(l); return { n: c[iN], t: c[iT], premium: iP >= 0 ? c[iP] : '', asesora: iA >= 0 ? c[iA] : '' }; }).filter(function (r) { return r.n && r.t; });
  }
  if ($('baseFile')) {
    $('baseFile').onchange = function () {
      var f = this.files[0]; if (!f) return; var r = new FileReader();
      r.onload = function () {
        var filas = parseCSV(String(r.result)), norm = normaliza(filas);
        if (!norm.length) { $('baseMsg').textContent = 'No encontré nombres y celulares en ese archivo. Revisa que tenga columnas Nombre y Celular.'; return; }
        S.set('base', filas);
        $('baseMsg').textContent = norm.length + ' clientes cargados (' + norm.filter(function (c) { return c.premium; }).length + ' premium, ' + norm.filter(function (c) { return !c.ok; }).length + ' con número para revisar). Recargando…';
        setTimeout(function () { location.reload(); }, 900);
      };
      r.readAsText(f, 'utf-8');
      this.value = '';
    };
    $('baseQuitar').onclick = function () { if (confirm('¿Quitar la base cargada en este navegador? El avance de cada cliente no se borra.')) { S.set('base', null); location.reload(); } };
    $('baseInfo').textContent = ORIGEN === 'local' ? 'Base cargada en este navegador: ' + BASE.length + ' clientes.' : ORIGEN === 'archivo' ? 'Base del archivo assets/clientes.js: ' + BASE.length + ' clientes.' : 'Ahora se ve la lista de ejemplo.';
  }

  /* ---------------- lo que usa la pestaña de la propietaria ---------------- */
  window.CoroAse = {
    registros: function () { return BASE.map(function (c) { var s = seg(c.id); return { nombre: c.nombre, tel: c.tel, premium: c.premium, estado: s.estado, cita: s.cita, monto: s.monto, nota: s.nota, hist: s.hist }; }); },
    pieza: pieza, datosPieza: datosPieza, horaBonita: horaBonita, mensajeBase: function () { return PASOS.invitacion.premium; },
    render: render
  };

  aviso(); render(); renderPiezas();
})();
