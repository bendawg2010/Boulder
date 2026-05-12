// SettingsView.swift
//
// The settings window. Two tabs: General (launch at login, about),
// and Blocked Apps (the list + an Add button that opens an
// NSOpenPanel pointed at /Applications).

import SwiftUI
import AppKit
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var store: BoulderStore
    @EnvironmentObject var appDelegate: AppDelegate

    @State private var selection: Tab = .general

    enum Tab: Hashable { case general, blocked, about }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selection) {
                Text("General").tag(Tab.general)
                Text("Blocked Apps").tag(Tab.blocked)
                Text("About").tag(Tab.about)
            }
            .pickerStyle(.segmented)
            .padding(16)

            Divider()

            Group {
                switch selection {
                case .general: generalTab
                case .blocked: blockedTab
                case .about:   aboutTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 480, height: 540)
    }

    // MARK: General

    @State private var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled

    private var generalTab: some View {
        Form {
            Section("Boulder") {
                LabeledContent("Tier", value: store.model.tier.rawValue)
                LabeledContent("Pixels", value: "\(store.model.pixelCount)")
                LabeledContent("Mountains released", value: "\(store.model.range.count)")
            }
            Section("Startup") {
                Toggle("Launch Boulder at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            if newValue { try SMAppService.mainApp.register() }
                            else        { try SMAppService.mainApp.unregister() }
                        } catch {
                            NSLog("Boulder: SMAppService toggle failed: \(error)")
                            launchAtLogin = (SMAppService.mainApp.status == .enabled)
                        }
                    }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    // MARK: Blocked apps

    private var blockedTab: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Apps that chip the Boulder")
                    .font(.headline)
                Text("While you're focusing, switching to one of these apps will chip a few pixels off Boulder and post a notification. There's an 8-second cooldown so a single accidental tab doesn't take a big chunk.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)

            Divider()

            if store.model.blockedApps.isEmpty {
                VStack(spacing: 8) {
                    Text("No apps blocked yet.")
                        .foregroundStyle(.secondary)
                    Text("Add Slack, Twitter, Discord — whatever pulls you off task.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(store.model.blockedApps) { app in
                        HStack(spacing: 10) {
                            Image(nsImage: app.icon)
                                .resizable()
                                .frame(width: 28, height: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(app.displayName).font(.body)
                                Text(app.bundleIdentifier)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                store.removeBlockedApp(app.bundleIdentifier)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listStyle(.inset)
            }

            Divider()

            HStack {
                Spacer()
                Button {
                    pickApps()
                } label: {
                    Label("Add app…", systemImage: "plus")
                }
            }
            .padding(12)
        }
    }

    private func pickApps() {
        let panel = NSOpenPanel()
        panel.title = "Choose apps to block during focus"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let app = BlockedApp.from(appURL: url) {
                store.addBlockedApp(app)
            }
        }
    }

    // MARK: About

    private var aboutTab: some View {
        VStack(spacing: 16) {
            Text("🪨").font(.system(size: 64))
            Text("Boulder").font(.title.bold())
            Text("A pet rock for your focus.")
                .foregroundStyle(.secondary)
            Text("Version \(appVersion)")
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
            VStack(spacing: 8) {
                Link("Source on GitHub", destination: URL(string: "https://github.com/bendawg2010/Boulder")!)
                Link("Tip on Cash App ($5)", destination: URL(string: "https://cash.app/$Dryeetsolutions")!)
                Link("Sponsor on GitHub", destination: URL(string: "https://github.com/sponsors/bendawg2010")!)
            }
            Spacer()
            Text("Free · MIT licensed · ad-hoc signed")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }
}
