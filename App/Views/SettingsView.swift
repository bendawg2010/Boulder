// SettingsView.swift — Cmd+, opens this. Minimal: launch-at-login
// toggle, check-for-updates button, about/credits.

import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var store: BoulderStore
    @State private var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            if newValue { try SMAppService.mainApp.register() }
                            else        { try SMAppService.mainApp.unregister() }
                        } catch {
                            // Most common failure: user denied in System Settings.
                            NSLog("Boulder: SMAppService toggle failed: \(error)")
                        }
                    }
            }

            Section("About") {
                LabeledContent("Version", value: appVersion)
                LabeledContent("License", value: "MIT")
                Link("Source on GitHub", destination: URL(string: "https://github.com/bendawg2010/Boulder")!)
                Link("Tip on Cash App", destination: URL(string: "https://cash.app/$Dryeetsolutions")!)
            }

            Section("Boulder") {
                LabeledContent("Tier", value: store.model.tier.rawValue)
                LabeledContent("Pixels", value: "\(store.model.pixelCount)")
                LabeledContent("Mountains released", value: "\(store.model.range.count)")
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 380)
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }
}
