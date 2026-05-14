#!/bin/bash
# Generate Boulder's app icon set + website og-card from a pure-
# CoreGraphics Swift script (no NSImage, no display required) and
# write the PNGs into App/Assets.xcassets/AppIcon.appiconset/ and
# website/og-card.png.
#
# Algorithm matches v1.4.0 in-app boulder:
#   - Dense dome silhouette (every cell snaps to integer grid inside
#     a half-ellipse — packs edge-to-edge, no gaps).
#   - 20-shade granite ramp with directional lighting (crown highlight,
#     base shadow, edge darkening for rounded silhouette).
#   - Deterministic per-cell hash noise for organic texture.
#   - ~2% basalt/sandstone/slate veining for mineral inclusion feel.

set -euo pipefail
cd "$(dirname "$0")/.."

ICONSET="App/Assets.xcassets/AppIcon.appiconset"
WEBSITE_DIR="website"
mkdir -p "$ICONSET" "$WEBSITE_DIR"

TMP_SWIFT="$(mktemp -t boulder-icon-gen).swift"
TMP_OUT="$(mktemp -d -t boulder-icons)"
trap "rm -rf '$TMP_SWIFT' '$TMP_OUT'" EXIT

cat > "$TMP_SWIFT" <<'SWIFT'
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers
import Foundation

// =============================================================
// Boulder shape: deterministic dense-silhouette generator.
// Mirrors App/Features/BoulderShape.swift exactly so the icon
// matches the in-app rock pixel-for-pixel.
// =============================================================

struct Cell { let x: Int; let y: Int; let shade: Int }

let SHADE_LEVELS = 20
// FULL ellipse silhouette — a closed egg-shape, not a half-dome.
// The in-app rock is a half-ellipse dome resting on the ground
// (correct context: it's literally sitting on the floor of the
// popover canvas). For the ICON we want a free-floating BOULDER,
// so we generate a closed shape with a visible top curve.
//
// Visible boulder proportions = (2A : 2B) = (ASPECT : 1).
// ASPECT = 1.15 → slightly wider than tall — classic boulder shape.
let ASPECT       = 1.30
let MAX_CELLS    = 2000   // tuned for a chunky icon-scale boulder.

// =============================================================
// Realism helpers — ported from BoulderShape.swift.
// Hash math uses the UInt32-truncating pattern; bare Int &* with
// big constants would trap.
// =============================================================
@inline(__always)
func iconHash2(_ x: Int, _ y: Int, salt: UInt32 = 0) -> UInt32 {
    let xu = UInt32(bitPattern: Int32(truncatingIfNeeded: x))
    let yu = UInt32(bitPattern: Int32(truncatingIfNeeded: y))
    var h = (xu &* UInt32(73856093)) ^ (yu &* UInt32(19349663))
    h ^= salt &* UInt32(83492791)
    h ^= h >> 13
    h = h &* UInt32(2654435761)
    h ^= h >> 16
    return h
}
@inline(__always)
func iconRand01(_ x: Int, _ y: Int, salt: UInt32 = 0) -> Double {
    Double(iconHash2(x, y, salt: salt) % 10000) / 10000.0
}
@inline(__always)
func iconValueNoise(_ x: Double, _ y: Double, salt: UInt32) -> Double {
    let xi = Int(floor(x))
    let yi = Int(floor(y))
    let xf = x - Double(xi)
    let yf = y - Double(yi)
    let u = xf * xf * (3 - 2 * xf)
    let v = yf * yf * (3 - 2 * yf)
    let a = iconRand01(xi,     yi,     salt: salt)
    let b = iconRand01(xi + 1, yi,     salt: salt)
    let c = iconRand01(xi,     yi + 1, salt: salt)
    let d = iconRand01(xi + 1, yi + 1, salt: salt)
    let ab = a + (b - a) * u
    let cd = c + (d - c) * u
    return (ab + (cd - ab) * v) * 2.0 - 1.0
}
@inline(__always)
func iconCrackField(_ x: Double, _ y: Double) -> Double {
    let a = sin(x * 0.18 + y * 0.07 + 0.4)
         +  cos(x * 0.05 - y * 0.13 + 1.7)
    let b = sin(x * 0.09 - y * 0.21 + 2.3)
         +  cos(x * 0.14 + y * 0.04 - 0.6)
    return a * b
}
@inline(__always)
func iconIsCrack(_ x: Int, _ y: Int) -> Bool {
    let xd = Double(x) + iconValueNoise(Double(x) * 0.5, Double(y) * 0.5, salt: 77) * 0.4
    let yd = Double(y) + iconValueNoise(Double(x) * 0.5, Double(y) * 0.5, salt: 78) * 0.4
    return abs(iconCrackField(xd, yd)) < 0.10
}

