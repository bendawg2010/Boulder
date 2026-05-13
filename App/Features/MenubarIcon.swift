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
    /// Render the menubar icon as a TEMPLATE image — pure black pixels
    /// with a subtle two-tier alpha (body / crown) so macOS auto-tints
    /// it for light/dark mode the same way it does built-in symbols
    /// (the paw, the moon, the diamond). AppDelegate sets isTemplate
    /// = true on the result. Keeps Boulder's asymmetric pixel silhouette
    /// as the brand identity while looking system-native.
    ///
    /// The `pixels` and `paletteFor` parameters are accepted for API
    /// compatibility with earlier versions but intentionally unused —
    /// a template icon is monochrome by definition.
    static func render(
        pixels: [BoulderPixel] = [],
        paletteFor: (BoulderPixel) -> [Color] = { p in
            p.legacyType?.palette ?? BoulderRenderer.fallbackPalette
        }
    ) -> NSImage {
        _ = pixels        // unused — template icon is monochrome
        _ = paletteFor    // unused
        let widthPt:  CGFloat = 22
        let heightPt: CGFloat = 20
        let cells = MenubarBoulder.cells
        // Pixels above this y are "crown" and render slightly
        // translucent — gives the icon a hint of 3D volume without
        // breaking the template-tint convention.
        let crownThreshold = MenubarBoulder.crownThreshold

        return NSImage(
            size: NSSize(width: widthPt, height: heightPt),
            flipped: false
        ) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.setShouldAntialias(false)
            ctx.interpolationQuality = .none

            let cx: CGFloat = widthPt / 2
            let baseY: CGFloat = 3

            for c in cells {
                let x = cx + CGFloat(c.x)
                let y = baseY + CGFloat(c.y)
                let alpha: CGFloat = (c.y >= crownThreshold) ? 0.55 : 1.0
                ctx.setFillColor(CGColor(gray: 0, alpha: alpha))
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

    /// y-coordinate above which cells are considered "crown" and
    /// render at lower alpha to suggest volumetric shading inside
    /// the template-tinted silhouette. Computed from the cell array.
    static let crownThreshold: Int = {
        let maxY = computeCells().map { $0.y }.max() ?? 0
        return Int(Double(maxY) * 0.72)
    }()

    /// 4-shade granite ramp (kept for backwards compat with any
    /// non-template callers; the template renderer ignores it).
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
