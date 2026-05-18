// BoulderSync.swift
//
// Pulls + pushes BoulderModel to the Cloudflare Pages Function at
// /api/boulders. One row per `sync_id` UUID, last-write-wins on the
// server's updated_at. On launch we pull and prefer whichever side
// has more grains; on every save we push (throttled to 1 push per 5s
// so a busy minute doesn't hammer the API).
//
// No third-party deps — URLSession + JSON via the Pages Function.

import Foundation

@MainActor
final class BoulderSync {
    static let shared = BoulderSync()
    private init() {}

    private var lastPushTask: Task<Void, Never>?
    private var lastPushAt: Date = .distantPast
    private let minPushInterval: TimeInterval = 5

    // MARK: Push

    /// Throttled upsert. Coalesces back-to-back saves.
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

        // Encode the model JSON as a sub-object so the Pages Function
        // can write the full payload straight into the D1 jsonb column
        // without re-parsing.
        let enc = JSONEncoder()
        guard let modelJSON = try? enc.encode(model),
              let modelObj = try? JSONSerialization.jsonObject(with: modelJSON)
        else { return }

        let row: [String: Any] = [
            "sync_id": syncID.uuidString.lowercased(),
            "payload": modelObj,
            "user_first_name": model.userFirstName as Any,
            "rock_name": model.rockName as Any,
            "grain_count": model.pixels.count,
            "schema_version": model.schemaVersion,
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: row) else { return }

        var req = URLRequest(url: BoulderConfig.bouldersEndpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
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

    /// Fetch the server's copy. Returns nil if no row exists yet on
    /// this device's first launch, or the network is unreachable.
    func pull(syncID: UUID) async -> BoulderModel? {
        var comps = URLComponents(url: BoulderConfig.bouldersEndpoint,
                                  resolvingAgainstBaseURL: false)
        comps?.queryItems = [URLQueryItem(name: "sync_id", value: syncID.uuidString.lowercased())]
        guard let url = comps?.url else { return nil }

        var req = URLRequest(url: url)
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else { return nil }
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let payload = obj["payload"] as? [String: Any] else { return nil }
            let payloadData = try JSONSerialization.data(withJSONObject: payload)
            return try JSONDecoder().decode(BoulderModel.self, from: payloadData)
        } catch {
            NSLog("Boulder: sync pull error: \(error.localizedDescription)")
            return nil
        }
    }
}
