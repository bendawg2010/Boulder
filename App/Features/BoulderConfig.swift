// BoulderConfig.swift
//
// Supabase project coordinates for cloud sync. The publishable key is
// scoped to anon-role reads/writes against the `boulders` table, so
// it's safe to ship in the client binary. The auth model is "your
// sync_id UUID is your secret" — see reference_boulder_supabase.md.

import Foundation

enum BoulderConfig {
    /// Project: ujkvqwkdtcwnxueitepm — see memory.
    static let supabaseURL = URL(string: "https://ujkvqwkdtcwnxueitepm.supabase.co")!

    /// Publishable (anon) key. Safe to bundle in the client per
    /// Supabase docs — RLS is what gates access, not key secrecy.
    static let supabaseAnonKey =
        "sb_publishable_NLjbb-i-mzAcO6G2h5zl6w_caxZ3kiY"

    /// Table name we sync to.
    static let bouldersTable = "boulders"
}
