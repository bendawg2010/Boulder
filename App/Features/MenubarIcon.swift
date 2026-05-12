// MenubarIcon.swift
//
// Renders the current Boulder to a small NSImage suitable for the
// menubar (~18-22 points tall). Updated on every tick during focus
// sessions and on tier change otherwise.
//
// The menubar version uses TINY cells (1 pt each) so a 200-pixel
// boulder fits in a 22-point image. As Boulder grows, the menubar
// icon grows with it — visible proof of progress without opening the
// popover.

import AppKit
import SwiftUI

enum MenubarIcon {
    /// Returns a non-template image (we want the color). Sized to
    /// 22pt height — the standard NSStatusBar icon size.
    /// `paletteFor` resolves each pixel to a palette — pass the
    /// store's tag-aware resolver so the menubar icon stays in sync
    /// with the tag colors.
    static func render(
        pixels: [BoulderPixel],
        paletteFor: (BoulderPixel) -> [Color] = { p in
            p.legacyType?.palette ?? BoulderRenderer.fallbackPalette
        }
    ) -> NSImage {
        let height: CGFloat = 22
        let width:  CGFloat = 28   // a touch wider than tall — boulders are wide
        let size = NSSize(width: width, height: height)
        let cell: CGFloat = 1.0

        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        // Transparent background — menubar bg shows through.
        NSColor.clear.set()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

        let cx = width / 2
        let baseline = height - 4   // sits on the menubar baseline

        if pixels.isEmpty {
            // Empty Boulder → a single pebble dot, so the icon never
            // disappears entirely.
            let dot = NSRect(x: cx - 2, y: baseline - 2, width: 3, height: 2)
            NSColor(calibratedRed: 0.55, green: 0.46, blue: 0.38, alpha: 1.0).set()
            NSBezierPath(rect: dot).fill()
            return image
        }

        // Determine how much of the rock we can show at this size.
        // Past ~600 pixels the boulder grows taller than the menubar
        // can fit — we visually clip to the top edge, which still
        // communicates "it's getting big."
        for p in pixels {
            let x = cx + CGFloat(p.x) * cell - cell / 2
            let y = baseline - CGFloat(p.y) * cell - cell
            if y < -cell || y > height { continue }
            if x < -cell || x > width  { continue }
            let palette = paletteFor(p)
            let shade = palette[max(0, min(palette.count - 1, p.shade))]
            NSColor(shade).set()
            NSBezierPath(rect: NSRect(x: x, y: y, width: cell, height: cell)).fill()
        }

        return image
    }
}
