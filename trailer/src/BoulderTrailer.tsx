import {
  AbsoluteFill,
  Sequence,
  useCurrentFrame,
  useVideoConfig,
  interpolate,
  spring,
  Easing,
} from "remotion";

// Brand palette — same constants as the gravy promo CSS.
const PALETTE = {
  pink:    "#FF6B6B",
  magenta: "#C147FF",
  blue:    "#47A0FF",
  mint:    "#2EE6A0",
  yellow:  "#FFD960",
  bg:      "#06010f",
  cash:    "#00D632",
};

// 20-shade granite ramp. CRITICAL: the darkest shade is clearly
// brighter than the page backdrop (#06010f), so cells at the base
// shadow can't be mistaken for background showing through.
// Reads as a continuous lit surface rather than speckle.
const GRANITE: string[] = [
  "#2E2F36", "#32333A", "#36383F", "#3A3C43",
  "#3F4148", "#43464D", "#474A52", "#4C5058",
  "#51555D", "#565A63", "#5B606A", "#616671",
  "#676D78", "#6D737F", "#747A86", "#7B818D",
  "#828894", "#898F9B", "#9097A3", "#979EAA",
];

// Subtle warm/cool veining at low probability. Brightnesses match
// the mid-range of GRANITE so vein pixels don't pop visually —
// they read as natural mineral inclusion, not decoration.
const VEIN: string[] = [
  "#5A4838",  // basalt warm
  "#604F40",  // sandstone tan
  "#46495A",  // slate blue
];

// Drifting orb backdrop used in every scene — same vibe as the
// promo site, so the trailer feels like the same product.
const Backdrop: React.FC = () => {
  const frame = useCurrentFrame();
  const driftA = Math.sin(frame / 80) * 80;
  const driftB = Math.cos(frame / 70) * 90;
  return (
    <AbsoluteFill style={{ background: PALETTE.bg, overflow: "hidden" }}>
      <div
        style={{
          position: "absolute",
          width: 1200, height: 1200,
          top: -200 + driftB, right: -300 + driftA,
          background: `radial-gradient(circle, ${PALETTE.magenta} 0%, transparent 65%)`,
          filter: "blur(120px)", opacity: 0.5,
        }}
      />
      <div
        style={{
          position: "absolute",
          width: 1400, height: 1400,
          bottom: -300 + driftA, left: -400 + driftB,
          background: `radial-gradient(circle, ${PALETTE.blue} 0%, transparent 65%)`,
          filter: "blur(120px)", opacity: 0.5,
        }}
      />
    </AbsoluteFill>
  );
};

// Precomputed dense dome silhouette. Every cell is an INTEGER (x, y)
// grid coordinate inside a half-ellipse — so when rendered at any
// fixed cell size, the cells pack edge-to-edge with zero gaps and
// zero overlap. The rock reads as one solid mass, not scattered chunks.
//
// Cells are ordered by distance from center-bottom so a partial
// (N < max) slice still forms a coherent rounded boulder.
type ShapeCell = { x: number; y: number; shade: number };

function precomputeCells(maxN: number = 5600, aspect: number = 1.55): ShapeCell[] {
  // Half-ellipse area = (π/2)·A·B = (π/2)·aspect·B² ≥ maxN
  // → B = sqrt(2·maxN / (π·aspect)).
  const B = Math.ceil(Math.sqrt((2 * maxN) / (Math.PI * aspect)));
  const A = aspect * B;
  // y-stretch in the distance metric: boulder fills WIDE before TALL.
  const yStretch = 1.85;

  type Raw = { x: number; y: number; shade: number; dist: number };
  const raw: Raw[] = [];

  // Deterministic noise from (x,y) — adds 1-2 levels of variation
  // per cell so the lighting gradient isn't pixel-perfectly smooth,
  // which would look fake. Real rock has texture.
  function noise(x: number, y: number): number {
    const h = ((x * 73856093) ^ (y * 19349663)) >>> 0;
    return (h % 1000) / 1000;   // 0..1 deterministic
  }

  for (let y = 0; y <= B; y++) {
    const yNorm = y / B;
    const halfWidth = Math.floor(A * Math.sqrt(Math.max(0, 1 - yNorm * yNorm)));
    if (halfWidth < 0) continue;
    for (let x = -halfWidth; x <= halfWidth; x++) {
      const xNorm = Math.abs(x) / Math.max(1, halfWidth);
      // Smooth lighting: base → ~shade 4, crown → ~shade 17 (of 20).
      // Edge darkening: outer cells drop 2-4 shades for round silhouette.
      // Per-cell noise: ±1 shade for texture.
      // Smooth lighting curve — base is shadow, crown is highlight.
      // Edge darkening for a rounded silhouette. Noise is only ±1
      // shade so adjacent cells stay visually CONNECTED (big shade
      // jumps make a uniform surface look like speckled gravel).
      let s = 4 + yNorm * 13;
      s -= xNorm * xNorm * 3.5;
      s += (noise(x, y) - 0.5) * 1.2;
      const shade = Math.max(0, Math.min(GRANITE.length - 1, Math.round(s)));

      const dx = x;
      const dy = y * yStretch;
      const dist = Math.sqrt(dx * dx + dy * dy);
      raw.push({ x, y, shade, dist });
    }
  }
  raw.sort((a, b) => {
    if (a.dist !== b.dist) return a.dist - b.dist;
    if (a.y !== b.y) return a.y - b.y;
    return a.x - b.x;
  });
  return raw.slice(0, maxN).map((r) => ({ x: r.x, y: r.y, shade: r.shade }));
}

