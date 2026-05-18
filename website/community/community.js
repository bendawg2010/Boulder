// Community rock renderer.
//
// Fetches all community grains from /api/community, packs them into
// the same dense-silhouette algorithm as the per-user rock, and lets
// you hover/tap any pixel to see who was focusing on what.

const API_URL = "/api/community";

const canvas = document.getElementById("community-canvas");
const ctx = canvas.getContext("2d");
const meta = document.getElementById("community-meta");
const tooltip = document.getElementById("community-tooltip");

// ---- Palette ----
function hsvToRgb(h, s, v) {
  h = ((h % 1) + 1) % 1;
  const i = Math.floor(h * 6), f = h * 6 - i;
  const p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s);
  let r = 0, g = 0, b = 0;
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
const paletteCache = new Map();
function paletteFor(hue) {
  const key = Math.round(hue * 255);
  let p = paletteCache.get(key);
  if (p) return p;
  p = new Array(20);
  for (let i = 0; i < 20; i++) {
    const t = i / 19;
    const b = 0.15 + 0.70 * Math.pow(t, 0.95);
    const s = 0.08 + 0.22 * Math.sin(Math.PI * t);
    p[i] = hsvToRgb(hue, s, b);
  }
  paletteCache.set(key, p);
  return p;
}

// ---- Silhouette packer (same as the personal rock) ----
const ALL_CELLS = (() => {
  function rand01(x, y, seed) {
    const xu = (x | 0) >>> 0;
    const yu = (y | 0) >>> 0;
    const h = ((xu * 374761393) ^ (yu * 668265263) ^ (seed * 982451653)) >>> 0;
    return (h % 100000) / 100000;
  }
  const maxN = 50000, aspect = 1.55;
  const B = Math.ceil(Math.sqrt((2 * maxN) / (Math.PI * aspect)));
  const A = aspect * B;
  const Bmax = Math.floor(B);
  const halfWidths = [];
  for (let y = 0; y <= Bmax; y++) {
    const yNorm = y / B;
    const baseHalf = A * Math.sqrt(Math.max(0, 1 - yNorm * yNorm));
    const wob = 1.0 + 0.045 * Math.sin(y * 0.85) + 0.030 * Math.cos(y * 1.40 + 1.2) + 0.022 * Math.sin(y * 2.30 + 0.7);
    halfWidths.push(Math.max(0, Math.floor(baseHalf * wob)));
  }
  const raw = [];
  for (let y = 0; y <= Bmax; y++) {
    const halfWidth = halfWidths[y];
    if (halfWidth <= 0) continue;
    const yNorm = y / B;
    for (let x = -halfWidth; x <= halfWidth; x++) {
      const xNorm = Math.abs(x) / Math.max(1, halfWidth);
      let s = 4 + yNorm * 13 - xNorm * xNorm * 4.0;
      if (x > 0) s -= (x / halfWidth) * 0.8;
      const edgeDist = halfWidth - Math.abs(x);
      if (edgeDist < 1.5) s -= (1.5 - edgeDist) * 1.2;
      s += (rand01(x, y, 33) - 0.5) * 1.2;
      const topness = Math.max(0, (yNorm - 0.70) / 0.30);
      const leftness = Math.max(0, (-x / Math.max(1, halfWidth) - 0.10) / 0.55);
      s += topness * leftness * 2.8;
      const shade = Math.max(0, Math.min(19, Math.round(s)));
      const dist = Math.sqrt(x * x + (y * 1.85) * (y * 1.85));
      raw.push({ x, y, shade, dist });
    }
  }
  raw.sort((a, b) => a.dist - b.dist || a.y - b.y || a.x - b.x);
  return raw.slice(0, maxN);
})();

// ---- Render ----
let grains = [];
let totalCount = 0;
let renderState = null;

