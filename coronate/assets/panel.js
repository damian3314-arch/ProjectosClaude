/* Panel de campaña: asesoras, propietaria y creativo. Los datos viven en localStorage (este navegador). */
(function () {
  var C = window.CORO, U = window.CoroUtil, S = U.S, esc = U.esc;
  var $ = function (id) { return document.getElementById(id); };

  /* Las asesoras trabajan en assets/asesoras.js; aquí se leen sus registros. */
  var A = window.CoroAse;
  function regs() { return A ? A.registros() : []; }
  function fechaTarjeta(f) { return (f ? U.fmtDate(f, true) : 'Pronto') + ' · jornada continua'; }

  /* ---------- configuración pendiente ---------- */
  var faltan = [];
  if (!C.contacto.whatsapp) faltan.push('WhatsApp de la joyería');
  if (/\[/.test(C.contacto.direccion)) faltan.push('dirección');
  if (/\[/.test(C.contacto.horario)) faltan.push('horario');
  if (faltan.length) {
    var w = $('cfgWarn'); w.hidden = false; w.className = 'warn-box';
    w.innerHTML = '<b>Faltan datos en assets/config.js:</b> ' + esc(faltan.join(', ')) + '. Mientras tanto la landing muestra los marcadores.';
  }
  $('pTitulo').textContent = C.campana.nombre;

  /* ---------- pestañas ---------- */
  function tab(p) {
    ['ase', 'adm', 'cre'].forEach(function (k) {
      $('p-' + k).classList.toggle('on', k === p);
      $('t-' + k).setAttribute('aria-selected', k === p ? 'true' : 'false');
    });
    if (p === 'adm') renderAdm();
    if (p === 'cre') renderCre();
    try { history.replaceState(null, '', '#' + p); } catch (e) { /* file:// */ }
  }
  Array.prototype.forEach.call(document.querySelectorAll('.tabs button'), function (b) {
    b.onclick = function () { tab(b.dataset.p); };
  });

  /* ================= PROPIETARIA ================= */
  function ratio(a, meta) { return meta ? a / meta : 0; }
  function luz(r, vacio) { if (vacio) return '<span class="light n">–</span>'; return '<span class="light ' + (r >= 1 ? 'g' : r >= 0.7 ? 'y' : 'r') + '">' + Math.round(r * 100) + '%</span>'; }
  function money(n) { return '$' + Math.round(n).toLocaleString('es-CO'); }



  /* ---------- meta noviembre + diciembre ---------- */
  function renderMeta() {
    var m = C.metaNovDic; if (!m) return;
    var ly = m.nov2025 + m.dic2025, falta = m.meta - m.vendidoNov, dias = m.diasAbiertos + m.domingos;
    var porDia = falta / dias, brecha = m.meta - m.proyeccion;
    $('meta400').innerHTML = '<div class="kpis">' + [
      ['Meta noviembre + diciembre', money(m.meta), 'ajustada desde ' + money(m.metaOriginal)],
      ['Mismo período de 2025', money(ly), 'la meta es ' + Math.round((m.meta / ly - 1) * 100) + '% más'],
      ['Vendido en noviembre', money(m.vendidoNov), 'hasta el ' + U.fmtDate(m.corte)],
      ['Falta por día abierto', money(porDia), dias + ' días (' + m.diasAbiertos + ' hábiles + ' + m.domingos + ' domingos)'],
      ['Al ritmo actual llegamos a', money(m.proyeccion), 'sin campaña'],
      ['Lo que trae la campaña', money(brecha), 'brecha a cerrar']
    ].map(function (k) { return '<div class="kpi"><small>' + k[0] + '</small><b class="num">' + k[1] + '</b><em>' + esc(k[2]) + '</em></div>'; }).join('') + '</div>' +
      '<p class="note" style="margin-top:10px">En el libro de ventas, noviembre y diciembre de 2025 suman ' + money(ly) + ' (noviembre ' + money(m.nov2025) + ', diciembre ' + money(m.dic2025) + '). Los $327 M que se recuerdan incluyen del 29 al 31 de octubre. Para $380 M hay que vender ' + money(porDia) + ' cada día abierto, unas ' + (porDia / m.ritmoOct).toFixed(1).replace('.', ',') + ' veces el ritmo de octubre: la campaña tiene que sumarse a las ventas grandes (encargos, argollas, selectos) y a una semana de Navidad completa. Actualiza "vendidoNov" en config.js cada semana.</p>';
  }

  /* ---------- costos y retorno ---------- */
  var CAMPOS = [
    ['sabados', 'Sábados de campaña', 1], ['domingos', 'Domingos con cita', 1],
    ['invitadosRegalo', 'Invitados con shampoo de regalo', 5], ['costoShampoo', 'Costo del shampoo de regalo (3 joyas) ($)', 500],
    ['clientesPagan', 'Clientes que pagan el shampoo', 5], ['costoShampooPago', 'Costo del shampoo pago ($)', 500], ['precioShampoo', 'Precio que paga el cliente ($)', 1000],
    ['acompanantes', 'Acompañantes por cliente', 0.1], ['partCervezaSoda', 'Parte que toma Corona o soda (0 a 1)', 0.05],
    ['costoCervezaSoda', 'Costo Corona o soda ($)', 100], ['costoAguaCanada', 'Costo agua o Canada Dry ($)', 100],
    ['hieloJornada', 'Hielo por jornada ($)', 5000], ['snacksPersona', 'Snacks por persona ($, 0 = no)', 500],
    ['decoracion', 'Decoración de Navidad ($)', 50000], ['fotoVideo', 'Foto y video del creativo ($)', 50000],
    ['empaques', 'Empaques nuevos ($, 0 = los asume la joyería)', 50000], ['personalExtraJornada', 'Personal extra por jornada ($, 0 = no)', 10000],
    ['honorarios', 'Honorarios Fase 1 ($)', 100000],
    ['ventaSabadoCampana', 'Venta esperada por sábado de campaña ($)', 500000], ['ventaSabadoNormal', 'Venta de un sábado normal ($)', 100000], ['ventaSabado2025', 'Venta de esos sábados en 2025 ($)', 100000],
    ['ventaDomingo', 'Venta esperada por domingo ($)', 100000], ['canibalizacionDomingo', 'Parte del domingo que se habría vendido igual (0 a 1)', 0.05], ['margen', 'Margen sobre la venta de joyas (0 a 1)', 0.01]
  ];
  function costosBase() { var b = {}; Object.keys(C.costos).forEach(function (k) { b[k] = C.costos[k]; }); b.honorarios = C.honorarios.fase1; b.ventaSabadoNormal = C.ventaSabadoNormal; return b; }
  function costosVal() { var b = costosBase(), o = S.get('costos2', {}) || {}; Object.keys(o).forEach(function (k) { if (o[k] !== '' && o[k] != null) b[k] = +o[k]; }); return b; }
  function renderCostosIn() {
    var v = costosVal(), base = costosBase(), o = S.get('costos2', {}) || {};
    $('costIn').innerHTML = CAMPOS.map(function (c) {
      var editado = o[c[0]] != null && o[c[0]] !== '' && +o[c[0]] !== base[c[0]];
      return '<label>' + esc(c[1]) + (editado ? '' : ' <span class="note">[CONFIRMAR]</span>') + '<input type="number" step="' + c[2] + '" data-cs="' + c[0] + '" value="' + v[c[0]] + '"></label>';
    }).join('');
    Array.prototype.forEach.call($('costIn').querySelectorAll('input'), function (i) {
      i.oninput = function () { var o2 = S.get('costos2', {}) || {}; o2[i.getAttribute('data-cs')] = i.value; S.set('costos2', o2); renderCostos(); };
    });
  }
  function renderCostos() {
    var v = costosVal();
    var jornadas = v.sabados + v.domingos;
    var atendidos = v.invitadosRegalo + v.clientesPagan;
    var personas = atendidos * (1 + v.acompanantes);
    var rubros = [
      ['Shampoo de regalo a invitados', v.invitadosRegalo * v.costoShampoo, v.invitadosRegalo + ' invitados'],
      ['Corona y soda', personas * v.partCervezaSoda * v.costoCervezaSoda, Math.round(personas * v.partCervezaSoda) + ' bebidas'],
      ['Agua y Canada Dry', personas * (1 - v.partCervezaSoda) * v.costoAguaCanada, Math.round(personas * (1 - v.partCervezaSoda)) + ' bebidas'],
      ['Hielo', jornadas * v.hieloJornada, jornadas + ' jornadas'],
      ['Snacks', personas * v.snacksPersona, 'por persona'],
      ['Decoración de Navidad', v.decoracion, 'una vez'],
      ['Foto y video del creativo', v.fotoVideo, 'una vez'],
      ['Empaques nuevos', v.empaques, 'una vez'],
      ['Personal extra', jornadas * v.personalExtraJornada, 'por jornada'],
      ['Honorarios Fase 1', v.honorarios, 'una vez']
    ];
    var total = rubros.reduce(function (s, r) { return s + r[1]; }, 0);
    var servicio = v.clientesPagan * (v.precioShampoo - v.costoShampooPago);
    var ventaCamp = v.sabados * v.ventaSabadoCampana + v.domingos * v.ventaDomingo;
    var incr = v.sabados * (v.ventaSabadoCampana - v.ventaSabadoNormal) + v.domingos * v.ventaDomingo * (1 - v.canibalizacionDomingo);
    var incr25 = v.sabados * (v.ventaSabadoCampana - v.ventaSabado2025) + v.domingos * v.ventaDomingo * (1 - v.canibalizacionDomingo);
    var margenIncr = incr * v.margen + servicio, neto = margenIncr - total, roi = total ? margenIncr / total : 0;
    var equilibrio = v.margen ? Math.max(0, total - servicio) / v.margen : 0;
    $('costKpis').innerHTML = [
      ['Costo de la campaña', money(total), 'lo que se carga al proyecto'],
      ['Costo por cliente atendido', money(atendidos ? total / atendidos : 0), atendidos + ' clientes · ' + Math.round(personas) + ' personas'],
      ['El shampoo pago deja', money(servicio), v.clientesPagan + ' clientes × ' + money(v.precioShampoo - v.costoShampooPago)],
      ['Venta incremental de joyas', money(incr), 'contra un sábado normal · ' + money(incr25) + ' contra 2025'],
      ['Margen incremental total', money(margenIncr), 'joyas al ' + Math.round(v.margen * 100) + '% + shampoo pago'],
      ['Por cada $1 invertido vuelven', '$' + roi.toFixed(2).replace('.', ','), 'de margen'],
      ['Punto de equilibrio', money(equilibrio), 'de venta incremental de joyas']
    ].map(function (k) { return '<div class="kpi"><small>' + k[0] + '</small><b class="num">' + k[1] + '</b><em>' + esc(k[2]) + '</em></div>'; }).join('');
    var cumple = v.ventaSabadoCampana >= C.metasDia.venta, vb = $('costVeredicto');
    if (neto >= 0) { vb.className = 'ok-box'; vb.innerHTML = '<b>La campaña se paga y deja ' + money(neto) + ' de margen.</b> Venta de la campaña: ' + money(ventaCamp) + '. No se cargan el tiempo del taller, las asesoras ni la energía: ya son costos de la joyería.'; }
    else if (cumple) { vb.className = 'warn-box'; vb.innerHTML = '<b>Cumplimos la meta de venta del día pero no ganamos:</b> faltan ' + money(-neto) + ' de margen. La venta incremental de joyas tiene que llegar a ' + money(equilibrio) + '.'; }
    else { vb.className = 'warn-box'; vb.innerHTML = '<b>Con estos supuestos la campaña no se paga:</b> faltan ' + money(-neto) + ' de margen. La venta incremental de joyas tiene que llegar a ' + money(equilibrio) + '.'; }
    $('costTbl').innerHTML = '<thead><tr><th>Rubro</th><th>Base</th><th class="r">Costo</th><th class="r">%</th></tr></thead><tbody>' +
      rubros.map(function (r) { return '<tr><td>' + esc(r[0]) + '</td><td class="note">' + esc(r[2]) + '</td><td class="r num">' + money(r[1]) + '</td><td class="r num">' + (total ? Math.round(r[1] / total * 100) : 0) + '%</td></tr>'; }).join('') +
      '<tr><td><b>Total cargado a la campaña</b></td><td></td><td class="r num"><b>' + money(total) + '</b></td><td class="r">100%</td></tr></tbody>';
  }
  $('costReset').onclick = function () { S.set('costos2', {}); renderCostosIn(); renderCostos(); };

  function renderPend() {
    $('pendTbl').innerHTML = '<thead><tr><th>Decisión</th><th>Opciones</th><th>Quién decide</th></tr></thead><tbody>' +
      (C.pendientes || []).map(function (p) { return '<tr><td><b>' + esc(p.q) + '</b></td><td>' + esc(p.opciones) + '</td><td>' + esc(p.quien) + '</td></tr>'; }).join('') + '</tbody>';
  }

  function renderAdm() {
    renderMeta(); renderCostosIn(); renderCostos(); renderPend();
    var hoy = U.today();
    var clientes = regs();
    var cnt = function (arr) { return clientes.filter(function (c) { return arr.indexOf(c.estado) >= 0; }).length; };
    var enviadas = clientes.length - cnt(['porinvitar']);
    var resp = cnt(['interesado', 'agendado', 'recordado', 'llego', 'compro', 'nointeresa', 'baja']);
    var ag = cnt(['agendado', 'recordado', 'llego', 'compro']);
    var monto = clientes.reduce(function (s, c) { return s + (c.estado === 'compro' ? (+c.monto || 0) : 0); }, 0);
    $('admKpis').innerHTML = [
      ['Invitaciones enviadas', enviadas, 'de ' + clientes.length + ' en lista'],
      ['Respondieron', resp, enviadas ? Math.round(resp / enviadas * 100) + '% de las enviadas' : ''],
      ['Turnos agendados', ag, cnt(['nointeresa']) + ' no les interesa · ' + cnt(['baja']) + ' pidieron no escribir'],
      ['Llegaron', cnt(['llego', 'compro']), ''],
      ['Compraron', cnt(['compro']), ''],
      ['Venta atribuida', money(monto), 'suma de lo anotado']
    ].map(function (k) { return '<div class="kpi"><small>' + k[0] + '</small><b class="num">' + k[1] + '</b><em>' + k[2] + '</em></div>'; }).join('');

    var ventaDia = S.get('ventaDia', {}) || {};
    var rows = C.fechas.filter(function (x) { return x.tipo !== 'ensayo'; }).map(function (x) {
      var m = x.tipo === 'prueba' ? C.metasPrueba : C.metasDia;
      var cl = clientes.filter(function (c) { return c.cita && c.cita.f === x.f; });
      var citas = cl.filter(function (c) { return ['agendado', 'recordado', 'llego', 'compro'].indexOf(c.estado) >= 0; }).length;
      var llegan = cl.filter(function (c) { return c.estado === 'llego' || c.estado === 'compro'; }).length;
      var compran = cl.filter(function (c) { return c.estado === 'compro'; }).length;
      var atr = cl.reduce(function (s, c) { return s + (c.estado === 'compro' ? (+c.monto || 0) : 0); }, 0);
      var vd = +ventaDia[x.f] || 0;
      var venta = vd || atr;
      var futuro = x.f > hoy && !citas && !venta;
      return '<tr><td><b>' + esc(U.fmtDate(x.f)) + '</b><br><span class="note">' + esc(x.etiqueta) + '</span></td>' +
        '<td class="r num">' + citas + ' / ' + m.citas + '<br>' + luz(ratio(citas, m.citas), futuro) + '</td>' +
        '<td class="r num">' + llegan + ' / ' + m.llegan + '<br>' + luz(ratio(llegan, m.llegan), futuro) + '</td>' +
        '<td class="r num">' + compran + ' / ' + m.compran + '<br>' + luz(ratio(compran, m.compran), futuro) + '</td>' +
        '<td class="r num">' + money(atr) + '</td>' +
        '<td class="r"><input data-vd="' + x.f + '" type="number" inputmode="numeric" min="0" step="100000" value="' + (vd || '') + '" placeholder="$ caja" style="max-width:140px;min-height:40px;padding:6px 8px;text-align:right" aria-label="Venta del día ' + esc(x.f) + '"></td>' +
        '<td class="r">' + luz(ratio(venta, m.venta), futuro) + '<br><span class="note">meta ' + money(m.venta) + '</span></td></tr>';
    }).join('');
    $('semaforo').innerHTML = '<thead><tr><th>Fecha</th><th class="r">Citas</th><th class="r">Llegan</th><th class="r">Compran</th><th class="r">Atribuida</th><th class="r">Venta del día</th><th class="r">Semáforo</th></tr></thead><tbody>' + rows + '</tbody>';
    Array.prototype.forEach.call($('semaforo').querySelectorAll('input[data-vd]'), function (i) {
      i.onchange = function () { var o = S.get('ventaDia', {}) || {}; o[i.getAttribute('data-vd')] = +i.value || 0; S.set('ventaDia', o); renderAdm(); };
    });

    /* línea de tiempo */
    var ls = C.linea.slice().sort(function (a, b) { return a.f < b.f ? -1 : 1; });
    $('linea').innerHTML = ls.map(function (x) {
      var d = U.daysUntil(x.f);
      var cuando = d === 0 ? 'hoy' : d > 0 ? 'en ' + d + (d === 1 ? ' día' : ' días') : 'pasó';
      return '<div class="line-item' + (x.tipo === 'evento' ? ' evento' : '') + '"><b>' + esc(U.fmtDate(x.f)) + '</b><span>' + esc(x.t) + '</span><span class="note">' + cuando + '</span></div>';
    }).join('');

    /* citas */
    var todas = [];
    clientes.forEach(function (c) { if (c.cita && ['agendado', 'recordado', 'llego', 'compro'].indexOf(c.estado) >= 0) todas.push({ f: c.cita.f, h: c.cita.h, n: c.nombre, t: c.tel, j: c.nota, o: c.premium ? 'Premium' : 'General', e: c.estado }); });
    todas.sort(function (a, b) { return (a.f + a.h) < (b.f + b.h) ? -1 : 1; });
    $('citasTbl').innerHTML = todas.length ? '<thead><tr><th>Día</th><th>Hora</th><th>Cliente</th><th>WhatsApp</th><th>Nota</th><th>Tipo</th></tr></thead><tbody>' +
      todas.map(function (c) { return '<tr><td>' + esc(U.fmtDate(c.f)) + '</td><td>' + esc(c.h || '–') + '</td><td>' + esc(c.n) + '</td><td><a href="' + esc(U.waLink(c.t)) + '" target="_blank" rel="noopener">' + esc(c.t) + '</a></td><td>' + esc(c.j || '–') + '</td><td>' + c.o + '</td></tr>'; }).join('') + '</tbody>'
      : '<tbody><tr><td class="muted">Aún no hay citas.</td></tr></tbody>';
    $('citasNote').textContent = 'Turnos que agendaron las asesoras en este navegador.';

    /* checklist */
    var ck = S.get('check', {}) || {};
    $('checklist').innerHTML = C.checklist.map(function (t, i) {
      return '<label class="chk"><input type="checkbox" data-ck="' + i + '"' + (ck[i] ? ' checked' : '') + '><span>' + esc(t) + '</span></label>';
    }).join('');
    Array.prototype.forEach.call($('checklist').querySelectorAll('input'), function (i) {
      i.onchange = function () { var o = S.get('check', {}) || {}; o[i.getAttribute('data-ck')] = i.checked; S.set('check', o); };
    });
  }

  $('icsLinea').onclick = function () {
    var ev = C.linea.map(function (x) { return { titulo: 'Realeza · ' + x.t, f: x.f }; });
    U.download('sabados-de-realeza-fechas.ics', 'text/calendar', U.makeICS(ev));
  };
  $('bkDown').onclick = function () {
    var dump = {}; ['seg', 'base', 'tpl2', 'check', 'piezas', 'ventaDia', 'asesora', 'drive', 'costos2'].forEach(function (k) { dump[k] = S.get(k, null); });
    U.download('coronate-copia-' + U.today() + '.json', 'application/json', JSON.stringify(dump, null, 1));
  };
  $('bkUp').onchange = function () {
    var f = this.files[0]; if (!f) return; var r = new FileReader();
    r.onload = function () {
      try { var d = JSON.parse(String(r.result)); Object.keys(d).forEach(function (k) { if (d[k] != null) S.set(k, d[k]); }); location.reload(); }
      catch (e) { alert('El archivo no es una copia válida.'); }
    };
    r.readAsText(f);
  };

  /* ================= CREATIVO ================= */
  var PIEZAS = [
    'Tarjeta de invitación personalizada (diseño final)', 'Flyer / post de lanzamiento del 21',
    'Reel teaser: vitrina tapada, "algo muy especial"', 'Reel de la revelación (21 nov)',
    'Historias de cuenta regresiva', 'Fotos de la vitrina nueva y del producto',
    'Foto y video del evento del 21', 'Video de 15 s: banderas rojas del oro',
    'Pieza de regalo: agenda, bolsa y empaque nuevos', 'Cartel / señalética de la fachada (menú de bebidas, "+18")'
  ];
  var TEXTOS = [
    ['Teaser de expectativa (historia o post)', 'Algo muy especial se está preparando en Joyería Tanya Santiago ✨\nEl sábado 21 de noviembre lo vas a ver. Guarda la fecha.'],
    ['Lanzamiento (post del 21)', 'Hoy se abre el telón 🎄 La vitrina más linda de la Navidad está lista. Pasa por tu shampoo de brillo de regalo, una Corona bien fría (+18) y lo nuevo de la colección. Agenda tu turno: [LINK]'],
    ['Revelación (historia del 21, al quitar la tela)', 'Se abrió el telón ✨ Esta es la vitrina más linda de la Navidad en Barrancabermeja. Hoy te esperamos con shampoo de brillo de regalo para tus joyas, una Corona bien fría (+18) y todo lo nuevo de la colección. Agenda tu turno: [LINK]'],
    ['Información abierta del servicio (redes, 18–20 nov)', 'Este sábado 21 de noviembre, de corrido: shampoo de brillo para tus joyas de oro mientras disfrutas la nueva vitrina de Navidad. Invitados con cita: de regalo. Sin invitación: [PRECIO] por hasta 3 joyas. Cupos limitados, agenda por WhatsApp.'],
    ['Gracias: tu oro, tu corona (después de la visita)', 'Gracias por venir, {nombre} 💛 Tu oro ya brilla como se merece: tu oro, tu corona. Si quieres, aquí te dejamos la foto de tu joya. Nos vemos en Navidad.'],
    ['Banderas rojas (reel)', '¿Hace cuánto tu oro no se da un baño? Aretes que nunca te quitas, manillas con olorcito a guardado, cadena sin brillo. Es oro de verdad: que se note. Ven este sábado y hacemos el shampoo de brillo de regalo.']
  ];
  function renderCre() {
    var u = S.get('drive', '') || C.drive.carpeta || '';
    $('driveUrl').value = u; $('driveGo').href = u || '#'; $('driveGo').style.opacity = u ? 1 : .5;
    var pz = S.get('piezas', {}) || {};
    $('piezas').innerHTML = PIEZAS.map(function (t, i) { return '<label class="chk"><input type="checkbox" data-pz="' + i + '"' + (pz[i] ? ' checked' : '') + '><span>' + esc(t) + '</span></label>'; }).join('');
    Array.prototype.forEach.call($('piezas').querySelectorAll('input'), function (i) {
      i.onchange = function () { var o = S.get('piezas', {}) || {}; o[i.getAttribute('data-pz')] = i.checked; S.set('piezas', o); };
    });
    var all = [['Invitación por WhatsApp (premium)', A ? A.mensajeBase() : '']].concat(TEXTOS);
    $('textos').innerHTML = all.map(function (t, i) { return '<div><b>' + esc(t[0]) + '</b><div class="cpy">' + esc(t[1]) + '</div><button class="btn line small" style="margin-top:6px" data-cp="' + i + '">Copiar</button></div>'; }).join('');
    Array.prototype.forEach.call($('textos').querySelectorAll('button'), function (b) {
      b.onclick = function () { U.copy(all[+b.dataset.cp][1], function () { var o = b.textContent; b.textContent = 'Copiado ✓'; setTimeout(function () { b.textContent = o; }, 1200); }); };
    });
    $('cardFecha').innerHTML = C.fechas.map(function (x) { return '<option value="' + x.f + '"' + (x.f === C.campana.lanzamiento ? ' selected' : '') + '>' + esc(U.fmtDate(x.f)) + '</option>'; }).join('');
    pintarTarjeta();
  }
  function pintarTarjeta() {
    var cv = $('tarjeta');
    (document.fonts && document.fonts.ready ? document.fonts.ready : Promise.resolve()).then(function () {
      if (A) A.pieza(cv, A.datosPieza('invitacion', { id: '_cre', nombre: $('cardNombre').value || 'Cliente', premium: true }));
    });
  }
  $('driveUrl').addEventListener('input', function () { S.set('drive', this.value.trim()); $('driveGo').href = this.value.trim() || '#'; $('driveGo').style.opacity = this.value.trim() ? 1 : .5; });
  $('cardNombre').addEventListener('input', pintarTarjeta);
  $('cardFecha').addEventListener('change', pintarTarjeta);
  $('cardDown').onclick = function () { $('tarjeta').toBlob(function (b) { U.download('invitacion-' + ($('cardNombre').value || 'cliente').toLowerCase() + '.png', 'image/png', b); }); };

  /* ---------- arranque ---------- */
  var h = (location.hash || '').replace('#', '');
  if (['ase', 'adm', 'cre'].indexOf(h) >= 0) tab(h);
})();
