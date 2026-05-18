// Boulder — web port.
//
// Same model as the macOS Swift app. Reads/writes the same Supabase
// `boulders` row keyed by sync_id. Anyone with the sync_id can edit;
// pairing is "I scanned your QR and now I have your sync_id."

const SUPABASE_URL = "https://ujkvqwkdtcwnxueitepm.supabase.co";
const SUPABASE_ANON = "sb_publishable_NLjbb-i-mzAcO6G2h5zl6w_caxZ3kiY";
const TABLE = "boulders";

const PIXELS_PER_SECOND = 1.0 / 300.0;          // 1 grain per 5 min
const SCHEMA_VERSION = 3;

const DEFAULT_TAGS = [
  { id: crypto.randomUUID(), name: "Code",    emoji: "💻", hue: 0.62 },
  { id: crypto.randomUUID(), name: "Write",   emoji: "✏️", hue: 0.09 },
  { id: crypto.randomUUID(), name: "Read",    emoji: "📖", hue: 0.13 },
  { id: crypto.randomUUID(), name: "Design",  emoji: "🎨", hue: 0.78 },
  { id: crypto.randomUUID(), name: "Study",   emoji: "🧠", hue: 0.36 },
];

const STORAGE_KEY = "boulder.model.v1";

function emptyModel() {
  return {
    schemaVersion: SCHEMA_VERSION,
    id: crypto.randomUUID(),
    startedAt: nowSec(),
    pixels: [],
    pixelAccumulator: 0,
    tags: structuredClone(DEFAULT_TAGS),
    sessions: [],
    userFirstName: null,
    rockName: null,
    syncID: null,
    cloudSyncEnabled: true,
  };
}
function nowSec() { return Math.floor(Date.now() / 1000); }
function readLocal() {
  try {
    const s = localStorage.getItem(STORAGE_KEY);
    if (!s) return null;
    const m = JSON.parse(s);
    return { ...emptyModel(), ...m, tags: (m.tags && m.tags.length) ? m.tags : structuredClone(DEFAULT_TAGS) };
  } catch { return null; }
}
function writeLocal(model) {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(model));
}
function isUUID(s) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(s);
}

let model = readLocal() || emptyModel();
if (!model.syncID) {
  model.syncID = crypto.randomUUID();
  writeLocal(model);
}

