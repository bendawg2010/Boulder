// FocusTag.swift
//
// A user-created focus category. Each tag has a name, emoji, short
// description ("what does focusing on this tag mean to you?"), and a
// base hue from which a 4-shade palette is derived. Pixels grown
// during a session referencing this tag get painted from that
// palette, so YOUR rock visually encodes how you spent your year.
//
// Colors are constrained to a curated set of ROCK PRESETS (granite,
// slate, jade, quartz, etc.) — saturation is capped low so every
// tag reads as tinted stone, never as neon candy. The editor renders
// these as named swatches instead of a free hue slider.

import SwiftUI

struct FocusTag: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var emoji: String
    /// 0.0..1.0 hue used to derive the 4-shade palette. Stored as
    /// a float (not a preset enum) so the preset list can evolve
    /// without invalidating saved tags.
    var hue: Double
    /// Optional user-written blurb. Shown in the tag editor and when
    /// the user clicks a pixel-cluster painted by this tag.
    var blurb: String
    var createdAt: Date

    init(id: UUID = UUID(), name: String, emoji: String, hue: Double,
         blurb: String = "", createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.hue = hue
        self.blurb = blurb
        self.createdAt = createdAt
    }

    /// 20-shade tinted-stone palette interpolated between a deep
    /// shadow (saturation low, brightness ~0.15) and a crown highlight
    /// (saturation slightly higher, brightness ~0.85). The hue gives
    /// the rock its character (Granite cool, Sandstone warm, Jade
    /// gently green) but no shade ever reads as a pure color — the
    /// rock always reads as rock first, tag second.
    ///
    /// Index 0 is the darkest shadow, index 19 is the brightest
    /// crown highlight. BoulderShape.Cell.shade maps directly into
    /// this array — see BoulderShape.shadeLevels (must stay in sync).
    var palette: [Color] {
        let count = 20
        return (0..<count).map { i in
            let t = Double(i) / Double(count - 1)
            // Brightness curve: gently steeper near the highlight.
            let b = 0.15 + (0.85 - 0.15) * pow(t, 0.95)
            // Saturation curve: stays low at the bottom so shadows
            // never look chromatic; midtones get the most tint.
            let s = 0.08 + 0.22 * sin(.pi * t)
            return Color(hue: hue, saturation: s, brightness: b)
        }
    }

    /// Color used for the tag chip itself — slightly more saturated
    /// than the palette so the chip is identifiable, but still firmly
    /// in stone-tint territory.
    var chipColor: Color {
        Color(hue: hue, saturation: 0.42, brightness: 0.66)
    }

    /// Curated rock-like hues the tag editor offers as named swatches.
    static let rockPresets: [RockPreset] = [
        .init(name: "Granite",   hue: 0.62),
        .init(name: "Slate",     hue: 0.58),
        .init(name: "Basalt",    hue: 0.05),
        .init(name: "Sandstone", hue: 0.09),
        .init(name: "Limestone", hue: 0.13),
        .init(name: "Schist",    hue: 0.25),
        .init(name: "Jade",      hue: 0.36),
        .init(name: "Marble",    hue: 0.55),
        .init(name: "Lapis",     hue: 0.65),
        .init(name: "Amethyst",  hue: 0.78),
        .init(name: "Quartz",    hue: 0.95),
        .init(name: "Hematite",  hue: 0.02),
    ]
}

struct RockPreset: Identifiable, Hashable {
    let name: String
    let hue: Double
    var id: String { name }
    var swatch: Color {
        Color(hue: hue, saturation: 0.50, brightness: 0.72)
    }
    var palette: [Color] {
        FocusTag(name: "", emoji: "", hue: hue).palette
    }
}
