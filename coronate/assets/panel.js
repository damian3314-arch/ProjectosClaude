/* Panel de campaña: asesoras, propietaria y creativo. Los datos viven en localStorage (este navegador). */
(function () {
  var C = window.CORO, U = window.CoroUtil, S = U.S, esc = U.esc;
  var $ = function (id) { return document.getElementById(id); };

  var ESTADOS = [
    ['pendiente', 'Por escribir'], ['enviada', 'Invitación enviada'], ['respondio', 'Respondió'],
    ['agendo', 'Agendó'], ['llego', 'Llegó'], ['compro', 'Compró'], ['baja', 'Pidió BAJA']
  ];
  var META_DIARIA = 75;

  var TPL_DEF = {
    invitacion: {
      nombre: 'Invitación',
      txt: 'Hola {nombre} ✨ Soy {asesora} de Joyería Tanya Santiago.\n\nQueremos consentirte: el {fecha} trae hasta 3 joyas de oro y les hacemos un shampoo de brillo de regalo. Mientras tanto te relajas con una Corona bien fría (+18) o una bebida sin alcohol, y conoces lo nuevo de nuestra vitrina de Navidad.\n\nAquí ves todo y agendas tu turno: {link}\n\n¿Te aparto un espacio? Respóndeme QUIERO. Si prefieres no recibir más mensajes, responde BAJA.'
    },
    seguimiento: {
      nombre: 'Seguimiento (no respondió)',
      txt: 'Hola {nombre}, soy {asesora} de Joyería Tanya Santiago. Te escribo por si se te pasó la invitación del {fecha}: shampoo de brillo de regalo para tus joyas de oro y una Corona bien fría. Cupos limitados, aquí agendas: {link}\n\nSi no quieres recibir más mensajes, responde BAJA.'
    },
    recordatorio: {
      nombre: 'Recordatorio de cita',
      txt: 'Hola {nombre}, te recuerdo que te esperamos el {fecha} en Joyería Tanya Santiago. Trae tus joyas y ven con ganas de disfrutar. Si necesitas cambiar la hora, respóndeme por aquí. {asesora}'
    },
    gracias: {
      nombre: 'Gracias por venir',
      txt: 'Gracias por venir, {nombre} 💛 Fue un gusto consentir tu oro. Si quieres, cuéntame cómo te fue. {asesora}, Joyería Tanya Santiago'
    }
  };

  /* ---------- datos ---------- */
  var clientes = S.get('clientes', []) || [];
  function guardar() { S.set('clientes', clientes); }
  function primerNombre(n) { return String(n || '').trim().split(/\s+/)[0] || ''; }

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

  /* ================= ASESORAS ================= */
  var fechasOf = C.fechas.filter(function (x) { return x.f >= U.today(); });
  $('fechaOf').innerHTML = fechasOf.map(function (x) { return '<option value="' + x.f + '">' + esc(U.fmtDate(x.f, true)) + '</option>'; }).join('');
  $('asesora').value = S.get('asesora', '') || '';
  $('asesora').addEventListener('input', function () { S.set('asesora', $('asesora').value); renderClientes(); });
  $('fechaOf').addEventListener('change', function () { renderClientes(); });

  function tplTexto(id) { var o = S.get('tpl', {}) || {}; return o[id] != null ? o[id] : TPL_DEF[id].txt; }
  $('tplSel').innerHTML = Object.keys(TPL_DEF).map(function (k) { return '<option value="' + k + '">' + esc(TPL_DEF[k].nombre) + '</option>'; }).join('');
  function cargarTpl() { $('tplTxt').value = tplTexto($('tplSel').value); }
  $('tplSel').addEventListener('change', function () { cargarTpl(); renderClientes(); });
  $('tplTxt').addEventListener('input', renderClientes);
  $('tplSave').onclick = function () { var o = S.get('tpl', {}) || {}; o[$('tplSel').value] = $('tplTxt').value; S.set('tpl', o); this.textContent = 'Guardado ✓'; var b = this; setTimeout(function () { b.textContent = 'Guardar cambios de esta plantilla'; }, 1500); };
  $('tplReset').onclick = function () { var o = S.get('tpl', {}) || {}; delete o[$('tplSel').value]; S.set('tpl', o); cargarTpl(); renderClientes(); };
  cargarTpl();

  function linkPara(c) {
    return U.baseUrl() + '?n=' + encodeURIComponent(primerNombre(c.nombre)) + (c.prueba ? '&p=1' : '');
  }
  function mensajePara(c) {
    var f = $('fechaOf').value;
    var fechaTxt = f ? U.fmtDate(f, true) : '[fecha]';
    return $('tplTxt').value
      .replace(/\{nombre\}/g, primerNombre(c.nombre))
      .replace(/\{fecha\}/g, fechaTxt)
      .replace(/\{link\}/g, linkPara(c))
      .replace(/\{asesora\}/g, $('asesora').value.trim() || 'tu asesora');
  }

  /* importar */
  function parseLine(l) {
    var m = l.match(/(\+?\d[\d\s\-().]{8,}\d)/);
    if (!m) return null;
    var tel = U.normPhone(m[1]);
    var nombre = l.replace(m[1], ' ').replace(/[,;\t"]+/g, ' ').replace(/\s+/g, ' ').trim() || 'Cliente';
    return { nombre: nombre, tel: tel.num, ok: tel.ok };
  }
  function importar(texto, prueba) {
    var vistos = {}; clientes.forEach(function (c) { vistos[c.tel] = 1; });
    var nuevos = 0, dup = 0, mal = 0, sin = 0;
    texto.split(/\r?\n/).forEach(function (l) {
      if (!l.trim()) return;
      var p = parseLine(l);
      if (!p) { sin++; return; }
      if (vistos[p.tel]) { dup++; return; }
      vistos[p.tel] = 1; if (!p.ok) mal++;
      clientes.push({ id: U.uid(), nombre: p.nombre, tel: p.tel, estado: 'pendiente', prueba: !!prueba, fechaCita: '', monto: 0, nota: '', enviadaAt: '' });
      nuevos++;
    });
    guardar();
    $('impMsg').textContent = nuevos + ' agregados · ' + dup + ' repetidos' + (mal ? ' · ' + mal + ' con teléfono dudoso' : '') + (sin ? ' · ' + sin + ' líneas sin teléfono' : '') + '.';
    renderClientes();
  }
  $('impBtn').onclick = function () { importar($('imp').value, $('impPrueba').checked); $('imp').value = ''; };
  $('impFile').onchange = function () {
    var f = this.files[0]; if (!f) return;
    var r = new FileReader(); var pr = $('impPrueba').checked;
    r.onload = function () { importar(String(r.result), pr); };
    r.readAsText(f);
    this.value = '';
  };

  $('filtro').innerHTML = '<option value="">Todos</option>' + ESTADOS.map(function (e) { return '<option value="' + e[0] + '">' + e[1] + '</option>'; }).join('');
  $('filtro').addEventListener('change', renderClientes);
  $('busq').addEventListener('input', renderClientes);

  function renderClientes() {
    var hoy = U.today();
    var porEstado = {}; ESTADOS.forEach(function (e) { porEstado[e[0]] = 0; });
    clientes.forEach(function (c) { porEstado[c.estado] = (porEstado[c.estado] || 0) + 1; });
    var enviadasHoy = clientes.filter(function (c) { return c.enviadaAt === hoy; }).length;
    var respondieron = porEstado.respondio + porEstado.agendo + porEstado.llego + porEstado.compro;
    $('aseKpis').innerHTML = [
      ['En la lista', clientes.length, ''],
      ['Por escribir', porEstado.pendiente, ''],
      ['Enviadas hoy', enviadasHoy, 'meta ' + META_DIARIA],
      ['Respondieron', respondieron, ''],
      ['Agendaron', porEstado.agendo + porEstado.llego + porEstado.compro, '']
    ].map(function (k) { return '<div class="kpi"><small>' + k[0] + '</small><b class="num">' + k[1] + '</b><em>' + k[2] + '</em></div>'; }).join('');

    var fil = $('filtro').value, bq = $('busq').value.trim().toLowerCase();
    var lista = clientes.filter(function (c) {
      return (!fil || c.estado === fil) && (!bq || c.nombre.toLowerCase().indexOf(bq) >= 0 || c.tel.indexOf(bq.replace(/\D/g, '') || '§') >= 0);
    }).slice(0, 200);

    if (!clientes.length) { $('clientes').innerHTML = '<p class="muted">Aún no hay clientes. Pega una lista arriba.</p>'; return; }
    if (!lista.length) { $('clientes').innerHTML = '<p class="muted">Nada con ese filtro.</p>'; return; }

    var opts = '<option value="">Día de la cita…</option>' + C.fechas.map(function (x) { return '<option value="' + x.f + '">' + esc(U.fmtDate(x.f)) + '</option>'; }).join('');
    $('clientes').innerHTML = lista.map(function (c) {
      var ok = U.normPhone(c.tel).ok;
      return '<div class="cli' + (c.estado === 'compro' ? ' hecho' : '') + '" data-id="' + c.id + '">' +
        '<div><div class="nm">' + esc(c.nombre) + (c.prueba ? ' <span class="pill">selecto</span>' : '') + (ok ? '' : ' <span class="pill bad">revisar teléfono</span>') + '</div>' +
        '<div class="sub">' + esc(c.tel) + (c.enviadaAt ? ' · enviada ' + esc(c.enviadaAt) : '') + '</div></div>' +
        '<div class="bt"><button class="btn wa small" data-a="wa"' + (ok && c.estado !== 'baja' ? '' : ' disabled') + '>WhatsApp</button>' +
        '<button class="btn line small" data-a="card">Tarjeta</button></div>' +
        '<div class="ctl">' +
        '<select data-f="estado" aria-label="Estado">' + ESTADOS.map(function (e) { return '<option value="' + e[0] + '"' + (e[0] === c.estado ? ' selected' : '') + '>' + e[1] + '</option>'; }).join('') + '</select>' +
        '<select data-f="fechaCita" aria-label="Día de la cita">' + opts.replace('value="' + c.fechaCita + '"', 'value="' + c.fechaCita + '" selected') + '</select>' +
        '<input data-f="monto" type="number" inputmode="numeric" min="0" step="1000" placeholder="Compra $" value="' + (c.monto || '') + '" aria-label="Valor de la compra">' +
        '<input data-f="nota" placeholder="Nota" value="' + esc(c.nota) + '" aria-label="Nota">' +
        '</div></div>';
    }).join('');
  }

  $('clientes').addEventListener('change', function (e) {
    var t = e.target, f = t.getAttribute('data-f'); if (!f) return;
    var id = t.closest('.cli').dataset.id;
    var c = clientes.filter(function (x) { return x.id === id; })[0]; if (!c) return;
    c[f] = f === 'monto' ? (+t.value || 0) : t.value;
    if (f === 'estado' && c.estado === 'enviada' && !c.enviadaAt) c.enviadaAt = U.today();
    guardar(); renderClientes();
  });
  $('clientes').addEventListener('click', function (e) {
    var b = e.target.closest('button[data-a]'); if (!b) return;
    var id = b.closest('.cli').dataset.id;
    var c = clientes.filter(function (x) { return x.id === id; })[0]; if (!c) return;
    if (b.dataset.a === 'wa') {
      window.open(U.waLink(c.tel, mensajePara(c)), '_blank', 'noopener');
      if (c.estado === 'pendiente') { c.estado = 'enviada'; c.enviadaAt = U.today(); guardar(); renderClientes(); }
    } else if (b.dataset.a === 'card') {
      abrirTarjeta(c);
    }
  });

  /* ---------- tarjeta personalizada (canvas) ---------- */
  function drawCard(cv, nombre, fechaTxt) {
    var g = cv.getContext('2d'), W = cv.width, H = cv.height;
    var grad = g.createLinearGradient(0, 0, W, H); grad.addColorStop(0, '#22421F'); grad.addColorStop(1, '#16301A');
    g.fillStyle = grad; g.fillRect(0, 0, W, H);
    var seed = 7; function rnd() { seed = (seed * 9301 + 49297) % 233280; return seed / 233280; }
    for (var i = 0; i < 70; i++) { g.fillStyle = 'rgba(255,255,255,' + (0.15 + rnd() * 0.5).toFixed(2) + ')'; g.beginPath(); g.arc(rnd() * W, rnd() * H, 2 + rnd() * 5, 0, 7); g.fill(); }
    g.strokeStyle = '#C9A44A'; g.lineWidth = 5; g.strokeRect(48, 48, W - 96, H - 96);
    g.strokeStyle = 'rgba(201,164,74,.45)'; g.lineWidth = 2; g.strokeRect(68, 68, W - 136, H - 136);
    g.fillStyle = '#B3261E'; g.beginPath(); g.moveTo(W - 220, 48); g.lineTo(W - 140, 48); g.lineTo(W - 140, 260); g.lineTo(W - 180, 225); g.lineTo(W - 220, 260); g.closePath(); g.fill();
    g.textAlign = 'center';
    g.fillStyle = '#C9A44A'; g.font = '700 30px "Hanken Grotesk", system-ui, sans-serif';
    if ('letterSpacing' in g) g.letterSpacing = '8px';
    g.fillText('JOYERÍA TANYA SANTIAGO', W / 2 - 40, 170);
    if ('letterSpacing' in g) g.letterSpacing = '0px';
    var nm = primerNombre(nombre) + ',';
    var size = 190; g.font = size + 'px "Instrument Serif", Georgia, serif';
    while (g.measureText(nm).width > W - 220 && size > 70) { size -= 6; g.font = size + 'px "Instrument Serif", Georgia, serif'; }
    g.fillStyle = '#F7F2E8'; g.fillText(nm, W / 2, 520);
    g.font = 'italic 78px "Instrument Serif", Georgia, serif'; g.fillStyle = '#C9A44A';
    g.fillText('esta invitación es solo para ti', W / 2, 630);
    g.fillStyle = '#F7F2E8'; g.font = '700 42px "Hanken Grotesk", system-ui, sans-serif';
    g.fillText(fechaTxt, W / 2, 790);
    g.font = '500 38px "Hanken Grotesk", system-ui, sans-serif'; g.fillStyle = '#D9E3D6';
    ['Shampoo de brillo de regalo para tus joyas', 'Una Corona bien fría (+18) o bebida sin alcohol', 'Lo nuevo de nuestra vitrina de Navidad'].forEach(function (t, i) { g.fillText(t, W / 2, 880 + i * 62); });
    g.fillStyle = '#C9A44A'; var bw = 760, bh = 96, bx = (W - bw) / 2, by = 1130;
    g.beginPath(); g.moveTo(bx + 48, by); g.arcTo(bx + bw, by, bx + bw, by + bh, 48); g.arcTo(bx + bw, by + bh, bx, by + bh, 48); g.arcTo(bx, by + bh, bx, by, 48); g.arcTo(bx, by, bx + bw, by, 48); g.fill();
    g.fillStyle = '#2A1D00'; g.font = '800 38px "Hanken Grotesk", system-ui, sans-serif';
    g.fillText('Responde QUIERO y te apartamos tu turno', W / 2, by + 62);
  }
  function fechaTarjeta(f) { return (f ? U.fmtDate(f, true) : 'Pronto') + ' · jornada continua'; }

  function abrirTarjeta(c) {
    var d = $('dlg'), body = $('dlgBody');
    body.innerHTML = '<h3>Tarjeta para ' + esc(primerNombre(c.nombre)) + '</h3><canvas id="tarjetaDlg" width="1080" height="1350" style="width:100%;border-radius:14px;margin:10px 0"></canvas>' +
      '<div class="actions"><button class="btn fill small" id="tdDown">Descargar</button><button class="btn wa small" id="tdShare">Compartir</button><button class="btn line small" id="tdClose">Cerrar</button></div>' +
      '<p class="note" style="margin-top:8px">En el celular, "Compartir" abre WhatsApp con la imagen. En computador, descárgala y adjúntala.</p>';
    var cv = $('tarjetaDlg');
    var go = function () { drawCard(cv, c.nombre, fechaTarjeta($('fechaOf').value)); };
    (document.fonts && document.fonts.ready ? document.fonts.ready : Promise.resolve()).then(go);
    $('tdClose').onclick = function () { d.close(); };
    $('tdDown').onclick = function () { cv.toBlob(function (b) { U.download('invitacion-' + primerNombre(c.nombre).toLowerCase() + '.png', 'image/png', b); }); };
    $('tdShare').onclick = function () {
      cv.toBlob(function (b) {
        var file = new File([b], 'invitacion.png', { type: 'image/png' });
        if (navigator.canShare && navigator.canShare({ files: [file] })) {
          navigator.share({ files: [file], text: mensajePara(c) }).catch(function () { /* cancelado */ });
        } else { U.download('invitacion-' + primerNombre(c.nombre).toLowerCase() + '.png', 'image/png', b); }
      });
    };
    if (d.showModal) d.showModal(); else d.setAttribute('open', '');
  }

  /* ================= PROPIETARIA ================= */
  function ratio(a, meta) { return meta ? a / meta : 0; }
  function luz(r, vacio) { if (vacio) return '<span class="light n">–</span>'; return '<span class="light ' + (r >= 1 ? 'g' : r >= 0.7 ? 'y' : 'r') + '">' + Math.round(r * 100) + '%</span>'; }
  function money(n) { return '$' + Math.round(n).toLocaleString('es-CO'); }

  function citasWeb() { return S.get('citas', []) || []; }

  function renderAdm() {
    var hoy = U.today();
    var cnt = function (arr) { return clientes.filter(function (c) { return arr.indexOf(c.estado) >= 0; }).length; };
    var enviadas = clientes.length - cnt(['pendiente']);
    var resp = cnt(['respondio', 'agendo', 'llego', 'compro']);
    var ag = cnt(['agendo', 'llego', 'compro']);
    var web = citasWeb().length;
    var monto = clientes.reduce(function (s, c) { return s + (c.estado === 'compro' ? (+c.monto || 0) : 0); }, 0);
    $('admKpis').innerHTML = [
      ['Invitaciones enviadas', enviadas, 'de ' + clientes.length + ' en lista'],
      ['Respuestas', resp, enviadas ? Math.round(resp / enviadas * 100) + '% de las enviadas' : ''],
      ['Citas (asesoras + web)', ag + web, ag + ' asesoras · ' + web + ' web'],
      ['Llegaron', cnt(['llego', 'compro']), ''],
      ['Compraron', cnt(['compro']), ''],
      ['Venta atribuida', money(monto), 'suma de lo anotado']
    ].map(function (k) { return '<div class="kpi"><small>' + k[0] + '</small><b class="num">' + k[1] + '</b><em>' + k[2] + '</em></div>'; }).join('');

    var ventaDia = S.get('ventaDia', {}) || {};
    var rows = C.fechas.map(function (x) {
      var m = x.tipo === 'prueba' ? C.metasPrueba : C.metasDia;
      var cl = clientes.filter(function (c) { return c.fechaCita === x.f; });
      var citas = cl.filter(function (c) { return ['agendo', 'llego', 'compro'].indexOf(c.estado) >= 0; }).length + citasWeb().filter(function (c) { return c.f === x.f; }).length;
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
    var todas = citasWeb().map(function (c) { return { f: c.f, h: c.h, n: c.nombre, t: c.tel, j: c.joyas, o: 'Web' }; });
    clientes.forEach(function (c) { if (c.fechaCita && ['agendo', 'llego', 'compro'].indexOf(c.estado) >= 0) todas.push({ f: c.fechaCita, h: '', n: c.nombre, t: c.tel, j: '', o: 'Asesora' }); });
    todas.sort(function (a, b) { return (a.f + a.h) < (b.f + b.h) ? -1 : 1; });
    $('citasTbl').innerHTML = todas.length ? '<thead><tr><th>Día</th><th>Hora</th><th>Cliente</th><th>WhatsApp</th><th>Joyas</th><th>Origen</th></tr></thead><tbody>' +
      todas.map(function (c) { return '<tr><td>' + esc(U.fmtDate(c.f)) + '</td><td>' + esc(c.h || '–') + '</td><td>' + esc(c.n) + '</td><td><a href="' + esc(U.waLink(c.t)) + '" target="_blank" rel="noopener">' + esc(c.t) + '</a></td><td>' + esc(c.j || '–') + '</td><td>' + c.o + '</td></tr>'; }).join('') + '</tbody>'
      : '<tbody><tr><td class="muted">Aún no hay citas.</td></tr></tbody>';
    $('citasNote').textContent = C.agenda.endpoint ? 'Las citas de la web también se guardan en tu hoja y Calendar de Google.' : 'Modo prueba: solo se ven las citas hechas desde este navegador. Para recibir las de todos los clientes, conecta el Apps Script (ver README).';

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
    var dump = {}; ['clientes', 'citas', 'tpl', 'check', 'piezas', 'ventaDia', 'asesora', 'drive'].forEach(function (k) { dump[k] = S.get(k, null); });
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
    var all = [['Invitación por WhatsApp (plantilla base)', TPL_DEF.invitacion.txt]].concat(TEXTOS);
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
      drawCard(cv, $('cardNombre').value || 'Cliente', fechaTarjeta($('cardFecha').value));
    });
  }
  $('driveUrl').addEventListener('input', function () { S.set('drive', this.value.trim()); $('driveGo').href = this.value.trim() || '#'; $('driveGo').style.opacity = this.value.trim() ? 1 : .5; });
  $('cardNombre').addEventListener('input', pintarTarjeta);
  $('cardFecha').addEventListener('change', pintarTarjeta);
  $('cardDown').onclick = function () { $('tarjeta').toBlob(function (b) { U.download('invitacion-' + ($('cardNombre').value || 'cliente').toLowerCase() + '.png', 'image/png', b); }); };

  /* ---------- arranque ---------- */
  renderClientes();
  var h = (location.hash || '').replace('#', '');
  if (['ase', 'adm', 'cre'].indexOf(h) >= 0) tab(h);
})();