func computeCells(maxN: Int) -> ([Cell], Set<Int>) {
    // Full ellipse area = π·A·B = π·ASPECT·B² ≥ maxN
    let B = ceil(sqrt(Double(maxN) / (.pi * ASPECT)))
    let A = ASPECT * B

    struct Raw { let x: Int; let y: Int; let shade: Int; let dist: Double }
    var raw: [Raw] = []
    raw.reserveCapacity(Int(.pi * ASPECT * B * B))

    let Bmax = Int(B)
    // y in [0, 2B]. yc = y - B is the centered y (negative below
    // boulder midline, positive above). Asymmetric ellipse:
    //   - bottom half: full A (heavy base, like a rock at rest)
    //   - top half: narrower (boulder tapers up to a rounded crown)
    // Then per-row deterministic irregularity perturbs the silhouette
    // so the outline reads as "weathered stone," not a perfect
    // math object.
    // Boulder is heavier at the bottom, narrower at the top. The
    // widest point is below the equator (yEquator = -0.15·B), giving
    // the silhouette a heavy-base / round-shoulder profile rather
    // than a perfect ellipse. Apex tapers to a roundish crown.
    let A_BOTTOM = A * 1.00
    let A_TOP    = A * 0.60
    for y in 0...(2 * Bmax) {
        let yc = Double(y) - B
        // Re-anchor "equator" slightly below center so the rock
        // bulges in the lower half.
        let equator = -0.15 * B
        let yFromEq = yc - equator
        // Vertical "fill" goes from -1 (base) to +1 (crown), with 0
        // at the widest point. Use cube-root taper to make the shape
        // taper more aggressively above the equator.
        let yRange = max(B - equator, B + equator)   // half-height in either direction
        let ycNorm = yFromEq / yRange
        let topness = max(0, ycNorm)
        let bottomness = max(0, -ycNorm)
        let Arow = A_BOTTOM
            - (A_BOTTOM - A_TOP) * pow(topness, 0.85)
            - A_BOTTOM * 0.05 * pow(bottomness, 1.5)
        // Per-row outline wobble (~±10%) — gives the boulder a
        // weathered, hand-carved silhouette with visible bumps and
        // dents at multiple scales.
        let wobble = 1.0
            + 0.055 * sin(Double(y) * 0.85)
            + 0.045 * cos(Double(y) * 1.40 + 1.2)
            + 0.035 * sin(Double(y) * 2.30 + 0.7)
        let rowA = Arow * wobble
        let halfWidth = Int(rowA * sqrt(max(0, 1 - ycNorm * ycNorm)))
        if halfWidth < 0 { continue }
        for x in -halfWidth...halfWidth {
            let xNorm = abs(Double(x)) / max(1.0, Double(halfWidth))
            // Vertical lighting factor: 0 at base, 1 at crown.
            let yLight = Double(y) / (2.0 * B)
            var s = 2.0 + yLight * 17.0
            s -= xNorm * xNorm * 4.5
            if x > 0 {
                let r = Double(x) / max(1.0, Double(halfWidth))
                s -= r * 1.2
            }
            // Multi-octave value noise — large lumps, medium grain, fine grit.
            let nLarge = iconValueNoise(Double(x) * 0.10, Double(y) * 0.10, salt: 11) * 1.6
            let nMed   = iconValueNoise(Double(x) * 0.33, Double(y) * 0.33, salt: 22) * 1.0
            let nFine  = (iconRand01(x, y, salt: 33) - 0.5) * 1.2
            s += nLarge + nMed + nFine

            // Upper-left highlight arc — top 25% + left 30% gets a boost.
            let topness = max(0, (yLight - 0.65) / 0.35)
            let leftness = max(0, (-Double(x) / max(1.0, Double(halfWidth)) - 0.10) / 0.55)
            s += topness * leftness * 2.8

            var shade = Int(s.rounded())

            // Cracks — only away from silhouette edge.
            let edgeDist = Double(halfWidth) - abs(Double(x))
            if edgeDist >= 2.0 && iconIsCrack(x, y) {
                shade -= 7
            }
            shade = max(0, min(SHADE_LEVELS - 1, shade))

            // Distance from the BOULDER'S CENTER.
            let dx = Double(x)
            let dy = yc
            let dist = sqrt(dx * dx + dy * dy)
            raw.append(Raw(x: x, y: y, shade: shade, dist: dist))
        }
    }
    raw.sort { a, b in
        if a.dist != b.dist { return a.dist < b.dist }
        if a.y != b.y { return a.y < b.y }
        return a.x < b.x
    }
    let cells = raw.prefix(maxN).map { Cell(x: $0.x, y: $0.y, shade: $0.shade) }

    // Moss flagging — lower-left quadrant, value-noise clustered.
    var maxY = 1
    for c in cells { if c.y > maxY { maxY = c.y } }
    let yLimit = Int(Double(maxY) * 0.55)
    var moss: Set<Int> = []
    for c in cells {
        if c.x >= 0 || c.y >= yLimit { continue }
        let n = iconValueNoise(Double(c.x) * 0.22, Double(c.y) * 0.22, salt: 91)
        if n > 0.55 && iconRand01(c.x, c.y, salt: 92) > 0.35 {
            moss.insert(((c.x + 1024) << 16) | (c.y + 1024))
        }
    }
    return (cells, moss)
}

