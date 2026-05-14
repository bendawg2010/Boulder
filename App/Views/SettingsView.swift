// SettingsView.swift
//
// Four-tab settings window: General, Tags (the new tag library),
// Blocked Apps, About.

import SwiftUI
import AppKit
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var store: BoulderStore
    @EnvironmentObject var appDelegate: AppDelegate

    @State private var selection: Tab = .general
    @State private var editingTag: FocusTag? = nil
    @State private var presentTagEditor: Bool = false

    enum Tab: Hashable { case general, tags, blocked, stats, about }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selection) {
                Text("General").tag(Tab.general)
                Text("Tags").tag(Tab.tags)
                Text("Blocked Apps").tag(Tab.blocked)
                Text("Stats").tag(Tab.stats)
                Text("About").tag(Tab.about)
            }
            .pickerStyle(.segmented)
            .padding(16)

            Divider()

            Group {
                switch selection {
                case .general: generalTab
                case .tags:    tagsTab
                case .blocked: blockedTab
                case .stats:   StatsView().environmentObject(store)
                case .about:   aboutTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 520, height: 580)
        .sheet(isPresented: $presentTagEditor) {
            TagEditorView(existing: editingTag)
                .environmentObject(store)
        }
    }

    // MARK: General

    @State private var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled

    private var generalTab: some View {
        Form {
            Section("You") {
                LabeledContent("Your first name") {
                    TextField("Your first name", text: Binding(
                        get: { store.model.userFirstName ?? "" },
                        set: { store.setIdentity(firstName: $0, rockName: store.model.rockName ?? "") }
                    ))
                    .multilineTextAlignment(.trailing)
                }
                LabeledContent("Rock name") {
                    TextField("(optional)", text: Binding(
                        get: { store.model.rockName ?? "" },
                        set: { store.setRockName($0) }
                    ))
                    .multilineTextAlignment(.trailing)
                }
            }
            Section("Boulder") {
                LabeledContent("Tier", value: store.model.tier.rawValue)
                LabeledContent("Grains", value: "\(store.model.pixelCount)")
                LabeledContent("Mountains released", value: "\(store.model.range.count)")
                LabeledContent("Sessions logged", value: "\(store.model.sessions.count)")
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

    // MARK: Tags

    private var tagsTab: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Your tag library")
                    .font(.headline)
                Text("Pick a tag before each focus session. Pixels grown during the session take on the tag's color. Click a pixel on your Boulder to see what you were working on.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)

            Divider()

            List {
                ForEach(store.model.tags) { tag in
                    Button {
                        editingTag = tag
                        presentTagEditor = true
                    } label: {
                        HStack(spacing: 10) {
                            VStack(spacing: 3) {
                                Text(tag.emoji).font(.system(size: 24))
                                HStack(spacing: 2) {
                                    ForEach(0..<4, id: \.self) { i in
                                        RoundedRectangle(cornerRadius: 1.5)
                                            .fill(tag.palette[i])
                                            .frame(width: 8, height: 4)
                                    }
                                }
                            }
                            .frame(width: 50)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(tag.name).font(.body.weight(.semibold))
                                Text(tag.blurb.isEmpty
                                     ? "No description"
                                     : tag.blurb)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { idx in
                    for i in idx { store.deleteTag(id: store.model.tags[i].id) }
                }
            }
            .listStyle(.inset)

            Divider()

            HStack {
                Spacer()
                Button {
                    editingTag = nil
                    presentTagEditor = true
                } label: {
                    Label("New tag", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(12)
        }
    }

    // MARK: Blocked apps

    private var blockedTab: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Apps that chip the Boulder")
                    .font(.headline)
                Text("While focusing, switching to one of these apps will chip 3 pixels off Boulder. 8-second cooldown so a single mis-tab doesn't punish you twice.")
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
                Button { pickApps() } label: {
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
        VStack(spacing: 14) {
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
