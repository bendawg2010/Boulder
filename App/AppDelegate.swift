// AppDelegate.swift
//
// Owns the menubar status item, the popover containing the Boulder
// view, the gallery window, and the Sparkle updater. Persists the
// Boulder state on terminate.

import AppKit
import SwiftUI
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = BoulderStore.shared
    let updater = UpdaterController()

    var statusItem: NSStatusItem?
    var popover: NSPopover?
    var galleryWindow: NSWindow?

    private var tickCancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // No Dock icon; live in the menubar.
        NSApp.setActivationPolicy(.accessory)

        installStatusItem()
        installPopover()

        // Drive the focus session at 1 Hz from a single source so
        // the UI, the persistence layer, and the growth accumulator
        // all see the same tick. Boulder grows fractionally per
        // second; visible pixel changes accumulate slowly on purpose.
        tickCancellable = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.store.tick() }

        // Kick Sparkle awake.
        _ = updater.controller
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.persist()
    }

    // MARK: - Menubar

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            // Unicode 🪨 looks decent in the menubar; on a real release
            // we'd swap to a template PDF rendered from the app icon.
            button.title = "🪨"
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
        statusItem = item
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

    // MARK: - Popover

    private func installPopover() {
        let pop = NSPopover()
        pop.behavior = .transient
        pop.contentSize = NSSize(width: 360, height: 520)
        pop.contentViewController = NSHostingController(
            rootView: PopoverContentView()
                .environmentObject(store)
                .environmentObject(self)
        )
        popover = pop
    }

    // MARK: - Gallery window

    func openGallery() {
        if let win = galleryWindow {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
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
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Menu helpers

    func openSettings() {
        // SwiftUI Settings scene is invoked by sending the standard
        // showSettingsWindow: / showPreferencesWindow: selector.
        NSApp.activate(ignoringOtherApps: true)
        if #available(macOS 14, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }

    @objc func quit(_ sender: Any?) {
        NSApp.terminate(sender)
    }
}

extension AppDelegate: ObservableObject {}