@inline(__always)
func mossKey(_ x: Int, _ y: Int) -> Int {
    return ((x + 1024) << 16) | (y + 1024)
}

// =============================================================
// 20-shade granite ramp — same colors as trailer/src/BoulderTrailer.tsx.
// Darkest shade is brighter than #06010f backdrop, so the rock
// silhouette stays separated from the sky even at the base shadow.
// =============================================================
let GRANITE_HEX: [String] = [
    "#2E2F36", "#32333A", "#36383F", "#3A3C43",
    "#3F4148", "#43464D", "#474A52", "#4C5058",
    "#51555D", "#565A63", "#5B606A", "#616671",
    "#676D78", "#6D737F", "#747A86", "#7B818D",
    "#828894", "#898F9B", "#9097A3", "#979EAA",
]
let VEIN_HEX: [String] = ["#5A4838", "#604F40", "#46495A"]

func hex(_ s: String) -> CGColor {
    var v: UInt64 = 0
    Scanner(string: String(s.dropFirst())).scanHexInt64(&v)
    let r = CGFloat((v >> 16) & 0xFF) / 255
    let g = CGFloat((v >> 8)  & 0xFF) / 255
    let b = CGFloat( v        & 0xFF) / 255
    return CGColor(srgbRed: r, green: g, blue: b, alpha: 1)
}

let GRANITE: [CGColor] = GRANITE_HEX.map(hex)
let VEIN:    [CGColor] = VEIN_HEX.map(hex)