// Module-level cache — computed once.
const ALL_CELLS: ShapeCell[] = precomputeCells();

// Deterministic vein assignment — same (x,y) always reads as the
// same vein color, so it doesn't shimmer across frames.
// Capped at ~2% so veins read as inclusions, not as polka dots.
function veinAt(x: number, y: number): string | null {
  const h = ((x * 374761393) ^ (y * 668265263)) >>> 0;
  if (h % 50 !== 0) return null;
  return VEIN[h % VEIN.length];
}

// Boulder — renders the first N cells from the precomputed dense
// silhouette onto a SINGLE HTML canvas. Drawing every cell with
// `fillRect` into one bitmap eliminates the sub-pixel seam risk
// that absolutely-positioned divs have in Chromium at fractional
// DPRs. One rasterized surface = guaranteed pixel-perfect packing.
const Boulder: React.FC<{
  pixelCount: number;
  cell?: number;
  width?: number;
  height?: number;
}> = ({ pixelCount, cell = 8, width = 600, height = 420 }) => {
  const canvasRef = React.useRef<HTMLCanvasElement | null>(null);
  React.useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    // High-DPI canvas: scale the bitmap by devicePixelRatio so
    // every rect lands on whole device pixels — no anti-aliasing
    // between adjacent cells.
    const dpr = window.devicePixelRatio || 1;
    canvas.width = Math.round(width * dpr);
    canvas.height = Math.round(height * dpr);
    canvas.style.width = `${width}px`;
    canvas.style.height = `${height}px`;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;
    ctx.imageSmoothingEnabled = false;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, width, height);

    const cells = ALL_CELLS.slice(0, pixelCount);
    const cx = Math.round(width / 2);
    const baselineY = Math.round(height - 40);
    const cs = Math.max(1, Math.round(cell));
    const halfCell = Math.floor(cs / 2);

    for (let i = 0; i < cells.length; i++) {
      const c = cells[i];
      const vein = veinAt(c.x, c.y);
      ctx.fillStyle = vein ?? GRANITE[c.shade];
      ctx.fillRect(
        cx + c.x * cs - halfCell,
        baselineY - c.y * cs - cs,
        cs,
        cs
      );
    }
    // Subtle ground line.
    ctx.fillStyle = "rgba(255,255,255,0.15)";
    ctx.fillRect(40, baselineY, width - 80, 1);
  }, [pixelCount, cell, width, height]);
  return (
    <div style={{ width, height, position: "relative" }}>
      <canvas ref={canvasRef} />
    </div>
  );
};

// React import has to happen via the Remotion runtime's default
// resolution. Adding the explicit `import * as React` so useMemo
// is in scope (the rest of Remotion auto-imports React JSX).
import * as React from "react";

// ============================================================
// Helper — cross-fade envelope for a scene given its duration.
// Each scene fades in over 15f and fades out over 15f at the tail.
// Combined with 5-frame Sequence overlaps in the parent comp,
// this produces smooth scene-to-scene cross-fades instead of cuts.
// ============================================================
function fadeEnvelope(frame: number, duration: number, fadeFrames = 15): number {
  const inOpacity = interpolate(frame, [0, fadeFrames], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const outOpacity = interpolate(
    frame,
    [duration - fadeFrames, duration],
    [1, 0],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp" }
  );
  return Math.min(inOpacity, outOpacity);
}

// ============================================================
// Scene 1 — Logo + main tagline (with staggered letter reveal
// for "Boulder" and char-by-char type-on for the subtitle).
// ============================================================
const SceneLogo: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const sceneDuration = 150;
  const envelope = fadeEnvelope(frame, sceneDuration, 15);

  const rockScale = spring({ frame, fps, config: { damping: 14, stiffness: 90 } });

  // "Boulder" — each letter springs in on its own delay.
  const word = "Boulder";
  const letterDelay = 4; // frames between letters
  const letterStartFrame = 14;

  // Subtitle types on character-by-character after Boulder is mostly in.
  const subtitle = "A pet rock for your focus.";
  const subtitleStart = 60;
  const subtitleCharsPerFrame = 0.9;
  const typedLen = Math.floor(
    interpolate(frame, [subtitleStart, subtitleStart + subtitle.length / subtitleCharsPerFrame],
      [0, subtitle.length], {
        extrapolateLeft: "clamp", extrapolateRight: "clamp",
      })
  );
  const typed = subtitle.slice(0, typedLen);
  const showCaret = frame > subtitleStart && typedLen < subtitle.length;

  return (
    <AbsoluteFill style={{ alignItems: "center", justifyContent: "center", opacity: envelope }}>
      <div style={{ fontSize: 220, transform: `scale(${rockScale})` }}>🪨</div>
      <div
        style={{
          fontSize: 140, fontWeight: 900, letterSpacing: -3,
          color: "white",
          marginTop: 12,
          display: "flex",
        }}
      >
        {word.split("").map((ch, i) => {
          const letterFrame = frame - (letterStartFrame + i * letterDelay);
          const s = spring({
            frame: letterFrame, fps,
            config: { damping: 12, stiffness: 180 },
          });
          const y = interpolate(s, [0, 1], [60, 0]);
          return (
            <span
              key={i}
              style={{
                display: "inline-block",
                opacity: s,
                transform: `translateY(${y}px)`,
              }}
            >
              {ch}
            </span>
          );
        })}
      </div>
      <div
        style={{
          fontSize: 38, fontWeight: 600,
          color: "rgba(255,255,255,0.78)",
          marginTop: 18,
          minHeight: 50, // prevent layout shift during type-on
        }}
      >
        {typed}
        {showCaret && (
          <span
            style={{
              opacity: Math.floor(frame / 8) % 2 === 0 ? 1 : 0,
              marginLeft: 2,
            }}
          >
            ▍
          </span>
        )}
      </div>
    </AbsoluteFill>
  );
};

