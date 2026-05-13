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

extension Notification.Name {
    /// Posted by FocusBlocker when a blocked app is activated. The
    /// AppDelegate listens for this and pops the menubar popover so
    /// the user sees the crumble flash immediately.
    static let boulderShowPopover = Notification.Name("boulder.showPopover")
}

@MainActor
final class FocusBlocker: NSObject, UNUserNotificationCenterDelegate {
    private weak var store: BoulderStore?
    private var observer: NSObjectProtocol?
    private var lastCrumbleAt: Date = .distantPast

    /// Don't crumble more than once per N seconds. Tight enough to
    /// be visible during testing, generous enough that one fumbled
    /// alt-tab doesn't eat multiple pixels.
    private let cooldown: TimeInterval = 2

    /// Pixels removed per infraction. Small on purpose — the rock
    /// chips, it doesn't shatter.
    private let pixelsPerCrumble: Int = 3

    init(store: BoulderStore) {
        self.store = store
        super.init()
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            Task { @MainActor in self?.handleActivation(note) }
        }

        // Become the foreground-presentation delegate so banners show
        // even when Boulder itself is frontmost.
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // UNUserNotificationCenterDelegate: show notifications in the
    // foreground (default is to suppress them while the app is active).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    deinit {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }

    private func handleActivation(_ note: Notification) {
        guard let store else { return }
        guard let runningApp = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        guard let bid = runningApp.bundleIdentifier else { return }

        // Never punish the user for activating Boulder itself.
        if bid == Bundle.main.bundleIdentifier { return }

        let blocked = store.model.blockedApps
        guard let match = blocked.first(where: { $0.bundleIdentifier == bid }) else { return }

        // HARD push-back. Apple won't grant indie apps the
        // FamilyControls entitlement for true OS-level blocking,
        // so we do the strongest non-destructive thing macOS allows:
        //   1) Hide the blocked app immediately on EVERY activation
        //      — no cooldown on the hide, so cmd-tabbing to it just
        //      makes it vanish again
        //   2) Hide it again ~0.2s later (defense against apps that
        //      auto-restore themselves)
        //   3) Bring Boulder forward
        //   4) Show a fullscreen lockout overlay the user can't miss
        //   5) Crumble + notify (cooldown only on the pixel cost so
        //      we don't drain 3px/sec on a rapid-fire mash)
        runningApp.hide()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak runningApp] in
            runningApp?.hide()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak runningApp] in
            runningApp?.hide()
        }

        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .boulderShowPopover, object: nil)
        FocusLockoutWindow.show(appName: match.displayName, pixelsLost: pixelsPerCrumble)

        let now = Date()
        guard now.timeIntervalSince(lastCrumbleAt) >= cooldown else { return }
        lastCrumbleAt = now
        NSLog("Boulder: blocked app activated — \(match.displayName) (\(bid)); hiding + crumbling \(pixelsPerCrumble) px")
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