// Deterministic vein assignment — same (x,y) always reads as the
// same vein color so the rock looks identical at every size.
// ~2% probability (h % 50 == 0) reads as inclusion, not decoration.
func veinAt(_ x: Int, _ y: Int) -> CGColor? {
    let xu = UInt32(bitPattern: Int32(truncatingIfNeeded: x))
    let yu = UInt32(bitPattern: Int32(truncatingIfNeeded: y))
    let h  = (xu &* 374761393) ^ (yu &* 668265263)
    // ~1.25% vein density. At icon scale this reads as occasional
    // mineral flecks rather than the "polka dot" effect we'd get
    // at the in-app 2% rate, which is calibrated for a larger rock.
    if h % 80 != 0 { return nil }
    return VEIN[Int(h) % VEIN.count]
}

// Precompute the maximum boulder once. We slice down per-size below.
let _COMPUTED = computeCells(maxN: MAX_CELLS)
let ALL_CELLS: [Cell] = _COMPUTED.0
let MOSS_COORDS: Set<Int> = _COMPUTED.1
// Olive-green moss ink — pre-blended target. Roughly hue 0.27,
// sat 0.45, brightness 0.48 mixed at 0.70 with a body-tone granite.
let MOSS_COLOR: CGColor = CGColor(srgbRed: 92.0/255, green: 113.0/255, blue: 80.0/255, alpha: 1)

// =============================================================
// Backdrop: vertical gradient + subtle magenta orb glow.
// Matches the website + trailer brand backdrop.
// =============================================================
let BG_TOP    = hex("#06010F")
let BG_BOTTOM = hex("#1A1230")
let ORB       = CGColor(srgbRed: 0.76, green: 0.28, blue: 1.0, alpha: 0.45)

func drawBackdrop(ctx: CGContext, width: Int, height: Int, rounded: Bool) {
    let cs = CGColorSpaceCreateDeviceRGB()
    let W = CGFloat(width)
    let H = CGFloat(height)
    let bg = CGRect(x: 0, y: 0, width: W, height: H)

    ctx.saveGState()
    if rounded {
        let r = min(W, H) * 0.225
        let path = CGPath(roundedRect: bg, cornerWidth: r, cornerHeight: r, transform: nil)
        ctx.addPath(path)
        ctx.clip()
    }

    // Vertical gradient backdrop. CG origin is bottom-left, so the
    // "top" of the visible canvas is y = H. We want #06010f at top.
    let grad = CGGradient(
        colorsSpace: cs,
        colors: [BG_TOP, BG_BOTTOM] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        grad,
        start: CGPoint(x: 0, y: H),
        end:   CGPoint(x: 0, y: 0),
        options: []
    )

    // Magenta orb behind the rock — subtle, brand-consistent.
    // Place it slightly above-center and to the right; the rock will
    // sit centered/bottom and partially eclipse the orb.
    let orbCenter = CGPoint(x: W * 0.62, y: H * 0.62)
    let orbRadius = max(W, H) * 0.55
    let orbGrad = CGGradient(
        colorsSpace: cs,
        colors: [ORB, CGColor(srgbRed: 0.76, green: 0.28, blue: 1.0, alpha: 0)] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawRadialGradient(
        orbGrad,
        startCenter: orbCenter, startRadius: 0,
        endCenter:   orbCenter, endRadius:   orbRadius,
        options: []
    )
    ctx.restoreGState()
}

// =============================================================
// Boulder renderer: draw N cells centered on the canvas with a
// given cell pixel size. Cells render with the granite ramp +
// occasional vein. Anti-aliasing OFF so cells stay crisp.
// =============================================================
func drawBoulder(
    ctx: CGContext,
    width: Int,
    height: Int,
    pixelCount: Int,
    cellSize: Int,
    centerX: CGFloat,
    baselineY: CGFloat
) {
    let cs = CGFloat(max(1, cellSize))
    let halfCell = floor(cs / 2)
    let n = min(pixelCount, ALL_CELLS.count)
    let smallScale = cellSize <= 1   // gate moss at 1pt — too few cells.

    // Cast shadow ellipse — painted BEFORE the boulder. Gated off for
    // the absolute smallest icons (cellSize=1 AND tiny pixelCount)
    // where it would dominate. Anti-alias ON for soft ellipse fill.
    if n > 0 && pixelCount >= 200 {
        var maxAbsX = 0
        for i in 0..<n {
            let ax = abs(ALL_CELLS[i].x)
            if ax > maxAbsX { maxAbsX = ax }
        }
        let halfW = CGFloat(maxAbsX + 1) * cs
        let shadowW = halfW * 2.0 * 1.10
        let shadowH = max(cs * 1.4, cs * 2.2)
        ctx.saveGState()
        ctx.setShouldAntialias(true)
        // CG origin is bottom-left; baselineY is the bottom of the rock.
        // Center the shadow's vertical span around baselineY - small offset.
        let shadowRect = CGRect(
            x: centerX - shadowW / 2,
            y: baselineY - shadowH * 0.70,
            width: shadowW,
            height: shadowH
        )
        ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.28))
        ctx.addEllipse(in: shadowRect)
        ctx.fillPath()
        // Soft outer falloff.
        let outerRect = shadowRect.insetBy(dx: -cs * 0.6, dy: -cs * 0.25)
        ctx.setBlendMode(.multiply)
        ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.10))
        ctx.addEllipse(in: outerRect)
        ctx.fillPath()
        ctx.setBlendMode(.normal)
        ctx.restoreGState()
    }

    ctx.setShouldAntialias(false)
    ctx.interpolationQuality = .none

    for i in 0..<n {
        let c = ALL_CELLS[i]
        let color: CGColor
        if !smallScale && MOSS_COORDS.contains(mossKey(c.x, c.y)) {
            color = MOSS_COLOR
        } else {
            color = veinAt(c.x, c.y) ?? GRANITE[c.shade]
        }
        ctx.setFillColor(color)
        let x = centerX + CGFloat(c.x) * cs - halfCell
        // y grows UP in our model; CG origin is bottom-left.
        let y = baselineY + CGFloat(c.y) * cs
        ctx.fill(CGRect(x: x, y: y, width: cs, height: cs))
    }
}

