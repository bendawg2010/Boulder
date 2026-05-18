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
    @State private var presentPairSheet: Bool = false
    @State private var presentNewGroupPrompt: Bool = false
    @State private var presentJoinGroupPrompt: Bool = false
    @State private var newGroupName: String = ""
    @State private var joinGroupCode: String = ""
    @State private var groupError: String? = nil

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
        .sheet(isPresented: $presentPairSheet) {
            PairDeviceSheet()
                .environmentObject(store)
        }
        .alert("New group rock", isPresented: $presentNewGroupPrompt) {
            TextField("Group name", text: $newGroupName)
            Button("Create", action: { confirmCreateGroup() })
            Button("Cancel", role: .cancel) { newGroupName = "" }
        } message: {
            Text("Friends can join with the 6-letter invite code Boulder will give you.")
        }
        .alert("Join group rock", isPresented: $presentJoinGroupPrompt) {
            TextField("6-letter code", text: $joinGroupCode)
            Button("Join", action: { confirmJoinGroup() })
            Button("Cancel", role: .cancel) { joinGroupCode = "" }
        } message: {
            Text("Ask the group creator for their invite code.")
        }
        .alert("Group error", isPresented: Binding(
            get: { groupError != nil },
            set: { if !$0 { groupError = nil } }
        )) {
            Button("OK") { groupError = nil }
        } message: {
            Text(groupError ?? "")
        }
    }

    private func confirmCreateGroup() {
        let name = newGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
        newGroupName = ""
        guard !name.isEmpty else { return }
        Task { @MainActor in
            if let g = await store.createGroup(name: name) {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(g.inviteCode, forType: .string)
            } else {
                groupError = "Couldn't reach the server. Try again."
            }
        }
    }

    private func confirmJoinGroup() {
        let raw = joinGroupCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        joinGroupCode = ""
        guard raw.range(of: "^[A-Z2-9]{6}$", options: .regularExpression) != nil else {
            groupError = "Invite codes are 6 letters/digits (no 0/O/1/I)."
            return
        }
        Task { @MainActor in
            if await store.joinGroup(code: raw) == nil {
                groupError = "No group with that code, or you couldn't reach the server."
            }
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
            Section("Cloud sync") {
                Toggle("Sync rock across devices", isOn: Binding(
                    get: { store.model.cloudSyncEnabled },
                    set: { store.setCloudSyncEnabled($0) }
                ))
                if let syncID = store.model.syncID {
                    LabeledContent("Sync ID") {
                        Text(syncID.uuidString.prefix(8) + "…")
                            .font(.callout.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                HStack {
                    Text("Pair another device")
                    Spacer()
                    Button("Show QR code…") { presentPairSheet = true }
                        .disabled(store.model.syncID == nil || !store.model.cloudSyncEnabled)
                }
                Text("Your rock uploads to Cloudflare D1 keyed by sync_id. Scan the QR from your phone to open the same rock in any browser.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("Group rocks") {
                ForEach(store.model.groups) { group in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.name).font(.body.weight(.semibold))
                            Text(group.inviteCode)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .tracking(0.1)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { group.contributesGrains },
                            set: { store.setGroupContributes(id: group.id, contributes: $0) }
                        )).labelsHidden()
                        Link(destination: URL(string: "https://boulder-43p.pages.dev/g/\(group.inviteCode)")!) {
                            Image(systemName: "arrow.up.right.square")
                        }
                        Button {
                            store.leaveGroup(id: group.id)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(Color(hex: 0xFF6B6B))
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack {
                    Button("+ New group") { presentNewGroupPrompt = true }
                    Button("Join with code") { presentJoinGroupPrompt = true }
                }
                Text("Group rocks are rocks you grow with friends. Each member's claimed grains land on the same rock. Anyone with the 6-letter invite code can join.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("Community rock") {
                Toggle("Contribute claimed grains", isOn: Binding(
                    get: { store.model.contributeToCommunity },
                    set: { store.setContributeToCommunity($0) }
                ))
                HStack {
                    Text("View community rock")
                    Spacer()
                    Link("Open in browser",
                         destination: URL(string: "https://boulder-43p.pages.dev/community")!)
                }
                Text("When on, each grain you claim is mirrored to the public Community Rock at boulder-43p.pages.dev/community. Other Boulder users can click any grain to see your first name, what you were working on, and when. Capped at 20,000 lifetime grains per device.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
