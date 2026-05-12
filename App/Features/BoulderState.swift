// BoulderState.swift
//
// The persistent model behind your one and only Boulder.
//
// The growth mechanic in one paragraph:
//   • Each focus session generates "pixels" at a constant rate
//     (PIXELS_PER_SECOND). Sessions don't subtract — pausing or
//     stopping just halts accumulation. There is no death.
//   • Each generated pixel is recorded with its FocusType and a
//     deterministic placement offset so Boulder's shape is reproducible
//     from the pixel log on any device, and so the renderer can pull
//     palette and texture from focus type per pixel.
//   • Size tiers (Pebble → Stone → Rock → Boulder → Mountain) are
//     pure functions of total pixel count.
//
// The pixel log is the source of truth — render is a function of it.

import Foundation
import SwiftUI

/// Rate at which a running focus session emits pixels into Boulder.
/// 1 / 12 ≈ a pixel every 12 seconds → ~300 pixels per hour →
/// ~6,000 pixels per 20 hours of focused work → "Mountain" size.
let PIXELS_PER_SECOND: Double = 1.0 / 12.0

/// One generated pixel. Position is in a normalized unit grid; the
/// renderer scales to the current size tier on draw.
struct BoulderPixel: Codable, Hashable {
    var x: Int          // grid X (negative = left of center)
    var y: Int          // grid Y (negative = below baseline)
    var type: FocusType
    var shade: Int      // 0..3 → index into FocusType.palette
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

    /// Cumulative pixels that put Boulder at the BOTTOM of this tier.
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

/// A retired Boulder lives in the Mountain Range gallery — frozen
/// silhouette + birth/release dates. The user can release once
/// they've reached the Mountain tier.
struct RetiredBoulder: Codable, Identifiable, Hashable {
    var id: UUID
    var startedAt: Date
    var releasedAt: Date
    var pixels: [BoulderPixel]
    var dominantType: FocusType
}

/// On-disk state for the running Boulder.
struct BoulderModel: Codable {
    var id: UUID = UUID()
    var startedAt: Date = Date()
    var pixels: [BoulderPixel] = []

    /// Fractional pixel accumulator — when this crosses 1.0 we emit
    /// a real pixel into `pixels` and subtract 1.0. Lets us tick at
    /// 1 Hz while still generating pixels at a fractional rate.
    var pixelAccumulator: Double = 0.0

    var range: [RetiredBoulder] = []

    var pixelCount: Int { pixels.count }
    var tier: SizeTier { SizeTier.from(pixelCount: pixelCount) }

    /// Progress within the current tier, 0.0..1.0. The next tier's
    /// threshold defines the cap; Mountain caps at the release point.
    var tierProgress: Double {
        let tiers = SizeTier.allCases
        guard let idx = tiers.firstIndex(of: tier) else { return 0 }
        let lo = tier.thresholdPixels
        let hi: Int
        if idx + 1 < tiers.count {
            hi = tiers[idx + 1].thresholdPixels
        } else {
            hi = lo + 1   // already mountain
        }
        let span = max(1, hi - lo)
        let into = max(0, pixelCount - lo)
        return min(1.0, Double(into) / Double(span))
    }

    /// Eligible to perform the release ceremony once we hit Mountain.
    var canRelease: Bool { tier == .mountain }
}
