// BoulderShape.swift
//
// Deterministic dense-silhouette boulder generator with PHOTO-REAL
// surface detail.
//
// The rock snaps every pixel to an integer grid cell inside a dome
// silhouette. Cells are pre-ordered by distance from the center-
// bottom of the dome, so adding the Nth pixel always places it at
// the same fixed coordinate. The same N pixels always produce the
// same SHAPE on every device.
//
// Surface realism stack (each layer is deterministic per (x,y)):
//   1. Smooth base lighting gradient (base shadow → crown highlight)
//   2. Edge darkening for rounded silhouette + ambient occlusion
//   3. Three-octave hash noise — large, medium, fine — for organic
//      "lumpy" surface variation (patches of lighter/darker stone)
//   4. Procedural cracks: thin connected bands of much darker pixels
//      that walk across the boulder following a 2D wave field
//   5. Weathering streaks: vertical dark drips down from cracks/crown
//   6. Upper-left highlight arc (top-20% AND left-30% gets +2 shade)
//   7. Moss/lichen flecks in the lower-left shadow quadrant
//
// All effects are layered as shade offsets and the final shade is
// clamped into [0, shadeLevels-1] so FocusTag.palette mapping holds.

import Foundation

enum BoulderShape {
    /// Number of shade levels in the per-tag palette. MUST stay at 20
    /// to match `FocusTag.palette` which hardcodes count = 20.
    /// The realism stack treats indices 0..3 as deep shadow (cracks,
    /// AO), 4..7 as base body, 8..14 as midtone surface, and 15..19
    /// as crown highlight / upper-left lit arc.
    static let shadeLevels: Int = 20

    struct Cell: Hashable {
        let x: Int
        let y: Int
        let shade: Int   // 0..shadeLevels-1 into FocusTag.palette
    }

    /// Sentinel shade for moss/lichen cells. The renderer special-
    /// cases this index by tinting the resolved palette color toward
    /// olive-green. Using a sentinel keeps the shade-as-int contract
    /// without expanding the palette length (FocusTag is locked at 20).
    /// Renderer maps this to a green-tinted version of shade 7.
    /// NOTE: stays in the valid 0..19 range so any palette indexing is
    /// safe; the renderer treats it as a tinted cell.
    static let mossShadeSentinel: Int = 7   // body-toned; renderer tints green

    /// Max pixel capacity. Mountain tier ~5000 + a small buffer.
    static let maxCells: Int = 5600

    /// Aspect (width:height) of the dome. 1.55 reads as a
    /// satisfyingly wide-but-not-flat boulder.
    static let aspect: Double = 1.55

    /// Precomputed cells + moss coordinate set, computed in a single
    /// pass so cells and moss-flags stay deterministic together.
    private static let _computed: (cells: [Cell], moss: Set<Int>) = computeAll()

    /// Precomputed cells in growth order. cells[n] = the position +
    /// shade of the Nth pixel a Boulder will ever earn. Indexing
    /// past `count` should never happen — guard at the call site.
    static var cells: [Cell] { _computed.cells }

    /// Set of packed (x,y) coordinates that should render as moss.
    /// Renderer looks this up and applies a green tint.
    static var mossCoords: Set<Int> { _computed.moss }

    // MARK: - Helpers

    /// Truncating hash — MUST use UInt32(bitPattern: Int32(truncating-
    /// IfNeeded:)) before multiplying. Raw `Int &* 73856093` traps
    /// when the product exceeds Int32 range. (Crash fix referenced
    /// in the original v1.4.0 work.)
    @inline(__always)
    private static func hash2(_ x: Int, _ y: Int, salt: UInt32 = 0) -> UInt32 {
        let xu = UInt32(bitPattern: Int32(truncatingIfNeeded: x))
        let yu = UInt32(bitPattern: Int32(truncatingIfNeeded: y))
        var h = (xu &* UInt32(73856093)) ^ (yu &* UInt32(19349663))
        h ^= salt &* UInt32(83492791)
        // xorshift mix so adjacent (x,y) values diverge well — without
        // this the multiplicative hash leaves visible diagonal
        // banding at low magnitudes.
        h ^= h >> 13
        h = h &* UInt32(2654435761)
        h ^= h >> 16
        return h
    }