// ============================================================
// Scene 2 — It can't die. It just grows. (rock visibly growing)
// ============================================================
const SceneGrow: React.FC = () => {
  const frame = useCurrentFrame();
  const sceneDuration = 180;
  const envelope = fadeEnvelope(frame, sceneDuration, 15);

  // Pixel count ramps from 0 → 1200 by frame 150.
  const pixelCount = Math.floor(
    interpolate(frame, [0, 150], [0, 1200], {
      extrapolateLeft: "clamp", extrapolateRight: "clamp",
      easing: Easing.out(Easing.cubic),
    })
  );
  const headlineOpacity = interpolate(frame, [0, 25], [0, 1], { extrapolateRight: "clamp" });
  const headlineY = interpolate(frame, [0, 25], [30, 0], {
    extrapolateRight: "clamp",
    easing: Easing.out(Easing.cubic),
  });

  return (
    <AbsoluteFill style={{
      alignItems: "center", justifyContent: "center",
      flexDirection: "column", opacity: envelope,
    }}>
      <div
        style={{
          fontSize: 92, fontWeight: 900, letterSpacing: -2,
          color: "white", textAlign: "center",
          opacity: headlineOpacity,
          transform: `translateY(${headlineY}px)`,
          marginBottom: 32,
        }}
      >
        <span style={{
          background: `linear-gradient(90deg, ${PALETTE.pink}, ${PALETTE.magenta}, ${PALETTE.blue})`,
          WebkitBackgroundClip: "text",
          WebkitTextFillColor: "transparent",
        }}>
          It can't die.
        </span>
        <br />
        It just grows.
      </div>
      <Boulder pixelCount={pixelCount} cell={8} width={900} height={520} />
      <div
        style={{
          fontSize: 28, color: "rgba(255,255,255,0.55)",
          marginTop: 14, fontFamily: "monospace",
        }}
      >
        {pixelCount} pixels · {tierFor(pixelCount)}
      </div>
    </AbsoluteFill>
  );
};

function tierFor(n: number): string {
  if (n < 60) return "Pebble";
  if (n < 300) return "Stone";
  if (n < 1200) return "Rock";
  if (n < 5000) return "Boulder";
  return "Mountain";
}

