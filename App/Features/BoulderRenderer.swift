// BoulderRenderer.swift
//
// SwiftUI Canvas that paints a BoulderModel as chunky pixel art.
// Pixel colors come from the store's tag library: each pixel carries
// a `tagID` which the store resolves to a 20-shade palette. Legacy
// pixels (pre-v1.3.0) fall back to FocusType.palette.
//
// Realism extras handled at draw time:
//   - `shadowBelow`: a soft cast shadow ellipse painted on the
//     baseline BEFORE the boulder cells. Sells the "rock is sitting
//     on something" effect.
//   - Moss tinting: cells whose (x,y) is in BoulderShape.mossCoords
//     get their resolved palette color blended toward an olive-green.
//
// Empty-state behavior: the renderer draws nothing when pixels is
// empty — the popover shows a clear "Press Focus" empty state in
// its place.
//
// Click-to-inspect: callers can pass a `.onTap` handler that receives
// the pixel index nearest the tap location. Used by the popover to
// show what session a pixel cluster came from.

import SwiftUI

struct BoulderRenderer: View {
    let pixels: [BoulderPixel]
    /// Closure that resolves a pixel to its palette. Wired by the
    /// caller (usually `store.palette(for:)`) so this view doesn't
    /// need to know about BoulderStore.
    var paletteFor: (BoulderPixel) -> [Color] = { p in
        p.legacyType?.palette ?? BoulderRenderer.fallbackPalette
    }

    var cellSize: CGFloat = 4
    var autoScale: Bool = true
    var groundLine: Bool = true
    /// Draw a cast shadow ellipse under the boulder. Adds "weight"
    /// and grounds the rock visually. Default on; disable for hero
    /// renders that don't need a baseline.
    var shadowBelow: Bool = true

    /// Optional tap handler. Receives the pixel array index nearest
    /// the tap point, or nil if the tap missed every pixel.
    var onPixelTap: ((Int?) -> Void)? = nil

    /// Pour-in animation state. When non-nil, pixels with index >=
    /// `firstNewIndex` fade + scale in staggered by `stagger` seconds
    /// from `startedAt`. Caller (PopoverContentView) reads this from
    /// the store and forwards it.
    var flushState: BoulderStore.FlushState? = nil