// =============================================================
// Per-size icon parameters. We tune (pixelCount, cellSize) per
// canvas so the boulder fills ~70% of the canvas width at every
// size without sub-pixel gaps. Tiny icons (16, 32) use a smaller
// boulder so individual cells stay visible.
// =============================================================
struct IconSpec {
    let px: Int
    let name: String
    let pixelCount: Int
    let cellSize: Int
    let baselineFrac: Double
}

// pixelCount/cellSize chosen so the BOULDER fills ~55-65% of the
// canvas centered vertically — a chunky rock sitting in the icon
// with breathing room. baselineFrac is the bottom of the boulder
// as a fraction of canvas height (CG origin bottom-left).
//
// With ASPECT = 1.15 and MAX_CELLS = 2400, a full boulder is
// ~58 × 50 cells (2A × 2B). cellSize tuned to fill the canvas:
//   16  → cellSize 1 → boulder ~10×8 inside the 16×16 (tiny boulder)
//   32  → cellSize 1 → ~28×24 in 32×32 (almost fills; small icons
//                                       use a SHRUNK boulder)
//   64  → cellSize 2 → 58×50 in 64×64
//   128 → cellSize 2 → 116×100 in 128×128
//   256 → cellSize 4 → 232×200 in 256×256
//   512 → cellSize 8 → 464×400 in 512×512
//   1024→ cellSize 16→ 928×800 in 1024×1024
//
// Tiny sizes (16, 32) use a SMALLER boulder (fewer cells) so each
// cell stays >= 1px and the silhouette is readable.
let SIZES: [IconSpec] = [
    IconSpec(px: 16,   name: "icon_16x16.png",      pixelCount: 60,   cellSize: 1,  baselineFrac: 0.25),
    IconSpec(px: 32,   name: "icon_16x16@2x.png",   pixelCount: 240,  cellSize: 1,  baselineFrac: 0.20),
    IconSpec(px: 32,   name: "icon_32x32.png",      pixelCount: 240,  cellSize: 1,  baselineFrac: 0.20),
    IconSpec(px: 64,   name: "icon_32x32@2x.png",   pixelCount: 2000, cellSize: 1,  baselineFrac: 0.17),
    IconSpec(px: 128,  name: "icon_128x128.png",    pixelCount: 2000, cellSize: 2,  baselineFrac: 0.17),
    IconSpec(px: 256,  name: "icon_128x128@2x.png", pixelCount: 2000, cellSize: 4,  baselineFrac: 0.17),
    IconSpec(px: 256,  name: "icon_256x256.png",    pixelCount: 2000, cellSize: 4,  baselineFrac: 0.17),
    IconSpec(px: 512,  name: "icon_256x256@2x.png", pixelCount: 2000, cellSize: 8,  baselineFrac: 0.17),
    IconSpec(px: 512,  name: "icon_512x512.png",    pixelCount: 2000, cellSize: 8,  baselineFrac: 0.17),
    IconSpec(px: 1024, name: "icon_512x512@2x.png", pixelCount: 2000, cellSize: 16, baselineFrac: 0.17),
]

