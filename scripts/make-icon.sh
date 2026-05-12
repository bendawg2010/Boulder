#!/bin/bash
# Generate Boulder's app icon set from a pure-CoreGraphics Swift
# script (no NSImage, no display required) and write the PNGs into
# App/Assets.xcassets/AppIcon.appiconset/.

set -euo pipefail
cd "$(dirname "$0")/.."

ICONSET="App/Assets.xcassets/AppIcon.appiconset"
mkdir -p "$ICONSET"

TMP_SWIFT="$(mktemp -t boulder-icon-gen).swift"
TMP_OUT="$(mktemp -d -t boulder-icons)"
trap "rm -rf '$TMP_SWIFT' '$TMP_OUT'" EXIT

cat > "$TMP_SWIFT" <<'SWIFT'
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation

// Render a pixel boulder of the same shape used in-app to a PNG of
// the requested pixel dimension. Pure CGContext — no AppKit, so this
// runs fine from any CLI environment.

func boulderPixels(count: Int) -> [(x: Double, y: Double, shadeIdx: Int)] {
    var out: [(Double, Double, Int)] = []
    var seed: UInt64 = 0x9E3779B97F4A7C15
    func rng() -> Double {
        seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
        return Double(seed >> 11) / Double(UInt64(1) << 53)
    }
    for n in 0..<count {
        let radius = sqrt(Double(n)) * 0.95
        let theta  = Double(n) * 2.39996
        let x = radius * cos(theta) + (rng() * 2 - 1) * 0.6
        var y = radius * sin(theta) * 0.55 + (rng() * 2 - 1) * 0.6
        if y < 0 { y = -y / 2 }
        let shade = Int(rng() * 4) % 4
        out.append((x, y, shade))
    }
    return out
}

// Warm earthy palette with a magenta accent so the icon doesn't read
// as pure brown / monochrome.
let palette: [CGColor] = [
    CGColor(srgbRed: 0.23, green: 0.23, blue: 0.27, alpha: 1.0),
    CGColor(srgbRed: 0.36, green: 0.36, blue: 0.44, alpha: 1.0),
    CGColor(srgbRed: 0.55, green: 0.54, blue: 0.66, alpha: 1.0),
    CGColor(srgbRed: 0.76, green: 0.28, blue: 1.00, alpha: 1.0)
]

let pixels = boulderPixels(count: 1800)

func render(px: Int, outURL: URL) {
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil,
        width: px, height: px,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return }
    ctx.interpolationQuality = .none

    // Rounded-rect mask — Apple's icon mask handles the squircle in
    // dock/finder, but we round our own corners for a cleaner edge
    // inside the bitmap (helps when shown without a system mask, e.g.
    // in the About panel).
    let bg = CGRect(x: 0, y: 0, width: px, height: px)
    let r = CGFloat(px) * 0.225
    let roundedPath = CGPath(roundedRect: bg, cornerWidth: r, cornerHeight: r, transform: nil)
    ctx.addPath(roundedPath)
    ctx.clip()

    // Night-sky gradient backdrop.
    let colors = [
        CGColor(srgbRed: 0.07, green: 0.04, blue: 0.12, alpha: 1),
        CGColor(srgbRed: 0.18, green: 0.10, blue: 0.32, alpha: 1)
    ] as CFArray
    let gradient = CGGradient(colorsSpace: cs, colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: CGFloat(px)),
        end:   CGPoint(x: 0, y: 0),
        options: []
    )

    // Boulder. CGContext's origin is bottom-left; we render the rock
    // with y growing UP, so a higher `p.y` in our model lands higher
    // on the canvas. Baseline is ~22% from the bottom.
    let baselineY = CGFloat(px) * 0.22
    let cx = CGFloat(px) / 2
    let cell = CGFloat(px) / 70.0  // ~75% width fill at every size
    for p in pixels {
        let rect = CGRect(
            x: cx + CGFloat(p.x) * cell - cell / 2,
            y: baselineY + CGFloat(p.y) * cell,
            width: cell,
            height: cell
        )
        ctx.setFillColor(palette[p.shadeIdx])
        ctx.fill(rect)
    }

    guard let cgImage = ctx.makeImage(),
          let dest = CGImageDestinationCreateWithURL(
            outURL as CFURL, UTType.png.identifier as CFString, 1, nil
          ) else { return }
    CGImageDestinationAddImage(dest, cgImage, nil)
    _ = CGImageDestinationFinalize(dest)
}

let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
let sizes: [(Int, String)] = [
    (16,   "icon_16x16.png"),
    (32,   "icon_16x16@2x.png"),
    (32,   "icon_32x32.png"),
    (64,   "icon_32x32@2x.png"),
    (128,  "icon_128x128.png"),
    (256,  "icon_128x128@2x.png"),
    (256,  "icon_256x256.png"),
    (512,  "icon_256x256@2x.png"),
    (512,  "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]
for (px, name) in sizes {
    render(px: px, outURL: outDir.appendingPathComponent(name))
}
print("✓ wrote \(sizes.count) PNGs to \(outDir.path)")
SWIFT

swift "$TMP_SWIFT" "$TMP_OUT" 2>&1 | grep -v "^warning:" || true
cp "$TMP_OUT"/icon_*.png "$ICONSET/"

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
