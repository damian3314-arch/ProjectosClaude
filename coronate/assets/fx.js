/* Detalles de movimiento: luz que sigue el cursor en tarjetas. Sin efecto en pantallas táctiles ni con movimiento reducido. */
(function () {
  if (!window.matchMedia || !matchMedia('(pointer:fine)').matches || matchMedia('(prefers-reduced-motion: reduce)').matches) return;
  document.addEventListener('pointermove', function (e) {
    var el = e.target.closest && e.target.closest('.card,.kpi,.fl');
    if (!el) return;
    var r = el.getBoundingClientRect();
    el.style.setProperty('--mx', (e.clientX - r.left) + 'px');
    el.style.setProperty('--my', (e.clientY - r.top) + 'px');
  }, { passive: true });
})();
