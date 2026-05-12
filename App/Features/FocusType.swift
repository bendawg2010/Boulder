// FocusType.swift
//
// The kind of work a focus session represents. Each type stamps a
// different visual texture into Boulder as it grows — granite crystals
// from code, smooth river-stone curves from writing, etc. The shape
// of YOUR Boulder ends up a unique signature of how you spent the
// year.

import SwiftUI

enum FocusType: String, CaseIterable, Codable, Identifiable {
    case code   = "Code"
    case write  = "Write"
    case read   = "Read"
    case audio  = "Audio"
    case design = "Design"

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .code:   return "⌨️"
        case .write:  return "✍️"
        case .read:   return "📖"
        case .audio:  return "🎧"
        case .design: return "🎨"
        }
    }

    var subtitle: String {
        switch self {
        case .code:   return "Spiky / crystalline"
        case .write:  return "Smooth / river stone"
        case .read:   return "Sedimentary layers"
        case .audio:  return "Geode pockets"
        case .design: return "Marbled swirl"
        }
    }

    /// Palette for the pixels this session adds to Boulder.
    /// Tuned to be earthy with brand-palette accents — not garish.
    var palette: [Color] {
        switch self {
        case .code:
            return [Color(hex: 0x3B3B45), Color(hex: 0x5A5A6E), Color(hex: 0x8E8AA8), Color(hex: 0xC147FF)]
        case .write:
            return [Color(hex: 0x6A5A4A), Color(hex: 0x8B7860), Color(hex: 0xB5A085), Color(hex: 0xD9C7A8)]
        case .read:
            return [Color(hex: 0x4A3526), Color(hex: 0x7A5638), Color(hex: 0x9E7549), Color(hex: 0xC59766)]
        case .audio:
            return [Color(hex: 0x2E3E4F), Color(hex: 0x44627A), Color(hex: 0x2EE6A0), Color(hex: 0x47A0FF)]
        case .design:
            return [Color(hex: 0x5C3A4B), Color(hex: 0x8C5468), Color(hex: 0xFF6B6B), Color(hex: 0xFFD960)]
        }
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >>  8) & 0xFF) / 255.0
        let b = Double( hex        & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}
