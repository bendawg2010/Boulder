// UpdaterController.swift
//
// Thin wrapper around Sparkle's SPUStandardUpdaterController. Boulder
// is intentionally simpler than NotchPop's updater — we don't expose
// a Force Update Now button in the UI yet, but the cache-busting
// feedURL hook is here from day one so we never repeat the
// stuck-on-stale-version pain that hit NotchPop early.

import AppKit
import Sparkle

final class UpdaterController: NSObject, SPUUpdaterDelegate {
    private(set) lazy var controller: SPUStandardUpdaterController =
        SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )

    @objc func checkForUpdates(_ sender: Any?) {
        controller.checkForUpdates(sender)
    }

    // MARK: SPUUpdaterDelegate

    /// Append a cache-buster to the feed URL so Cloudflare can't serve
    /// a stale 304. Cheap to do; the appcast is tiny.
    func feedURLString(for updater: SPUUpdater) -> String? {
        let base = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String
            ?? "https://boulder.pages.dev/appcast.xml"
        return base + "?t=\(Int(Date().timeIntervalSince1970))"
    }
}
