// BoulderSync.swift
//
// Pulls + pushes BoulderModel to Supabase. Strategy is dirt simple:
// the server stores ONE row per `sync_id` UUID, last-write-wins on
// updated_at. On launch we pull and compare timestamps; on every save
// we push (throttled to 1 push per 5s so a busy minute doesn't hammer
// the API).
//
// No third-party dependencies — uses URLSession + JSON via PostgREST.

import Foundation

@MainActor
final class BoulderSync {
    static let shared = BoulderSync()
    private init() {}

    private var lastPushTask: Task<Void, Never>?
    private var lastPushAt: Date = .distantPast
    private let minPushInterval: TimeInterval = 5

    // MARK: Push

    /// Throttled upsert. Coalesces back-to-back saves so a minute of
    /// rapid grain growth doesn't fire 60 round trips.
    func schedulePush(_ model: BoulderModel) {
        guard model.cloudSyncEnabled, model.syncID != nil else { return }

        lastPushTask?.cancel()
        let delay = max(0, minPushInterval - Date().timeIntervalSince(lastPushAt))
        let snapshot = model
        lastPushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            if Task.isCancelled { return }
            await self?.push(snapshot)
        }
    }

    private func push(_ model: BoulderModel) async {
        guard let syncID = model.syncID else { return }
        guard let body = encodeRow(model, syncID: syncID) else { return }

        var req = URLRequest(url: postgrestURL(query: "on_conflict=sync_id"))
        req.httpMethod = "POST"
        // PostgREST upsert via the `resolution=merge-duplicates` Prefer header.
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("resolution=merge-duplicates,return=minimal",
                     forHTTPHeaderField: "Prefer")
        req.setValue(BoulderConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(BoulderConfig.supabaseAnonKey)",
                     forHTTPHeaderField: "Authorization")
        req.httpBody = body

        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                NSLog("Boulder: sync push failed status=\(http.statusCode)")
            } else {
                lastPushAt = Date()
            }
        } catch {
            NSLog("Boulder: sync push error: \(error.localizedDescription)")
        }
    }

    // MARK: Pull

    /// Fetch the server's copy of this user's boulder. Returns nil if
    /// the row doesn't exist yet (first launch on a new device) or the
    /// network is unavailable.
    func pull(syncID: UUID) async -> BoulderModel? {
        var comps = URLComponents(url: postgrestURL(), resolvingAgainstBaseURL: false)
        comps?.queryItems = [
            URLQueryItem(name: "sync_id", value: "eq.\(syncID.uuidString.lowercased())"),
            URLQueryItem(name: "select", value: "payload,updated_at"),
            URLQueryItem(name: "limit", value: "1"),
        ]
        guard let url = comps?.url else { return nil }

        var req = URLRequest(url: url)
        req.setValue(BoulderConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(BoulderConfig.supabaseAnonKey)",
                     forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else { return nil }
            guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let first = rows.first,
                  let payload = first["payload"] as? [String: Any] else { return nil }
            let payloadData = try JSONSerialization.data(withJSONObject: payload)
            let dec = JSONDecoder()
            return try dec.decode(BoulderModel.self, from: payloadData)
        } catch {
            NSLog("Boulder: sync pull error: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: Helpers

    private func postgrestURL(query: String? = nil) -> URL {
        var comps = URLComponents(
            url: BoulderConfig.supabaseURL
                .appendingPathComponent("rest/v1")
                .appendingPathComponent(BoulderConfig.bouldersTable),
            resolvingAgainstBaseURL: false
        )!
        if let q = query { comps.query = q }
        return comps.url!
    }

    private func encodeRow(_ model: BoulderModel, syncID: UUID) -> Data? {
        // We send the full model as the `payload` jsonb plus a few
        // denormalized columns for indexing/debugging.
        let enc = JSONEncoder()
        guard let modelJSON = try? enc.encode(model),
              let modelObject = try? JSONSerialization.jsonObject(with: modelJSON)
        else { return nil }
        let row: [String: Any] = [
            "sync_id": syncID.uuidString.lowercased(),
            "payload": modelObject,
            "user_first_name": model.userFirstName as Any,
            "rock_name": model.rockName as Any,
            "grain_count": model.pixels.count,
            "schema_version": model.schemaVersion,
        ]
        return try? JSONSerialization.data(withJSONObject: row)
    }
}