// ============================================================
// Scene 3 — Tag picker concept.
// Chips spring in with scale + slight rotation, then persist.
// ============================================================
const SceneTags: React.FC = () => {
  const frame = useCurrentFrame();
  const sceneDuration = 180;
  const envelope = fadeEnvelope(frame, sceneDuration, 15);
  const headline = interpolate(frame, [0, 25], [0, 1], { extrapolateRight: "clamp" });

  // Tag hues match the app's rock presets: Granite, Basalt, Quartz,
  // Marble, Limestone. Low saturation so chips read as stone tones.
  const sampleTags = [
    { emoji: "⌨️", name: "Code",     hue: 0.62 },  // Granite
    { emoji: "📖", name: "Reading",  hue: 0.05 },  // Basalt
    { emoji: "🎨", name: "Design",   hue: 0.95 },  // Quartz
    { emoji: "🎧", name: "Music",    hue: 0.55 },  // Marble
    { emoji: "✍️", name: "Writing",  hue: 0.13 },  // Limestone
  ];

  // Chips pop in one at a time and stay onscreen — spring config
  // returns 1.0 at rest, so once the chip frame > settle, the
  // transform is steady (no per-frame jitter).
  return (
    <AbsoluteFill style={{
      alignItems: "center", justifyContent: "center",
      flexDirection: "column", opacity: envelope,
    }}>
      <div
        style={{
          fontSize: 84, fontWeight: 900, letterSpacing: -2,
          color: "white", opacity: headline, marginBottom: 12,
        }}
      >
        Your tags. Your colors.
      </div>
      <div
        style={{
          fontSize: 30, color: "rgba(255,255,255,0.6)",
          marginBottom: 56,
          opacity: interpolate(frame, [10, 35], [0, 1], { extrapolateRight: "clamp" }),
        }}
      >
        Build your own focus categories.
      </div>
      <div style={{ display: "flex", gap: 22 }}>
        {sampleTags.map((tag, i) => {
          const chipFrame = frame - (35 + i * 8);
          const scale = spring({
            frame: chipFrame, fps: 30,
            config: { damping: 12, stiffness: 160 },
          });
          // Rotation springs from -8° to 0° on the same chip frame.
          // Slight overshoot from the spring gives the chip a
          // playful "tossed onto the table" arrival.
          const rotation = interpolate(scale, [0, 1], [-8, 0]);
          // Match FocusTag.chipColor in the Swift app: hue × 360°,
          // 50% saturation, 72% brightness. Reads as tinted stone.
          const chipColor = `hsl(${tag.hue * 360}, 50%, 55%)`;
          return (
            <div
              key={tag.name}
              style={{
                width: 150, height: 170,
                borderRadius: 22,
                background: "rgba(255,255,255,0.07)",
                border: `2px solid ${chipColor}`,
                display: "flex", flexDirection: "column",
                alignItems: "center", justifyContent: "center",
                transform: `scale(${scale}) rotate(${rotation}deg)`,
                gap: 12,
              }}
            >
              <div style={{ fontSize: 64 }}>{tag.emoji}</div>
              <div style={{ fontSize: 22, fontWeight: 700, color: "white" }}>
                {tag.name}
              </div>
              <div style={{
                width: 80, height: 6, borderRadius: 3,
                background: chipColor,
              }} />
            </div>
          );
        })}
      </div>
    </AbsoluteFill>
  );
};