func renderIcon(spec: IconSpec, outURL: URL) {
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil,
        width: spec.px, height: spec.px,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return }

    drawBackdrop(ctx: ctx, width: spec.px, height: spec.px, rounded: true)

    // Inside the rounded backdrop, also clip the rock so it never
    // pokes through the rounded corners.
    ctx.saveGState()
    let r = CGFloat(spec.px) * 0.225
    let path = CGPath(
        roundedRect: CGRect(x: 0, y: 0, width: spec.px, height: spec.px),
        cornerWidth: r, cornerHeight: r, transform: nil
    )
    ctx.addPath(path)
    ctx.clip()

    let centerX  = CGFloat(spec.px) / 2
    let baseline = CGFloat(spec.px) * CGFloat(spec.baselineFrac)
    drawBoulder(
        ctx: ctx,
        width: spec.px, height: spec.px,
        pixelCount: spec.pixelCount,
        cellSize: spec.cellSize,
        centerX: centerX,
        baselineY: baseline
    )
    ctx.restoreGState()

    guard let cgImage = ctx.makeImage(),
          let dest = CGImageDestinationCreateWithURL(
            outURL as CFURL, UTType.png.identifier as CFString, 1, nil
          ) else { return }
    CGImageDestinationAddImage(dest, cgImage, nil)
    _ = CGImageDestinationFinalize(dest)
}

