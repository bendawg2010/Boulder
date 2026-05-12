// BoulderApp.swift — main entry.
//
// Boulder is menubar-only (LSUIElement). The Settings scene is
// intentionally NOT a SwiftUI `Settings { }` block: with LSUIElement
// the standard showSettingsWindow: selector is unreliable. AppDelegate
// builds a real NSWindow for settings on demand.
//
// We declare a tiny placeholder Settings scene so SwiftUI is satisfied
// and the menubar Cmd+, key path doesn't crash if it ever fires —
// the user-facing path goes through AppDelegate.openSettings().

import SwiftUI

@main
struct BoulderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}