// ============================================================
// Scene 4 — NEW: Click to inspect. A cursor approaches the
// boulder, the inspector card pops up over a specific cell.
// ============================================================
const SceneInspect: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const sceneDuration = 150;
  const envelope = fadeEnvelope(frame, sceneDuration, 15);

  // Boulder is centered slightly left of center so the inspector
  // card has room to land on the right.
  const boulderW = 760;
  const boulderH = 460;
  const boulderCell = 8;
  const pixelCount = 1500;

  // Headline + caption.
  const headline = interpolate(frame, [0, 22], [0, 1], { extrapolateRight: "clamp" });
  const caption = interpolate(frame, [10, 35], [0, 1], { extrapolateRight: "clamp" });

  // Cursor path — starts off-screen bottom-right, moves to a
  // target pixel on the boulder (slightly above-left of center).
  // Target is the click position, in canvas pixels relative to
  // the boulder's containing div.
  const targetX = boulderW * 0.46;
  const targetY = boulderH * 0.55;
  const startX = boulderW * 0.95;
  const startY = boulderH * 1.05;

  const cursorProgress = spring({
    frame: frame - 20, fps,
    config: { damping: 18, stiffness: 60 },
  });
  const cursorX = interpolate(cursorProgress, [0, 1], [startX, targetX]);
  const cursorY = interpolate(cursorProgress, [0, 1], [startY, targetY]);

  // Click ring — when cursor arrives (frame ~ 58), a pulse rings out.
  const clickFrame = 60;
  const ringScale = interpolate(frame, [clickFrame, clickFrame + 22], [0.3, 2.6], {
    extrapolateLeft: "clamp", extrapolateRight: "clamp",
    easing: Easing.out(Easing.cubic),
  });
  const ringOpacity = interpolate(frame, [clickFrame, clickFrame + 22], [0.9, 0], {
    extrapolateLeft: "clamp", extrapolateRight: "clamp",
  });

  // Inspector card pops up just after click.
  const cardFrame = frame - (clickFrame + 4);
  const cardScale = spring({
    frame: cardFrame, fps,
    config: { damping: 14, stiffness: 170 },
  });

  return (
    <AbsoluteFill style={{
      alignItems: "center", justifyContent: "center",
      flexDirection: "column", opacity: envelope,
    }}>
      <div
        style={{
          fontSize: 76, fontWeight: 900, letterSpacing: -2,
          color: "white", opacity: headline, marginBottom: 10,
          textAlign: "center",
        }}
      >
        Click any pixel.{" "}
        <span style={{
          background: `linear-gradient(90deg, ${PALETTE.mint}, ${PALETTE.blue})`,
          WebkitBackgroundClip: "text",
          WebkitTextFillColor: "transparent",
        }}>
          Remember what you did.
        </span>
      </div>
      <div style={{
        fontSize: 26, color: "rgba(255,255,255,0.6)",
        marginBottom: 36, opacity: caption,
      }}>
        Every cell is a focus session. Tap to revisit it.
      </div>

      <div style={{
        position: "relative",
        width: boulderW, height: boulderH,
      }}>
        <Boulder
          pixelCount={pixelCount}
          cell={boulderCell}
          width={boulderW}
          height={boulderH}
        />

        {/* Click ring pulse over the target cell. */}
        <div style={{
          position: "absolute",
          left: targetX - 40, top: targetY - 40,
          width: 80, height: 80,
          borderRadius: "50%",
          border: `3px solid ${PALETTE.mint}`,
          transform: `scale(${ringScale})`,
          opacity: ringOpacity,
          pointerEvents: "none",
        }} />

        {/* Highlight square on the clicked cell. */}
        {frame >= clickFrame && (
          <div style={{
            position: "absolute",
            left: targetX - boulderCell / 2,
            top: targetY - boulderCell / 2,
            width: boulderCell,
            height: boulderCell,
            boxShadow: `0 0 0 2px ${PALETTE.mint}, 0 0 18px ${PALETTE.mint}`,
            pointerEvents: "none",
          }} />
        )}

        {/* Cursor — SVG arrow. */}
        <svg
          width={42}
          height={48}
          viewBox="0 0 24 28"
          style={{
            position: "absolute",
            left: cursorX,
            top: cursorY,
            pointerEvents: "none",
            filter: "drop-shadow(0 2px 4px rgba(0,0,0,0.5))",
          }}
        >
          <path
            d="M 2 2 L 2 22 L 8 16 L 12 24 L 15 23 L 11 15 L 19 14 Z"
            fill="white"
            stroke="#06010f"
            strokeWidth={1.2}
          />
        </svg>

        {/* Inspector card. */}
        <div style={{
          position: "absolute",
          left: targetX + 70,
          top: targetY - 80,
          width: 340,
          padding: "20px 22px",
          borderRadius: 18,
          background: "rgba(20, 16, 32, 0.92)",
          border: "1px solid rgba(255,255,255,0.14)",
          boxShadow: "0 20px 60px rgba(0,0,0,0.5)",
          backdropFilter: "blur(20px)",
          transform: `scale(${cardScale})`,
          transformOrigin: "top left",
          opacity: cardScale,
        }}>
          <div style={{
            display: "flex", alignItems: "center", gap: 10,
            marginBottom: 8,
          }}>
            <div style={{ fontSize: 32 }}>⌨️</div>
            <div style={{
              fontSize: 22, fontWeight: 800, color: "white",
            }}>
              Code
            </div>
            <div style={{
              marginLeft: "auto",
              padding: "3px 9px",
              borderRadius: 999,
              fontSize: 13, fontWeight: 700,
              background: `hsl(${0.62 * 360}, 50%, 55%, 0.25)`,
              color: `hsl(${0.62 * 360}, 65%, 75%)`,
              border: `1px solid hsl(${0.62 * 360}, 50%, 55%, 0.5)`,
            }}>
              Granite
            </div>
          </div>
          <div style={{
            fontSize: 19, fontWeight: 600,
            color: "white", lineHeight: 1.3,
            marginBottom: 6,
          }}>
            Refactoring the renderer
          </div>
          <div style={{
            fontSize: 14,
            color: "rgba(255,255,255,0.55)",
            fontFamily: "monospace",
          }}>
            Tue · May 12 · 47 min
          </div>
          <div style={{
            marginTop: 12, paddingTop: 10,
            borderTop: "1px solid rgba(255,255,255,0.08)",
            fontSize: 13,
            color: "rgba(255,255,255,0.45)",
          }}>
            Pixel #1,247 · +1 px earned
          </div>
        </div>
      </div>
    </AbsoluteFill>
  );
};

