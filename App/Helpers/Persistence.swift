// Persistence.swift
//
// Read/write BoulderModel to ~/Library/Application Support/Boulder/
// state.json. Pure JSON — small enough not to bother with a more
// elaborate store, and human-inspectable for debugging.

import Foundation

enum Persistence {
    private static var fileURL: URL {
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory,
                                in: .userDomainMask,
                                appropriateFor: nil,
                                create: true))
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("Boulder", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("state.json")
    }

    static func load() -> BoulderModel? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(BoulderModel.self, from: data)
    }

    static func save(_ model: BoulderModel) {
        do {
            let data = try JSONEncoder().encode(model)
            try data.write(to: fileURL, options: .atomic)
            // Also write a copy to the shared App Group container so
            // the BoulderWidget extension can read the latest state.
            writeToAppGroup(data)
        } catch {
            NSLog("Boulder: failed to persist state: \(error)")
        }
    }

    /// Writes model JSON to the App Group shared container.
    /// Failures are non-fatal — the widget will simply show stale data.
    private static func writeToAppGroup(_ data: Data) {
        let groupID = "group.com.benburnette.Boulder"
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupID)
        else {
            NSLog("Boulder: App Group container not available for id '\(groupID)'")
            return
        }
        let dest = container.appendingPathComponent("widget-state.json")
        do {
            try data.write(to: dest, options: .atomic)
        } catch {
            NSLog("Boulder: failed to write widget-state to App Group: \(error)")
        }
    }
}
