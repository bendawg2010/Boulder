// BoulderStore.swift
//
// Single observable owner of BoulderModel. Drives focus session
// lifecycle, persistence, momentum-tier multiplier, app blocker
// callbacks, and tag/session CRUD.

import Foundation
import SwiftUI
import Combine

@MainActor
final class BoulderStore: ObservableObject {
    static let shared = BoulderStore()

    // MARK: Published state

    @Published var model: BoulderModel
    @Published var isFocusing: Bool = false
    @Published var sessionElapsed: TimeInterval = 0
    @Published var isReleasing: Bool = false
    @Published var crumbleFlashAt: Date? = nil

    /// The tag the user has picked for the *next* focus session.
    /// Bound to the popover's tag picker. Defaults to the first
    /// available tag on load.
    @Published var selectedTagID: UUID

    /// What the user types into the description field before pressing
    /// Focus. Captured into the FocusSession on startFocus().
    @Published var draftBlurb: String = ""

    /// User's pre-selected session duration (seconds).
    /// - nil  → user hasn't picked anything yet (no chip selected)
    /// - some(0)   → user explicitly picked Open (no commitment)
    /// - some(>0)  → committed duration in seconds
    ///
    /// We use the 0 sentinel instead of a second nil case so the
    /// UI can distinguish "nothing picked" from "Open picked" — that
    /// distinction is what makes the picker not look pre-selected.
    @Published var draftDuration: TimeInterval? = nil

    /// The ID of the currently-running FocusSession, if any.
    /// nil between sessions.
    @Published var currentSessionID: UUID? = nil

    /// Set briefly when a committed session completes naturally
    /// (timer reaches 0). Popover plays a golden flash.
    @Published var completionFlashAt: Date? = nil

    // MARK: Init / persistence

    private init() {
        var loaded = Persistence.load() ?? BoulderModel()
        // Migration: pre-v1.4 pixels used a jittered golden-angle
        // spiral that looked like scattered rubble. v1.4 introduces
        // BoulderShape — a deterministic dense dome silhouette.
        // Re-derive every existing pixel's position from its index
        // so old rocks look solid too. Tag/session attribution is
        // preserved per pixel; only the (x, y, shade) get updated.
        if loaded.schemaVersion < 3 {
            loaded.pixels = Self.reshape(loaded.pixels)
            loaded.schemaVersion = 3
        }
        self.model = loaded
        self.selectedTagID = loaded.tags.first?.id ?? UUID()
    }

    private static func reshape(_ old: [BoulderPixel]) -> [BoulderPixel] {
        old.enumerated().map { (i, p) -> BoulderPixel in
            guard i < BoulderShape.cells.count else { return p }
            let cell = BoulderShape.cells[i]
            return BoulderPixel(
                x: cell.x, y: cell.y,
                tagID: p.tagID, sessionID: p.sessionID,
                shade: cell.shade,
                legacyType: p.legacyType
            )
        }
    }

    func persist() { Persistence.save(model) }

    // MARK: Tick

    func tick() {
        guard isFocusing else { return }
        sessionElapsed += 1

        model.pixelAccumulator += PIXELS_PER_SECOND * currentMultiplier
        while model.pixelAccumulator >= 1.0 {
            model.pixelAccumulator -= 1.0
            emitPixel()
        }
        if Int(sessionElapsed) % 30 == 0 { persist() }

        // Committed session reached its planned duration → auto-complete
        // with a bonus. The bonus is small but real, so following through
        // on a commit always nets more pixels than abandoning would.
        if let target = currentPlannedDuration, sessionElapsed >= target {
            completeCommittedSession()
        }
    }

    /// Number of seconds remaining on the committed timer, or nil
    /// when the session is open-ended (no preselected duration).
    var timeRemaining: TimeInterval? {
        guard let target = currentPlannedDuration else { return nil }
        return max(0, target - sessionElapsed)
    }

