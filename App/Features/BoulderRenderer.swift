// BoulderRenderer.swift
//
// SwiftUI Canvas that paints a BoulderModel as chunky pixel art.
// Pixel colors come from the store's tag library: each pixel carries
// a `tagID` which the store resolves to a 4-color palette. Legacy
// pixels (pre-v1.3.0) fall back to FocusType.palette.
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

    /// Optional tap handler. Receives the pixel array index nearest
    /// the tap point, or nil if the tap missed every pixel.
    var onPixelTap: ((Int?) -> Void)? = nil

    @State private var lastSize: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                guard !pixels.isEmpty else { return }
                let (cell, cx, baselineY) = layout(in: size)

                if groundLine {
                    var dust = Path()
                    dust.move(to: CGPoint(x: 8, y: baselineY + cell * 0.5))
                    dust.addLine(to: CGPoint(x: size.width - 8, y: baselineY + cell * 0.5))
                    ctx.stroke(dust, with: .color(Color.white.opacity(0.12)), lineWidth: 1)
                }

                for p in pixels {
                    let rect = rectFor(p, cell: cell, cx: cx, baselineY: baselineY)
                    let palette = paletteFor(p)
                    let color = palette[max(0, min(palette.count - 1, p.shade))]
                    ctx.fill(Path(rect), with: .color(color))
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
        Color(white: 0.18), Color(white: 0.35),
        Color(white: 0.55), Color(white: 0.80)
    ]
}
