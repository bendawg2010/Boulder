// Boulder — web port.
//
// Same model as the macOS Swift app. Reads/writes the same Supabase
// `boulders` row keyed by sync_id. Anyone with the sync_id can edit;
// pairing is "I scanned your QR and now I have your sync_id."

// Same-origin Pages Function backed by Cloudflare D1. The function
// source is at website/functions/api/boulders.ts.
const API_URL = "/api/boulders";

const PIXELS_PER_SECOND = 1.0 / 300.0;          // 1 grain per 5 min
const SCHEMA_VERSION = 3;

const DEFAULT_TAGS = [
  { id: crypto.randomUUID(), name: "Code",    emoji: "💻", hue: 0.62 },
  { id: crypto.randomUUID(), name: "Write",   emoji: "✏️", hue: 0.09 },
  { id: crypto.randomUUID(), name: "Read",    emoji: "📖", hue: 0.13 },
  { id: crypto.randomUUID(), name: "Design",  emoji: "🎨", hue: 0.78 },
  { id: crypto.randomUUID(), name: "Study",   emoji: "🧠", hue: 0.36 },
];

// Mirror of FocusTag.rockPresets in FocusTag.swift — same names + hues
// so the Mac app and the web app pick from the same palette.
const ROCK_PRESETS = [
  { name: "Granite",   hue: 0.62 },
  { name: "Slate",     hue: 0.58 },
  { name: "Basalt",    hue: 0.05 },
  { name: "Sandstone", hue: 0.09 },
  { name: "Limestone", hue: 0.13 },
  { name: "Schist",    hue: 0.25 },
  { name: "Jade",      hue: 0.36 },
  { name: "Marble",    hue: 0.55 },
  { name: "Lapis",     hue: 0.65 },
  { name: "Amethyst",  hue: 0.78 },
  { name: "Quartz",    hue: 0.95 },
  { name: "Hematite",  hue: 0.02 },
];

// Momentum tiers — must match BoulderStore.multiplier(forElapsed:) in Swift.
function momentumFor(elapsedSec) {
  let mult, label;
  if (elapsedSec < 300)        { mult = 1.0;                          label = "Warming up"; }
  else if (elapsedSec < 900)   { mult = lerp(1.0, 1.5, (elapsedSec -  300) /  600); label = "Rolling"; }
  else if (elapsedSec < 1800)  { mult = lerp(1.5, 2.0, (elapsedSec -  900) /  900); label = "Locked in"; }
  else if (elapsedSec < 3600)  { mult = lerp(2.0, 3.0, (elapsedSec - 1800) / 1800); label = "Flow state"; }
  else                          { mult = 3.0;                          label = "Deep flow"; }
  return { mult, label };
}
function lerp(a, b, t) { return a + (b - a) * Math.max(0, Math.min(1, t)); }

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
    contributeToCommunity: false,
    groups: [],   // [{id, name, inviteCode, contributesGrains}]
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
    const res = await fetch(`${API_URL}?sync_id=${encodeURIComponent(model.syncID.toLowerCase())}`);
    if (res.status === 404) { setStatus("synced"); return; }
    if (!res.ok) { setStatus("error"); return; }
    const body = await res.json();
    if (lastPulledUpdatedAt && body.updated_at === lastPulledUpdatedAt) {
      setStatus("synced");
      return;
    }
    lastPulledUpdatedAt = body.updated_at;
    const remote = body.payload;
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
    const res = await fetch(API_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(row),
    });
    if (!res.ok) { setStatus("error"); return; }
    lastPushAt = Date.now();
    setStatus("synced");
  } catch {
    setStatus("error");
  }
}

