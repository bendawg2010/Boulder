// MenubarIcon.swift
//
// Renders the menubar 🪨. ALWAYS draws a recognizable boulder
// silhouette — the menubar is the app's logo, so the user should
// see a rock there from the very first launch.
//
// Thread-safety note: NSImage's drawing handler is invoked by AppKit
// at draw time, which can happen on a non-main thread. We MUST NOT
// reference @MainActor state (e.g. BoulderStore) from inside the
// handler — that crashes under Swift's actor isolation checks.
// Instead, `render` resolves every cell's CGColor up front on the
// caller's actor (always MainActor in practice), bakes the result
// into a plain `[CGColor]` array, and the drawing handler only
// touches that array + the precomputed cell coordinates.

import AppKit
import SwiftUI

enum MenubarIcon {
    /// Render the menubar icon. `paletteFor` MUST be safe to call on
    /// the caller's actor — we invoke it inline during render(), not
    /// inside the drawing handler.
    static func render(
        pixels: [BoulderPixel],
        paletteFor: (BoulderPixel) -> [Color] = { p in
            p.legacyType?.palette ?? BoulderRenderer.fallbackPalette
        }
    ) -> NSImage {
        let widthPt:  CGFloat = 28
        let heightPt: CGFloat = 22

        // Index user pixels by their (x,y) so we can match them
        // against the logo silhouette cells.
        let userByCoord: [String: BoulderPixel] = Dictionary(
            uniqueKeysWithValues: pixels.prefix(MenubarBoulder.cells.count).map { p in
                ("\(p.x),\(p.y)", p)
            }
        )

        // Pre-resolve every silhouette cell's color HERE (on the
        // caller's actor) so the drawing handler doesn't touch any
        // actor-isolated state.
        let baseGranite: [CGColor] = MenubarBoulder.granite.map { $0.cgColor }
        let resolvedColors: [CGColor] = MenubarBoulder.cells.map { c in
            if let p = userByCoord["\(c.x),\(c.y)"] {
                let pal = paletteFor(p)
                let shadeIdx = min(pal.count - 1, max(0, p.shade))
                return NSColor(pal[shadeIdx]).cgColor
            }
            return baseGranite[min(baseGranite.count - 1, max(0, c.shade))]
        }

        // The drawing handler captures only stable, thread-safe data:
        // the precomputed cells + the resolved color array. Safe to
        // invoke from any thread AppKit chooses.
        let cells = MenubarBoulder.cells
        return NSImage(
            size: NSSize(width: widthPt, height: heightPt),
            flipped: false   // CG-style: bottom-left origin, y grows up
        ) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.setShouldAntialias(false)
            ctx.interpolationQuality = .none

            let cx: CGFloat = widthPt / 2
            let baseY: CGFloat = 4

            for (i, c) in cells.enumerated() {
                let x = cx + CGFloat(c.x)
                let y = baseY + CGFloat(c.y)
                ctx.setFillColor(resolvedColors[i])
                ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
            return true
        }
    }
}

// MARK: - Baseline boulder silhouette (matches the app-icon shape)

/// Hand-tuned ~250-cell asymmetric boulder. Same algorithm as the
/// app icon — heavy wide base, narrower rounded crown, weathered
/// outline — scaled down to fit the 22pt menubar.
enum MenubarBoulder {
    struct Cell { let x: Int; let y: Int; let shade: Int }

    static let cells: [Cell] = computeCells()

    /// 4-shade granite ramp. NSColors so we can call .cgColor on
    /// MainActor before passing into the drawing handler.
    static let granite: [NSColor] = [
        NSColor(srgbRed: 0.21, green: 0.21, blue: 0.24, alpha: 1.0),
        NSColor(srgbRed: 0.31, green: 0.32, blue: 0.36, alpha: 1.0),
        NSColor(srgbRed: 0.45, green: 0.46, blue: 0.51, alpha: 1.0),
        NSColor(srgbRed: 0.62, green: 0.63, blue: 0.68, alpha: 1.0),
    ]

    private static func computeCells() -> [Cell] {
        let aspect = 1.30
        let A_BOTTOM = 11.0
        let A_TOP    =  7.0
        let B = A_BOTTOM / aspect

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
            let wobble = 1.0
                + 0.050 * sin(Double(y) * 0.85)
                + 0.040 * cos(Double(y) * 1.40 + 1.2)
            let rowA = Arow * wobble
            let halfWidth = Int(rowA * sqrt(max(0, 1 - ycNorm * ycNorm)))
            if halfWidth < 0 { continue }
            for x in -halfWidth...halfWidth {
                let xNorm = abs(Double(x)) / max(1.0, Double(halfWidth))
                let yLight = Double(y) / (2.0 * B)
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