    private var currentPlannedDuration: TimeInterval? {
        session(forID: currentSessionID)?.plannedDuration
    }

    private func emitPixel() {
        let n = model.pixels.count
        guard n < BoulderShape.cells.count else { return }
        let cell = BoulderShape.cells[n]
        model.pixels.append(BoulderPixel(
            x: cell.x, y: cell.y,
            tagID: selectedTagID,
            sessionID: currentSessionID,
            shade: cell.shade
        ))
    }

    // MARK: Momentum tiers

    var currentMultiplier: Double { Self.multiplier(forElapsed: sessionElapsed) }

    static func multiplier(forElapsed t: TimeInterval) -> Double {
        switch t {
        case ..<300:     return 1.0
        case 300..<900:  return lerp(1.0, 1.5, t: (t -  300) /  600)
        case 900..<1800: return lerp(1.5, 2.0, t: (t -  900) /  900)
        case 1800..<3600: return lerp(2.0, 3.0, t: (t - 1800) / 1800)
        default:         return 3.0
        }
    }

    var momentumTierLabel: String {
        switch sessionElapsed {
        case ..<300:  return "Warming up"
        case ..<900:  return "Rolling"
        case ..<1800: return "Locked in"
        case ..<3600: return "Flow state"
        default:      return "Deep flow"
        }
    }

    // MARK: Session control

    func startFocus() {
        // Refuse to start without a tag — every pixel must be tagged.
        guard model.tags.contains(where: { $0.id == selectedTagID }) else { return }
        // Treat the 0 sentinel ("Open" chip explicitly picked) and
        // nil ("no chip picked at all") as the same open-ended case.
        // Only a strictly-positive draftDuration becomes a commitment.
        let planned: TimeInterval? = {
            guard let d = draftDuration, d > 0 else { return nil }
            return d
        }()
        let session = FocusSession(
            tagID: selectedTagID,
            blurb: draftBlurb.trimmingCharacters(in: .whitespacesAndNewlines),
            plannedDuration: planned
        )
        model.sessions.append(session)
        currentSessionID = session.id
        sessionElapsed = 0
        isFocusing = true
    }

    /// Normal stop — open-ended session, or a committed session that
    /// the user is allowed to end. Closes the record, no penalty.
    func stopFocus() {
        isFocusing = false
        if let sid = currentSessionID,
           let idx = model.sessions.firstIndex(where: { $0.id == sid }) {
            model.sessions[idx].endedAt = Date()
            let earned = model.pixels.filter { $0.sessionID == sid }.count
            model.sessions[idx].pixelsGrown = earned
        }
        currentSessionID = nil
        draftBlurb = ""
        draftDuration = nil
        persist()
    }

    /// Number of pixels a give-up costs RIGHT NOW for the current
    /// committed session. 25% of pixels earned this session, floor 5.
    var giveUpPenalty: Int {
        guard let sid = currentSessionID else { return 0 }
        let earned = model.pixels.filter { $0.sessionID == sid }.count
        return max(5, Int(Double(earned) * 0.25))
    }

    /// User pressed "Give up" on a committed session before the
    /// timer ran out. Marks the session as abandoned, crumbles a
    /// penalty off Boulder, then stops normally. Penalty is capped
    /// by what was earned + a small floor — Boulder can lose pixels
    /// you earned this session, but not pixels from before.
    func giveUpEarly() {
        guard let sid = currentSessionID else { stopFocus(); return }
        let penalty = giveUpPenalty
        if let idx = model.sessions.firstIndex(where: { $0.id == sid }) {
            model.sessions[idx].gaveUp = true
        }
        crumble(pixels: penalty)
        stopFocus()
    }

