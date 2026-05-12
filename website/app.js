// Boulder promo — two pieces:
//   1. Download gate modal (3-second hold, gravy standard).
//   2. Hero canvas: a slowly-growing pixel boulder so visitors see
//      the in-app vibe without installing.

// -------- 1. Download gate --------
(function () {
  const gate = document.getElementById('dlGate');
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
  if (gate) gate.addEventListener('click', function (e) {
    if (e.target === gate) closeGate();
  });
  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape' && !gate.hasAttribute('hidden')) closeGate();
  });
})();

// -------- 2. Hero boulder canvas --------
//
// Replays the in-app growth: a golden-angle spiral of pixels rising
// out of nothing, each pixel colored by a randomized "focus type."
// Loops slowly. Purely decorative — no interaction.
(function () {
  const canvas = document.getElementById('heroBoulder');
  if (!canvas) return;
  const ctx = canvas.getContext('2d');
  ctx.imageSmoothingEnabled = false;

  const palettes = [
    ['#3B3B45', '#5A5A6E', '#8E8AA8', '#C147FF'],  // code
    ['#6A5A4A', '#8B7860', '#B5A085', '#D9C7A8'],  // write
    ['#4A3526', '#7A5638', '#9E7549', '#C59766'],  // read
    ['#2E3E4F', '#44627A', '#2EE6A0', '#47A0FF'],  // audio
    ['#5C3A4B', '#8C5468', '#FF6B6B', '#FFD960'],  // design
  ];

  const W = canvas.width;
  const H = canvas.height;
  const cell = 4;
  const target = 1100;
  let pixels = [];

  function reset() { pixels = []; }

  function step() {
    if (pixels.length >= target) {
      setTimeout(reset, 1800);
      return;
    }
    // emit ~8 pixels per frame so the boulder grows visibly during
    // a 6-7 second scroll past the hero
    for (let i = 0; i < 8; i++) {
      const n = pixels.length;
      if (n >= target) break;
      const radius = Math.sqrt(n) * 1.6;
      const theta = n * 2.39996;
      const x = radius * Math.cos(theta) + (Math.random() * 2 - 1);
      const y = radius * Math.sin(theta) * 0.55 + (Math.random() * 2 - 1);
      const pal = palettes[(n + Math.floor(n / 80)) % palettes.length];
      const shade = pal[(Math.floor(Math.random() * pal.length))];
      pixels.push({ x, y: y < 0 ? -y * 0.5 : y, c: shade });
    }
    draw();
  }

  function draw() {
    ctx.clearRect(0, 0, W, H);
    // subtle ground line
    ctx.fillStyle = 'rgba(255,255,255,0.08)';
    ctx.fillRect(40, H - 30, W - 80, 1);
    const cx = W / 2;
    const baseline = H - 36;
    for (let i = 0; i < pixels.length; i++) {
      const p = pixels[i];
      ctx.fillStyle = p.c;
      ctx.fillRect(
        Math.round(cx + p.x * cell - cell / 2),
        Math.round(baseline - p.y * cell - cell),
        cell, cell
      );
    }
  }

  setInterval(step, 60);
})();
