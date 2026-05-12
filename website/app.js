// Boulder promo — two pieces:
//   1. Download gate modal (3-second hold, gravy standard).
//   2. Scroll-spy: highlight the nav item for the section in view.

// -------- 1. Download gate --------
(function () {
  const gate = document.getElementById('dlGate');
  if (!gate) return;
  const closeBtn = document.getElementById('dlGateClose');
  const confirmBtn = document.getElementById('dlGateConfirm');
  const confirmText = confirmBtn && confirmBtn.querySelector('.dl-gate-btn-text');
  let countdownTimer = null;

  function openGate(href) {
    gate.removeAttribute('hidden');
    confirmBtn.setAttribute('data-locked', 'true');
    confirmBtn.setAttribute('href', href);
    let remaining = 3;
    const tick = function () {
      if (remaining > 0) {
        confirmText.textContent = 'Read above (' + remaining + 's)…';
        remaining--;
      } else {
        confirmBtn.removeAttribute('data-locked');
        confirmText.textContent = '↓ I understand · Download Boulder';
        clearInterval(countdownTimer);
      }
    };
    tick();
    clearInterval(countdownTimer);
    countdownTimer = setInterval(tick, 1000);
  }
  function closeGate() {
    gate.setAttribute('hidden', '');
    clearInterval(countdownTimer);
    confirmBtn.setAttribute('data-locked', 'true');
    if (confirmText) confirmText.textContent = 'Read above first…';
  }
  document.querySelectorAll('[data-download-trigger]').forEach(function (link) {
    link.addEventListener('click', function (e) {
      e.preventDefault();
      openGate(link.getAttribute('href'));
    });
  });
  if (confirmBtn) confirmBtn.addEventListener('click', function (e) {
    if (confirmBtn.getAttribute('data-locked') === 'true') { e.preventDefault(); return; }
    setTimeout(closeGate, 400);
  });
  if (closeBtn) closeBtn.addEventListener('click', closeGate);
  gate.addEventListener('click', function (e) {
    if (e.target === gate) closeGate();
  });
  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape' && !gate.hasAttribute('hidden')) closeGate();
  });
})();

// -------- 2. Scroll-spy --------
// Light a nav link when its section is the most prominent one on screen.
(function () {
  const links = document.querySelectorAll('.nav nav a[data-spy]');
  if (!links.length || !('IntersectionObserver' in window)) return;

  const linkById = new Map();
  const sections = [];
  links.forEach(function (a) {
    const id = a.getAttribute('data-spy');
    const el = document.getElementById(id);
    if (el) {
      linkById.set(id, a);
      sections.push(el);
    }
  });
  if (!sections.length) return;

  let visible = new Map();
  function pickActive() {
    let bestId = null;
    let bestRatio = 0;
    visible.forEach(function (ratio, id) {
      if (ratio > bestRatio) { bestRatio = ratio; bestId = id; }
    });
    linkById.forEach(function (link, id) {
      link.classList.toggle('is-active', id === bestId);
    });
  }

  const io = new IntersectionObserver(function (entries) {
    entries.forEach(function (entry) {
      visible.set(entry.target.id, entry.isIntersecting ? entry.intersectionRatio : 0);
    });
    pickActive();
  }, {
    rootMargin: '-30% 0px -55% 0px',
    threshold: [0, 0.25, 0.5, 0.75, 1]
  });
  sections.forEach(function (s) { io.observe(s); });
})();
