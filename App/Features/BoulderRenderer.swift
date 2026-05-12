// BoulderRenderer.swift
//
// SwiftUI Canvas that paints a BoulderModel as chunky pixel art.
// Pure function of `pixels` — no animation state of its own. Used by
// the popover (live), the gallery (frozen), and the release ceremony
// (translated off-screen).

import SwiftUI

struct BoulderRenderer: View {
    let pixels: [BoulderPixel]

    /// Side length in points of a single "pixel" cell.
    var cellSize: CGFloat = 4

    /// Drawn at the bottom of the canvas — Boulder sits ON ground.
    var groundLine: Bool = true

    var body: some View {
        Canvas { ctx, size in
            let centerX = size.width / 2
            let baselineY = size.height - (groundLine ? 18 : 4)

            if groundLine {
                // Subtle ground hint — single horizontal line of dust.
                var dust = Path()
                dust.move(to: CGPoint(x: 8, y: baselineY + cellSize * 0.5))
                dust.addLine(to: CGPoint(x: size.width - 8, y: baselineY + cellSize * 0.5))
                ctx.stroke(dust, with: .color(Color.white.opacity(0.12)), lineWidth: 1)
            }

            for p in pixels {
                let rect = CGRect(
                    x: centerX + CGFloat(p.x) * cellSize - cellSize / 2,
                    y: baselineY - CGFloat(p.y) * cellSize - cellSize,
                    width: cellSize,
                    height: cellSize
                )
                let palette = p.type.palette
                let shade = palette[max(0, min(palette.count - 1, p.shade))]
                ctx.fill(Path(rect), with: .color(shade))
            }
        }
        .drawingGroup() // rasterize for cheap redraws as pixels grow
    }
}