    /// Deterministic 0..1 value from (x,y) + salt.
    @inline(__always)
    private static func rand01(_ x: Int, _ y: Int, salt: UInt32 = 0) -> Double {
        Double(hash2(x, y, salt: salt) % 10000) / 10000.0
    }

    /// "Value noise" — bilinear blend between random values at
    /// integer lattice points scaled by `cellSize`. Smooth-ish.
    /// Returns roughly [-1, +1].
    @inline(__always)
    private static func valueNoise(_ x: Double, _ y: Double, salt: UInt32) -> Double {
        let xi = Int(floor(x))
        let yi = Int(floor(y))
        let xf = x - Double(xi)
        let yf = y - Double(yi)
        // Smoothstep for a softer interpolation.
        let u = xf * xf * (3 - 2 * xf)
        let v = yf * yf * (3 - 2 * yf)
        let a = rand01(xi,     yi,     salt: salt)
        let b = rand01(xi + 1, yi,     salt: salt)
        let c = rand01(xi,     yi + 1, salt: salt)
        let d = rand01(xi + 1, yi + 1, salt: salt)
        let ab = a + (b - a) * u
        let cd = c + (d - c) * u
        let n = ab + (cd - ab) * v
        return n * 2.0 - 1.0
    }

    /// Crack field. Two crossed sinusoids whose product produces
    /// narrow bands of near-zero values that look like organic
    /// fissures. Each (x,y) maps to a field value; cells where
    /// |field| < threshold render as crack cells.
    /// Two separately-phased fields cover the boulder with 2-3
    /// visually distinct cracks at different angles.
    @inline(__always)
    private static func crackField(_ x: Double, _ y: Double) -> Double {
        // Crack field A: diagonal, gentle curvature.
        let a = sin(x * 0.18 + y * 0.07 + 0.4)
             +  cos(x * 0.05 - y * 0.13 + 1.7)
        // Crack field B: steeper diagonal, different phase.
        let b = sin(x * 0.09 - y * 0.21 + 2.3)
             +  cos(x * 0.14 + y * 0.04 - 0.6)
        // Multiplying the two makes cracks appear where EITHER field
        // hits zero — looks like a few thin, branching fissures
        // rather than a regular pattern.
        return a * b
    }

    /// Returns true if (x,y) is a "crack core" — narrow band where
    /// the crack field crosses zero. Adds a small noise perturbation
    /// so cracks have organic micro-jitter rather than being perfect
    /// sine curves.
    @inline(__always)
    private static func isCrack(_ x: Int, _ y: Int) -> Bool {
        let xd = Double(x) + valueNoise(Double(x) * 0.5, Double(y) * 0.5, salt: 77) * 0.4
        let yd = Double(y) + valueNoise(Double(x) * 0.5, Double(y) * 0.5, salt: 78) * 0.4
        return abs(crackField(xd, yd)) < 0.10
    }

    /// Streak field. Vertical "drip lines" — sparse columns where a
    /// stain runs downward from the crown or from a crack.
    /// True where x is near one of a handful of streak columns.
    @inline(__always)
    private static func isStreak(_ x: Int, _ y: Int) -> Bool {
        // Phase-offset sines pick out a few vertical columns. The
        // `y * 0.03` term lets streaks drift slightly with height.
        let s1 = sin(Double(x) * 0.42 + Double(y) * 0.03)
        let s2 = cos(Double(x) * 0.27 - Double(y) * 0.02 + 1.5)
        // Streaks ONLY appear at certain x-bands AND only in the
        // lower 70% of the boulder (rain runs down from the crown
        // but evaporates near the base).
        return abs(s1) > 0.94 || abs(s2) > 0.95
    }