// ============================================================
// Scene 5 — Commitment timer ramping down.
// Now features a multiplier tier ramp: ROLLING ×1.5 → FLOW ×3.0×.
// Stop button shifts to "Give up · -15 px" near the end as a
// warning-tinted hint about the penalty mechanic.
// ============================================================
const SceneCommit: React.FC = () => {
  const frame = useCurrentFrame();
  const sceneDuration = 150;
  const envelope = fadeEnvelope(frame, sceneDuration, 15);
  const headline = interpolate(frame, [0, 25], [0, 1], { extrapolateRight: "clamp" });

  // Timer counts down from 25:00 → 24:55ish over the scene.
  const elapsed = interpolate(frame, [0, 120], [0, 12]); // 12 simulated seconds
  const totalSeconds = 25 * 60 - Math.floor(elapsed);
  const m = Math.floor(totalSeconds / 60);
  const s = totalSeconds % 60;
  const timerText = `${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`;

  // Multiplier ramps across the scene: 1.5× rolling → 3.0× flow state.
  // Frame thresholds: Rolling (0-60), tier flip at ~70, Flow (90+).
  const mult = interpolate(frame, [0, 30, 70, 110], [1.5, 1.8, 2.4, 3.0], {
    extrapolateLeft: "clamp", extrapolateRight: "clamp",
  });
  const inFlow = frame >= 70;
  const tierLabel = inFlow ? "FLOW STATE" : "ROLLING";
  const tierColor = inFlow ? PALETTE.mint : PALETTE.yellow;

  // Tier flip — pop the label when it changes.
  const tierFlipFrame = frame - 70;
  const tierFlipScale = inFlow
    ? interpolate(tierFlipFrame, [0, 8, 16], [1.0, 1.18, 1.0], {
        extrapolateLeft: "clamp", extrapolateRight: "clamp",
      })
    : 1.0;

  // Stop button — at the tail, it morphs to "Give up · -15 px".
  const giveUpReveal = interpolate(frame, [100, 125], [0, 1], {
    extrapolateLeft: "clamp", extrapolateRight: "clamp",
  });

  return (
    <AbsoluteFill style={{
      alignItems: "center", justifyContent: "center",
      flexDirection: "column", opacity: envelope,
    }}>
      <div
        style={{
          fontSize: 84, fontWeight: 900, letterSpacing: -2,
          color: "white", opacity: headline, marginBottom: 16,
        }}
      >
        Commit. <span style={{ color: PALETTE.yellow }}>Earn more.</span>
      </div>
      <div style={{
        fontSize: 26, color: "rgba(255,255,255,0.6)", marginBottom: 50,
        opacity: interpolate(frame, [10, 35], [0, 1], { extrapolateRight: "clamp" }),
      }}>
        Pre-commit a duration. Focus longer → grow faster.
      </div>

      {/* Tier badge ABOVE the card — shows the momentum ramp. */}
      <div style={{
        display: "flex", alignItems: "center", gap: 14,
        marginBottom: 18,
        transform: `scale(${tierFlipScale})`,
      }}>
        <div style={{
          padding: "8px 18px",
          borderRadius: 999,
          fontSize: 22, fontWeight: 800,
          letterSpacing: 1.5,
          background: `${tierColor}1F`,
          color: tierColor,
          border: `1.5px solid ${tierColor}80`,
        }}>
          ● {tierLabel}
        </div>
        <div style={{
          fontSize: 38, fontWeight: 900,
          color: tierColor,
          fontFamily: "monospace",
          letterSpacing: -1,
        }}>
          ×{mult.toFixed(1)}
        </div>
      </div>

      {/* Mock popover-style card. */}
      <div style={{
        width: 480, padding: 30,
        borderRadius: 24,
        background: "rgba(255,255,255,0.06)",
        border: "1px solid rgba(255,255,255,0.12)",
        backdropFilter: "blur(20px)",
      }}>
        <div style={{
          display: "flex", justifyContent: "space-between",
          fontSize: 18, color: "rgba(255,255,255,0.55)", marginBottom: 8,
        }}>
          <span>● {inFlow ? "Flow" : "Rolling"} × {mult.toFixed(1)}×</span>
          <span style={{ color: PALETTE.yellow }}>🔒 Committed</span>
        </div>
        <div style={{
          fontSize: 92, fontWeight: 800, color: "white",
          fontFamily: "monospace", textAlign: "center",
          letterSpacing: -3,
        }}>
          {timerText}
        </div>
        <div style={{
          textAlign: "center", fontSize: 18,
          color: "rgba(255,255,255,0.45)", marginTop: -8,
        }}>
          {totalSeconds}s left
        </div>
        <div style={{
          display: "flex", gap: 8, marginTop: 20,
        }}>
          {["15m", "25m", "45m", "1h", "Open"].map((label, i) => (
            <div key={label} style={{
              flex: 1, padding: "10px 0",
              textAlign: "center", borderRadius: 8,
              fontSize: 16, fontWeight: 700,
              background: i === 1
                ? `${PALETTE.yellow}33`
                : "rgba(255,255,255,0.05)",
              color: i === 1 ? PALETTE.yellow : "rgba(255,255,255,0.6)",
              border: i === 1 ? `1.5px solid ${PALETTE.yellow}99` : "1.5px solid transparent",
            }}>
              {label}
            </div>
          ))}
        </div>

        {/* Give up / Stop button — animates to a warning tint
            with "-15 px" suffix near the end of the scene. */}
        <div style={{
          marginTop: 18,
          padding: "12px 0",
          textAlign: "center",
          borderRadius: 10,
          fontSize: 17, fontWeight: 700,
          background: `rgba(255, 107, 107, ${0.08 + 0.16 * giveUpReveal})`,
          color: interpolate(giveUpReveal, [0, 1], [0, 1]) > 0.4
            ? PALETTE.pink
            : "rgba(255,255,255,0.55)",
          border: `1.5px solid rgba(255, 107, 107, ${0.2 + 0.4 * giveUpReveal})`,
          transition: "all 0.3s",
        }}>
          {giveUpReveal < 0.5
            ? "Stop"
            : `Give up · -15 px`}
        </div>
      </div>
    </AbsoluteFill>
  );
};

