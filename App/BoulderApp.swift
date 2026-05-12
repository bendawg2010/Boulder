// BoulderApp.swift — main entry point.
//
// Boulder is a menubar-only app (LSUIElement). All UI lives in a
// popover hung off an NSStatusItem, plus optional standalone windows
// for the Mountain Range gallery and Settings. SwiftUI renders;
// AppKit hosts.

import SwiftUI

@main
struct BoulderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Cmd+, opens Settings. Nothing else mounts a WindowGroup;
        // the popover and the gallery window are created imperatively
        // by AppDelegate so we can control activation policy precisely.
        Settings {
            SettingsView()
                .environmentObject(appDelegate.store)
        }
    }
}
