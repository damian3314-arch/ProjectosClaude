/* Promoción de fin de año · Tumbao (idea de la dueña, 24 nov 2026)
 *
 *   Compras del 24 de noviembre al 31 de diciembre de 2026 → 45 días calendario de vigencia, en mensualidades y tiqueteras.
 *   No hay clases: 8, 25, 26 y 31 de diciembre. Receso del 1 al 5 de enero. Regresamos el miércoles 6 de enero.
 *
 * Un solo archivo para las dos páginas:
 *   <script src="promo-fin-de-ano.js" data-modo="pop"  defer>   → página de reservas: pop-up (una vez al día) que lleva a /mensualidad
 *   <script src="promo-fin-de-ano.js" data-modo="hero" defer>   → /mensualidad: portada navideña con cuenta regresiva y calculadora de vencimiento
 *
 * Solo corre dentro de las fechas (hora de Bogotá). ?promo=1 la fuerza (pruebas), ?promo=0 la apaga.
 * La vigencia de la tiquetera la da la base (tiquetera_paquetes); la de la mensualidad viene de AdminGym. Esto solo la comunica.
 */
(function () {
  'use strict';
  var tag = document.currentScript || document.querySelector('script[src*="promo-fin-de-ano"]');
  var modo = (tag && tag.getAttribute('data-modo')) || 'pop';

  var P = {
    desde: '2026-11-24', hasta: '2026-12-31', dias: 45,
    fin: Date.parse('2027-01-01T00:00:00-05:00'),
    llave: 'tumbao_fda_2026'
  };
  var qs = location.search;
  var q = (qs.match(/[?&]promo=(\d)/) || [])[1];
  if (q === '0') return;

  function hoyBogota() { return new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Bogota' }).format(new Date()); }
  var hoy = hoyBogota();
  var activa = q === '1' || (hoy >= P.desde && hoy <= P.hasta);
  if (!activa) return;
  window.PROMO_FDA = { dias: P.dias, hasta: P.hasta };

  var $ = function (s, r) { return (r || document).querySelector(s); };
  var refR = (qs.match(/[?&]r=(\d{1,9})\b/) || [])[1];
  var aMens = 'mensualidad.html' + (refR ? '?r=' + refR : '');

  var MESES = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];
  var DIAS = ['domingo', 'lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado'];
  // compra + 45 días calendario (el mismo criterio de «compra 31 dic → vence 14 feb»)
  function vence(iso) {
    var p = iso.split('-').map(Number);
    var d = new Date(Date.UTC(p[0], p[1] - 1, p[2] + P.dias));
    return DIAS[d.getUTCDay()] + ' ' + d.getUTCDate() + ' de ' + MESES[d.getUTCMonth()] + (d.getUTCFullYear() !== p[0] ? ' de ' + d.getUTCFullYear() : '');
  }
  function dosD(n) { return (n < 10 ? '0' : '') + n; }

  /* ───────── estilos ───────── */
  var css = [
    '.fda-nieve{position:fixed;inset:0;z-index:2;pointer-events:none;opacity:.8}',
    '.fda-caja{position:relative;overflow:hidden;border-radius:22px;color:#fff;text-align:center;',
    '  background:radial-gradient(110% 70% at 50% -20%,rgba(255,46,143,.16),transparent 65%),#1a1226;',
    '  box-shadow:0 14px 40px rgba(0,0,0,.4),0 0 0 1px rgba(255,255,255,.1)}',
    '.fda-luces{position:absolute;left:0;right:0;top:0;height:26px;pointer-events:none}',
    '.fda-luces i{position:absolute;top:7px;width:6px;height:6px;border-radius:50%;background:#ffd9a0;box-shadow:0 0 8px rgba(255,217,160,.7);opacity:.7;animation:fdaTw 3.6s ease-in-out infinite}',
    '.fda-luces::before{content:"";position:absolute;left:-4%;right:-4%;top:-14px;height:30px;border-bottom:1px solid rgba(255,255,255,.18);border-radius:0 0 50% 50%/0 0 100% 100%}',
    '@keyframes fdaTw{0%,100%{opacity:.4}50%{opacity:.85}}',
    '.fda-in{position:relative;padding:2.1rem 1.2rem 1.2rem}',
    '.fda-k{margin:0;font-size:.72rem;font-weight:700;letter-spacing:.14em;text-transform:uppercase;color:#cdbfdc}',
    '.fda-t{margin:.3rem 0 0;font-size:1.3rem;line-height:1.15;font-weight:700;letter-spacing:-.01em}',
    '.fda-45{display:block;margin:.2rem 0;font-size:4rem;line-height:1;font-weight:800;letter-spacing:-.04em;',
    '  background:linear-gradient(100deg,#ff9a4d,#ff4f93);-webkit-background-clip:text;background-clip:text;color:transparent}',
        '.fda-sub{margin:0;font-size:.98rem;font-weight:600;color:#fff}',
    '.fda-sub small{display:block;margin-top:.15rem;font-weight:500;font-size:.84rem;color:#d7c9e6}',
    '.fda-cuenta{display:grid;grid-template-columns:repeat(4,1fr);gap:6px;margin:.6rem auto .1rem;max-width:300px}',
    '.fda-cuenta div{padding:.45rem .2rem;border-radius:12px;background:rgba(255,255,255,.06)}',
    '.fda-cuenta b{display:block;font-size:1.25rem;line-height:1;font-weight:700;font-variant-numeric:tabular-nums}',
    '.fda-cuenta span{display:block;margin-top:.2rem;font-size:.58rem;letter-spacing:.1em;text-transform:uppercase;color:#a99bb8}',
    '.fda-cuenta-t{margin:.8rem 0 0;font-size:.76rem;color:#a99bb8}',
    '.fda-hoy{margin:.8rem 0 0;font-size:.9rem;color:#e9def5}',
    '.fda-hoy b{color:#fff}',
    '.fda-cta{display:block;width:100%;margin-top:.9rem;border:0;border-radius:99px;padding:14px 18px;font:700 1rem/1.2 inherit;color:#26101a;cursor:pointer;text-decoration:none;',
    '  background:linear-gradient(90deg,#ff8a4d,#ff4f93)}',
    '.fda-no{display:block;margin:.5rem auto 0;border:0;background:none;color:#cdbfdc;font:500 .9rem/1.2 inherit;padding:6px;cursor:pointer}',
    '.fda-x{position:absolute;right:10px;top:12px;z-index:3;width:36px;height:36px;border-radius:50%;border:0;cursor:pointer;background:rgba(0,0,0,.5);color:#fff;font:700 1.15rem/1 inherit}',
    /* pop-up */
    '.fda-pop{position:fixed;inset:0;z-index:10000;display:none;align-items:center;justify-content:center;padding:16px;background:rgba(8,4,16,.8);backdrop-filter:blur(3px)}',
    '.fda-pop.on{display:flex}',
    '.fda-pop .fda-caja{width:min(400px,100%);max-height:calc(100dvh - 28px);overflow:auto;animation:fdaEntra .4s cubic-bezier(.23,1,.32,1)}',
    '@keyframes fdaEntra{from{opacity:0;transform:translateY(18px) scale(.96)}to{opacity:1;transform:none}}',
    /* portada de /mensualidad */
    '.fda-hero{margin:.4rem 0 1.1rem}',
    '.fda-cal{margin-top:1rem;text-align:left}',
    '.fda-cal label{display:block;font-size:.8rem;font-weight:600;color:#cdbfdc;margin-bottom:.35rem;text-align:center}',
    '.fda-cal input{display:block;margin:0 auto;width:min(230px,100%);padding:.6rem .8rem;border-radius:12px;border:1px solid rgba(255,255,255,.25);background:rgba(0,0,0,.35);color:#fff;font:600 1rem inherit;color-scheme:dark;text-align:center}',
    '.fda-vence{margin:.7rem 0 0;text-align:center;font-size:.95rem;color:#e9def5}',
    '.fda-vence b{display:block;margin-top:.1rem;font-size:1.15rem;color:#fff;font-weight:700}',
    '.fda-cierre{margin-top:1rem;padding-top:.9rem;border-top:1px solid rgba(255,255,255,.14);text-align:center}',
    '.fda-cierre p{margin:0 0 .5rem;font-size:.76rem;font-weight:700;letter-spacing:.08em;text-transform:uppercase;color:#cdbfdc}',
    '.fda-chips{display:flex;flex-wrap:wrap;gap:6px;justify-content:center}',
    '.fda-chips span{padding:.3rem .6rem;border-radius:99px;font-size:.8rem;font-weight:600;background:rgba(255,255,255,.07)}',
    '.fda-chips .v{background:rgba(255,255,255,.14);color:#fff}',
    '.fda-cuenta-aviso{margin:.8rem 0 0;font-size:.82rem;color:#d7c9e6}',
    '.fda-aviso summary{cursor:pointer;margin-top:.9rem;font-size:.84rem;font-weight:600;color:#cdbfdc;list-style:none}',
    '.fda-aviso summary::-webkit-details-marker{display:none}',
    '.fda-aviso ul{margin:.5rem 0 0;padding:0;list-style:none;text-align:left;font-size:.85rem;color:#e9def5}',
    '.fda-aviso li{padding:.3rem 0 .3rem 1.4rem;position:relative}',
    '.fda-aviso li::before{content:"•";position:absolute;left:.3rem;color:#a99bb8}',
    /* gorro del logo */
    '.fda-gorro{position:absolute;width:24%;max-width:96px;right:1%;top:-44%;pointer-events:none;transform:rotate(14deg);filter:drop-shadow(0 3px 6px rgba(0,0,0,.4))}',
    '@media (prefers-reduced-motion:reduce){.fda-luces i,.fda-45,.fda-pop .fda-caja{animation:none}}',
    '@media (max-width:380px){.fda-45{font-size:3.6rem}.fda-t{font-size:1.2rem}}'
  ].join('\n');
  var st = document.createElement('style'); st.id = 'fda-estilos'; st.textContent = css; document.head.appendChild(st);

  /* ───────── piezas ───────── */
  function luces() {
    var s = '<div class="fda-luces" aria-hidden="true">';
    for (var i = 0; i < 8; i++) s += '<i style="left:' + (7 + i * 12.6) + '%;animation-delay:' + ((i % 4) * 0.7) + 's"></i>';
    return s + '</div>';
  }
  function cuentaHTML() {
    return '<div class="fda-cuenta" data-fda-cuenta aria-label="Tiempo que queda de la promoción">' +
      '<div><b data-u="d">--</b><span>días</span></div><div><b data-u="h">--</b><span>horas</span></div>' +
      '<div><b data-u="m">--</b><span>min</span></div><div><b data-u="s">--</b><span>seg</span></div></div>';
  }
  function tick() {
    var ms = P.fin - Date.now();
    if (ms <= 0) { document.querySelectorAll('.fda-pop,.fda-hero').forEach(function (n) { n.remove(); }); return false; }
    var s = Math.floor(ms / 1000);
    var v = { d: Math.floor(s / 86400), h: Math.floor(s % 86400 / 3600), m: Math.floor(s % 3600 / 60), s: s % 60 };
    document.querySelectorAll('[data-fda-cuenta]').forEach(function (box) {
      Object.keys(v).forEach(function (k) { var e = box.querySelector('[data-u="' + k + '"]'); if (e) e.textContent = k === 'd' ? v[k] : dosD(v[k]); });
    });
    return true;
  }
  var timer = setInterval(function () { if (!tick()) clearInterval(timer); }, 1000);

  function nieve() {
    if (window.matchMedia && matchMedia('(prefers-reduced-motion:reduce)').matches) return;
    var c = document.createElement('canvas'); c.className = 'fda-nieve'; c.setAttribute('aria-hidden', 'true');
    document.body.appendChild(c);
    var x = c.getContext('2d'), W = 0, H = 0, n = innerWidth < 600 ? 22 : 38, f = [];
    function medir() { W = c.width = innerWidth; H = c.height = innerHeight; }
    medir(); addEventListener('resize', medir);
    for (var i = 0; i < n; i++) f.push({ x: Math.random() * W, y: Math.random() * H, r: 1 + Math.random() * 1.6, v: .3 + Math.random() * .6, a: Math.random() * 6.28 });
    var activo = true;
    document.addEventListener('visibilitychange', function () { activo = !document.hidden; if (activo) paso(); });
    function paso() {
      if (!activo) return;
      x.clearRect(0, 0, W, H);
      x.fillStyle = 'rgba(255,255,255,.5)';
      for (var i = 0; i < f.length; i++) {
        var p = f[i]; p.y += p.v; p.a += .012; p.x += Math.sin(p.a) * .5;
        if (p.y > H + 4) { p.y = -4; p.x = Math.random() * W; }
        x.beginPath(); x.arc(p.x, p.y, p.r, 0, 6.2832); x.fill();
      }
      requestAnimationFrame(paso);
    }
    paso();
  }

  function gorro() {
    var m = $('.marca');
    if (!m || $('.fda-gorro', m)) return;
    m.style.position = 'relative'; m.style.display = 'inline-block';
    m.insertAdjacentHTML('beforeend',
      '<svg class="fda-gorro" viewBox="0 0 120 90" aria-hidden="true"><path d="M8 78C20 40 50 8 100 14c-12 14-12 34-8 64z" fill="#e8283c"/>' +
      '<rect x="2" y="70" width="104" height="20" rx="10" fill="#fff"/><circle cx="104" cy="16" r="10" fill="#fff"/></svg>');
  }

  function cuerpoPromo(extra) {
    return luces() +
      '<div class="fda-in">' +
      '<p class="fda-k">Especial de fin de año</p>' +
      '<p class="fda-t">¡Este fin de año tus clases duran más!</p>' +
      '<span class="fda-45">45</span>' +
      '<p class="fda-sub">días de vigencia<small>En mensualidades y tiqueteras · compras hasta el 31 de diciembre</small></p>' +
      '<p class="fda-cuenta-t">La promo termina en</p>' + cuentaHTML() +
      extra + '</div>';
  }

  /* ───────── modo pop-up (página de reservas) ───────── */
  function pop() {
    var d = document.createElement('div');
    d.className = 'fda-pop'; d.id = 'fda-pop'; d.setAttribute('role', 'dialog'); d.setAttribute('aria-modal', 'true');
    d.setAttribute('aria-label', 'Promoción de fin de año: 45 días de vigencia'); d.hidden = true;
    d.innerHTML = '<div class="fda-caja"><button type="button" class="fda-x" data-fda-x aria-label="Cerrar">×</button>' +
      cuerpoPromo(
        '<p class="fda-hoy">Si compras hoy, tu plan vive hasta el <b>' + vence(hoy >= P.desde && hoy <= P.hasta ? hoy : P.desde) + '</b>.</p>' +
        '<a class="fda-cta" id="fda-ir" href="' + aMens + '">Ver mensualidades y tiqueteras →</a>' +
        '<button type="button" class="fda-no" data-fda-x>Ahora no</button>') +
      '</div>';
    document.body.appendChild(d);
    function cerrar() { d.classList.remove('on'); d.hidden = true; try { localStorage.setItem(P.llave, hoyBogota()); } catch (e) {} }
    d.addEventListener('click', function (e) { if (e.target === d || (e.target.closest && e.target.closest('[data-fda-x]'))) cerrar(); });
    document.addEventListener('keydown', function (e) { if (e.key === 'Escape' && d.classList.contains('on')) cerrar(); });
    tick();
    var visto = false; try { visto = localStorage.getItem(P.llave) === hoyBogota(); } catch (e) {}
    // Una vez al día. Los navegadores automáticos (las pruebas de la página) no lo ven; con ?promo=1 se fuerza.
    if (q === '1' || (!visto && !navigator.webdriver)) setTimeout(function () { d.hidden = false; d.classList.add('on'); }, 1200);

    // La opción «Quiero un plan» de la página lo recuerda sin ser una tarjeta más.
    var et = $('#franja-promo .etq-nueva'); if (et) et.textContent = '45 días';
  }

  /* ───────── modo portada (/mensualidad) ───────── */
  function hero() {
    var ancla = $('#renovar-caja') || $('#el-titulo');
    if (!ancla) return;
    var h = document.createElement('section'); h.className = 'fda-hero fda-caja'; h.id = 'fda-hero';
    var minF = hoy >= P.desde ? hoy : P.desde;
    h.innerHTML = cuerpoPromo(
      '<div class="fda-cal"><label for="fda-fecha">Si compras el…</label>' +
      '<input type="date" id="fda-fecha" value="' + minF + '" min="' + P.desde + '" max="' + P.hasta + '">' +
      '<p class="fda-vence">tu plan vence el<b id="fda-vence">' + vence(minF) + '</b></p></div>' +
      '<div class="fda-cierre"><p>Días sin clase</p><div class="fda-chips">' +
      '<span>8 dic</span><span>25 dic</span><span>26 dic</span><span>31 dic</span><span>Receso 1–5 ene</span><span class="v">Volvemos mié 6 ene</span></div></div>' +
      '<details class="fda-aviso"><summary>Ten en cuenta ▾</summary><ul>' +
      '<li>Los 45 días son de calendario y empiezan el día de tu compra.</li>' +
      '<li>La mensualidad permite asistir sin límite en el horario que elijas.</li>' +
      '<li>La tiquetera conserva sus clases y se reserva antes en tumbaobaila.com.</li>' +
      '<li>No hay servicio domingos, festivos ni los días de cierre anunciados.</li></ul></details>' +
      '<p class="fda-cuenta-aviso">Termina el año bailando y empieza el 2027 con Tumbao.</p>');
    ancla.parentNode.insertBefore(h, ancla);
    var f = $('#fda-fecha', h), out = $('#fda-vence', h);
    f.addEventListener('input', function () {
      var v = f.value;
      if (/^\d{4}-\d{2}-\d{2}$/.test(v) && v >= P.desde && v <= P.hasta) out.textContent = vence(v);
      else out.textContent = 'elige una fecha entre el 24 de noviembre y el 31 de diciembre';
    });
    tick();
  }

  function iniciar() {
    nieve();
    if (modo === 'hero') hero(); else pop();
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', iniciar); else iniciar();
})();
