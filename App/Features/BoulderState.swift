// BoulderState.swift
//
// The persistent model behind your one and only Boulder.
//
// Pixel coloring is resolved through tagID lookup: each pixel has a
// `tagID` referring to a FocusTag in `model.tags`, and the renderer
// uses that tag's palette to paint. Pixels older than v1.3.0 don't
// have a tagID; they fall back to `legacyType` (a FocusType raw
// value) for their color, so existing rocks render exactly as before.

import Foundation
import SwiftUI

/// Rate at which a running focus session emits pixels into Boulder
/// (before the momentum multiplier). 1 / 12 ≈ a pixel every 12 seconds
/// at 1.0× → ~300 pixels per hour at full focus.
let PIXELS_PER_SECOND: Double = 1.0 / 12.0

/// One generated pixel. Position is in a normalized unit grid; the
/// renderer scales to the current size tier on draw.
struct BoulderPixel: Codable, Hashable {
    var x: Int
    var y: Int
    /// New (v1.3.0+) — UUID of the FocusTag that minted this pixel.
    /// Nil for legacy pixels grown before tags existed.
    var tagID: UUID? = nil
    /// New (v1.3.0+) — the FocusSession that emitted this pixel.
    /// Nil for legacy pixels. Used by the click-to-inspect feature.
    var sessionID: UUID? = nil
    /// Legacy (≤ v1.2.0) — used as a color fallback when tagID is nil.
    var legacyType: FocusType? = nil
    /// 0..3 index into the palette of either the tag or legacyType.
    var shade: Int

    // Backwards-compat decoder: old payloads encoded `type` (FocusType)
    // as a required field. We accept either `type` or `legacyType`,
    // and store the result in `legacyType`.
    private enum CodingKeys: String, CodingKey {
        case x, y, tagID, sessionID, legacyType, type, shade
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.x = try c.decode(Int.self, forKey: .x)
        self.y = try c.decode(Int.self, forKey: .y)
        self.shade = try c.decode(Int.self, forKey: .shade)
        self.tagID = try c.decodeIfPresent(UUID.self, forKey: .tagID)
        self.sessionID = try c.decodeIfPresent(UUID.self, forKey: .sessionID)
        if let legacy = try c.decodeIfPresent(FocusType.self, forKey: .legacyType) {
            self.legacyType = legacy
        } else {
            self.legacyType = try c.decodeIfPresent(FocusType.self, forKey: .type)
        }
    }
    init(x: Int, y: Int, tagID: UUID?, sessionID: UUID?, shade: Int,
         legacyType: FocusType? = nil) {
        self.x = x; self.y = y
        self.tagID = tagID; self.sessionID = sessionID
        self.shade = shade; self.legacyType = legacyType
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(x, forKey: .x)
        try c.encode(y, forKey: .y)
        try c.encode(shade, forKey: .shade)
        try c.encodeIfPresent(tagID, forKey: .tagID)
        try c.encodeIfPresent(sessionID, forKey: .sessionID)
        try c.encodeIfPresent(legacyType, forKey: .legacyType)
    }
}

enum SizeTier: String, Codable, CaseIterable {
    case pebble    = "Pebble"
    case stone     = "Stone"
    case rock      = "Rock"
    case boulder   = "Boulder"
    case mountain  = "Mountain"

    static func from(pixelCount: Int) -> SizeTier {
        switch pixelCount {
        case ..<60:    return .pebble
        case ..<300:   return .stone
        case ..<1200:  return .rock
        case ..<5000:  return .boulder
        default:       return .mountain
        }
    }

    var thresholdPixels: Int {
        switch self {
        case .pebble:   return 0
        case .stone:    return 60
        case .rock:     return 300
        case .boulder:  return 1200
        case .mountain: return 5000
        }
    }
}

struct RetiredBoulder: Codable, Identifiable, Hashable {
    var id: UUID
    var startedAt: Date
    var releasedAt: Date
    var pixels: [BoulderPixel]
    var dominantType: FocusType
    /// Snapshot of the tags this Boulder was painted with — kept
    /// alongside the pixels so the gallery can render historical
    /// Boulders correctly even after the user deletes tags later.
    var tagSnapshot: [FocusTag] = []
}

struct BoulderModel: Codable {
    var schemaVersion: Int = 2
    var id: UUID = UUID()
    var startedAt: Date = Date()
    var pixels: [BoulderPixel] = []
    var pixelAccumulator: Double = 0.0
    var range: [RetiredBoulder] = []
    var blockedApps: [BlockedApp] = []

    /// User's tag library. Seeded with `FocusTag.defaults` on first
    /// load; freely editable thereafter.
    var tags: [FocusTag] = []

    /// Append-only log of every focus session you've ever started.
    /// Each pixel references one of these by sessionID for the
    /// click-to-inspect feature.
    var sessions: [FocusSession] = []

    var pixelCount: Int { pixels.count }
    var tier: SizeTier { SizeTier.from(pixelCount: pixelCount) }

    var tierProgress: Double {
        let tiers = SizeTier.allCases
        guard let idx = tiers.firstIndex(of: tier) else { return 0 }
        let lo = tier.thresholdPixels
        let hi: Int = (idx + 1 < tiers.count) ? tiers[idx + 1].thresholdPixels : (lo + 1)
        let span = max(1, hi - lo)
        let into = max(0, pixelCount - lo)
        return min(1.0, Double(into) / Double(span))
    }

    var canRelease: Bool { tier == .mountain }
}
