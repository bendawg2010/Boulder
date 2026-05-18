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

    /// Pixels EARNED during the running session that haven't been
    /// "minted" onto Boulder yet. The renderer doesn't see these —
    /// the user only sees the rock change on stop, when these flush
    /// in with the pour-in animation. During focus the popover shows
    /// "+N px pending" so the user still feels momentum.
    @Published var pendingPixelCount: Int = 0

    /// Set when stopFocus / completion / give-up flushes pending
    /// pixels onto the rock. Renderer reads this to animate the new
    /// pixels appearing one by one with a zoom-in / fade-in effect.
    /// Cleared automatically after the animation duration.
    @Published var flushState: FlushState? = nil

    /// One flush event — describes which pixel-array indices are
    /// "new" and when the animation started so the renderer can stage
    /// per-pixel opacity/scale.
    struct FlushState: Equatable {
        let firstNewIndex: Int
        let count: Int
        let startedAt: Date
        /// Seconds between each pixel's appearance.
        let stagger: TimeInterval
        /// Per-pixel fade-in window — kept on the state so the renderer
        /// matches whatever pacing the store chose.
        let fadeIn: TimeInterval
        /// Total animation duration including the trailing pause.
        var totalDuration: TimeInterval {
            // fadeIn + stagger * (count - 1) + 1.2s celebratory tail
            return fadeIn + stagger * Double(max(0, count - 1)) + 1.2
        }
    }

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

        // Cloud sync: pull the server copy in the background. If it's
        // newer than our local startedAt, swap it in. This is the
        // "open Boulder on a second Mac, get your same rock" story.
        if loaded.cloudSyncEnabled, let syncID = loaded.syncID {
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let remote = await BoulderSync.shared.pull(syncID: syncID),
                   remote.pixels.count >= self.model.pixels.count
                {
                    var merged = remote
                    merged.syncID = syncID
                    merged.cloudSyncEnabled = true
                    self.model = merged
                }
            }
        }
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

    func persist() {
        Persistence.save(model)
        // Fire-and-forget cloud sync (throttled inside BoulderSync to
        // ~one push per 5s so a busy minute doesn't hammer the API).
        if model.cloudSyncEnabled, model.syncID != nil {
            BoulderSync.shared.schedulePush(model)
        }
    }

    // MARK: Tick

    func tick() {
        guard isFocusing else { return }
        sessionElapsed += 1

        // Accumulate pending pixels — do NOT mint them onto the rock
        // until the user stops focusing. Keeps the visual reveal for
        // the pour-in animation in stopFocus().
        model.pixelAccumulator += PIXELS_PER_SECOND * currentMultiplier
        while model.pixelAccumulator >= 1.0 {
            model.pixelAccumulator -= 1.0
            pendingPixelCount += 1
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
            shade: cell.shade,
            earnedAt: Date()
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
    /// Pending pixels stay in escrow; the user must press "Claim
    /// grains" to fire the pour-in. That separation makes the reward
    /// feel earned instead of automatic.
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

    /// Mints all pendingPixelCount pixels onto the rock and triggers
    /// the slow, luxurious pour-in animation. Clears pendingPixelCount
    /// and sets flushState so BoulderRenderer staggers the new pixels'
    /// fade-in. Schedules a cleanup that nils flushState after the
    /// animation. Called from the "Claim N grains" button.
    func claimGrains() {
        let count = pendingPixelCount
        pendingPixelCount = 0
        guard count > 0 else { return }
        let firstNewIndex = model.pixels.count
        for _ in 0..<count { emitPixel() }
        // Long, deliberate pacing — each grain should feel like a
        // gem landing on the rock. Floor 0.14s so a tiny flush still
        // unfolds; ceiling 0.32s so a 5-grain claim takes ~1.5s and a
        // 50-grain claim takes ~12s. The user pressed a button to
        // start this — they're watching, so reward them.
        let perPixel = 9.0 / Double(count)
        let stagger = min(0.32, max(0.14, perPixel))
        let fadeIn: TimeInterval = 0.9
        let f = FlushState(
            firstNewIndex: firstNewIndex,
            count: count,
            startedAt: Date(),
            stagger: stagger,
            fadeIn: fadeIn
        )
        flushState = f
        persist()
        let cleanup = f.totalDuration + 0.5
        DispatchQueue.main.asyncAfter(deadline: .now() + cleanup) { [weak self] in
            guard let self else { return }
            if self.flushState == f { self.flushState = nil }
        }
    }

    /// Grace period after starting a session during which give-up
    /// costs ZERO pixels. Covers accidental starts.
    static let giveUpGracePeriod: TimeInterval = 120

    /// Is the current session still within the no-cost grace window?
    var isInGiveUpGrace: Bool {
        currentSessionID != nil && sessionElapsed < Self.giveUpGracePeriod
    }

    /// Seconds remaining in the grace window. 0 once grace has expired.
    var giveUpGraceRemaining: TimeInterval {
        max(0, Self.giveUpGracePeriod - sessionElapsed)
    }

    /// Give-up costs zero. The session ends, pending pixels still
    /// pour in via stopFocus's flush. No punishment, ever. The "give
    /// up" button is purely a graceful early-exit for committed
    /// sessions, NOT a penalty mechanic.
    var giveUpPenalty: Int { 0 }

    /// User pressed "Give up" on a committed session. Marks the
    /// session as gave-up (for the inspector flag), then ends the
    /// session normally. Pending grains remain in escrow — the user
    /// still claims them manually. Boulder never loses pixels.
    func giveUpEarly() {
        guard let sid = currentSessionID else { stopFocus(); return }
        if let idx = model.sessions.firstIndex(where: { $0.id == sid }) {
            model.sessions[idx].gaveUp = true
        }
        stopFocus()
    }

    /// Committed session reached its planned duration. Adds the
    /// bonus pixels to the pending escrow, then stops the session.
    /// The bonus stays in escrow with the regular grains; the user
    /// presses "Claim N grains" to fire the pour-in.
    private func completeCommittedSession() {
        guard isFocusing else { return }
        let target = currentPlannedDuration ?? 0
        let bonus = min(25, 5 + Int(target / 300))
        pendingPixelCount += bonus
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
            tagSnapshot: model.tags,
            name: model.rockName
        )
        var newModel = BoulderModel()
        newModel.range = model.range + [retired]
        newModel.tags = model.tags                  // user keeps their tag library
        newModel.blockedApps = model.blockedApps    // and their blocked-app list
        newModel.userFirstName = model.userFirstName // identity persists across boulders
        newModel.rockName = nil                      // new boulder, new name (or none)
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

    // MARK: Identity

    /// Set on first launch from OnboardingView, and editable later in
    /// Settings → General. An empty rockName clears the field (no
    /// name), but firstName is required for sharing.
    func setIdentity(firstName: String, rockName: String) {
        let trimmedFirst = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFirst.isEmpty else { return }
        model.userFirstName = trimmedFirst
        let trimmedRock = rockName.trimmingCharacters(in: .whitespacesAndNewlines)
        model.rockName = trimmedRock.isEmpty ? nil : trimmedRock
        // First onboarding completion always provisions a sync UUID so
        // cloud sync can be flipped on later without a fresh setup.
        if model.syncID == nil { model.syncID = UUID() }
        persist()
    }

    /// Apple Sign-In completion. Saves the stable user identifier and
    /// the name Apple returned (only present on first auth). Enables
    /// cloud sync automatically — the whole point of signing in is the
    /// cross-device story.
    func completeAppleSignIn(userID: String, firstName: String?) {
        model.appleUserID = userID
        if let n = firstName?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty {
            model.userFirstName = n
        }
        if model.syncID == nil { model.syncID = UUID() }
        model.cloudSyncEnabled = true
        persist()
    }

    func setCloudSyncEnabled(_ enabled: Bool) {
        model.cloudSyncEnabled = enabled
        if enabled, model.syncID == nil { model.syncID = UUID() }
        persist()
    }

    /// Called from OnboardingView when the user pastes a sync ID from
    /// another device. We replace the current empty model wholesale
    /// (no merge — the user explicitly chose "pull from there") and
    /// pin the same sync_id so future pushes write into that row.
    func adoptPairedModel(_ remote: BoulderModel, syncID: UUID) {
        var adopted = remote
        adopted.syncID = syncID
        adopted.cloudSyncEnabled = true
        self.model = adopted
        persist()
    }

    func setRockName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        model.rockName = trimmed.isEmpty ? nil : trimmed
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