// ============================================================
// Scene 6 — Features + Mountain Range tease.
// Three feature cards on top, then a side-scroll panorama of
// 4 retired-boulder silhouettes forming a "skyline".
// ============================================================
const SceneFeatures: React.FC = () => {
  const frame = useCurrentFrame();
  const sceneDuration = 95;
  const envelope = fadeEnvelope(frame, sceneDuration, 12);

  const features = [
    { emoji: "🪨", title: "No death.",      sub: "No streak guilt." },
    { emoji: "✍️", title: "Tag every pixel.", sub: "Click to remember." },
    { emoji: "⛰️", title: "Build a mountain.", sub: "One year. One landmark." },
  ];

  // Panorama boulders — increasing size to suggest months/years stacking.
  const panoramaBoulders: Array<{ px: number; cell: number; w: number; h: number; label: string }> = [
    { px: 320,  cell: 4, w: 200, h: 130, label: "Jan" },
    { px: 720,  cell: 5, w: 240, h: 160, label: "Apr" },
    { px: 1180, cell: 5, w: 280, h: 180, label: "Aug" },
    { px: 1800, cell: 6, w: 320, h: 200, label: "Dec" },
  ];

  // Panorama slides in from the right after features settle.
  const panoramaStart = 30;
  const panoramaSlide = interpolate(
    frame, [panoramaStart, panoramaStart + 30],
    [200, 0], {
      extrapolateLeft: "clamp", extrapolateRight: "clamp",
      easing: Easing.out(Easing.cubic),
    }
  );
  const panoramaOpacity = interpolate(
    frame, [panoramaStart, panoramaStart + 20], [0, 1],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp" }
  );
  const panoramaCaption = interpolate(
    frame, [panoramaStart + 15, panoramaStart + 40], [0, 1],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp" }
  );

  return (
    <AbsoluteFill style={{
      alignItems: "center", justifyContent: "center",
      flexDirection: "column", opacity: envelope,
      gap: 30,
    }}>
      <div style={{ display: "flex", gap: 50 }}>
        {features.map((f, i) => {
          const localFrame = frame - i * 10;
          const scale = spring({
            frame: localFrame, fps: 30, config: { damping: 13, stiffness: 140 },
          });
          const yOff = interpolate(scale, [0, 1], [40, 0]);
          return (
            <div key={f.title} style={{
              width: 340,
              textAlign: "center",
              transform: `translateY(${yOff}px)`,
              opacity: scale,
            }}>
              <div style={{ fontSize: 92 }}>{f.emoji}</div>
              <div style={{ fontSize: 36, fontWeight: 900, color: "white", marginTop: 12 }}>
                {f.title}
              </div>
              <div style={{ fontSize: 22, color: "rgba(255,255,255,0.6)", marginTop: 4 }}>
                {f.sub}
              </div>
            </div>
          );
        })}
      </div>

      {/* Mountain range panorama — boulders sit on a shared baseline. */}
      <div style={{
        display: "flex",
        alignItems: "flex-end",
        justifyContent: "center",
        gap: 18,
        marginTop: 10,
        transform: `translateX(${panoramaSlide}px)`,
        opacity: panoramaOpacity,
      }}>
        {panoramaBoulders.map((b) => (
          <div key={b.label} style={{
            display: "flex", flexDirection: "column",
            alignItems: "center", gap: 4,
          }}>
            <Boulder pixelCount={b.px} cell={b.cell} width={b.w} height={b.h} />
            <div style={{
              fontSize: 14, fontWeight: 700,
              color: "rgba(255,255,255,0.5)",
              fontFamily: "monospace",
              letterSpacing: 1,
              marginTop: -6,
            }}>
              {b.label}
            </div>
          </div>
        ))}
      </div>

      <div style={{
        fontSize: 26, fontWeight: 600,
        color: "rgba(255,255,255,0.75)",
        opacity: panoramaCaption,
        marginTop: -4,
      }}>
        Years become a{" "}
        <span style={{
          background: `linear-gradient(90deg, ${PALETTE.blue}, ${PALETTE.mint})`,
          WebkitBackgroundClip: "text",
          WebkitTextFillColor: "transparent",
          fontWeight: 800,
        }}>
          skyline
        </span>.
      </div>
    </AbsoluteFill>
  );
};