// =============================================================
// 1200x630 social/OG card — boulder on the brand backdrop,
// "Boulder" wordmark + tagline.
// =============================================================
func renderOGCard(outURL: URL) {
    let W = 1200, H = 630
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil,
        width: W, height: H,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return }

    // No rounded mask — social cards display as plain rectangles.
    drawBackdrop(ctx: ctx, width: W, height: H, rounded: false)

    // Boulder placement: left third of the card, sitting on a
    // visible baseline ~15% from the bottom. ASPECT=0.85 means
    // 5600 cells = 110 × 65 cells. At cellSize=5 → 550 × 325 px,
    // a chunky hero rock that anchors the social card visually.
    let centerX = CGFloat(W) * 0.27
    let baseline = CGFloat(H) * 0.15
    drawBoulder(
        ctx: ctx,
        width: W, height: H,
        pixelCount: 5600,
        cellSize: 5,
        centerX: centerX,
        baselineY: baseline
    )

    // Text: "Boulder" wordmark + tagline. Use CoreText.
    func draw(text: String, x: CGFloat, y: CGFloat, size: CGFloat,
              weight: CGFloat, alpha: CGFloat) {
        let fontDescAttrs: [CFString: Any] = [
            kCTFontFamilyNameAttribute: "SF Pro Display" as CFString,
            kCTFontTraitsAttribute: [kCTFontWeightTrait: weight] as CFDictionary
        ]
        var fontDesc = CTFontDescriptorCreateWithAttributes(fontDescAttrs as CFDictionary)
        var font = CTFontCreateWithFontDescriptor(fontDesc, size, nil)
        // Fall back to system "Helvetica" family if SF Pro Display
        // isn't available (some CI environments).
        let postScript = CTFontCopyPostScriptName(font) as String
        if !postScript.lowercased().contains("sf") &&
           !postScript.lowercased().contains("system") {
            let alt: [CFString: Any] = [
                kCTFontFamilyNameAttribute: "Helvetica" as CFString,
                kCTFontTraitsAttribute: [kCTFontWeightTrait: weight] as CFDictionary
            ]
            fontDesc = CTFontDescriptorCreateWithAttributes(alt as CFDictionary)
            font = CTFontCreateWithFontDescriptor(fontDesc, size, nil)
        }

        let color = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: alpha)
        // Use CoreText attribute keys directly — works without AppKit.
        let attrs: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: color
        ]
        let cfText = text as CFString
        let attributed = CFAttributedStringCreate(
            kCFAllocatorDefault, cfText, attrs as CFDictionary
        )!
        let line = CTLineCreateWithAttributedString(attributed)

        ctx.saveGState()
        ctx.textMatrix = .identity
        ctx.setShouldAntialias(true)
        ctx.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }

    // Right two-thirds: text block.
    let textX: CGFloat = CGFloat(W) * 0.52
    // "Boulder" — chunky weight, big.
    draw(text: "Boulder",
         x: textX, y: CGFloat(H) * 0.55,
         size: 140, weight: 0.62, alpha: 1.0)
    // Tagline.
    draw(text: "A pet rock for your focus.",
         x: textX, y: CGFloat(H) * 0.40,
         size: 44, weight: 0.20, alpha: 0.85)
    // Small footer URL/footnote.
    draw(text: "macOS · Free · MIT",
         x: textX, y: CGFloat(H) * 0.28,
         size: 26, weight: 0.10, alpha: 0.55)

    guard let cgImage = ctx.makeImage(),
          let dest = CGImageDestinationCreateWithURL(
            outURL as CFURL, UTType.png.identifier as CFString, 1, nil
          ) else { return }
    CGImageDestinationAddImage(dest, cgImage, nil)
    _ = CGImageDestinationFinalize(dest)
}

// =============================================================
// Run.
// =============================================================
let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write("usage: swift make-icon.swift <iconset-dir> <og-card-path>\n".data(using: .utf8)!)
    exit(1)
}
let iconsetDir = URL(fileURLWithPath: args[1])
let ogCardURL  = URL(fileURLWithPath: args[2])

for spec in SIZES {
    renderIcon(spec: spec, outURL: iconsetDir.appendingPathComponent(spec.name))
}
renderOGCard(outURL: ogCardURL)

print("✓ wrote \(SIZES.count) PNGs to \(iconsetDir.path)")
print("✓ wrote og-card to \(ogCardURL.path)")
SWIFT

swift "$TMP_SWIFT" "$TMP_OUT" "$TMP_OUT/og-card.png" 2>&1 | grep -v "^warning:" || true
cp "$TMP_OUT"/icon_*.png "$ICONSET/"
cp "$TMP_OUT/og-card.png" "$WEBSITE_DIR/og-card.png"

cat > "$ICONSET/Contents.json" <<'JSON'
{
  "images" : [
    { "filename" : "icon_16x16.png",      "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "filename" : "icon_16x16@2x.png",   "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "filename" : "icon_32x32.png",      "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "filename" : "icon_32x32@2x.png",   "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "filename" : "icon_128x128.png",    "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "filename" : "icon_128x128@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "filename" : "icon_256x256.png",    "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "filename" : "icon_256x256@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "filename" : "icon_512x512.png",    "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "filename" : "icon_512x512@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON

echo ""
echo "✓ Icon set written to $ICONSET"
ls -lh "$ICONSET"/*.png
echo ""
echo "✓ OG card written to $WEBSITE_DIR/og-card.png"
ls -lh "$WEBSITE_DIR/og-card.png"
