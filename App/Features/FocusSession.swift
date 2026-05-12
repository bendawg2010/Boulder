// FocusSession.swift
//
// One contiguous focus session. Holds the tag the user picked, what
// they described they were doing ("Refactoring Boulder's renderer"),
// and the timestamps. Every pixel grown during the session carries
// this session's id, so clicking the rock can look back through the
// log and report what was being worked on.

import Foundation

struct FocusSession: Codable, Identifiable, Hashable {
    var id: UUID
    var tagID: UUID
    var blurb: String           // user's description for this session
    var startedAt: Date
    var endedAt: Date?
    /// How many pixels this session grew. Filled in on stopFocus().
    var pixelsGrown: Int = 0
    /// User's pre-committed session length. nil = open-ended.
    /// When set, the timer counts down; hitting 0 auto-completes the
    /// session with a bonus. Stopping early triggers a penalty.
    var plannedDuration: TimeInterval? = nil
    /// True if the user pre-committed (plannedDuration != nil). Stored
    /// separately so we can preserve "this WAS committed" even after
    /// the duration field would otherwise be cleared.
    var committed: Bool = false
    /// True if the session was abandoned via the Give Up button (or
    /// by force-quitting the app during a committed run). Used by
    /// the inspector to label penalized pixel groups.
    var gaveUp: Bool = false

    init(id: UUID = UUID(), tagID: UUID, blurb: String,
         plannedDuration: TimeInterval? = nil,
         startedAt: Date = Date()) {
        self.id = id
        self.tagID = tagID
        self.blurb = blurb
        self.startedAt = startedAt
        self.plannedDuration = plannedDuration
        self.committed = (plannedDuration != nil)
    }
}