// Status labels you actually see in the pill — keep them short.
// We avoid the literal word "synced" because users read that as
// "matches my other device" rather than "saved to cloud."
const STATUS_LABEL = {
  syncing: "Saving…",
  synced:  "Saved",
  error:   "Offline",
};
function setStatus(s) {
  const el = document.getElementById("sync-status");
  el.className = "sync-status " + s;
  el.textContent = STATUS_LABEL[s] || s;
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

let tagManageMode = false;
function renderTags() {
  const row = document.getElementById("tag-row");
  row.textContent = "";
  for (const t of model.tags) {
    const el = document.createElement("button");
    el.className = "tag" + (t.id === selectedTagID ? " active" : "");
    el.dataset.id = t.id;
    el.type = "button";
    const emoji = document.createElement("span");
    emoji.className = "tag-emoji";
    emoji.textContent = t.emoji;
    const name = document.createElement("span");
    name.textContent = t.name;
    el.appendChild(emoji);
    el.appendChild(name);
    el.addEventListener("click", () => {
      if (tagManageMode) {
        openTagEditor(t);
      } else {
        selectedTagID = t.id;
        renderTags();
      }
    });
    row.appendChild(el);
  }
  if (tagManageMode) {
    const addBtn = document.createElement("button");
    addBtn.className = "tag tag-add";
    addBtn.type = "button";
    addBtn.textContent = "+ New tag";
    addBtn.addEventListener("click", () => openTagEditor(null));
    row.appendChild(addBtn);
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
  renderMomentum();
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
  const { mult } = momentumFor(elapsed);
  model.pixelAccumulator += PIXELS_PER_SECOND * mult;
  while (model.pixelAccumulator >= 1.0) {
    model.pixelAccumulator -= 1.0;
    pendingCount += 1;
  }
  elapsed += 1;
  updateTimer();
  renderMomentum();
  renderActionRow();
  if (plannedSeconds !== null && elapsed >= plannedSeconds) {
    stopFocus();
  }
}

function renderMomentum() {
  const pill = document.getElementById("momentum-pill");
  const pending = document.getElementById("pending-badge");
  if (!isFocusing) {
    pill.hidden = true;
    pending.hidden = pendingCount === 0;
    if (!pending.hidden) pending.textContent = `+${pendingCount} banked`;
    return;
  }
  const { mult, label } = momentumFor(elapsed);
  document.getElementById("m-tier").textContent = label;
  document.getElementById("m-mult").textContent = `×${mult.toFixed(1)}`;
  pill.hidden = false;
  if (pendingCount > 0) {
    pending.hidden = false;
    pending.textContent = `+${pendingCount} banked`;
  } else {
    pending.hidden = true;
  }
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
  const firstNew = model.pixels.length;
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
  contributeIfEnabled(firstNew);
  renderAll();
}

async function contributeIfEnabled(firstNewIndex) {
  if (!model.syncID || !model.userFirstName) return;
  const newPixels = model.pixels.slice(firstNewIndex);
  if (newPixels.length === 0) return;
  const tagsByID = Object.fromEntries(model.tags.map((t) => [t.id, t]));
  const sessionsByID = Object.fromEntries(model.sessions.map((s) => [s.id, s]));
  const grains = newPixels.map((p) => {
    const tag = p.tagID ? tagsByID[p.tagID] : null;
    if (!tag) return null;
    const blurb = p.sessionID ? sessionsByID[p.sessionID]?.blurb : null;
    return {
      tag_name: tag.name,
      tag_emoji: tag.emoji,
      hue: tag.hue,
      shade: p.shade,
      blurb: blurb || null,
      earned_at: p.earnedAt || nowSec(),
    };
  }).filter(Boolean);
  if (grains.length === 0) return;
  const body = {
    sync_id: model.syncID.toLowerCase(),
    contributor_name: model.userFirstName,
    grains,
  };
  const headers = { "Content-Type": "application/json" };

  // Global Community Rock (opt-in).
  if (model.contributeToCommunity) {
    try {
      await fetch("/api/community", { method: "POST", headers, body: JSON.stringify(body) });
    } catch {/* fire-and-forget */}
  }

  // Group rocks the user has joined (each can be opted out individually).
  for (const g of (model.groups || [])) {
    if (!g.contributesGrains) continue;
    try {
      await fetch(`/api/groups/${encodeURIComponent(g.id)}/grains`, {
        method: "POST", headers, body: JSON.stringify(body),
      });
    } catch {/* fire-and-forget */}
  }
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
  const newForm = document.getElementById("onb-new-form");
  const pairForm = document.getElementById("onb-pair-form");
  const nameInput = document.getElementById("onb-name");
  const rockInput = document.getElementById("onb-rock");
  const startBtn = document.getElementById("onb-start");
  const syncInput = document.getElementById("onb-syncid");
  const pairBtn = document.getElementById("onb-pair-go");
  const pairError = document.getElementById("onb-pair-error");

  nameInput.addEventListener("input", () => {
    startBtn.disabled = nameInput.value.trim().length === 0;
  });
  startBtn.addEventListener("click", () => {
    const n = nameInput.value.trim();
    if (!n) return;
    model.userFirstName = n;
    const r = rockInput.value.trim();
    model.rockName = r || null;
    const contribEl = document.getElementById("onb-contribute");
    model.contributeToCommunity = !!(contribEl && contribEl.checked);
    writeLocal(model);
    schedulePush();
    document.getElementById("onboarding").hidden = true;
    renderAll();
  });

  document.getElementById("onb-show-pair").addEventListener("click", () => {
    newForm.hidden = true;
    pairForm.hidden = false;
    syncInput.focus();
  });
  document.getElementById("onb-show-new").addEventListener("click", () => {
    pairForm.hidden = true;
    newForm.hidden = false;
    pairError.hidden = true;
    nameInput.focus();
  });

  syncInput.addEventListener("input", () => {
    pairError.hidden = true;
    pairBtn.disabled = !isUUID(syncInput.value.trim());
  });
  pairBtn.addEventListener("click", async () => {
    const id = syncInput.value.trim().toLowerCase();
    if (!isUUID(id)) {
      pairError.textContent = "That doesn't look like a sync ID.";
      pairError.hidden = false;
      return;
    }
    pairBtn.disabled = true;
    pairBtn.textContent = "Pulling rock…";
    try {
      const res = await fetch(`${API_URL}?sync_id=${encodeURIComponent(id)}`);
      if (res.status === 404) {
        pairError.textContent = "No rock found for that sync ID.";
        pairError.hidden = false;
        pairBtn.disabled = false;
        pairBtn.textContent = "Pair this device";
        return;
      }
      if (!res.ok) {
        pairError.textContent = "Couldn't reach the server. Try again.";
        pairError.hidden = false;
        pairBtn.disabled = false;
        pairBtn.textContent = "Pair this device";
        return;
      }
      const body = await res.json();
      const remote = body.payload;
      model = { ...emptyModel(), ...remote, syncID: id, cloudSyncEnabled: true };
      writeLocal(model);
      document.getElementById("onboarding").hidden = true;
      renderAll();
    } catch (e) {
      pairError.textContent = "Couldn't reach the server. Try again.";
      pairError.hidden = false;
      pairBtn.disabled = false;
      pairBtn.textContent = "Pair this device";
    }
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
  renderGroups();
  document.getElementById("group-create").addEventListener("click", createGroup);
  document.getElementById("group-join").addEventListener("click", joinGroup);

  const contribToggle = document.getElementById("contribute-toggle");
  if (contribToggle) {
    contribToggle.checked = !!model.contributeToCommunity;
    contribToggle.addEventListener("change", () => {
      model.contributeToCommunity = !!contribToggle.checked;
      writeLocal(model); schedulePush();
    });
  }
  document.getElementById("reset-btn").addEventListener("click", () => {
    if (!confirm("Forget this device? Your rock stays in the cloud — paste your sync ID back to recover it.")) return;
    localStorage.removeItem(STORAGE_KEY);
    location.reload();
  });
}

// ---------------- Boot ----------------

let editingTag = null;        // null = new tag
let editingHue = 0.62;
function openTagEditor(tag) {
  editingTag = tag;
  editingHue = tag ? tag.hue : 0.62;
  document.getElementById("tag-sheet-title").textContent = tag ? "Edit tag" : "New tag";
  document.getElementById("tag-emoji").value = tag ? tag.emoji : "🪨";
  document.getElementById("tag-name").value = tag ? tag.name : "";
  document.getElementById("tag-delete").hidden = !tag;
  renderHueGrid();
  document.getElementById("tag-sheet").hidden = false;
}
function closeTagEditor() {
  document.getElementById("tag-sheet").hidden = true;
  editingTag = null;
}
function renderHueGrid() {
  const grid = document.getElementById("hue-swatch-grid");
  grid.textContent = "";
  for (const preset of ROCK_PRESETS) {
    const sw = document.createElement("button");
    sw.type = "button";
    sw.className = "hue-swatch" + (Math.abs(preset.hue - editingHue) < 0.005 ? " selected" : "");
    sw.style.background = hsvToRgb(preset.hue, 0.50, 0.72);
    sw.title = preset.name;
    const label = document.createElement("span");
    label.className = "hue-swatch-label";
    label.textContent = preset.name;
    sw.appendChild(label);
    sw.addEventListener("click", () => {
      editingHue = preset.hue;
      renderHueGrid();
    });
    grid.appendChild(sw);
  }
}
function bindTagEditor() {
  document.getElementById("manage-tags-btn").addEventListener("click", () => {
    tagManageMode = !tagManageMode;
    document.getElementById("manage-tags-btn").textContent = tagManageMode ? "Done" : "Manage";
    renderTags();
  });
  document.getElementById("tag-close").addEventListener("click", closeTagEditor);
  document.getElementById("tag-cancel").addEventListener("click", closeTagEditor);
  document.getElementById("tag-sheet").addEventListener("click", (e) => {
    if (e.target.id === "tag-sheet") closeTagEditor();
  });
  document.getElementById("tag-save").addEventListener("click", () => {
    const emoji = document.getElementById("tag-emoji").value.trim() || "🪨";
    const name = document.getElementById("tag-name").value.trim() || "Untitled";
    if (editingTag) {
      const idx = model.tags.findIndex((x) => x.id === editingTag.id);
      if (idx >= 0) {
        model.tags[idx] = { ...model.tags[idx], emoji, name, hue: editingHue };
      }
    } else {
      const newTag = { id: crypto.randomUUID(), emoji, name, hue: editingHue };
      model.tags.push(newTag);
      if (!selectedTagID) selectedTagID = newTag.id;
    }
    writeLocal(model);
    schedulePush();
    closeTagEditor();
    renderTags();
    paletteCache.clear();
    renderRock();
  });
  document.getElementById("tag-delete").addEventListener("click", () => {
    if (!editingTag) return;
    if (!confirm(`Delete the "${editingTag.name}" tag? Existing grains stay but become uncolored.`)) return;
    model.tags = model.tags.filter((x) => x.id !== editingTag.id);
    if (selectedTagID === editingTag.id) selectedTagID = model.tags[0]?.id || null;
    writeLocal(model);
    schedulePush();
    closeTagEditor();
    renderTags();
    paletteCache.clear();
    renderRock();
  });
}

function renderGroups() {
  const list = document.getElementById("groups-list");
  if (!list) return;
  list.textContent = "";
  if (!model.groups || model.groups.length === 0) {
    const empty = document.createElement("p");
    empty.className = "muted small";
    empty.style.fontStyle = "italic";
    empty.textContent = "Not in any groups yet.";
    list.appendChild(empty);
    return;
  }
  for (const g of model.groups) {
    const row = document.createElement("div");
    row.className = "group-item";
    const name = document.createElement("span");
    name.className = "group-name";
    name.textContent = g.name;
    const code = document.createElement("span");
    code.className = "group-code";
    code.textContent = g.inviteCode;
    const link = document.createElement("a");
    link.href = `/g/${encodeURIComponent(g.inviteCode)}`;
    link.target = "_blank";
    link.textContent = "View";
    const leave = document.createElement("button");
    leave.className = "group-leave";
    leave.title = "Leave group";
    leave.textContent = "×";
    leave.addEventListener("click", () => {
      if (!confirm(`Leave "${g.name}"? You can rejoin with the code.`)) return;
      model.groups = model.groups.filter((x) => x.id !== g.id);
      writeLocal(model); schedulePush(); renderGroups();
    });
    row.appendChild(name);
    row.appendChild(code);
    row.appendChild(link);
    row.appendChild(leave);
    list.appendChild(row);
  }
}

async function createGroup() {
  const name = prompt("Name your group rock:");
  if (!name) return;
  if (!model.syncID) { alert("Save your name first."); return; }
  try {
    const res = await fetch("/api/groups", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ sync_id: model.syncID.toLowerCase(), name }),
    });
    if (!res.ok) { alert("Couldn't create group."); return; }
    const g = await res.json();
    model.groups = model.groups || [];
    model.groups.push({ id: g.id, name: g.name, inviteCode: g.invite_code, contributesGrains: true });
    writeLocal(model); schedulePush(); renderGroups();
    alert(`Group "${g.name}" created!\n\nInvite code: ${g.invite_code}\n\nShare boulder-43p.pages.dev/g/${g.invite_code} with friends.`);
  } catch {
    alert("Couldn't reach server.");
  }
}

async function joinGroup() {
  const raw = prompt("Enter the 6-letter invite code:");
  if (!raw) return;
  const code = raw.trim().toUpperCase();
  if (!/^[A-Z2-9]{6}$/.test(code)) { alert("Invalid code format."); return; }
  try {
    const res = await fetch(`/api/groups?code=${encodeURIComponent(code)}`);
    if (res.status === 404) { alert("No group with that code."); return; }
    if (!res.ok) { alert("Couldn't look up group."); return; }
    const body = await res.json();
    const g = body.group;
    if (model.groups.some((x) => x.id === g.id)) { alert("You're already in this group."); return; }
    model.groups.push({ id: g.id, name: g.name, inviteCode: g.invite_code, contributesGrains: true });
    writeLocal(model); schedulePush(); renderGroups();
  } catch {
    alert("Couldn't reach server.");
  }
}

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
bindTagEditor();
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
