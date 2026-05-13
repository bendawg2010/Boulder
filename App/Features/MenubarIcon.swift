// MenubarIcon.swift
//
// Renders the menubar 🪨. ALWAYS draws a recognizable boulder
// silhouette — the menubar is the app's logo, so the user should
// see a rock there from the very first launch, regardless of how
// many pixels they've actually earned.
//
// Once the user's earned pixel count exceeds the baseline silhouette
// (~200 cells), the rendered cells track their real rock instead —
// so a Mountain-tier user sees a hand-grown menubar boulder, and a
// fresh user sees the default chunky logo.

import AppKit
import SwiftUI

enum MenubarIcon {
    static func render(
        pixels: [BoulderPixel],
        paletteFor: (BoulderPixel) -> [Color] = { p in
            p.legacyType?.palette ?? BoulderRenderer.fallbackPalette
        }
    ) -> NSImage {
        let height: CGFloat = 22
        let width:  CGFloat = 28
        let size = NSSize(width: width, height: height)

        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor.clear.set()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

        let cx = width / 2
        let baseY = height - 4
        let cell: CGFloat = 1.0

        // Always draw the baseline boulder silhouette first. If the
        // user has real pixels, blend them in for color personality —
        // but the SHAPE comes from the logo, so the menubar always
        // looks like a rock.
        let userByCoord: [String: BoulderPixel] = Dictionary(
            uniqueKeysWithValues: pixels.prefix(MenubarBoulder.cells.count).map { p in
                ("\(p.x),\(p.y)", p)
            }
        )

        for c in MenubarBoulder.cells {
            let x = cx + CGFloat(c.x) * cell - cell / 2
            let y = baseY - CGFloat(c.y) * cell - cell
            let color: NSColor
            if let p = userByCoord["\(c.x),\(c.y)"] {
                let pal = paletteFor(p)
                let shadeIdx = min(pal.count - 1, max(0, p.shade))
                color = NSColor(pal[shadeIdx])
            } else {
                color = MenubarBoulder.granite[c.shade]
            }
            color.set()
            NSBezierPath(rect: NSRect(x: x, y: y, width: cell, height: cell)).fill()
        }
        return image
    }
}

// MARK: - Baseline boulder silhouette (matching app-icon shape)

/// A hand-tuned ~150-cell asymmetric boulder silhouette. Same
/// algorithm as the app icon — heavy wide base, narrower rounded
/// crown, weathered outline — scaled down to fit the 22pt menubar.
enum MenubarBoulder {
    struct Cell { let x: Int; let y: Int; let shade: Int }

    static let cells: [Cell] = computeCells()

    /// 4-shade granite ramp (NSColor, calibrated sRGB). Sub-sampled
    /// from the in-app 20-shade ramp for menubar simplicity.
    static let granite: [NSColor] = [
        NSColor(srgbRed: 0.21, green: 0.21, blue: 0.24, alpha: 1.0),
        NSColor(srgbRed: 0.31, green: 0.32, blue: 0.36, alpha: 1.0),
        NSColor(srgbRed: 0.45, green: 0.46, blue: 0.51, alpha: 1.0),
        NSColor(srgbRed: 0.62, green: 0.63, blue: 0.68, alpha: 1.0),
    ]

    private static func computeCells() -> [Cell] {
        let aspect = 1.30      // wider than tall
        let A_BOTTOM = 11.0    // half-width at the widest point
        let A_TOP    =  7.0
        let B = A_BOTTOM / aspect   // ~8.5

        var cells: [Cell] = []
        let Bmax = Int(B.rounded(.up))
        for y in 0...(2 * Bmax) {
            let yc = Double(y) - B
            let equator = -0.15 * B
            let yFromEq = yc - equator
            let yRange = max(B - equator, B + equator)
            let ycNorm = yFromEq / yRange
            if abs(ycNorm) > 1 { continue }
            let topness = max(0, ycNorm)
            let bottomness = max(0, -ycNorm)
            let Arow = A_BOTTOM
                - (A_BOTTOM - A_TOP) * pow(topness, 0.85)
                - A_BOTTOM * 0.05 * pow(bottomness, 1.5)
            // Outline wobble — same multi-scale sine pattern as the
            // app icon, scaled for menubar size.
            let wobble = 1.0
                + 0.050 * sin(Double(y) * 0.85)
                + 0.040 * cos(Double(y) * 1.40 + 1.2)
            let rowA = Arow * wobble
            let halfWidth = Int(rowA * sqrt(max(0, 1 - ycNorm * ycNorm)))
            if halfWidth < 0 { continue }
            for x in -halfWidth...halfWidth {
                let xNorm = abs(Double(x)) / max(1.0, Double(halfWidth))
                let yLight = Double(y) / (2.0 * B)
                // 4-shade ramp: base=0, mid=1-2, crown=3.
                var s = 0.5 + yLight * 3.0
                s -= xNorm * xNorm * 0.8
                if x > 0 {
                    let r = Double(x) / max(1.0, Double(halfWidth))
                    s -= r * 0.4
                }
                let shade = max(0, min(granite.count - 1, Int(s.rounded())))
                cells.append(Cell(x: x, y: y, shade: shade))
            }
        }
        return cells
    }
}