// QR-pairing path: ?sync=<uuid> or #sync=<uuid>
(function applyURLPairing() {
  const hashParams = new URLSearchParams(window.location.hash.replace(/^#/, ""));
  const search = new URLSearchParams(window.location.search);
  const remote = hashParams.get("sync") || search.get("sync");
  if (remote && isUUID(remote) && remote !== model.syncID) {
    model.syncID = remote;
    model.pixels = [];
    writeLocal(model);
    history.replaceState(null, "", window.location.pathname);
  }
})();

// ---------------- Supabase sync ----------------

let lastPushAt = 0;
let pushTimer = null;
let lastPulledUpdatedAt = null;

async function syncPull() {
  if (!model.syncID) return;
  setStatus("syncing");
  try {
    const url = `${SUPABASE_URL}/rest/v1/${TABLE}?sync_id=eq.${encodeURIComponent(model.syncID.toLowerCase())}&select=payload,updated_at&limit=1`;
    const res = await fetch(url, {
      headers: { apikey: SUPABASE_ANON, Authorization: `Bearer ${SUPABASE_ANON}` },
    });
    if (!res.ok) { setStatus("error"); return; }
    const rows = await res.json();
    if (!rows.length) { setStatus("synced"); return; }
    const row = rows[0];
    if (lastPulledUpdatedAt && row.updated_at === lastPulledUpdatedAt) {
      setStatus("synced");
      return;
    }
    lastPulledUpdatedAt = row.updated_at;
    const remote = row.payload;
    if (remote && Array.isArray(remote.pixels) && remote.pixels.length >= model.pixels.length) {
      const syncID = model.syncID;
      model = { ...emptyModel(), ...remote, syncID, cloudSyncEnabled: true };
      writeLocal(model);
      renderAll();
    }
    setStatus("synced");
  } catch {
    setStatus("error");
  }
}

function schedulePush() {
  if (pushTimer) clearTimeout(pushTimer);
  const delay = Math.max(0, 4000 - (Date.now() - lastPushAt));
  pushTimer = setTimeout(syncPush, delay);
}

async function syncPush() {
  if (!model.syncID) return;
  setStatus("syncing");
  try {
    const row = {
      sync_id: model.syncID.toLowerCase(),
      payload: model,
      user_first_name: model.userFirstName,
      rock_name: model.rockName,
      grain_count: model.pixels.length,
      schema_version: model.schemaVersion,
    };
    const res = await fetch(`${SUPABASE_URL}/rest/v1/${TABLE}?on_conflict=sync_id`, {
      method: "POST",
      headers: {
        apikey: SUPABASE_ANON,
        Authorization: `Bearer ${SUPABASE_ANON}`,
        "Content-Type": "application/json",
        Prefer: "resolution=merge-duplicates,return=minimal",
      },
      body: JSON.stringify(row),
    });
    if (!res.ok) { setStatus("error"); return; }
    lastPushAt = Date.now();
    setStatus("synced");
  } catch {
    setStatus("error");
  }
}

function setStatus(s) {
  const el = document.getElementById("sync-status");
  el.className = "sync-status " + s;
  el.textContent = s;
}

// ---------------- Renderer ----------------

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
function paletteFor(hue) {
  const out = [];
  for (let i = 0; i < 20; i++) {
    const t = i / 19;
    const b = 0.15 + 0.70 * Math.pow(t, 0.95);
    const s = 0.08 + 0.22 * Math.sin(Math.PI * t);
    out.push(hsvToRgb(hue, s, b));
  }
  return out;
}
const NEUTRAL_PALETTE = (() => {
  const out = [];
  for (let i = 0; i < 20; i++) {
    const t = i / 19;
    const v = 0.18 + 0.62 * Math.pow(t, 0.95);
    const c = Math.round(v * 255);
    out.push(`rgb(${c},${c},${c})`);
  }
  return out;
})();
const paletteCache = new Map();
function tagPalette(tag) {
  if (!tag) return NEUTRAL_PALETTE;
  const key = Math.round(tag.hue * 255);
  let p = paletteCache.get(key);
  if (!p) { p = paletteFor(tag.hue); paletteCache.set(key, p); }
  return p;
}

// Dense silhouette packer — mirrors BoulderShape.swift.
const ALL_CELLS = (() => {
  function rand01(x, y, seed) {
    const xu = (x | 0) >>> 0;
    const yu = (y | 0) >>> 0;
    const h = ((xu * 374761393) ^ (yu * 668265263) ^ (seed * 982451653)) >>> 0;
    return (h % 100000) / 100000;
  }
  const maxN = 5600, aspect = 1.55;
  const B = Math.ceil(Math.sqrt((2 * maxN) / (Math.PI * aspect)));
  const A = aspect * B;
  const Bmax = Math.floor(B);
  const yStretch = 1.85;
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
      const nFine = (rand01(x, y, 33) - 0.5) * 1.2;
      s += nFine;
      const topness = Math.max(0, (yNorm - 0.70) / 0.30);
      const leftness = Math.max(0, (-x / Math.max(1, halfWidth) - 0.10) / 0.55);
      s += topness * leftness * 2.8;
      let shade = Math.max(0, Math.min(19, Math.round(s)));
      const dx = x, dy = y * yStretch;
      const dist = Math.sqrt(dx * dx + dy * dy);
      raw.push({ x, y, shade, dist });
    }
  }
  raw.sort((a, b) => a.dist - b.dist || a.y - b.y || a.x - b.x);
  return raw.slice(0, maxN);
})();

function tagByID(id) {
  return model.tags.find((t) => t.id === id);
}

