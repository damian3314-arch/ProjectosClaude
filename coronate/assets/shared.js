/* Utilidades compartidas por la landing y el panel. Sin dependencias, funciona con file:// y con cualquier servidor estático. */
(function () {
  var C = window.CORO;

  var S = {
    get: function (k, d) {
      try { var v = localStorage.getItem('coro.' + k); return v ? JSON.parse(v) : d; } catch (e) { return d; }
    },
    set: function (k, v) {
      try { localStorage.setItem('coro.' + k, JSON.stringify(v)); return true; } catch (e) { return false; }
    }
  };

  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }

  function uid() { return Date.now().toString(36) + Math.random().toString(36).slice(2, 7); }

  /* Teléfonos colombianos: 10 dígitos que empiezan en 3 -> 57 + número. */
  function normPhone(t) {
    var d = String(t || '').replace(/\D/g, '');
    if (d.length === 10 && d.charAt(0) === '3') d = '57' + d;
    return { num: d, ok: /^573\d{9}$/.test(d) };
  }

  function waLink(phone, text) {
    var p = normPhone(phone);
    return 'https://wa.me/' + p.num + (text ? '?text=' + encodeURIComponent(text) : '');
  }

  function dateObj(f, hhmm) {
    var p = f.split('-'), h = hhmm ? hhmm.split(':') : ['12', '00'];
    return new Date(+p[0], +p[1] - 1, +p[2], +h[0], +h[1], 0);
  }

  function fmtDate(f, largo) {
    return dateObj(f).toLocaleDateString('es-CO', largo
      ? { weekday: 'long', day: 'numeric', month: 'long' }
      : { weekday: 'short', day: 'numeric', month: 'short' }).replace(/,/g, '');
  }

  function today() {
    var n = new Date();
    return n.getFullYear() + '-' + ('0' + (n.getMonth() + 1)).slice(-2) + '-' + ('0' + n.getDate()).slice(-2);
  }

  function daysUntil(f) {
    var a = dateObj(today()), b = dateObj(f);
    return Math.round((b - a) / 864e5);
  }

  /* Bloques de la agenda: ["09:00","09:30",...] */
  function slots() {
    var A = C.agenda, out = [];
    var s = A.inicio.split(':'), e = A.fin.split(':');
    var t = +s[0] * 60 + +s[1], end = +e[0] * 60 + +e[1];
    for (; t < end; t += A.bloqueMin) {
      out.push(('0' + Math.floor(t / 60)).slice(-2) + ':' + ('0' + (t % 60)).slice(-2));
    }
    return out;
  }

  function addMin(hhmm, m) {
    var p = hhmm.split(':'), t = +p[0] * 60 + +p[1] + m;
    return ('0' + Math.floor(t / 60)).slice(-2) + ':' + ('0' + (t % 60)).slice(-2);
  }

  /* Colombia es UTC-5 todo el año, sin horario de verano. */
  function utcStamp(f, hhmm) {
    var p = f.split('-'), h = hhmm.split(':');
    var d = new Date(Date.UTC(+p[0], +p[1] - 1, +p[2], +h[0] + 5, +h[1], 0));
    return d.toISOString().replace(/[-:]/g, '').replace(/\.\d{3}/, '');
  }

  function icsEscape(s) { return String(s).replace(/\\/g, '\\\\').replace(/;/g, '\\;').replace(/,/g, '\\,').replace(/\n/g, '\\n'); }

  /* events: [{titulo, f, ini, fin, detalle, lugar}] (ini/fin "HH:MM"; si faltan, evento de día completo) */
  function makeICS(events) {
    var L = ['BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//Corónate//ES', 'CALSCALE:GREGORIAN'];
    events.forEach(function (ev) {
      L.push('BEGIN:VEVENT', 'UID:' + uid() + '@coronate');
      L.push('DTSTAMP:' + utcStamp(today(), '12:00'));
      if (ev.ini) {
        L.push('DTSTART:' + utcStamp(ev.f, ev.ini), 'DTEND:' + utcStamp(ev.f, ev.fin || addMin(ev.ini, 30)));
      } else {
        var d = ev.f.replace(/-/g, '');
        var n = dateObj(ev.f); n.setDate(n.getDate() + 1);
        var nx = n.getFullYear() + ('0' + (n.getMonth() + 1)).slice(-2) + ('0' + n.getDate()).slice(-2);
        L.push('DTSTART;VALUE=DATE:' + d, 'DTEND;VALUE=DATE:' + nx);
      }
      L.push('SUMMARY:' + icsEscape(ev.titulo));
      if (ev.detalle) L.push('DESCRIPTION:' + icsEscape(ev.detalle));
      if (ev.lugar) L.push('LOCATION:' + icsEscape(ev.lugar));
      L.push('END:VEVENT');
    });
    L.push('END:VCALENDAR');
    return L.join('\r\n');
  }

  function gcalLink(ev) {
    var q = 'action=TEMPLATE&text=' + encodeURIComponent(ev.titulo) +
      '&dates=' + utcStamp(ev.f, ev.ini) + '/' + utcStamp(ev.f, ev.fin || addMin(ev.ini, 30)) +
      '&details=' + encodeURIComponent(ev.detalle || '') + '&location=' + encodeURIComponent(ev.lugar || '');
    return 'https://calendar.google.com/calendar/render?' + q;
  }

  function download(name, mime, content) {
    var blob = content instanceof Blob ? content : new Blob([content], { type: mime });
    var a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = name;
    document.body.appendChild(a);
    a.click();
    setTimeout(function () { URL.revokeObjectURL(a.href); a.remove(); }, 500);
  }

  function baseUrl() {
    if (C.baseUrl) return C.baseUrl.replace(/\/$/, '');
    var u = location.href.split('#')[0].split('?')[0];
    return u.replace(/[^\/]*$/, '') + 'index.html';
  }

  function copy(text, done) {
    var fb = function () {
      var ta = document.createElement('textarea');
      ta.value = text; document.body.appendChild(ta); ta.select();
      try { document.execCommand('copy'); } catch (e) { /* nada */ }
      ta.remove(); if (done) done();
    };
    try { navigator.clipboard.writeText(text).then(done || function () {}, fb); } catch (e) { fb(); }
  }

  function fechasPublicas(conPrueba) {
    var t = today();
    return C.fechas.filter(function (x) { return (x.publico || (conPrueba && x.tipo === 'prueba')) && x.f >= t; });
  }

  window.CoroUtil = {
    S: S, esc: esc, uid: uid, normPhone: normPhone, waLink: waLink, dateObj: dateObj, fmtDate: fmtDate,
    today: today, daysUntil: daysUntil, slots: slots, addMin: addMin, makeICS: makeICS, gcalLink: gcalLink,
    download: download, baseUrl: baseUrl, copy: copy, fechasPublicas: fechasPublicas
  };
})();