    @State private var lastSize: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            // TimelineView keeps the Canvas redrawing while a flush
            // animation is in progress. Steady-state has no schedule
            // changes so the canvas only repaints when pixels change.
            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: flushState == nil)) { timeline in
                Canvas { ctx, size in
                    guard !pixels.isEmpty else { return }
                    let (cell, cx, baselineY) = layout(in: size)
                    let now = timeline.date

                    // Cast shadow — painted BEFORE the boulder so the
                    // rock sits on top of it.
                    if shadowBelow {
                        let maxAbsX = pixels.reduce(0) { max($0, abs($1.x)) }
                        let halfW = CGFloat(maxAbsX + 1) * cell
                        let shadowW = halfW * 2.0 * 1.10
                        let shadowH = max(cell * 1.4, cell * 2.2)
                        let shadowRect = CGRect(
                            x: cx - shadowW / 2,
                            y: baselineY - shadowH * 0.30,
                            width: shadowW,
                            height: shadowH
                        )
                        let shadowPath = Path(ellipseIn: shadowRect)
                        ctx.fill(shadowPath, with: .color(Color.black.opacity(0.28)))
                        let outerRect = shadowRect.insetBy(dx: -cell * 0.6, dy: -cell * 0.25)
                        let outerPath = Path(ellipseIn: outerRect)
                        ctx.blendMode = .multiply
                        ctx.fill(outerPath, with: .color(Color.black.opacity(0.10)))
                        ctx.blendMode = .normal
                    }

                    if groundLine {
                        var dust = Path()
                        dust.move(to: CGPoint(x: 8, y: baselineY + cell * 0.5))
                        dust.addLine(to: CGPoint(x: size.width - 8, y: baselineY + cell * 0.5))
                        ctx.stroke(dust, with: .color(Color.white.opacity(0.12)), lineWidth: 1)
                    }

                    for (i, p) in pixels.enumerated() {
                        // Pour-in animation: each new pixel pops in with
                        // (a) a yellow halo glow that fades over ~0.9s,
                        // (b) an overshoot scale 0.0 → 1.65 → 1.0,
                        // (c) an opacity ramp 0 → 1.
                        // Pixels staggered by f.stagger seconds so each
                        // one is individually visible. The store sets
                        // f.fadeIn so the renderer matches the chosen
                        // pacing — long for manual claims, short for
                        // anything that fires programmatically.
                        var opacity: Double = 1.0
                        var scale: CGFloat = 1.0
                        var glowAlpha: Double = 0.0
                        if let f = flushState, i >= f.firstNewIndex {
                            let offset = Double(i - f.firstNewIndex) * f.stagger
                            let elapsed = now.timeIntervalSince(f.startedAt) - offset
                            if elapsed < 0 { continue }   // not yet visible
                            let fadeIn = max(0.2, f.fadeIn)
                            let halo   = fadeIn * 1.05
                            if elapsed < fadeIn {
                                let t = elapsed / fadeIn
                                opacity = t
                                // Overshoot: 0.0 → 1.65 by 60%, settle to 1.0.
                                let s = t
                                if s < 0.60 {
                                    scale = 0.05 + (1.65 - 0.05) * (s / 0.60)
                                } else {
                                    scale = 1.65 - (1.65 - 1.0) * ((s - 0.60) / 0.40)
                                }
                            }
                            if elapsed < halo {
                                glowAlpha = 0.95 * (1.0 - elapsed / halo)
                            }
                        }

                        let rect = rectFor(p, cell: cell, cx: cx, baselineY: baselineY)
                        let scaledRect: CGRect
                        if scale != 1.0 {
                            let dx = rect.width * (1 - scale) / 2
                            let dy = rect.height * (1 - scale) / 2
                            scaledRect = rect.insetBy(dx: dx, dy: dy)
                        } else {
                            scaledRect = rect
                        }

                        // Halo glow — two layered soft circles behind the
                        // pixel. The outer halo is broad+dim (atmospheric
                        // bloom); the inner halo is tight+bright (the
                        // landing flash itself). Reads as a small star
                        // each grain leaves behind.
                        if glowAlpha > 0.01 {
                            let outerSize = rect.width * 5.2
                            let outerRect = CGRect(
                                x: rect.midX - outerSize / 2,
                                y: rect.midY - outerSize / 2,
                                width: outerSize, height: outerSize
                            )
                            var outerCtx = ctx
                            outerCtx.opacity = glowAlpha * 0.55
                            outerCtx.fill(
                                Path(ellipseIn: outerRect),
                                with: .color(Color(hex: 0xFFD960).opacity(0.35))
                            )

                            let innerSize = rect.width * 2.4
                            let innerRect = CGRect(
                                x: rect.midX - innerSize / 2,
                                y: rect.midY - innerSize / 2,
                                width: innerSize, height: innerSize
                            )
                            var innerCtx = ctx
                            innerCtx.opacity = glowAlpha
                            innerCtx.fill(
                                Path(ellipseIn: innerRect),
                                with: .color(Color(hex: 0xFFEFA8).opacity(0.85))
                            )
                        }

                        let palette = paletteFor(p)
                        var color = palette[max(0, min(palette.count - 1, p.shade))]
                        if BoulderShape.isMoss(p.x, p.y) {
                            color = Self.tintMoss(color)
                        }
                        var ctxCopy = ctx
                        ctxCopy.opacity = opacity
                        ctxCopy.fill(Path(scaledRect), with: .color(color))
                    }
                }
            }
            .drawingGroup()
            .contentShape(Rectangle())
            .onTapGesture { location in
                guard let onPixelTap, !pixels.isEmpty else { return }
                onPixelTap(nearestPixelIndex(to: location, in: geo.size))
            }
        }
    }

    // MARK: Tinting

    /// Blend a base palette color toward an olive-green for moss/
    /// lichen cells. Keeps the underlying brightness so moss reads
    /// as natural growth, not a paint splat.
    private static func tintMoss(_ base: Color) -> Color {
        // Olive-green target. Hue ~0.27, low saturation, body
        // brightness — reads as old, weathered lichen.
        let target = Color(hue: 0.27, saturation: 0.45, brightness: 0.48)
        // Mix base and target in sRGB via NSColor (works on macOS).
        #if canImport(AppKit)
        let nb = NSColor(base).usingColorSpace(.sRGB) ?? NSColor.gray
        let nt = NSColor(target).usingColorSpace(.sRGB) ?? NSColor.gray
        let mix: CGFloat = 0.70
        let r = nb.redComponent * (1 - mix) + nt.redComponent * mix
        let g = nb.greenComponent * (1 - mix) + nt.greenComponent * mix
        let b = nb.blueComponent * (1 - mix) + nt.blueComponent * mix
        return Color(NSColor(srgbRed: r, green: g, blue: b, alpha: 1))
        #else
        return target
        #endif
    }

    // MARK: Geometry

    private func layout(in size: CGSize) -> (cell: CGFloat, cx: CGFloat, baselineY: CGFloat) {
        // Snap baseline + center to integer pixels so adjacent cells
        // share crisp edges instead of getting anti-aliased into a
        // dotty mess.
        let centerX = (size.width / 2).rounded()
        let baselineY = (size.height - (groundLine ? 18 : 4)).rounded()
        let effectiveN = max(50, pixels.count)
        // Pick a cell size proportional to the rock's expected radius
        // so the boulder fills ~60% of the canvas at every size, then
        // ROUND to an integer so cells pack edge-to-edge without
        // sub-pixel seams. Floor of 2 — anything smaller turns the
        // dome into anti-aliased fuzz.
        let targetRadius = min(size.width, size.height * 1.6) * 0.32
        let rawCell: CGFloat = autoScale
            ? max(2, min(10, targetRadius / CGFloat(sqrt(Double(effectiveN)))))
            : cellSize
        let resolved = rawCell.rounded()
        return (max(1, resolved), centerX, baselineY)
    }

    private func rectFor(_ p: BoulderPixel, cell: CGFloat, cx: CGFloat, baselineY: CGFloat) -> CGRect {
        CGRect(
            x: cx + CGFloat(p.x) * cell - cell / 2,
            y: baselineY - CGFloat(p.y) * cell - cell,
            width: cell, height: cell
        )
    }

    /// Linear scan — fine for any practical Boulder size. Returns
    /// the index of the pixel whose drawn rect contains `loc`, or
    /// the nearest pixel within a tap-tolerance radius.
    private func nearestPixelIndex(to loc: CGPoint, in size: CGSize) -> Int? {
        let (cell, cx, baselineY) = layout(in: size)
        // First pass: exact-hit.
        for (i, p) in pixels.enumerated().reversed() {
            if rectFor(p, cell: cell, cx: cx, baselineY: baselineY).contains(loc) {
                return i
            }
        }
        // Fall back: nearest within ~2 cells.
        var bestIdx: Int? = nil
        var bestDist: CGFloat = cell * 3
        for (i, p) in pixels.enumerated() {
            let r = rectFor(p, cell: cell, cx: cx, baselineY: baselineY)
            let center = CGPoint(x: r.midX, y: r.midY)
            let d = hypot(center.x - loc.x, center.y - loc.y)
            if d < bestDist { bestDist = d; bestIdx = i }
        }
        return bestIdx
    }

    static let fallbackPalette: [Color] = [
        Color(white: 0.14), Color(white: 0.20), Color(white: 0.26), Color(white: 0.32),
        Color(white: 0.36), Color(white: 0.40), Color(white: 0.44), Color(white: 0.48),
        Color(white: 0.52), Color(white: 0.56), Color(white: 0.60), Color(white: 0.64),
        Color(white: 0.68), Color(white: 0.72), Color(white: 0.76), Color(white: 0.80),
        Color(white: 0.83), Color(white: 0.86), Color(white: 0.89), Color(white: 0.92)
    ]
}