    // MARK: - Cell computation

    private static func computeAll() -> (cells: [Cell], moss: Set<Int>) {
        let cells = computeCells()
        let moss = computeMossCoords(from: cells)
        return (cells, moss)
    }

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

        // Pre-compute silhouette half-widths per row WITH wobble so
        // we can detect concave dents (rows where the wobble pulls
        // the outline inward).
        var rowHalfWidth: [Int] = []
        rowHalfWidth.reserveCapacity(Bmax + 1)
        for y in 0...Bmax {
            let yNorm = Double(y) / B
            let baseHalf = A * sqrt(max(0, 1 - yNorm * yNorm))
            // Wobble: low-frequency outline irregularity so the
            // silhouette reads as weathered, not as a math ellipse.
            let wob = 1.0
                + 0.045 * sin(Double(y) * 0.85)
                + 0.030 * cos(Double(y) * 1.40 + 1.2)
                + 0.022 * sin(Double(y) * 2.30 + 0.7)
            let hw = Int(baseHalf * wob)
            rowHalfWidth.append(max(0, hw))
        }

        // "Smoothed" half-width — average of this row and a couple
        // neighbours. Used to detect concave dents: a row whose
        // wobble-modulated half-width is significantly LESS than its
        // smoothed value sits in a dent, so cells just inside that
        // edge should get extra AO darkening.
        func smoothedHalfWidth(_ y: Int) -> Int {
            let y0 = max(0, y - 2)
            let y1 = min(Bmax, y + 2)
            var sum = 0
            var n = 0
            for yi in y0...y1 { sum += rowHalfWidth[yi]; n += 1 }
            return sum / max(1, n)
        }

