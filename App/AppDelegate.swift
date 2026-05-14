// AppDelegate.swift
//
// Owns the menubar status item, popover, settings window, gallery
// window, focus blocker, and Sparkle updater. Persists state on
// terminate.

import AppKit
import SwiftUI
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = BoulderStore.shared
    let updater = UpdaterController()
    private var blocker: FocusBlocker?

    var statusItem: NSStatusItem?
    var popover: NSPopover?
    var settingsWindow: NSWindow?
    var galleryWindow: NSWindow?

    private var tickCancellable: AnyCancellable?
    private var iconCancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        installStatusItem()
        installPopover()

        // 1 Hz tick — drives the focus session AND refreshes the
        // menubar countdown title.
        tickCancellable = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.store.tick()
                self?.updateMenubarTitle()
            }

        // Refresh the menubar icon whenever the model changes. Throttled
        // to once a second so heavy pixel growth doesn't repaint the
        // menubar 60x/s.
        iconCancellable = store.$model
            .throttle(for: 1.0, scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] model in
                self?.updateMenubarIcon(pixels: model.pixels)
            }
        // Paint once immediately so we don't sit on the placeholder.
        updateMenubarIcon(pixels: store.model.pixels)

        // Watch for blocked-app activations.
        blocker = FocusBlocker(store: store)

        // FocusBlocker can't reach the popover directly — listen for
        // its "show yourself" signal and pop the popover so the user
        // sees the crumble flash immediately.
        NotificationCenter.default.addObserver(
            forName: .boulderShowPopover,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.showPopoverFromAnywhere() }
        }

        _ = updater.controller
    }

    func applicationWillTerminate(_ notification: Notification) {
        // If the user is mid-commitment when they quit, count it as
        // a give-up so they can't dodge the penalty by force-quitting.
        // Falls through to a normal persist for open-ended sessions.
        MainActor.assumeIsolated { store.handleQuitDuringSession() }
    }

    // MARK: - Menubar

    @MainActor
    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: 32)
        if let button = item.button {
            button.image = MenubarIcon.render(pixels: [], paletteFor: { [weak self] in
                self?.store.palette(for: $0) ?? BoulderRenderer.fallbackPalette
            })
            button.image?.isTemplate = true    // template — macOS tints for light/dark
            button.imagePosition = .imageLeading
            button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
        statusItem = item
    }

    /// Refresh the menubar button's title to show a countdown timer
    /// next to the rock during committed focus sessions. Open-ended
    /// sessions show elapsed time. Not focusing: title is empty.
    @MainActor
    func updateMenubarTitle() {
        guard let button = statusItem?.button else { return }
        if store.isFocusing {
            let secs: Int
            if let remaining = store.timeRemaining {
                secs = Int(remaining)   // countdown
            } else {
                secs = Int(store.sessionElapsed)  // open-ended → count up
            }
            let h = secs / 3600, m = (secs % 3600) / 60, s = secs % 60
            button.title = h > 0
                ? String(format: " %d:%02d:%02d", h, m, s)
                : String(format: " %02d:%02d", m, s)
            // The status item auto-expands its width to fit the title
            // when length is .variableLength. We installed it at fixed
            // 32; bump to variable so the timer text doesn't clip.
            statusItem?.length = NSStatusItem.variableLength
        } else {
            button.title = ""
            statusItem?.length = 32
        }
    }

    @MainActor
    private func updateMenubarIcon(pixels: [BoulderPixel]) {
        guard let button = statusItem?.button else { return }
        let img = MenubarIcon.render(pixels: pixels, paletteFor: { [weak self] in
            self?.store.palette(for: $0) ?? BoulderRenderer.fallbackPalette
        })
        img.isTemplate = true
        button.image = img
        // Tooltip: human-readable status. Helps the user remember
        // there's a rock living in their menubar and what tier it is.
        button.toolTip = "Boulder · \(store.model.tier.rawValue) · \(store.model.pixelCount) grains"
    }

    @objc func togglePopover(_ sender: Any?) {
        guard let popover, let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    /// Force the popover open from a non-UI caller (e.g. FocusBlocker
    /// when a blocked app is activated). Idempotent — no-op if already
    /// shown.
    func showPopoverFromAnywhere() {
        guard let popover, let button = statusItem?.button else { return }
        if popover.isShown { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    // MARK: - Popover

    private func installPopover() {
        let pop = NSPopover()
        pop.behavior = .transient
        pop.contentSize = NSSize(width: 380, height: 560)
        pop.contentViewController = NSHostingController(
            rootView: PopoverContentView()
                .environmentObject(store)
                .environmentObject(self)
        )
        popover = pop
    }

    // MARK: - Settings window

    func openSettings() {
        if let win = settingsWindow {
            NSApp.activate(ignoringOtherApps: true)
            win.makeKeyAndOrderFront(nil)
            return
        }
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 540),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.title = "Boulder Settings"
        win.center()
        win.contentView = NSHostingView(
            rootView: SettingsView()
                .environmentObject(store)
                .environmentObject(self)
        )
        win.isReleasedWhenClosed = false
        settingsWindow = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    // MARK: - Gallery window

    func openGallery() {
        if let win = galleryWindow {
            NSApp.activate(ignoringOtherApps: true)
            win.makeKeyAndOrderFront(nil)
            return
        }
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 360),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "Mountain Range"
        win.center()
        win.contentView = NSHostingView(
            rootView: MountainRangeView().environmentObject(store)
        )
        win.isReleasedWhenClosed = false
        galleryWindow = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    @objc func quit(_ sender: Any?) {
        NSApp.terminate(sender)
    }
}

extension AppDelegate: ObservableObject {}
