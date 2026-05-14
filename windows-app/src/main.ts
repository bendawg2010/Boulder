// Boulder for Windows — frontend.
//
// Mirrors the macOS Swift model in plain TS. Persists via the Tauri
// store plugin (file lives at %APPDATA%/Boulder/state.json). Renders
// the rock with the same dense-silhouette algorithm used by the
// website share page.

import { Store } from "@tauri-apps/plugin-store";
import { listen } from "@tauri-apps/api/event";

// ---------------- Model ----------------

const PIXELS_PER_SECOND = 1.0 / 300.0;          // one grain per 5 min

interface BoulderPixel {
  x: number;
  y: number;
  hue: number | null;   // null = legacy / no tag
  shade: number;
  earnedAt: number;     // unix seconds
}

interface BoulderModel {
  schemaVersion: number;
  startedAt: number;
  pixels: BoulderPixel[];
  pixelAccumulator: number;
  userFirstName: string | null;
  rockName: string | null;
}

function emptyModel(): BoulderModel {
  return {
    schemaVersion: 1,
    startedAt: Math.floor(Date.now() / 1000),
    pixels: [],
    pixelAccumulator: 0,
    userFirstName: null,
    rockName: null,
  };
}

// ---------------- Persistence ----------------

let store: Store | null = null;
let model: BoulderModel = emptyModel();

async function loadModel(): Promise<BoulderModel> {
  store = await Store.load("state.json");
  const saved = await store.get<BoulderModel>("model");
  return saved ?? emptyModel();
}
async function persist() {
  if (!store) return;
  await store.set("model", model);
  await store.save();
}

// ---------------- Tier ----------------

function tierFor(count: number): { name: string; next: string; needed: number } {
  if (count < 60)   return { name: "Pebble",   next: "Stone",    needed: 60 - count };
  if (count < 300)  return { name: "Stone",    next: "Rock",     needed: 300 - count };
  if (count < 1200) return { name: "Rock",     next: "Boulder",  needed: 1200 - count };
  if (count < 5000) return { name: "Boulder",  next: "Mountain", needed: 5000 - count };
  return { name: "Mountain", next: "—", needed: 0 };
}

// ---------------- Renderer ----------------
// (Compact port of share-renderer.js — same algorithm, no inspector.)

