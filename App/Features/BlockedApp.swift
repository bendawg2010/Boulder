// BlockedApp.swift
//
// A single entry in the user's blocked-apps list. Storing the bundle
// identifier is enough to match NSWorkspace activation events; the
// name + icon path are cached so the Settings list can render fast
// without re-reading the .app bundle on every redraw.

import Foundation
import AppKit

struct BlockedApp: Codable, Identifiable, Hashable {
    var bundleIdentifier: String
    var displayName: String
    var iconPath: String?  // /Applications/Foo.app — we re-read its icon at runtime

    var id: String { bundleIdentifier }

    /// Best-effort icon lookup. Falls back to a generic .app icon if
    /// the cached path is gone (user uninstalled the app, etc.).
    var icon: NSImage {
        if let path = iconPath, FileManager.default.fileExists(atPath: path) {
            return NSWorkspace.shared.icon(forFile: path)
        }
        return NSImage(named: NSImage.applicationIconName) ?? NSImage()
    }

    /// Build from an .app bundle URL (e.g. /Applications/Slack.app).
    static func from(appURL: URL) -> BlockedApp? {
        guard let bundle = Bundle(url: appURL),
              let bid = bundle.bundleIdentifier else { return nil }
        let name = (bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String)
            ?? (bundle.infoDictionary?["CFBundleDisplayName"] as? String)
            ?? (bundle.infoDictionary?["CFBundleName"] as? String)
            ?? appURL.deletingPathExtension().lastPathComponent
        return BlockedApp(bundleIdentifier: bid, displayName: name, iconPath: appURL.path)
    }
}
