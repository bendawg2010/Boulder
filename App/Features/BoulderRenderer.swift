// BoulderRenderer.swift
//
// SwiftUI Canvas that paints a BoulderModel as chunky pixel art.
// Pure function of `pixels` — no animation state of its own. Used by
// the popover (live), the gallery (frozen silhouettes), and the
// release ceremony (translated off-screen).
//
// When `pixels` is empty, the renderer draws NOTHING (not even a
// placeholder pebble). The PopoverContentView shows a clear
// "press Focus" empty state in its place — much less confusing than
// painting fake pixels when the user has zero.
//
// Auto-scale floors the pixel-count input at ~50 so the cell size
// doesn't pop when going from 1 → 2 → 3 real pixels.

import SwiftUI

struct BoulderRenderer: View {
    let pixels: [BoulderPixel]

    /// Side length in points of a single "pixel" cell. Ignored when
    /// `autoScale` is true.
    var cellSize: CGFloat = 4

    /// When true, the renderer picks a cell size based on pixel count
    /// so the rock fills roughly 60% of the canvas regardless of how
    /// many pixels it has. Use in the popover; turn off for gallery
    /// thumbnails where all retired Boulders should share a scale.
    var autoScale: Bool = true

    /// Drawn at the bottom of the canvas — Boulder sits ON ground.
    var groundLine: Bool = true

    var body: some View {
        Canvas { ctx, size in
            guard !pixels.isEmpty else { return }

            let centerX = size.width / 2
            let baselineY = size.height - (groundLine ? 18 : 4)

            // Auto-scale: pick a cell size that keeps the rock at a
            // stable visual footprint regardless of pixel count. Floor
            // the effective count at 50 so the first few real pixels
            // don't suddenly explode to oversized cells.
            let effectiveN = max(50, pixels.count)
            let targetRadius = min(size.width, size.height * 1.6) * 0.32
            let resolved: CGFloat = autoScale
                ? max(2.5, min(10, targetRadius / CGFloat(sqrt(Double(effectiveN)))))
                : cellSize

            if groundLine {
                var dust = Path()
                dust.move(to: CGPoint(x: 8, y: baselineY + resolved * 0.5))
                dust.addLine(to: CGPoint(x: size.width - 8, y: baselineY + resolved * 0.5))
                ctx.stroke(dust, with: .color(Color.white.opacity(0.12)), lineWidth: 1)
            }

            for p in pixels {
                let rect = CGRect(
                    x: centerX + CGFloat(p.x) * resolved - resolved / 2,
                    y: baselineY - CGFloat(p.y) * resolved - resolved,
                    width: resolved,
                    height: resolved
                )
                let palette = p.type.palette
                let color = palette[max(0, min(palette.count - 1, p.shade))]
                ctx.fill(Path(rect), with: .color(color))
            }
        }
        .drawingGroup()
    }
}
