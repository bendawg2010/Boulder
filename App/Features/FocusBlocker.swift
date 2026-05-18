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

    /// Posted by the warning lockout window when the user clicks
    /// "I'm back" inside the 3-sec grace window. FocusBlocker
    /// observes and cancels its pending termination.
    static let boulderResumeFocus = Notification.Name("boulder.resumeFocus")
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

    private var pendingTerminationTask: Task<Void, Never>?
    private var pendingApp: NSRunningApplication?
    private var resumeObserver: NSObjectProtocol?

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

        // Already warning about THIS app? Don't double up.
        if pendingApp?.bundleIdentifier == bid { return }

        NSLog("Boulder: blocked app activated — \(match.displayName); 3-sec warning")

        // Step 1: hide the blocked app immediately so the user can't
        // continue using it during the countdown. .hide() works for
        // most non-fullscreen apps; we follow with .hide() again at
        // 0.2s as defense against apps that auto-restore.
        runningApp.hide()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak runningApp] in
            runningApp?.hide()
        }

        // Step 2: bring Boulder forward and show the warning overlay
        // with a 3-second countdown + "I'm back" button.
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .boulderShowPopover, object: nil)

        pendingApp = runningApp
        FocusLockoutWindow.showWarning(
            appName: match.displayName,
            seconds: 3
        )

        // Step 3: if the user clicks "I'm back" within 3 seconds, the
        // panel posts .boulderResumeFocus. Cancel the pending termination.
        if let obs = resumeObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        resumeObserver = NotificationCenter.default.addObserver(
            forName: .boulderResumeFocus, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.cancelPendingTermination() }
        }

        // Step 4: schedule the actual termination + grain forfeit.
        pendingTerminationTask?.cancel()
        pendingTerminationTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if Task.isCancelled { return }
            await self?.executeBlock(app: runningApp, displayName: match.displayName, bundleID: bid)
        }
    }

    private func cancelPendingTermination() {
        pendingTerminationTask?.cancel()
        pendingTerminationTask = nil
        pendingApp = nil
        if let obs = resumeObserver {
            NotificationCenter.default.removeObserver(obs)
            resumeObserver = nil
        }
        FocusLockoutWindow.dismiss()
        NSLog("Boulder: user clicked 'I'm back' — termination canceled, no penalty")
    }

    private func executeBlock(app: NSRunningApplication?, displayName: String, bundleID: String) async {
        guard let store else { return }
        pendingApp = nil
        if let obs = resumeObserver {
            NotificationCenter.default.removeObserver(obs)
            resumeObserver = nil
        }

        // Forfeit grains banked THIS SESSION (not the rock's claimed grains).
        let forfeited = store.pendingPixelCount
        store.forfeitSessionGrains()

        // Terminate the offending app — graceful first, then force.
        if let app {
            _ = app.terminate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak app] in
                guard let a = app, !a.isTerminated else { return }
                a.forceTerminate()
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        FocusLockoutWindow.showBlocked(appName: displayName, grainsLost: forfeited)

        // Rate-limit the toast notification.
        let now = Date()
        guard now.timeIntervalSince(lastCrumbleAt) >= cooldown else { return }
        lastCrumbleAt = now
        notifyCrumble(appName: displayName, grainsLost: forfeited)
    }

    private func notifyCrumble(appName: String, grainsLost: Int) {
        let content = UNMutableNotificationContent()
        content.title = "🪨 Blocked during focus"
        let suffix = grainsLost == 1 ? "grain" : "grains"
        content.body = grainsLost > 0
            ? "\(appName) closed. Forfeited \(grainsLost) banked \(suffix). Your rock is safe."
            : "\(appName) closed. Get back to your rock."
        content.sound = nil
        let req = UNNotificationRequest(
            identifier: "boulder.crumble.\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }
}
