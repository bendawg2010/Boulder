// FocusBlocker.swift
//
// Watches NSWorkspace for app activations while a focus session is
// running. When the user switches to an app on their blocked list,
// we:
//   • crumble a few pixels off Boulder (instant visual feedback),
//   • post a system notification ("Focus broken — Boulder chipped"),
//   • cooldown so accidentally-clicking-Slack-twice doesn't take
//     a chunk out of the rock.
//
// We deliberately don't TRY TO HIDE the blocked app — macOS doesn't
// give third-party apps real "Screen Time" parental controls, and
// forcibly activating ourselves over the user's choice would be
// hostile UX. The crumble is the entire mechanic.

import AppKit
import UserNotifications

@MainActor
final class FocusBlocker {
    private weak var store: BoulderStore?
    private var observer: NSObjectProtocol?
    private var lastCrumbleAt: Date = .distantPast

    /// Don't crumble more than once per N seconds. Prevents a single
    /// alt-tab fumble from eating multiple pixels per second.
    private let cooldown: TimeInterval = 8

    /// Pixels removed per infraction. Small on purpose — the rock
    /// chips, it doesn't shatter.
    private let pixelsPerCrumble: Int = 3

    init(store: BoulderStore) {
        self.store = store
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            // Hop back to the main actor since the notification queue
            // is the main OperationQueue but Swift can't prove that.
            Task { @MainActor in self?.handleActivation(note) }
        }

        // Request notification permission once, ever. Already granted
        // → silent no-op.
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    deinit {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }

    private func handleActivation(_ note: Notification) {
        guard let store, store.isFocusing else { return }
        guard let runningApp = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        guard let bid = runningApp.bundleIdentifier else { return }

        // Never punish the user for activating Boulder itself.
        if bid == Bundle.main.bundleIdentifier { return }

        let blocked = store.model.blockedApps
        guard let match = blocked.first(where: { $0.bundleIdentifier == bid }) else { return }

        let now = Date()
        guard now.timeIntervalSince(lastCrumbleAt) >= cooldown else { return }
        lastCrumbleAt = now

        store.crumble(pixels: pixelsPerCrumble)
        notifyCrumble(appName: match.displayName)
    }

    private func notifyCrumble(appName: String) {
        let content = UNMutableNotificationContent()
        content.title = "Focus broken"
        content.body = "Opening \(appName) chipped \(pixelsPerCrumble) pixels off Boulder."
        content.sound = nil
        let req = UNNotificationRequest(
            identifier: "boulder.crumble.\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }
}