function renderRock() {
  const canvas = document.getElementById("rock");
  const wrap = canvas.parentElement;
  const empty = document.getElementById("empty-state");
  const width = wrap.clientWidth;
  const height = wrap.clientHeight;
  const dpr = window.devicePixelRatio || 1;
  canvas.width = Math.round(width * dpr);
  canvas.height = Math.round(height * dpr);
  canvas.style.width = `${width}px`;
  canvas.style.height = `${height}px`;
  const ctx = canvas.getContext("2d");
  ctx.imageSmoothingEnabled = false;
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  ctx.clearRect(0, 0, width, height);

  if (model.pixels.length === 0) {
    empty.hidden = false;
    return;
  }
  empty.hidden = true;

  let maxAbsX = 0, maxY = 0;
  for (const p of model.pixels) {
    if (Math.abs(p.x) > maxAbsX) maxAbsX = Math.abs(p.x);
    if (p.y > maxY) maxY = p.y;
  }
  const cellW = (width - 40) / (maxAbsX * 2 + 1);
  const cellH = (height - 50) / (maxY + 1);
  const cs = Math.max(2, Math.floor(Math.min(cellW, cellH)));
  const halfCell = Math.floor(cs / 2);
  const cx = Math.round(width / 2);
  const baselineY = Math.round(height - 24);

  const shadowW = (maxAbsX + 1) * cs * 2 * 1.1;
  const shadowH = Math.max(cs * 1.4, cs * 2.2);
  ctx.fillStyle = "rgba(0,0,0,0.28)";
  ctx.beginPath();
  ctx.ellipse(cx, baselineY - shadowH * 0.30 + shadowH / 2, shadowW / 2, shadowH / 2, 0, 0, Math.PI * 2);
  ctx.fill();

  for (const px of model.pixels) {
    const tag = px.tagID ? tagByID(px.tagID) : null;
    const pal = tagPalette(tag);
    const shade = Math.max(0, Math.min(pal.length - 1, px.shade));
    ctx.fillStyle = pal[shade];
    ctx.fillRect(cx + px.x * cs - halfCell, baselineY - px.y * cs - cs, cs, cs);
  }

  ctx.fillStyle = "rgba(255,255,255,0.15)";
  ctx.fillRect(20, baselineY, width - 40, 1);
}

// ---------------- Tier / HUD ----------------

function tierFor(count) {
  if (count < 60)   return { name: "Pebble",   next: "Stone",    needed: 60 - count };
  if (count < 300)  return { name: "Stone",    next: "Rock",     needed: 300 - count };
  if (count < 1200) return { name: "Rock",     next: "Boulder",  needed: 1200 - count };
  if (count < 5000) return { name: "Boulder",  next: "Mountain", needed: 5000 - count };
  return { name: "Mountain", next: "—", needed: 0 };
}

function renderHUD() {
  const tier = tierFor(model.pixels.length);
  document.getElementById("tier-name").textContent = tier.name;
  document.getElementById("tier-sub").textContent =
    tier.needed > 0 ? `${tier.needed} grains to ${tier.next}` : "Mountain reached";
  document.getElementById("grain-count").textContent =
    `${model.pixels.length} grain${model.pixels.length === 1 ? "" : "s"}`;
}

function renderTags() {
  const row = document.getElementById("tag-row");
  row.textContent = "";   // clear safely
  for (const t of model.tags) {
    const el = document.createElement("button");
    el.className = "tag" + (t.id === selectedTagID ? " active" : "");
    el.dataset.id = t.id;
    const emoji = document.createElement("span");
    emoji.className = "tag-emoji";
    emoji.textContent = t.emoji;
    const name = document.createElement("span");
    name.textContent = t.name;
    el.appendChild(emoji);
    el.appendChild(name);
    el.addEventListener("click", () => {
      selectedTagID = t.id;
      renderTags();
    });
    row.appendChild(el);
  }
}

function renderActionRow() {
  const row = document.getElementById("action-row");
  const claim = document.getElementById("claim-btn");
  const claimLabel = document.getElementById("claim-label");
  const share = document.getElementById("share-btn");
  if (model.pixels.length === 0 && pendingCount === 0) {
    row.hidden = true;
    return;
  }
  row.hidden = false;
  if (pendingCount > 0 && !isFocusing) {
    claim.hidden = false;
    claimLabel.textContent = `Claim ${pendingCount} grain${pendingCount === 1 ? "" : "s"}`;
    share.classList.add("compact");
    document.querySelector(".btn-share-label").textContent = "";
  } else {
    claim.hidden = true;
    share.classList.remove("compact");
    document.querySelector(".btn-share-label").textContent = "Share";
  }
}

