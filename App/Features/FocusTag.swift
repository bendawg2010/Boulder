// FocusTag.swift
//
// A user-created focus category. Each tag has a name, emoji, short
// description ("what does focusing on this tag mean to you?"), and a
// base hue from which a 4-shade palette is derived. Pixels grown
// during a session referencing this tag get painted from that
// palette, so YOUR rock visually encodes how you spent your year.
//
// The 5 built-in FocusType values (Code/Write/Read/Audio/Design) are
// seeded as default tags on first launch. The user can rename them,
// recolor them, delete them, and add their own ("Boulder app",
// "Reading Lord of the Rings", "Chess study").

import SwiftUI

struct FocusTag: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var emoji: String
    /// 0.0..1.0 hue used to derive the 4-shade palette. We store hue
    /// (not the four colors) so the palette derivation can evolve
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

    /// Derived 4-shade palette. Two darker stoney shades for body,
    /// two lighter accent shades for highlights. Earthy enough to
    /// feel like rock, vivid enough to tell tags apart at a glance.
    var palette: [Color] {
        [
            Color(hue: hue, saturation: 0.18, brightness: 0.22),
            Color(hue: hue, saturation: 0.30, brightness: 0.40),
            Color(hue: hue, saturation: 0.55, brightness: 0.65),
            Color(hue: hue, saturation: 0.80, brightness: 0.90)
        ]
    }

    /// Color used for the tag chip itself.
    var chipColor: Color {
        Color(hue: hue, saturation: 0.65, brightness: 0.78)
    }

}
