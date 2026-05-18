// Group rock viewer. URL form: /g/<INVITE_CODE>
// Resolves code → group id → grains, then renders + lets you hover/tap.

const path = window.location.pathname.replace(/^\/+/, "").split("/");
const code = (path[1] || "").toUpperCase().trim();

const canvas = document.getElementById("group-canvas");
const ctx = canvas.getContext("2d");
const meta = document.getElementById("group-meta");
const nameEl = document.getElementById("group-name");
const invitePill = document.getElementById("invite-pill");
const tooltip = document.getElementById("group-tooltip");

let grains = [];
let groupID = null;
let renderState = null;

// ---- Palette (same as community/share) ----
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
  return `rgb(${Math.round(r*255)},${Math.round(g*255)},${Math.round(b*255)})`;
}
const paletteCache = new Map();
function paletteFor(hue) {
  const key = Math.round(hue * 255);
  let p = paletteCache.get(key); if (p) return p;
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

// ---- Silhouette packer (50K cells) ----
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

function render() {
  const wrap = canvas.parentElement;
  const width = wrap.clientWidth - 48;
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

  renderState = { rects };
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
function showTooltipFor(i, cx, cy) {
  if (i < 0 || !grains[i]) { tooltip.style.opacity = "0"; return; }
  const g = grains[i];
  tooltip.textContent = "";
  const t1 = document.createElement("div"); t1.className = "row-title"; t1.textContent = g.contributor_name;
  const t2 = document.createElement("div"); t2.className = "row-tag"; t2.textContent = `${g.tag_emoji} ${g.tag_name}`;
  tooltip.appendChild(t1); tooltip.appendChild(t2);
  if (g.blurb) {
    const t3 = document.createElement("div"); t3.className = "row-blurb"; t3.textContent = `"${g.blurb}"`;
    tooltip.appendChild(t3);
  }
  const t4 = document.createElement("div"); t4.className = "row-when";
  t4.textContent = new Date(g.earned_at * 1000).toLocaleString(undefined, {
    month: "short", day: "numeric", year: "numeric", hour: "numeric", minute: "2-digit",
  });
  tooltip.appendChild(t4);
  tooltip.style.opacity = "1";
  const rect = canvas.parentElement.getBoundingClientRect();
  const x = Math.min(cx - rect.left + 14, rect.width - tooltip.offsetWidth - 8);
  const y = Math.min(cy - rect.top + 14, rect.height - tooltip.offsetHeight - 8);
  tooltip.style.left = `${x}px`;
  tooltip.style.top = `${y}px`;
}

canvas.addEventListener("mousemove", (e) => { showTooltipFor(hitTest(e.clientX, e.clientY), e.clientX, e.clientY); });
canvas.addEventListener("mouseleave", () => { tooltip.style.opacity = "0"; });
canvas.addEventListener("click", (e) => { showTooltipFor(hitTest(e.clientX, e.clientY), e.clientX, e.clientY); });
window.addEventListener("resize", render);

async function load() {
  if (!/^[A-Z2-9]{6}$/.test(code)) {
    meta.textContent = "invalid code";
    nameEl.textContent = "?";
    return;
  }
  try {
    const lookupRes = await fetch(`/api/groups?code=${encodeURIComponent(code)}`);
    if (lookupRes.status === 404) {
      meta.textContent = "code not found";
      nameEl.textContent = "?";
      return;
    }
    const lookup = await lookupRes.json();
    if (!lookup.group) return;
    groupID = lookup.group.id;
    nameEl.textContent = lookup.group.name;
    invitePill.textContent = lookup.group.invite_code;

    const grainsRes = await fetch(`/api/groups/${encodeURIComponent(groupID)}/grains?limit=20000`);
    const body = await grainsRes.json();
    grains = body.grains || [];
    const total = body.total ?? grains.length;
    const focusedHours = Math.round(total * 5 / 60);
    meta.textContent = total === 0
      ? "Be the first to add a grain"
      : `${total.toLocaleString()} grains · ${focusedHours.toLocaleString()} focused hours`;
    render();
  } catch (e) {
    meta.textContent = "couldn't load";
  }
}

document.getElementById("invite-copy").addEventListener("click", () => {
  navigator.clipboard.writeText(window.location.href).then(() => {
    const b = document.getElementById("invite-copy");
    const orig = b.textContent;
    b.textContent = "Copied!";
    setTimeout(() => { b.textContent = orig; }, 1500);
  });
});

load();
setInterval(load, 60_000);
