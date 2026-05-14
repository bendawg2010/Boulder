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

        // Block only during an active focus session. Outside a session
        // the block list is dormant — the user can do whatever.
        guard store.isFocusing else { return }

        let blocked = store.model.blockedApps
        guard let match = blocked.first(where: { $0.bundleIdentifier == bid }) else { return }

        NSLog("Boulder: blocked app activated during session — \(match.displayName) (\(bid)); terminating")

        // Real enforcement. `.hide()` is useless against true-fullscreen
        // games (Geometry Dash, Steam titles) since they capture the
        // display server. So we just close the app:
        //   1) Send SIGTERM via `terminate()` — graceful, most apps
        //      save state and exit cleanly
        //   2) After 1.0s if it's still running, `forceTerminate()` —
        //      hard kill for stubborn games
        let didTerminate = runningApp.terminate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak runningApp] in
            guard let app = runningApp, !app.isTerminated else { return }
            NSLog("Boulder: \(bid) survived terminate(); force-terminating")
            app.forceTerminate()
        }

        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .boulderShowPopover, object: nil)
        FocusLockoutWindow.show(appName: match.displayName, pixelsLost: 0)

        // Rate-limit the toast notification — terminate is loud enough
        // visually that we don't need to spam the notification center.
        let now = Date()
        guard now.timeIntervalSince(lastCrumbleAt) >= cooldown else { return }
        lastCrumbleAt = now
        if !didTerminate {
            NSLog("Boulder: terminate() returned false for \(bid) — relying on forceTerminate fallback")
        }
        notifyCrumble(appName: match.displayName)
    }

    private func notifyCrumble(appName: String) {
        let content = UNMutableNotificationContent()
        content.title = "🪨 Blocked during focus"
        content.body = "\(appName) was closed. Get back to your rock."
        content.sound = nil
        let req = UNNotificationRequest(
            identifier: "boulder.crumble.\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }
}
