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
        } catch {
            NSLog("Boulder: failed to persist state: \(error)")
        }
    }
}