        for y in 0...Bmax {
            let yNorm = Double(y) / B
            let halfWidth = rowHalfWidth[y]
            if halfWidth <= 0 { continue }
            let smoothed = smoothedHalfWidth(y)
            // Positive = this row is dented inward. Used to push AO.
            let dentDepth = max(0, smoothed - halfWidth)
            for x in -halfWidth...halfWidth {
                let xNorm = abs(Double(x)) / max(1.0, Double(halfWidth))

                // ---- Layer 1: base lighting gradient ----
                // base (yNorm=0)   → ~shade  4   (dark body, lit indirectly)
                // mid  (yNorm=0.5) → ~shade 10   (body, half-lit)
                // crown(yNorm=1)   → ~shade 17   (crown highlight)
                var s = 4.0 + yNorm * 13.0

                // ---- Layer 2: edge darkening + AO ----
                // xNorm² puts a soft falloff at outer cells.
                s -= xNorm * xNorm * 4.0
                // Right-side falls off slightly more (upper-left light).
                if x > 0 {
                    s -= (Double(x) / Double(halfWidth)) * 0.8
                }
                // EXTRA AO at concave dents — cells just inside a
                // wobble-induced dent get pushed darker, simulating
                // shadow caught in the dent.
                if dentDepth > 0 {
                    let edgeDist = Double(halfWidth) - abs(Double(x))
                    // Cells within `dentDepth + 1` of the edge get AO.
                    if edgeDist < Double(dentDepth) + 1.5 {
                        let aoStrength = 1.0 - edgeDist / (Double(dentDepth) + 1.5)
                        s -= aoStrength * 3.0
                    }
                }
                // Pure proximity-to-silhouette AO (no dent required) —
                // the outermost 1-2 cells of every row get a subtle
                // darkening to read as a rounded edge.
                let edgeDist = Double(halfWidth) - abs(Double(x))
                if edgeDist < 1.5 {
                    s -= (1.5 - edgeDist) * 1.2
                }

                // ---- Layer 3: multi-octave value noise ----
                // Large-scale lumpiness — patches of lighter/darker
                // rock spanning ~10 cells.
                let nLarge = valueNoise(Double(x) * 0.10, Double(y) * 0.10, salt: 11) * 1.6
                // Medium-scale — ~3 cells per patch.
                let nMed = valueNoise(Double(x) * 0.33, Double(y) * 0.33, salt: 22) * 1.0
                // Fine grain — per-cell sparkle for grit.
                let nFine = (rand01(x, y, salt: 33) - 0.5) * 1.2
                s += nLarge + nMed + nFine

                // ---- Layer 7: upper-left highlight arc ----
                // Top 20% of dome AND left 30% of dome get a +2 shade
                // boost. The product (topness × leftness) keeps the
                // boost smooth and curved, not a hard rectangle.
                // yNorm > 0.80 means top 20%. For "left 30%", x must
                // be in [-A·0.6, -A·0.3] ish — we use a normalized
                // 0..1 leftness factor.
                let topness = max(0, (yNorm - 0.70) / 0.30)
                let leftness = max(0, (-Double(x) / max(1.0, Double(halfWidth)) - 0.10) / 0.55)
                let highlightBoost = topness * leftness * 2.8
                s += highlightBoost

                // ---- Default shade calc ----
                var shade = Int(s.rounded())

                // ---- Layer 4: cracks ----
                // Detect AFTER base lighting so cracks darken whatever
                // shade the cell would otherwise be. But require the
                // cell to be at least 2 cells away from the silhouette
                // edge so cracks don't run right at the outline (they'd
                // visually look like silhouette wobble, not cracks).
                if edgeDist >= 2.0 && isCrack(x, y) {
                    shade -= 7
                }

                // ---- Layer 5: weathering streaks ----
                // Only in the lower 70% of the boulder. Subtle drop.
                // Streaks should "stain" the surface, not punch
                // through it like cracks.
                if yNorm < 0.78 && isStreak(x, y) {
                    shade -= 2
                }

                shade = max(0, min(Self.shadeLevels - 1, shade))

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
        // Moss/lichen flagging happens in `computeMossCoords(from:)`
        // — we keep the shade as the natural lighting shade so non-
        // moss palette mappings still index correctly, and the
        // renderer tints flagged cells green at draw time.
        return raw.prefix(maxCells).map { Cell(x: $0.x, y: $0.y, shade: $0.shade) }
    }

    /// Computes which cells should render as moss. Lower-left
    /// quadrant only (the shaded side of the rock); seeds value-
    /// noise patches; ~1-2% of cells in that quadrant.
    private static func computeMossCoords(from cells: [Cell]) -> Set<Int> {
        var set: Set<Int> = []
        // Find approximate boulder extents from `cells`.
        var maxY = 1
        for c in cells {
            if c.y > maxY { maxY = c.y }
        }
        let yLimit = Int(Double(maxY) * 0.55)   // lower 55%
        let xLimit = 0                          // x < 0 = left half
        for c in cells {
            if c.x >= xLimit || c.y >= yLimit { continue }
            // Value-noise patches: cluster moss into a few small
            // regions, not isolated speckle. Threshold at 0.55 keeps
            // overall density in the lower-left quadrant low.
            let n = valueNoise(Double(c.x) * 0.22, Double(c.y) * 0.22, salt: 91)
            if n > 0.55 {
                // Add a per-cell jitter so the patch isn't a perfect
                // smooth blob — looks more like clumped lichen.
                if rand01(c.x, c.y, salt: 92) > 0.35 {
                    set.insert(mossKey(c.x, c.y))
                }
            }
        }
        return set
    }

    /// Packs a signed (x,y) into a single Int suitable for a Set key.
    /// Boulder coordinates fit comfortably in [-256, +256] at our
    /// scale, so a +1024 bias keeps everything positive.
    @inline(__always)
    private static func mossKey(_ x: Int, _ y: Int) -> Int {
        return ((x + 1024) << 16) | (y + 1024)
    }

    /// O(1) lookup matching mossKey's packing.
    @inline(__always)
    static func isMoss(_ x: Int, _ y: Int) -> Bool {
        return mossCoords.contains(mossKey(x, y))
    }
}
