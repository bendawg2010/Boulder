// BoulderShape.swift
//
// Deterministic dense-silhouette boulder generator.
//
// Instead of randomly jittered golden-angle spirals (which looked
// like scattered rubble), the rock now snaps every pixel to an
// integer grid cell inside a dome silhouette. Cells are pre-ordered
// by distance from the center-bottom of the dome, so adding the
// Nth pixel always places it at the same fixed coordinate — and a
// rock at N pixels is always the same SHAPE at every device.
//
// The cell array also encodes a shade (0..3 into the tag's palette)
// based on lighting: top of the dome reads light, base reads dark,
// outer edges read slightly darker for a rounded silhouette.

import Foundation

enum BoulderShape {
    /// Number of shade levels in the per-tag palette. 20 levels give
    /// a smooth lighting gradient from base shadow to crown highlight,
    /// with enough variation for organic-looking rock texture.
    static let shadeLevels: Int = 20

    struct Cell: Hashable {
        let x: Int
        let y: Int
        let shade: Int   // 0..shadeLevels-1 into FocusTag.palette
    }

    /// Max pixel capacity. Mountain tier ~5000 + a small buffer.
    static let maxCells: Int = 5600

    /// Aspect (width:height) of the dome. 1.55 reads as a
    /// satisfyingly wide-but-not-flat boulder.
    static let aspect: Double = 1.55

    /// Precomputed cells in growth order. cells[n] = the position +
    /// shade of the Nth pixel a Boulder will ever earn. Indexing
    /// past `count` should never happen — guard at the call site.
    static let cells: [Cell] = computeCells()

    private static func computeCells() -> [Cell] {
        // Half-ellipse area = (π/2)·A·B = (π/2)·aspect·B² ≥ maxCells
        // → B ≥ sqrt(2·max / (π·aspect))
        let B = ceil(sqrt(2.0 * Double(maxCells) / (.pi * aspect)))
        let A = aspect * B

        // Stretching y in the distance metric makes the rock fill
        // outward (wider) faster than up — actual boulders are wider
        // than tall, especially at small sizes.
        let yStretch: Double = 1.85

        struct Raw { let x: Int; let y: Int; let shade: Int; let dist: Double }
        var raw: [Raw] = []
        raw.reserveCapacity(Int(.pi * aspect * B * B / 2))

        let Bmax = Int(B)
        for y in 0...Bmax {
            let yNorm = Double(y) / B
            // Half-ellipse: x in [-A·sqrt(1 - (y/B)²), +A·sqrt(...)].
            let halfWidth = Int(A * sqrt(max(0, 1 - yNorm * yNorm)))
            if halfWidth < 0 { continue }
            for x in -halfWidth...halfWidth {
                let xNorm = abs(Double(x)) / max(1.0, Double(halfWidth))
                // Smooth lighting across 20 levels:
                //   base (yNorm=0)  → ~shade  4   (dark body, lit indirectly)
                //   mid  (yNorm=0.5)→ ~shade 11   (body, half-lit)
                //   crown(yNorm=1)  → ~shade 17   (crown highlight)
                // Edge: drop up to ~4 shades for the rounded silhouette.
                // Noise: ±2 shades per cell for organic texture.
                var s = 4.0 + yNorm * 13.0
                s -= xNorm * xNorm * 4.0
                // Deterministic hash noise from (x,y). MUST truncate to
                // UInt32 BEFORE multiplying — otherwise `Int(64-bit) &*
                // 73856093` produces values up to 5.4B that trap when
                // squeezed into Int32. (Same bug we fixed in
                // scripts/make-icon.sh; main-app was missed.)
                let xu = UInt32(bitPattern: Int32(truncatingIfNeeded: x))
                let yu = UInt32(bitPattern: Int32(truncatingIfNeeded: y))
                let h: UInt32 = (xu &* UInt32(73856093)) ^ (yu &* UInt32(19349663))
                let n = (Double(h % 1000) / 1000.0 - 0.5) * 2.4
                s += n
                let shade = max(0, min(Self.shadeLevels - 1, Int(s.rounded())))

                let dx = Double(x)
                let dy = Double(y) * yStretch
                let dist = sqrt(dx * dx + dy * dy)
                raw.append(Raw(x: x, y: y, shade: shade, dist: dist))
            }
        }

        // Sort by distance from center-bottom so pixels accrete from
        // the heart of the rock outward — gives a natural growth feel.
        raw.sort { a, b in
            if a.dist != b.dist { return a.dist < b.dist }
            if a.y != b.y { return a.y < b.y }
            return a.x < b.x
        }
        return raw.prefix(maxCells).map { Cell(x: $0.x, y: $0.y, shade: $0.shade) }
    }
}
