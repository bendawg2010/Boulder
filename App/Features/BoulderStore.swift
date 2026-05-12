// BoulderStore.swift
//
// The single observable owner of BoulderModel. Drives the focus
// session lifecycle, handles persistence to ~/Library/Application
// Support/Boulder/state.json, and emits SwiftUI updates as Boulder
// grows.

import Foundation
import SwiftUI
import Combine

@MainActor
final class BoulderStore: ObservableObject {
    static let shared = BoulderStore()

    // MARK: Published state

    @Published var model: BoulderModel
    @Published var selectedFocusType: FocusType = .code

    /// Whether a focus session is currently running. Persisted across
    /// app restarts intentionally? No — we DON'T persist this. If you
    /// quit the app, the session pauses. Background growth would
    /// undermine "the visible sculpture is the proof of work."
    @Published var isFocusing: Bool = false

    /// Wall-clock seconds spent focused this session. Resets to 0
    /// each Start. Purely cosmetic for the timer label.
    @Published var sessionElapsed: TimeInterval = 0

    /// True while the release ceremony is playing — popover shows a
    /// rolling-off animation, suppresses interaction.
    @Published var isReleasing: Bool = false

    /// Set briefly when FocusBlocker crumbles Boulder. The popover
    /// reads this to play a shake/flash animation. UI clears it after
    /// the animation finishes — no persistent UI state.
    @Published var crumbleFlashAt: Date? = nil

    // MARK: Init / persistence

    private init() {
        self.model = Persistence.load() ?? BoulderModel()
    }

    func persist() {
        Persistence.save(model)
    }

    // MARK: Tick (called once per second by AppDelegate)

    func tick() {
        guard isFocusing else { return }
        sessionElapsed += 1

        // Accumulate fractional pixels at the current momentum rate.
        // The longer you've been focusing, the more you earn per
        // second — see sessionMultiplier(elapsed:). Each whole
        // crossing emits one deterministically-placed BoulderPixel.
        model.pixelAccumulator += PIXELS_PER_SECOND * currentMultiplier
        while model.pixelAccumulator >= 1.0 {
            model.pixelAccumulator -= 1.0
            emitPixel()
        }

        if Int(sessionElapsed) % 30 == 0 { persist() }
    }

    // MARK: Momentum tiers

    /// Multiplier on PIXELS_PER_SECOND based on how long you've been
    /// continuously focused this session. Ramps from 1.0× at session
    /// start to 3.0× after one hour, then plateaus. The math:
    ///
    ///   ≤ 5 min   →  1.0×   (warm-up)
    ///   5–15 min  →  1.0× → 1.5×   (linear)
    ///   15–30 min →  1.5× → 2.0×   (linear)
    ///   30–60 min →  2.0× → 3.0×   (linear)
    ///   > 60 min  →  3.0×   (plateau)
    ///
    /// Stopping the session resets sessionElapsed → multiplier drops
    /// to 1.0× on next start. Encourages longer sessions without
    /// punishing breaks (Boulder doesn't shrink — momentum just
    /// resets).
    var currentMultiplier: Double {
        Self.multiplier(forElapsed: sessionElapsed)
    }

    static func multiplier(forElapsed t: TimeInterval) -> Double {
        switch t {
        case ..<300:    return 1.0
        case 300..<900: return lerp(1.0, 1.5, t: (t -  300) /  600)
        case 900..<1800: return lerp(1.5, 2.0, t: (t -  900) /  900)
        case 1800..<3600: return lerp(2.0, 3.0, t: (t - 1800) / 1800)
        default:         return 3.0
        }
    }

    /// Human-readable name for the current momentum tier — shown
    /// in the popover so the user sees the system rewarding them.
    var momentumTierLabel: String {
        switch sessionElapsed {
        case ..<300:     return "Warming up"
        case ..<900:     return "Rolling"
        case ..<1800:    return "Locked in"
        case ..<3600:    return "Flow state"
        default:         return "Deep flow"
        }
    }

    private func emitPixel() {
        let n = model.pixels.count
        // Deterministic placement: cheap pseudo-random from pixel
        // index + Boulder id hash. Looks organic, but every device
        // would replay the exact same Boulder from the same log.
        var rng = SeededRNG(seed: UInt64(bitPattern: Int64(n)) &+ UInt64(model.id.hashValue & 0xFFFFFFFF))
        let radius = sqrt(Double(n)) * 0.95
        let theta  = Double(n) * 2.39996  // golden-angle spiral → tight packing
        var x = Int(radius * cos(theta))
        var y = Int(radius * sin(theta) * 0.55)   // squashed vertically — boulders are wider than tall
        // Add a small jitter so the spiral isn't visible up close.
        x += Int(rng.nextDouble() * 3) - 1
        y += Int(rng.nextDouble() * 3) - 1
        // Most pixels sit above the baseline (y >= 0 in our convention).
        if y < 0 { y = -y / 2 }
        let shade = Int(rng.nextDouble() * 4) % 4

        model.pixels.append(BoulderPixel(
            x: x, y: y,
            type: selectedFocusType,
            shade: shade
        ))
    }

    // MARK: Session control

    func startFocus() {
        sessionElapsed = 0
        isFocusing = true
    }

    func stopFocus() {
        isFocusing = false
        persist()
    }

    // MARK: Release ceremony

    /// Retire the current Boulder into the Mountain Range and start a
    /// fresh pebble. Caller is expected to play the rolling-into-the-
    /// sea animation BEFORE calling this — `isReleasing` gates the UI.
    func releaseBoulder() {
        guard model.canRelease else { return }
        let dominant = dominantType(in: model.pixels) ?? .code
        let retired = RetiredBoulder(
            id: model.id,
            startedAt: model.startedAt,
            releasedAt: Date(),
            pixels: model.pixels,
            dominantType: dominant
        )
        var newModel = BoulderModel()
        newModel.range = model.range + [retired]
        model = newModel
        isReleasing = false
        persist()
    }

    // MARK: Crumble (focus broken)

    /// Remove the most recently-grown pixels from Boulder. Floor is
    /// zero — we don't go negative. Persists immediately so the
    /// punishment survives a crash.
    func crumble(pixels n: Int) {
        let count = max(0, min(n, model.pixels.count))
        guard count > 0 else { return }
        model.pixels.removeLast(count)
        crumbleFlashAt = Date()
        persist()
    }

    // MARK: Blocked apps

    func addBlockedApp(_ app: BlockedApp) {
        guard !model.blockedApps.contains(where: { $0.bundleIdentifier == app.bundleIdentifier }) else { return }
        model.blockedApps.append(app)
        persist()
    }

    func removeBlockedApp(_ bundleID: String) {
        model.blockedApps.removeAll { $0.bundleIdentifier == bundleID }
        persist()
    }

    private func dominantType(in pixels: [BoulderPixel]) -> FocusType? {
        var counts: [FocusType: Int] = [:]
        for p in pixels { counts[p.type, default: 0] += 1 }
        return counts.max(by: { $0.value < $1.value })?.key
    }
}

// MARK: - Tiny helpers

private func lerp(_ a: Double, _ b: Double, t: Double) -> Double {
    let clamped = max(0, min(1, t))
    return a + (b - a) * clamped
}

// MARK: - Tiny seeded RNG

/// xorshift64 — small, fast, deterministic. We don't need crypto
/// randomness; we just want pixels to scatter without a visible grid.
private struct SeededRNG {
    var state: UInt64
    init(seed: UInt64) { self.state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
    mutating func nextDouble() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }
}
