// share-renderer.js — decodes a shared boulder payload from the URL
// and renders it onto #share-canvas. URL format:
//   /r/<base64url>
//   /r.html?p=<base64url>
//   /r.html#<base64url>
//
// Payload format (little-endian):
//   u8  version = 1
//   u16 pixelCount
//   per pixel (4 bytes):
//     i8  x
//     i8  y
//     u8  hue   (0..254 → hue/255, 0xFF = legacy / no tag)
//     u8  shade (0..19 typically)
//
// Drawing matches the in-app BoulderRenderer: each pixel uses
// FocusTag.palette[shade] (hue-derived) so the rock keeps its tint
// fingerprint when shared.

(function () {
  const canvas = document.getElementById("share-canvas");
  const meta = document.getElementById("share-meta");
  if (!canvas) return;
  const ctx = canvas.getContext("2d");

  function readPayload() {
    // /r/<payload>
    const path = window.location.pathname.replace(/^\/+/, "");
    if (path.startsWith("r/") && path.length > 2) {
      return path.slice(2);
    }
    // /r.html?p=… or /r.html#…
    const q = new URLSearchParams(window.location.search);
    if (q.get("p")) return q.get("p");
    if (window.location.hash && window.location.hash.length > 1) {
      return window.location.hash.slice(1);
    }
    return null;
  }

  function base64UrlDecode(s) {
    s = s.replace(/-/g, "+").replace(/_/g, "/");
    while (s.length % 4) s += "=";
    const bin = atob(s);
    const arr = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) arr[i] = bin.charCodeAt(i);
    return arr;
  }

  function decode(arr) {
    if (arr.length < 3) throw new Error("payload too short");
    if (arr[0] !== 1) throw new Error("unsupported version");
    const count = arr[1] | (arr[2] << 8);
    const pixels = [];
    for (let i = 0; i < count; i++) {
      const off = 3 + i * 4;
      if (off + 4 > arr.length) break;
      const bx = arr[off];
      const by = arr[off + 1];
      const hueByte = arr[off + 2];
      const shade = arr[off + 3];
      const x = bx > 127 ? bx - 256 : bx;
      const y = by > 127 ? by - 256 : by;
      const hue = hueByte === 0xff ? null : hueByte / 255;
      pixels.push({ x, y, hue, shade });
    }
    return pixels;
  }

  // FocusTag.palette in JS — mirrors App/Features/FocusTag.swift:49.
  // 20 entries; brightness 0.15..0.85 (pow 0.95), saturation
  // 0.08..0.30 (sin curve).
  function paletteFor(hue) {
    const out = new Array(20);
    for (let i = 0; i < 20; i++) {
      const t = i / 19;
      const b = 0.15 + (0.85 - 0.15) * Math.pow(t, 0.95);
      const s = 0.08 + 0.22 * Math.sin(Math.PI * t);
      out[i] = hsvToRgb(hue, s, b);
    }
    return out;
  }
  // Neutral grey palette for legacy / no-tag pixels.
  const NEUTRAL_PALETTE = (() => {
    const out = new Array(20);
    for (let i = 0; i < 20; i++) {
      const t = i / 19;
      const v = 0.18 + 0.62 * Math.pow(t, 0.95);
      const c = Math.round(v * 255);
      out[i] = `rgb(${c},${c},${c})`;
    }
    return out;
  })();

  function hsvToRgb(h, s, v) {
    h = ((h % 1) + 1) % 1;
    const i = Math.floor(h * 6);
    const f = h * 6 - i;
    const p = v * (1 - s);
    const q = v * (1 - f * s);
    const t = v * (1 - (1 - f) * s);
    let r, g, b;
    switch (i % 6) {
      case 0: r = v; g = t; b = p; break;
      case 1: r = q; g = v; b = p; break;
      case 2: r = p; g = v; b = t; break;
      case 3: r = p; g = q; b = v; break;
      case 4: r = t; g = p; b = v; break;
      default: r = v; g = p; b = q; break;
    }
    return `rgb(${Math.round(r * 255)},${Math.round(g * 255)},${Math.round(b * 255)})`;
  }

  function render(pixels) {
    const width = canvas.clientWidth || 600;
    const height = canvas.clientHeight || 420;
    const dpr = window.devicePixelRatio || 1;
    canvas.width = Math.round(width * dpr);
    canvas.height = Math.round(height * dpr);
    canvas.style.width = `${width}px`;
    canvas.style.height = `${height}px`;
    ctx.imageSmoothingEnabled = false;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, width, height);

    if (pixels.length === 0) return;

    // Auto-fit: find pixel extent, choose cell size.
    let minX = Infinity, maxX = -Infinity, maxY = 0;
    for (const p of pixels) {
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.y > maxY) maxY = p.y;
    }
    const xExtent = maxX - minX + 1;
    const yExtent = maxY + 1;
    const cellW = (width - 80) / xExtent;
    const cellH = (height - 80) / yExtent;
    const cs = Math.max(2, Math.floor(Math.min(cellW, cellH)));
    const halfCell = Math.floor(cs / 2);
    const cx = Math.round(width / 2);
    const baselineY = Math.round(height - 40);

    // Cast shadow.
    const maxAbsX = Math.max(Math.abs(minX), Math.abs(maxX));
    const halfW = (maxAbsX + 1) * cs;
    const shadowW = halfW * 2 * 1.1;
    const shadowH = Math.max(cs * 1.4, cs * 2.2);
    ctx.fillStyle = "rgba(0,0,0,0.28)";
    ctx.beginPath();
    ctx.ellipse(cx, baselineY - shadowH * 0.30 + shadowH / 2, shadowW / 2, shadowH / 2, 0, 0, Math.PI * 2);
    ctx.fill();

    // Palette cache by hue byte.
    const cache = new Map();
    function paletteAt(hue) {
      if (hue === null) return NEUTRAL_PALETTE;
      const key = Math.round(hue * 255);
      let p = cache.get(key);
      if (!p) { p = paletteFor(hue); cache.set(key, p); }
      return p;
    }

    for (const px of pixels) {
      const pal = paletteAt(px.hue);
      const shade = Math.max(0, Math.min(pal.length - 1, px.shade));
      ctx.fillStyle = pal[shade];
      ctx.fillRect(
        cx + px.x * cs - halfCell,
        baselineY - px.y * cs - cs,
        cs,
        cs
      );
    }

    // Ground line.
    ctx.fillStyle = "rgba(255,255,255,0.15)";
    ctx.fillRect(40, baselineY, width - 80, 1);
  }

  try {
    const payload = readPayload();
    if (!payload) {
      meta.textContent = "No rock data in URL.";
      return;
    }
    const arr = base64UrlDecode(payload);
    const pixels = decode(arr);
    if (pixels.length === 0) {
      meta.textContent = "Empty rock — start focusing!";
      return;
    }
    meta.textContent = `${pixels.length} px · ${Math.round(pixels.length * 5)} focused minutes`;
    render(pixels);
    window.addEventListener("resize", () => render(pixels));
  } catch (e) {
    console.error(e);
    meta.textContent = "Couldn't read this rock 😕";
  }
})();