// ============================================================
// Scene 7 — CTA / Logo close.
// "Start your pebble." reveals word-by-word.
// URL remains prominent. MIT badge + Cash App pill below.
// ============================================================
const SceneCTA: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const sceneDuration = 115;
  const envelope = fadeEnvelope(frame, sceneDuration, 15);

  const fadeIn = interpolate(frame, [0, 20], [0, 1], { extrapolateRight: "clamp" });

  // Word-by-word reveal of "Start your pebble."
  const ctaWords = ["Start", "your", "pebble."];
  const wordStartFrame = 18;
  const wordStagger = 8;

  const urlSlide = interpolate(frame, [40, 65], [30, 0], {
    extrapolateLeft: "clamp", extrapolateRight: "clamp",
    easing: Easing.out(Easing.cubic),
  });
  const urlOpacity = interpolate(frame, [40, 65], [0, 1], {
    extrapolateLeft: "clamp", extrapolateRight: "clamp",
  });

  const mitOpacity = interpolate(frame, [60, 80], [0, 1], {
    extrapolateLeft: "clamp", extrapolateRight: "clamp",
  });
  const cashOpacity = interpolate(frame, [72, 92], [0, 1], {
    extrapolateLeft: "clamp", extrapolateRight: "clamp",
  });
  const cashScale = spring({
    frame: frame - 72, fps,
    config: { damping: 12, stiffness: 160 },
  });

  return (
    <AbsoluteFill style={{
      alignItems: "center", justifyContent: "center",
      flexDirection: "column", opacity: envelope,
    }}>
      <div style={{ opacity: fadeIn, marginBottom: 16 }}>
        <Boulder pixelCount={1800} cell={6} width={620} height={360} />
      </div>

      {/* Headline — words reveal one at a time. */}
      <div style={{
        fontSize: 108, fontWeight: 900, letterSpacing: -2,
        display: "flex", gap: 26,
      }}>
        {ctaWords.map((w, i) => {
          const wf = frame - (wordStartFrame + i * wordStagger);
          const s = spring({
            frame: wf, fps,
            config: { damping: 14, stiffness: 130 },
          });
          const y = interpolate(s, [0, 1], [40, 0]);
          return (
            <span
              key={i}
              style={{
                display: "inline-block",
                opacity: s,
                transform: `translateY(${y}px)`,
                background: `linear-gradient(90deg, ${PALETTE.pink}, ${PALETTE.magenta}, ${PALETTE.blue}, ${PALETTE.mint})`,
                WebkitBackgroundClip: "text",
                WebkitTextFillColor: "transparent",
              }}
            >
              {w}
            </span>
          );
        })}
      </div>

      <div style={{
        fontSize: 42, color: "white", marginTop: 16,
        opacity: urlOpacity, transform: `translateY(${urlSlide}px)`,
        fontFamily: "monospace", fontWeight: 700,
      }}>
        boulder-43p.pages.dev
      </div>

      <div style={{
        fontSize: 22, color: "rgba(255,255,255,0.5)",
        marginTop: 16, opacity: mitOpacity,
        display: "flex", alignItems: "center", gap: 10,
      }}>
        <span style={{
          padding: "4px 12px",
          borderRadius: 999,
          background: "rgba(255,255,255,0.06)",
          border: "1px solid rgba(255,255,255,0.15)",
          fontWeight: 600,
        }}>
          Free · MIT · macOS 14+
        </span>
      </div>

      {/* Cash App tip pill — gravy workflow brand identity. */}
      <div style={{
        marginTop: 14,
        opacity: cashOpacity,
        transform: `scale(${cashScale})`,
      }}>
        <span style={{
          display: "inline-flex",
          alignItems: "center",
          gap: 8,
          padding: "10px 22px",
          borderRadius: 999,
          fontSize: 22,
          fontWeight: 800,
          letterSpacing: 0.2,
          color: "white",
          background: `linear-gradient(135deg, ${PALETTE.cash}, #00B82B)`,
          boxShadow: `0 8px 28px ${PALETTE.cash}55`,
          border: `1px solid ${PALETTE.cash}cc`,
          fontFamily:
            "ui-rounded, -apple-system, 'SF Pro Rounded', system-ui, sans-serif",
        }}>
          <span style={{ fontSize: 22 }}>💸</span>
          cash.app/$Dryeetsolutions
        </span>
      </div>
    </AbsoluteFill>
  );
};

// ============================================================
// Trailer — sequenced scenes (33 seconds total = 990 frames).
// Scenes overlap by 5 frames at the boundary; each scene
// internally fades in/out over 15 frames, producing smooth
// cross-fades between consecutive scenes.
// ============================================================
export const BoulderTrailer: React.FC = () => {
  return (
    <AbsoluteFill>
      <Backdrop />
      {/* Scene timeline (frames):
            Logo:     0  - 150  (150f, 5.0s)
            Grow:   145  - 325  (180f, 6.0s)   5fr overlap
            Tags:   320  - 500  (180f, 6.0s)
            Inspect:495  - 645  (150f, 5.0s)   NEW
            Commit: 640  - 790  (150f, 5.0s)
            Feats:  785  - 880  (95f,  ~3.2s)  + mountain range
            CTA:    875  - 990  (115f, ~3.8s)
          Total: 990 frames @ 30fps = 33.0s.
      */}
      <Sequence from={0}   durationInFrames={150}><SceneLogo /></Sequence>
      <Sequence from={145} durationInFrames={180}><SceneGrow /></Sequence>
      <Sequence from={320} durationInFrames={180}><SceneTags /></Sequence>
      <Sequence from={495} durationInFrames={150}><SceneInspect /></Sequence>
      <Sequence from={640} durationInFrames={150}><SceneCommit /></Sequence>
      <Sequence from={785} durationInFrames={95}><SceneFeatures /></Sequence>
      <Sequence from={875} durationInFrames={115}><SceneCTA /></Sequence>
    </AbsoluteFill>
  );
};
