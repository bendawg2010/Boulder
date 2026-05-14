// share-renderer.js — decodes a shared boulder payload from the URL
// and renders it onto #share-canvas with hover/click inspection.
//
// URL forms supported:
//   /r/?by=Ben&name=Granite#<payload>
//   /r/#<payload>
//   /r.html?p=<payload>      (legacy fallback)
//
// Payload format (little-endian):
//   v1:
//     u8  version=1, u16 count, [i8 x, i8 y, u8 hue, u8 shade] × N
//   v2:
//     u8  version=2, u32 count, [i8 x, i8 y, u8 hue, u8 shade, u32 earnedAt] × N
//   earnedAt = 0 means unknown.

(function () {
  const canvas = document.getElementById("share-canvas");
  const meta = document.getElementById("share-meta");
  const titleEl = document.getElementById("share-title");
  const bylineEl = document.getElementById("share-byline");
  const tooltipEl = document.getElementById("share-tooltip");
  if (!canvas) return;
  const ctx = canvas.getContext("2d");

  function readPayload() {
    if (window.location.hash && window.location.hash.length > 1) {
      return window.location.hash.slice(1);
    }
    const q = new URLSearchParams(window.location.search);
    if (q.get("p")) return q.get("p");
    const path = window.location.pathname.replace(/^\/+/, "");
    if (path.startsWith("r/") && path.length > 2) {
      return path.slice(2);
    }
    return null;
  }

  function readMetadata() {
    const q = new URLSearchParams(window.location.search);
    return {
      author: (q.get("by") || "").trim(),
      rockName: (q.get("name") || "").trim(),
    };
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
    if (arr.length < 1) throw new Error("payload too short");
    const version = arr[0];
    if (version === 1) return decodeV1(arr);
    if (version === 2) return decodeV2(arr);
    throw new Error(`unsupported version ${version}`);
  }

  function decodeV1(arr) {
    const count = arr[1] | (arr[2] << 8);
    const pixels = [];
    for (let i = 0; i < count; i++) {
      const off = 3 + i * 4;
      if (off + 4 > arr.length) break;
      const x = arr[off] > 127 ? arr[off] - 256 : arr[off];
      const y = arr[off + 1] > 127 ? arr[off + 1] - 256 : arr[off + 1];
      const hueByte = arr[off + 2];
      const shade = arr[off + 3];
      const hue = hueByte === 0xff ? null : hueByte / 255;
      pixels.push({ x, y, hue, shade, earnedAt: null });
    }
    return pixels;
  }

  function decodeV2(arr) {
    const count =
      arr[1] |
      (arr[2] << 8) |
      (arr[3] << 16) |
      ((arr[4] << 24) >>> 0);
    const pixels = [];
    for (let i = 0; i < count; i++) {
      const off = 5 + i * 8;
      if (off + 8 > arr.length) break;
      const x = arr[off] > 127 ? arr[off] - 256 : arr[off];
      const y = arr[off + 1] > 127 ? arr[off + 1] - 256 : arr[off + 1];
      const hueByte = arr[off + 2];
      const shade = arr[off + 3];
      const ts =
        arr[off + 4] |
        (arr[off + 5] << 8) |
        (arr[off + 6] << 16) |
        ((arr[off + 7] << 24) >>> 0);
      const hue = hueByte === 0xff ? null : hueByte / 255;
      pixels.push({
        x, y, hue, shade,
        earnedAt: ts > 0 ? new Date(ts * 1000) : null,
      });
    }
    return pixels;
  }

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

  // Render state — kept so click handlers can hit-test pixels.
  let renderState = null;

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

    if (pixels.length === 0) { renderState = null; return; }

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

    const maxAbsX = Math.max(Math.abs(minX), Math.abs(maxX));
    const halfW = (maxAbsX + 1) * cs;
    const shadowW = halfW * 2 * 1.1;
    const shadowH = Math.max(cs * 1.4, cs * 2.2);
    ctx.fillStyle = "rgba(0,0,0,0.28)";
    ctx.beginPath();
    ctx.ellipse(cx, baselineY - shadowH * 0.30 + shadowH / 2, shadowW / 2, shadowH / 2, 0, 0, Math.PI * 2);
    ctx.fill();

    const cache = new Map();
    function paletteAt(hue) {
      if (hue === null) return NEUTRAL_PALETTE;
      const key = Math.round(hue * 255);
      let p = cache.get(key);
      if (!p) { p = paletteFor(hue); cache.set(key, p); }
      return p;
    }

    // Cache rendered rects so the click handler can hit-test.
    const rects = new Array(pixels.length);

    for (let i = 0; i < pixels.length; i++) {
      const px = pixels[i];
      const pal = paletteAt(px.hue);
      const shade = Math.max(0, Math.min(pal.length - 1, px.shade));
      const rx = cx + px.x * cs - halfCell;
      const ry = baselineY - px.y * cs - cs;
      rects[i] = { rx, ry, cs };
      ctx.fillStyle = pal[shade];
      ctx.fillRect(rx, ry, cs, cs);
    }

    ctx.fillStyle = "rgba(255,255,255,0.15)";
    ctx.fillRect(40, baselineY, width - 80, 1);

    renderState = { width, height, dpr, rects, pixels, cs };
  }

  function highlight(index) {
    if (!renderState) return;
    // Redraw quickly with a bright outline on the chosen rect.
    const { rects } = renderState;
    if (index < 0 || index >= rects.length) return;
    const r = rects[index];
    ctx.save();
    ctx.lineWidth = Math.max(2, Math.round(r.cs * 0.55));
    ctx.strokeStyle = "rgba(255, 217, 96, 0.95)";
    ctx.shadowColor = "rgba(255, 217, 96, 0.85)";
    ctx.shadowBlur = 14;
    ctx.strokeRect(r.rx - 1, r.ry - 1, r.cs + 2, r.cs + 2);
    ctx.restore();
  }

  function hitTest(clientX, clientY) {
    if (!renderState) return -1;
    const rect = canvas.getBoundingClientRect();
    const x = clientX - rect.left;
    const y = clientY - rect.top;
    const { rects } = renderState;
    // Reverse iterate so the top-painted (later index) wins.
    for (let i = rects.length - 1; i >= 0; i--) {
      const r = rects[i];
      if (x >= r.rx && x < r.rx + r.cs && y >= r.ry && y < r.ry + r.cs) return i;
    }
    return -1;
  }

  let activeIndex = -1;
  function showTooltipFor(i, clientX, clientY) {
    if (!tooltipEl || !renderState) return;
    if (i < 0) { tooltipEl.style.opacity = "0"; tooltipEl.style.pointerEvents = "none"; return; }
    const px = renderState.pixels[i];
    const ordinal = `Grain ${i + 1} of ${renderState.pixels.length}`;
    let dateLine = "Earned: —";
    if (px.earnedAt) {
      dateLine = `Earned: ${px.earnedAt.toLocaleString(undefined, {
        month: "short", day: "numeric", year: "numeric",
        hour: "numeric", minute: "2-digit",
      })}`;
    }
    tooltipEl.textContent = "";
    const t1 = document.createElement("div");
    t1.style.fontWeight = "800";
    t1.style.fontSize = "13px";
    t1.textContent = ordinal;
    const t2 = document.createElement("div");
    t2.style.fontSize = "11px";
    t2.style.opacity = "0.7";
    t2.textContent = dateLine;
    tooltipEl.appendChild(t1);
    tooltipEl.appendChild(t2);

    tooltipEl.style.opacity = "1";
    tooltipEl.style.pointerEvents = "none";
    // Position near cursor, clamp inside viewport.
    const pad = 14;
    const rect = canvas.getBoundingClientRect();
    let left = clientX - rect.left + pad;
    let top = clientY - rect.top + pad;
    tooltipEl.style.left = `${left}px`;
    tooltipEl.style.top = `${top}px`;
  }

  function attachHandlers() {
    canvas.addEventListener("mousemove", (e) => {
      if (!renderState) return;
      const i = hitTest(e.clientX, e.clientY);
      if (i !== activeIndex) {
        activeIndex = i;
        // Redraw all pixels then highlight (cheap — a few thousand rects).
        render(renderState.pixels);
        if (i >= 0) highlight(i);
      }
      showTooltipFor(i, e.clientX, e.clientY);
      canvas.style.cursor = i >= 0 ? "pointer" : "default";
    });
    canvas.addEventListener("mouseleave", () => {
      activeIndex = -1;
      if (renderState) render(renderState.pixels);
      if (tooltipEl) tooltipEl.style.opacity = "0";
      canvas.style.cursor = "default";
    });
    canvas.addEventListener("click", (e) => {
      const i = hitTest(e.clientX, e.clientY);
      if (i < 0) return;
      activeIndex = i;
      render(renderState.pixels);
      highlight(i);
      showTooltipFor(i, e.clientX, e.clientY);
    });
  }

  function setIdentity({ author, rockName }) {
    if (titleEl) {
      if (rockName && author) {
        titleEl.textContent = `“${rockName}” — by ${author}`;
      } else if (rockName) {
        titleEl.textContent = `“${rockName}”`;
      } else if (author) {
        titleEl.textContent = `${author}’s rock`;
      } else {
        titleEl.textContent = "Someone grew this rock.";
      }
    }
    if (bylineEl) {
      bylineEl.textContent = author
        ? `Grown one grain at a time, five focused minutes each.`
        : `One grain per five minutes of focus. No streaks. No death. Just a rock that grows.`;
    }
  }

  try {
    const payload = readPayload();
    setIdentity(readMetadata());
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
    meta.textContent = `${pixels.length} grains · ${Math.round(pixels.length * 5)} focused minutes`;
    render(pixels);
    attachHandlers();
    window.addEventListener("resize", () => render(pixels));
  } catch (e) {
    console.error(e);
    meta.textContent = "Couldn't read this rock 😕";
  }
})();