function hsvToRgb(h: number, s: number, v: number): string {
  h = ((h % 1) + 1) % 1;
  const i = Math.floor(h * 6);
  const f = h * 6 - i;
  const p = v * (1 - s);
  const q = v * (1 - f * s);
  const t = v * (1 - (1 - f) * s);
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
function paletteFor(hue: number): string[] {
  const out: string[] = [];
  for (let i = 0; i < 20; i++) {
    const t = i / 19;
    const b = 0.15 + (0.85 - 0.15) * Math.pow(t, 0.95);
    const s = 0.08 + 0.22 * Math.sin(Math.PI * t);
    out.push(hsvToRgb(hue, s, b));
  }
  return out;
}
const NEUTRAL_PALETTE = (() => {
  const out: string[] = [];
  for (let i = 0; i < 20; i++) {
    const t = i / 19;
    const v = 0.18 + 0.62 * Math.pow(t, 0.95);
    const c = Math.round(v * 255);
    out.push(`rgb(${c},${c},${c})`);
  }
  return out;
})();

function render() {
  const canvas = document.getElementById("rock") as HTMLCanvasElement;
  const ctx = canvas.getContext("2d")!;
  const empty = document.getElementById("empty-state")!;

  const width = canvas.clientWidth || 356;
  const height = canvas.clientHeight || 200;
  const dpr = window.devicePixelRatio || 1;
  canvas.width = Math.round(width * dpr);
  canvas.height = Math.round(height * dpr);
  ctx.imageSmoothingEnabled = false;
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  ctx.clearRect(0, 0, width, height);

  if (model.pixels.length === 0) {
    empty.hidden = false;
    return;
  }
  empty.hidden = true;

  let minX = Infinity, maxX = -Infinity, maxY = 0;
  for (const p of model.pixels) {
    if (p.x < minX) minX = p.x;
    if (p.x > maxX) maxX = p.x;
    if (p.y > maxY) maxY = p.y;
  }
  const xExtent = maxX - minX + 1;
  const yExtent = maxY + 1;
  const cellW = (width - 40) / xExtent;
  const cellH = (height - 40) / yExtent;
  const cs = Math.max(2, Math.floor(Math.min(cellW, cellH)));
  const halfCell = Math.floor(cs / 2);
  const cx = Math.round(width / 2);
  const baselineY = Math.round(height - 20);

  const cache = new Map<number, string[]>();
  function pal(hue: number | null) {
    if (hue === null) return NEUTRAL_PALETTE;
    const key = Math.round(hue * 255);
    let p = cache.get(key);
    if (!p) { p = paletteFor(hue); cache.set(key, p); }
    return p;
  }

  for (const px of model.pixels) {
    const p = pal(px.hue);
    const shade = Math.max(0, Math.min(p.length - 1, px.shade));
    ctx.fillStyle = p[shade];
    ctx.fillRect(cx + px.x * cs - halfCell, baselineY - px.y * cs - cs, cs, cs);
  }
}

// ---------------- Focus session ----------------
// Same accretion rate as the macOS app: 1 grain per 5 focused minutes.

let isFocusing = false;
let plannedSeconds: number | null = null;
let pendingCount = 0;

function startFocus() {
  if (isFocusing) {
    stopFocus();
    return;
  }
  isFocusing = true;
  pendingCount = 0;
  // For brevity in the scaffold, grain placement reuses the silhouette
  // packer's "next available cell" — placeholder until we port the
  // BoulderShape algorithm.
  const focusBtn = document.getElementById("focus-btn")!;
  focusBtn.classList.add("focusing");
  focusBtn.textContent = "Stop";
}
function stopFocus() {
  isFocusing = false;
  const focusBtn = document.getElementById("focus-btn")!;
  focusBtn.classList.remove("focusing");
  focusBtn.textContent = "Focus";
  if (pendingCount > 0) showClaim();
}

function showClaim() {
  const row = document.getElementById("action-row")!;
  const label = document.getElementById("claim-label")!;
  label.textContent = `Claim ${pendingCount} grain${pendingCount === 1 ? "" : "s"}`;
  row.hidden = false;
}

function tick() {
  if (!isFocusing) return;
  model.pixelAccumulator += PIXELS_PER_SECOND;
  while (model.pixelAccumulator >= 1.0) {
    model.pixelAccumulator -= 1.0;
    pendingCount += 1;
  }
  // Auto-stop if a planned duration is up.
  if (plannedSeconds !== null) {
    plannedSeconds -= 1;
    if (plannedSeconds <= 0) stopFocus();
  }
  updateHUD();
}

// ---------------- HUD ----------------

function updateHUD() {
  const tier = tierFor(model.pixels.length);
  (document.getElementById("tier-name") as HTMLElement).textContent = tier.name;
  (document.getElementById("tier-sub") as HTMLElement).textContent =
    tier.needed > 0 ? `${tier.needed} grains to ${tier.next}` : "Mountain reached — release when ready";
  (document.getElementById("grain-count") as HTMLElement).textContent =
    `${model.pixels.length} grain${model.pixels.length === 1 ? "" : "s"}`;
  // Action row visibility: show when there are pixels (share) or pending (claim).
  const actionRow = document.getElementById("action-row")! as HTMLElement;
  if (model.pixels.length > 0 || pendingCount > 0) {
    actionRow.hidden = false;
    const claim = document.getElementById("claim-btn")! as HTMLButtonElement;
    claim.hidden = pendingCount <= 0;
    const claimLabel = document.getElementById("claim-label")!;
    claimLabel.textContent = `Claim ${pendingCount} grain${pendingCount === 1 ? "" : "s"}`;
  } else {
    actionRow.hidden = true;
  }
}

// ---------------- Onboarding ----------------

function maybeShowOnboarding() {
  const modal = document.getElementById("onboarding")!;
  modal.hidden = !!model.userFirstName;
}

function bindOnboarding() {
  const nameInput = document.getElementById("onb-name") as HTMLInputElement;
  const rockInput = document.getElementById("onb-rock") as HTMLInputElement;
  const startBtn = document.getElementById("onb-start") as HTMLButtonElement;
  nameInput.addEventListener("input", () => {
    startBtn.disabled = nameInput.value.trim().length === 0;
  });
  startBtn.addEventListener("click", async () => {
    const name = nameInput.value.trim();
    if (!name) return;
    model.userFirstName = name;
    const rock = rockInput.value.trim();
    model.rockName = rock.length > 0 ? rock : null;
    await persist();
    (document.getElementById("onboarding")!).hidden = true;
  });
}

// ---------------- Boot ----------------

(async () => {
  model = await loadModel();
  maybeShowOnboarding();
  bindOnboarding();
  render();
  updateHUD();

  // Duration chips
  document.querySelectorAll<HTMLButtonElement>(".chip").forEach((c) => {
    c.addEventListener("click", () => {
      document.querySelectorAll(".chip").forEach((x) => x.classList.remove("active"));
      c.classList.add("active");
      const mins = c.dataset.mins;
      plannedSeconds = mins ? parseInt(mins, 10) * 60 : null;
    });
  });

  document.getElementById("focus-btn")!.addEventListener("click", () => {
    startFocus();
  });

  document.getElementById("claim-btn")!.addEventListener("click", async () => {
    // Placeholder: just persist the pending grains into pixels.
    // TODO(v1.8): port BoulderShape silhouette packer for true placement.
    for (let i = 0; i < pendingCount; i++) {
      model.pixels.push({ x: i % 10 - 5, y: Math.floor(i / 10), hue: null, shade: 10, earnedAt: Math.floor(Date.now() / 1000) });
    }
    pendingCount = 0;
    (document.getElementById("action-row")!).hidden = model.pixels.length === 0;
    await persist();
    render();
    updateHUD();
  });

  document.getElementById("share-btn")!.addEventListener("click", () => {
    // TODO(v1.8): port BoulderShareEncoder.
    alert("Sharing coming soon on Windows. The Mac build can already share.");
  });

  document.getElementById("settings-btn")!.addEventListener("click", () => {
    alert("Settings pane coming in v1.8 (rename rock, edit name, sync).");
  });

  document.getElementById("quit-btn")!.addEventListener("click", () => {
    window.close();
  });

  // 1 Hz tick — drives the accretion and timer.
  setInterval(tick, 1000);

  // Listen for tray menu "Settings…" event.
  await listen("boulder://show-settings", () => {
    alert("Settings pane coming in v1.8.");
  });
})();