    /// Committed session reached its planned duration. Adds a small
    /// completion bonus and emits a completion-flash signal for the
    /// UI to celebrate.
    private func completeCommittedSession() {
        guard isFocusing else { return }
        // Bonus pixels: 5 + 1 per 5 minutes committed (capped at 25).
        let target = currentPlannedDuration ?? 0
        let bonus = min(25, 5 + Int(target / 300))
        for _ in 0..<bonus { emitPixel() }
        completionFlashAt = Date()
        stopFocus()
    }

    /// Called by AppDelegate.applicationWillTerminate. If a committed
    /// session is in progress, treat the quit as a give-up so the
    /// penalty applies on next launch. Without this, force-quitting
    /// Boulder would be a free escape hatch from commitment.
    func handleQuitDuringSession() {
        guard isFocusing, currentPlannedDuration != nil else {
            persist()
            return
        }
        giveUpEarly()
    }

    // MARK: Crumble

    func crumble(pixels n: Int) {
        let count = max(0, min(n, model.pixels.count))
        guard count > 0 else { return }
        model.pixels.removeLast(count)
        crumbleFlashAt = Date()
        persist()
    }

    // MARK: Release

    func releaseBoulder() {
        guard model.canRelease else { return }
        let dominant = dominantType(in: model.pixels) ?? .code
        let retired = RetiredBoulder(
            id: model.id,
            startedAt: model.startedAt,
            releasedAt: Date(),
            pixels: model.pixels,
            dominantType: dominant,
            tagSnapshot: model.tags
        )
        var newModel = BoulderModel()
        newModel.range = model.range + [retired]
        newModel.tags = model.tags                  // user keeps their tag library
        newModel.blockedApps = model.blockedApps    // and their blocked-app list
        model = newModel
        isReleasing = false
        persist()
    }

    private func dominantType(in pixels: [BoulderPixel]) -> FocusType? {
        var counts: [FocusType: Int] = [:]
        for p in pixels {
            if let t = p.legacyType { counts[t, default: 0] += 1 }
        }
        return counts.max(by: { $0.value < $1.value })?.key
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

    // MARK: Tags

    func addTag(_ tag: FocusTag) {
        model.tags.append(tag)
        // Auto-select the very first tag the user creates so they can
        // immediately press Focus.
        if model.tags.count == 1 { selectedTagID = tag.id }
        persist()
    }

    func updateTag(_ tag: FocusTag) {
        guard let idx = model.tags.firstIndex(where: { $0.id == tag.id }) else { return }
        model.tags[idx] = tag
        persist()
    }

    func deleteTag(id: UUID) {
        // Tag removal is non-destructive to pixels: pixels still carry
        // the tagID even if the tag struct is gone. The renderer falls
        // back to a neutral grey palette for orphan tagIDs so old
        // pixels still draw.
        model.tags.removeAll { $0.id == id }
        if selectedTagID == id, let first = model.tags.first {
            selectedTagID = first.id
        }
        persist()
    }

    func tag(forID id: UUID?) -> FocusTag? {
        guard let id else { return nil }
        return model.tags.first { $0.id == id }
    }

    func session(forID id: UUID?) -> FocusSession? {
        guard let id else { return nil }
        return model.sessions.first { $0.id == id }
    }

    /// Resolves the palette for a pixel — tag's palette if tagID
    /// matches a known tag, else legacy FocusType.palette, else a
    /// neutral fallback so the pixel still draws.
    func palette(for pixel: BoulderPixel) -> [Color] {
        if let tag = tag(forID: pixel.tagID) { return tag.palette }
        if let t = pixel.legacyType { return t.palette }
        return Self.neutralPalette
    }

    static let neutralPalette: [Color] = [
        Color(white: 0.18), Color(white: 0.35),
        Color(white: 0.55), Color(white: 0.80)
    ]

    var selectedTag: FocusTag? { tag(forID: selectedTagID) }
}

// MARK: - Tiny helpers

private func lerp(_ a: Double, _ b: Double, t: Double) -> Double {
    let clamped = max(0, min(1, t))
    return a + (b - a) * clamped
}

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
