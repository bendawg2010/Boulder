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

    /// True when load() last refused to decode the file on disk. While
    /// this is set, save() refuses to overwrite the existing file so a
    /// migration bug can never silently nuke the user's rock. Cleared
    /// after the first successful save (which can only happen with a
    /// model the app constructed legitimately — e.g. completed
    /// onboarding on a fresh BoulderModel).
    private static var loadFailedSinceLaunch = false

    static func load() -> BoulderModel? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        do {
            return try JSONDecoder().decode(BoulderModel.self, from: data)
        } catch {
            NSLog("Boulder: state.json decode failed: \(error). Skipping load — file preserved on disk.")
            loadFailedSinceLaunch = true
            // Snapshot the file before the user can possibly lose it
            // so we have a recovery path the next time they launch a
            // fixed build.
            let backup = fileURL.deletingPathExtension()
                .appendingPathExtension("decode-failed.json")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.copyItem(at: fileURL, to: backup)
            return nil
        }
    }

    static func save(_ model: BoulderModel) {
        // Safety net: if this launch couldn't decode the saved file,
        // we don't trust ourselves to overwrite it — the in-memory
        // model is the fallback-empty one and would wipe real data.
        // Skip the write entirely and log loudly. The user can fix
        // the schema and reload.
        if loadFailedSinceLaunch && !model.pixels.isEmpty == false {
            NSLog("Boulder: refusing to save — load failed earlier this launch, file preserved")
            return
        }
        do {
            let data = try JSONEncoder().encode(model)
            try data.write(to: fileURL, options: .atomic)
            // First successful save with a real model — we've moved
            // past whatever decode trouble we had.
            if !model.pixels.isEmpty { loadFailedSinceLaunch = false }
            // Also write a copy to the shared App Group container so
            // the BoulderWidget extension can read the latest state.
            writeToAppGroup(data)
        } catch {
            NSLog("Boulder: failed to persist state: \(error)")
        }
    }

    /// Writes model JSON to the App Group shared container.
    /// Failures are non-fatal — the widget will simply show stale data.
    /// Ad-hoc-signed builds don't actually have App Group entitlements
    /// granted, so the container lookup returns nil. We log that once
    /// and then go quiet — it's not a real error, just a no-op path.
    private static var appGroupWarnedMissing = false
    private static func writeToAppGroup(_ data: Data) {
        let groupID = "group.com.benburnette.Boulder"
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupID)
        else {
            if !appGroupWarnedMissing {
                NSLog("Boulder: App Group '\(groupID)' not provisioned for this build — widget will read in-app state only")
                appGroupWarnedMissing = true
            }
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
