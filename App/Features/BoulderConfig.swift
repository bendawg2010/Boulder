// BoulderConfig.swift
//
// Cloud-sync endpoint coordinates. As of v1.9.0 the backend is a
// Cloudflare Pages Function at boulder-43p.pages.dev/api/boulders
// backed by a D1 (SQLite) database. No more Supabase — the old
// project is being retired.

import Foundation

enum BoulderConfig {
    /// Cloudflare Pages Function — see website/functions/api/boulders.ts.
    /// The function is deployed alongside the static site so it lives
    /// at the same origin as the share + web-app routes.
    static let backendBase = URL(string: "https://boulder-43p.pages.dev")!
    static var bouldersEndpoint: URL {
        backendBase.appendingPathComponent("/api/boulders")
    }
}