function renderAll() {
  renderHUD();
  renderRock();
  renderTags();
  renderActionRow();
}

// ---------------- Focus session ----------------

let isFocusing = false;
let pendingCount = 0;
let plannedSeconds = null;
let elapsed = 0;
let selectedTagID = model.tags[0]?.id || null;
let currentSessionID = null;

function startFocus() {
  if (isFocusing) {
    stopFocus();
    return;
  }
  if (!selectedTagID) return;
  isFocusing = true;
  elapsed = 0;
  currentSessionID = crypto.randomUUID();
  model.sessions.push({
    id: currentSessionID,
    tagID: selectedTagID,
    blurb: document.getElementById("blurb").value,
    startedAt: nowSec(),
    plannedDuration: plannedSeconds,
    committed: !!plannedSeconds,
  });
  const btn = document.getElementById("focus-btn");
  btn.classList.add("focusing");
  btn.textContent = plannedSeconds ? "Give up" : "Stop";
}
function stopFocus() {
  isFocusing = false;
  if (currentSessionID) {
    const s = model.sessions.find((x) => x.id === currentSessionID);
    if (s) s.endedAt = nowSec();
    currentSessionID = null;
  }
  const btn = document.getElementById("focus-btn");
  btn.classList.remove("focusing");
  btn.textContent = "Focus";
  writeLocal(model);
  renderActionRow();
}

function tick() {
  if (!isFocusing) return;
  model.pixelAccumulator += PIXELS_PER_SECOND;
  while (model.pixelAccumulator >= 1.0) {
    model.pixelAccumulator -= 1.0;
    pendingCount += 1;
  }
  elapsed += 1;
  updateTimer();
  if (plannedSeconds !== null && elapsed >= plannedSeconds) {
    stopFocus();
  }
  renderActionRow();
}

function updateTimer() {
  let secs;
  if (isFocusing) {
    secs = plannedSeconds !== null ? Math.max(0, plannedSeconds - elapsed) : elapsed;
  } else {
    secs = plannedSeconds !== null ? plannedSeconds : 0;
  }
  const h = Math.floor(secs / 3600), m = Math.floor((secs % 3600) / 60), s = secs % 60;
  document.getElementById("timer-text").textContent =
    h > 0 ? `${h}:${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`
          : `${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`;
}

function claimGrains() {
  const count = pendingCount;
  pendingCount = 0;
  if (count <= 0) return;
  const sid = currentSessionID || (model.sessions[model.sessions.length - 1]?.id);
  for (let i = 0; i < count; i++) {
    const idx = model.pixels.length;
    if (idx >= ALL_CELLS.length) break;
    const cell = ALL_CELLS[idx];
    model.pixels.push({
      x: cell.x, y: cell.y, shade: cell.shade,
      tagID: selectedTagID, sessionID: sid,
      earnedAt: nowSec(),
    });
  }
  writeLocal(model);
  schedulePush();
  renderAll();
}

// ---------------- Share ----------------

function shareRock() {
  const url = buildShareURL();
  if (navigator.share && /mobile|iphone|android|ipad/i.test(navigator.userAgent)) {
    navigator.share({ url, title: "My Boulder" }).catch(() => copyShareURL(url));
  } else {
    copyShareURL(url);
  }
}
function copyShareURL(url) {
  navigator.clipboard.writeText(url).then(
    () => flashStatus("link copied!"),
    () => flashStatus("couldn't copy")
  );
}
function flashStatus(msg) {
  const el = document.getElementById("sync-status");
  const orig = el.className;
  const text = el.textContent;
  el.textContent = msg;
  setTimeout(() => { el.textContent = text; el.className = orig; }, 1800);
}