function render() {
  const wrap = canvas.parentElement;
  const width = wrap.clientWidth - 48; // subtract padding
  const height = Math.max(360, Math.floor(width * 0.66));
  const dpr = window.devicePixelRatio || 1;
  canvas.width = Math.round(width * dpr);
  canvas.height = Math.round(height * dpr);
  canvas.style.width = `${width}px`;
  canvas.style.height = `${height}px`;
  ctx.imageSmoothingEnabled = false;
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  ctx.clearRect(0, 0, width, height);

  if (grains.length === 0) { renderState = null; return; }

  const count = Math.min(grains.length, ALL_CELLS.length);
  let maxAbsX = 0, maxY = 0;
  for (let i = 0; i < count; i++) {
    const c = ALL_CELLS[i];
    if (Math.abs(c.x) > maxAbsX) maxAbsX = Math.abs(c.x);
    if (c.y > maxY) maxY = c.y;
  }
  const cellW = (width - 40) / (maxAbsX * 2 + 1);
  const cellH = (height - 60) / (maxY + 1);
  const cs = Math.max(2, Math.floor(Math.min(cellW, cellH)));
  const halfCell = Math.floor(cs / 2);
  const cx = Math.round(width / 2);
  const baselineY = Math.round(height - 32);

  // Cast shadow.
  const shadowW = (maxAbsX + 1) * cs * 2 * 1.1;
  const shadowH = Math.max(cs * 1.4, cs * 2.2);
  ctx.fillStyle = "rgba(0,0,0,0.28)";
  ctx.beginPath();
  ctx.ellipse(cx, baselineY - shadowH * 0.30 + shadowH / 2, shadowW / 2, shadowH / 2, 0, 0, Math.PI * 2);
  ctx.fill();

  const rects = new Array(count);
  for (let i = 0; i < count; i++) {
    const cell = ALL_CELLS[i];
    const grain = grains[i];
    const pal = paletteFor(grain.hue);
    const shade = Math.max(0, Math.min(pal.length - 1, grain.shade));
    const rx = cx + cell.x * cs - halfCell;
    const ry = baselineY - cell.y * cs - cs;
    rects[i] = { rx, ry, cs };
    ctx.fillStyle = pal[shade];
    ctx.fillRect(rx, ry, cs, cs);
  }
  ctx.fillStyle = "rgba(255,255,255,0.15)";
  ctx.fillRect(20, baselineY, width - 40, 1);

  renderState = { width, height, rects, cs };
}

function hitTest(clientX, clientY) {
  if (!renderState) return -1;
  const rect = canvas.getBoundingClientRect();
  const x = clientX - rect.left;
  const y = clientY - rect.top;
  const { rects } = renderState;
  for (let i = rects.length - 1; i >= 0; i--) {
    const r = rects[i];
    if (x >= r.rx && x < r.rx + r.cs && y >= r.ry && y < r.ry + r.cs) return i;
  }
  return -1;
}

function showTooltipFor(i, clientX, clientY) {
  if (i < 0 || !grains[i]) {
    tooltip.style.opacity = "0";
    return;
  }
  const g = grains[i];
  tooltip.textContent = "";
  const titleRow = document.createElement("div");
  titleRow.className = "row-title";
  titleRow.textContent = `${g.contributor_name}`;
  const tagRow = document.createElement("div");
  tagRow.className = "row-tag";
  tagRow.textContent = `${g.tag_emoji} ${g.tag_name}`;
  tooltip.appendChild(titleRow);
  tooltip.appendChild(tagRow);
  if (g.blurb) {
    const blurbRow = document.createElement("div");
    blurbRow.className = "row-blurb";
    blurbRow.textContent = `"${g.blurb}"`;
    tooltip.appendChild(blurbRow);
  }
  const whenRow = document.createElement("div");
  whenRow.className = "row-when";
  whenRow.textContent = new Date(g.earned_at * 1000).toLocaleString(undefined, {
    month: "short", day: "numeric", year: "numeric", hour: "numeric", minute: "2-digit",
  });
  tooltip.appendChild(whenRow);

  tooltip.style.opacity = "1";
  const rect = canvas.parentElement.getBoundingClientRect();
  const x = Math.min(clientX - rect.left + 14, rect.width - tooltip.offsetWidth - 8);
  const y = Math.min(clientY - rect.top + 14, rect.height - tooltip.offsetHeight - 8);
  tooltip.style.left = `${x}px`;
  tooltip.style.top = `${y}px`;
}

let activeIdx = -1;
canvas.addEventListener("mousemove", (e) => {
  const i = hitTest(e.clientX, e.clientY);
  if (i !== activeIdx) activeIdx = i;
  showTooltipFor(i, e.clientX, e.clientY);
  canvas.style.cursor = i >= 0 ? "pointer" : "default";
});
canvas.addEventListener("mouseleave", () => {
  tooltip.style.opacity = "0";
});
canvas.addEventListener("click", (e) => {
  const i = hitTest(e.clientX, e.clientY);
  showTooltipFor(i, e.clientX, e.clientY);
});

async function load() {
  try {
    const res = await fetch(`${API_URL}?limit=5000`);
    if (!res.ok) { meta.textContent = "Couldn't load community rock"; return; }
    const body = await res.json();
    grains = body.grains || [];
    totalCount = body.total || 0;
    const focusedHours = Math.round(totalCount * 5 / 60);
    meta.textContent = grains.length === 0
      ? "Be the first to add a grain"
      : `${totalCount.toLocaleString()} grains · ${focusedHours.toLocaleString()} focused hours`;
    render();
  } catch (e) {
    meta.textContent = "Couldn't reach the server";
  }
}

window.addEventListener("resize", render);
load();
setInterval(load, 60_000);