function buildShareURL() {
  const bytes = [2];
  const n = model.pixels.length;
  bytes.push(n & 0xff, (n >> 8) & 0xff, (n >> 16) & 0xff, (n >>> 24) & 0xff);
  const hueByID = Object.fromEntries(model.tags.map((t) => [t.id, t.hue]));
  for (const p of model.pixels) {
    bytes.push(p.x & 0xff, p.y & 0xff);
    const hue = p.tagID && hueByID[p.tagID] != null ? hueByID[p.tagID] : null;
    bytes.push(hue == null ? 0xff : Math.max(0, Math.min(254, Math.round(hue * 255))));
    bytes.push(Math.max(0, Math.min(255, p.shade | 0)));
    const ts = p.earnedAt || 0;
    bytes.push(ts & 0xff, (ts >> 8) & 0xff, (ts >> 16) & 0xff, (ts >>> 24) & 0xff);
  }
  const u8 = new Uint8Array(bytes);
  let bin = "";
  for (const b of u8) bin += String.fromCharCode(b);
  let b64 = btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  const qs = [];
  if (model.userFirstName) qs.push("by=" + encodeURIComponent(model.userFirstName));
  if (model.rockName) qs.push("name=" + encodeURIComponent(model.rockName));
  const query = qs.length ? "?" + qs.join("&") : "";
  return `${window.location.origin}/r/${query}#${b64}`;
}

// ---------------- Onboarding ----------------

function maybeShowOnboarding() {
  document.getElementById("onboarding").hidden = !!model.userFirstName;
}
function bindOnboarding() {
  const nameInput = document.getElementById("onb-name");
  const rockInput = document.getElementById("onb-rock");
  const startBtn = document.getElementById("onb-start");
  nameInput.addEventListener("input", () => {
    startBtn.disabled = nameInput.value.trim().length === 0;
  });
  startBtn.addEventListener("click", () => {
    const n = nameInput.value.trim();
    if (!n) return;
    model.userFirstName = n;
    const r = rockInput.value.trim();
    model.rockName = r || null;
    writeLocal(model);
    schedulePush();
    document.getElementById("onboarding").hidden = true;
    renderAll();
  });
}

// ---------------- Settings sheet ----------------

function bindSettings() {
  const sheet = document.getElementById("settings-sheet");
  document.getElementById("settings-toggle").addEventListener("click", () => {
    sheet.hidden = false;
    document.getElementById("set-name").value = model.userFirstName || "";
    document.getElementById("set-rock").value = model.rockName || "";
    document.getElementById("sync-id-text").textContent = model.syncID || "—";
  });
  document.getElementById("settings-close").addEventListener("click", () => { sheet.hidden = true; });
  sheet.addEventListener("click", (e) => { if (e.target === sheet) sheet.hidden = true; });
  document.getElementById("set-name").addEventListener("input", (e) => {
    model.userFirstName = e.target.value.trim() || null;
    writeLocal(model); schedulePush();
  });
  document.getElementById("set-rock").addEventListener("input", (e) => {
    model.rockName = e.target.value.trim() || null;
    writeLocal(model); schedulePush();
  });
  document.getElementById("copy-sync-id").addEventListener("click", () => {
    if (!model.syncID) return;
    navigator.clipboard.writeText(model.syncID).then(() => flashStatus("copied"));
  });
  document.getElementById("reset-btn").addEventListener("click", () => {
    if (!confirm("Forget this device? Your rock stays in the cloud — paste your sync ID back to recover it.")) return;
    localStorage.removeItem(STORAGE_KEY);
    location.reload();
  });
}

// ---------------- Boot ----------------

function bindFocusUI() {
  document.querySelectorAll(".chip").forEach((c) => {
    c.addEventListener("click", () => {
      document.querySelectorAll(".chip").forEach((x) => x.classList.remove("active"));
      c.classList.add("active");
      const m = c.dataset.mins;
      plannedSeconds = m ? parseInt(m, 10) * 60 : null;
      updateTimer();
    });
  });
  document.getElementById("focus-btn").addEventListener("click", startFocus);
  document.getElementById("claim-btn").addEventListener("click", claimGrains);
  document.getElementById("share-btn").addEventListener("click", shareRock);
}

maybeShowOnboarding();
bindOnboarding();
bindSettings();
bindFocusUI();
renderAll();
updateTimer();

setInterval(tick, 1000);
syncPull();
setInterval(syncPull, 30000);
document.addEventListener("visibilitychange", () => {
  if (document.hidden) { writeLocal(model); schedulePush(); }
});
window.addEventListener("beforeunload", () => writeLocal(model));
window.addEventListener("resize", renderRock);
