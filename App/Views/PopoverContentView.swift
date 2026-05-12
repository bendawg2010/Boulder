// PopoverContentView.swift
//
// The popover hung off the menubar 🪨. Stack:
//   • Tier + momentum + pixel count header
//   • Boulder canvas (or empty state when 0 px), tap-to-inspect
//   • Description text field
//   • Tag picker  (or "Create your first tag" prompt when 0 tags)
//   • Duration chips  (15m / 25m / 45m / 1h / Open)
//   • Timer + Focus/Give Up button  (countdown when committed)
//   • Blocked-apps strip
//   • Footer (Gallery / Settings / Quit)
//
// On crumble: shake + red "-N px" floater.
// On commitment completion: golden flash + auto-stop.

import SwiftUI

struct PopoverContentView: View {
    @EnvironmentObject var store: BoulderStore
    @EnvironmentObject var appDelegate: AppDelegate

    @State private var shake: CGFloat = 0
    @State private var crumblePop: Bool = false
    @State private var completionGlow: Bool = false
    @State private var presentTagEditor: Bool = false
    @State private var editingTag: FocusTag? = nil
    @State private var inspector: PixelInspection? = nil
    @State private var showGiveUpConfirm: Bool = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0x0A0518), Color(hex: 0x1C1338)],
                startPoint: .top, endPoint: .bottom
            ).ignoresSafeArea()

            if store.isReleasing {
                ReleaseCeremonyView()
                    .environmentObject(store)
            } else {
                VStack(spacing: 0) {
                    boulderStage
                    Divider().overlay(Color.white.opacity(0.08))
                    descriptionField
                    tagPickerOrEmpty
                    if !store.model.tags.isEmpty { durationPicker }
                    timerRow
                    blockedAppsStrip
                    footer
                }
            }
        }
        .frame(width: 380, height: 680)
        .overlay(alignment: .center) {
            if completionGlow {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(hex: 0xFFD960).opacity(0.85), lineWidth: 4)
                    .blur(radius: 6)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .onChange(of: store.crumbleFlashAt) { _, v in if v != nil { playCrumbleAnimation() } }
        .onChange(of: store.completionFlashAt) { _, v in if v != nil { playCompletionAnimation() } }
        .sheet(isPresented: $presentTagEditor) {
            TagEditorView(existing: editingTag)
                .environmentObject(store)
        }
        .alert("Give up early?", isPresented: $showGiveUpConfirm) {
            Button("Keep going", role: .cancel) { }
            Button("Give up (−\(store.giveUpPenalty) px)", role: .destructive) {
                store.giveUpEarly()
            }
        } message: {
            Text("You committed to \(formatDuration(store.session(forID: store.currentSessionID)?.plannedDuration ?? 0)). Giving up now chips \(store.giveUpPenalty) pixels off Boulder.")
        }
    }

    // MARK: Boulder stage

    private var boulderStage: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Text(store.model.tier.rawValue)
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.92))
                if store.isFocusing {
                    Circle()
                        .fill(Color(hex: 0x2EE6A0))
                        .frame(width: 6, height: 6)
                    Text(store.momentumTierLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(hex: 0x2EE6A0))
                    Text(String(format: "×%.1f", store.currentMultiplier))
                        .font(.caption.monospacedDigit().weight(.bold))
                        .foregroundStyle(Color(hex: 0xFFD960))
                }
                Spacer()
                Text("\(store.model.pixelCount) px")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.55))
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            ZStack {
                if store.model.pixels.isEmpty {
                    emptyRockState
                        .frame(maxWidth: .infinity)
                        .frame(height: 180)
                } else {
                    BoulderRenderer(
                        pixels: store.model.pixels,
                        paletteFor: { store.palette(for: $0) },
                        onPixelTap: handlePixelTap
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
                    .offset(x: shake)
                }
                if crumblePop {
                    Text("−3 px")
                        .font(.headline.bold())
                        .foregroundStyle(Color(hex: 0xFF6B6B))
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .padding(.bottom, 70)
                }
                if let inspector { inspectorOverlay(inspector) }
            }

            ProgressView(value: store.model.tierProgress)
                .progressViewStyle(.linear)
                .tint(Color(hex: 0xC147FF))
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
        }
    }

    private var emptyRockState: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)
            Text("🪨").font(.system(size: 52)).opacity(0.55)
            Text("Your Boulder is a pebble.")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.75))
            Text(store.model.tags.isEmpty
                 ? "Create a tag below, then press Focus to grow."
                 : "Pick a tag, describe what you're focusing on,\nand press Focus to start growing.")
                .multilineTextAlignment(.center)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.45))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
    }

    // MARK: Description field

    private var descriptionField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(store.isFocusing
                 ? "Currently focusing on"
                 : "What are you focusing on?")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.45))
            TextField(
                "e.g. \"Refactoring the boulder renderer\"",
                text: store.isFocusing
                    ? .constant(currentSessionBlurb)
                    : $store.draftBlurb
            )
            .textFieldStyle(.plain)
            .font(.body)
            .foregroundStyle(.white)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
            .disabled(store.isFocusing)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private var currentSessionBlurb: String {
        store.session(forID: store.currentSessionID)?.blurb ?? ""
    }

    // MARK: Tag picker / empty state

    @ViewBuilder
    private var tagPickerOrEmpty: some View {
        if store.model.tags.isEmpty {
            VStack(spacing: 8) {
                Button {
                    editingTag = nil
                    presentTagEditor = true
                } label: {
                    Label("Create your first tag", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(hex: 0xC147FF))
                        )
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                Text("Tags decide your pixel colors and let you click your rock to see what you were doing.")
                    .multilineTextAlignment(.center)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.horizontal, 24)
            }
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
        } else {
            tagPicker
        }
    }

    private var tagPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(store.model.tags) { tag in tagChip(tag) }
                Button {
                    editingTag = nil
                    presentTagEditor = true
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .bold))
                        Text("New").font(.caption2.weight(.semibold))
                    }
                    .frame(width: 56, height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.15),
                                    style: StrokeStyle(lineWidth: 1, dash: [3]))
                    )
                    .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private func tagChip(_ tag: FocusTag) -> some View {
        let isSelected = store.selectedTagID == tag.id
        return Button {
            store.selectedTagID = tag.id
        } label: {
            VStack(spacing: 2) {
                Text(tag.emoji).font(.system(size: 16))
                Text(tag.name)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                Rectangle()
                    .fill(tag.chipColor)
                    .frame(height: 3)
                    .cornerRadius(1.5)
            }
            .frame(width: 64)
            .padding(.vertical, 7).padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.18) : Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(isSelected ? tag.chipColor.opacity(0.7) : .clear, lineWidth: 1.5)
                    )
            )
            .foregroundStyle(.white.opacity(0.92))
        }
        .buttonStyle(.plain)
        .disabled(store.isFocusing)
        .opacity(store.isFocusing && !isSelected ? 0.4 : 1.0)
        .contextMenu {
            Button("Edit") {
                editingTag = tag
                presentTagEditor = true
            }
            Button("Delete", role: .destructive) {
                store.deleteTag(id: tag.id)
            }
        }
        .help(tag.blurb.isEmpty ? tag.name : tag.blurb)
    }

    // MARK: Duration picker

    /// Pre-commit chips. "Open" = no duration (just focus, stop when
    /// you want). Anything else = committed session with countdown +
    /// give-up penalty.
    private let durationOptions: [(label: String, seconds: TimeInterval?)] = [
        ("15 m",   15 * 60),
        ("25 m",   25 * 60),
        ("45 m",   45 * 60),
        ("1 h",    60 * 60),
        ("90 m",   90 * 60),
        ("Open",   nil)
    ]

    private var durationPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(store.isFocusing
                     ? "Committed to"
                     : "Commit to a duration")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.45))
                Spacer()
                if !store.isFocusing && store.draftDuration != nil {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(Color(hex: 0xFFD960))
                }
            }
            HStack(spacing: 6) {
                ForEach(durationOptions, id: \.label) { opt in
                    durationChip(label: opt.label, seconds: opt.seconds)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    private func durationChip(label: String, seconds: TimeInterval?) -> some View {
        let isSelected: Bool
        if store.isFocusing {
            isSelected = (store.session(forID: store.currentSessionID)?.plannedDuration == seconds)
        } else {
            isSelected = (store.draftDuration == seconds)
        }
        return Button {
            store.draftDuration = seconds
        } label: {
            Text(label)
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected
                              ? Color(hex: 0xFFD960).opacity(0.18)
                              : Color.white.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isSelected ? Color(hex: 0xFFD960).opacity(0.5) : .clear,
                                        lineWidth: 1)
                        )
                )
                .foregroundStyle(isSelected ? Color(hex: 0xFFD960) : .white.opacity(0.7))
        }
        .buttonStyle(.plain)
        .disabled(store.isFocusing)
    }

    // MARK: Timer row

    private var timerRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(timerText)
                    .font(.system(size: 26, weight: .bold, design: .monospaced))
                    .foregroundStyle(timerColor)
                    .contentTransition(.numericText())
                if store.isFocusing, let remaining = store.timeRemaining {
                    Text("\(formatDuration(remaining)) left")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            Spacer()
            focusButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var timerText: String {
        if store.isFocusing, let remaining = store.timeRemaining {
            return formatHMS(Int(remaining))
        }
        return formatHMS(Int(store.sessionElapsed))
    }

    private var timerColor: Color {
        guard store.isFocusing, let remaining = store.timeRemaining else { return .white }
        // Last 30 seconds: warm pulse.
        return remaining <= 30 ? Color(hex: 0xFFD960) : .white
    }

    private var focusButton: some View {
        Button {
            if store.isFocusing {
                if store.session(forID: store.currentSessionID)?.committed == true {
                    showGiveUpConfirm = true
                } else {
                    store.stopFocus()
                }
            } else {
                store.startFocus()
            }
        } label: {
            Text(focusButtonTitle)
                .font(.headline)
                .frame(width: 112, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(focusButtonFill)
                )
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .disabled(!store.isFocusing && store.selectedTag == nil)
        .opacity((!store.isFocusing && store.selectedTag == nil) ? 0.4 : 1.0)
    }

    private var focusButtonTitle: String {
        if !store.isFocusing { return "Focus" }
        if store.session(forID: store.currentSessionID)?.committed == true { return "Give up" }
        return "Stop"
    }

    private var focusButtonFill: Color {
        if store.isFocusing {
            return store.session(forID: store.currentSessionID)?.committed == true
                ? Color(hex: 0xFF6B6B)
                : Color(hex: 0xFF6B6B).opacity(0.85)
        }
        return store.selectedTag?.chipColor ?? Color(hex: 0xC147FF)
    }

    // MARK: Blocked apps strip

    private var blockedAppsStrip: some View {
        Group {
            if store.model.blockedApps.isEmpty {
                Button {
                    appDelegate.openSettings()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                        Text("Block apps that break your focus")
                            .font(.caption)
                    }
                    .foregroundStyle(.white.opacity(0.42))
                    .padding(.horizontal, 16).padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            } else {
                HStack(spacing: 6) {
                    Text("Blocking:")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.45))
                    ForEach(store.model.blockedApps.prefix(6)) { app in
                        Image(nsImage: app.icon)
                            .resizable()
                            .frame(width: 16, height: 16)
                            .opacity(0.85)
                    }
                    if store.model.blockedApps.count > 6 {
                        Text("+\(store.model.blockedApps.count - 6)")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.45))
                    }
                    Spacer()
                    Button("Edit") { appDelegate.openSettings() }
                        .buttonStyle(.plain)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .padding(.horizontal, 16).padding(.vertical, 6)
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 8) {
            footerButton("Gallery") { appDelegate.openGallery() }
            if store.model.canRelease {
                footerButton("Release →") { store.isReleasing = true }
            }
            Spacer()
            footerButton("Settings") { appDelegate.openSettings() }
            footerButton("Quit") { appDelegate.quit(nil) }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    private func footerButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Capsule().fill(Color.white.opacity(0.07)))
                .foregroundStyle(.white.opacity(0.85))
        }
        .buttonStyle(.plain)
    }

    // MARK: Pixel inspector

    private struct PixelInspection {
        let tag: FocusTag?
        let session: FocusSession?
    }

    private func handlePixelTap(_ index: Int?) {
        guard let i = index, i < store.model.pixels.count else {
            inspector = nil; return
        }
        let p = store.model.pixels[i]
        let info = PixelInspection(
            tag: store.tag(forID: p.tagID),
            session: store.session(forID: p.sessionID)
        )
        withAnimation(.easeOut(duration: 0.15)) { inspector = info }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) {
            withAnimation(.easeIn(duration: 0.2)) {
                if self.inspector?.session?.id == info.session?.id { self.inspector = nil }
            }
        }
    }

    private func inspectorOverlay(_ info: PixelInspection) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(info.tag?.emoji ?? "🪨")
                Text(info.tag?.name ?? "Untagged pixel")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    withAnimation(.easeIn(duration: 0.15)) { inspector = nil }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
            if let session = info.session {
                Text(session.blurb.isEmpty ? "(no description)" : session.blurb)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.85))
                HStack(spacing: 6) {
                    Text(formatDate(session.startedAt))
                    if session.gaveUp { Text("· gave up").foregroundStyle(Color(hex: 0xFF6B6B)) }
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.4))
            } else if let blurb = info.tag?.blurb, !blurb.isEmpty {
                Text(blurb)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
        .padding(10)
        .frame(maxWidth: 280, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.7))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.1), lineWidth: 1))
        )
        .padding(.horizontal, 24).padding(.vertical, 10)
    }

    // MARK: Animations

    private func playCrumbleAnimation() {
        let pattern: [CGFloat] = [-8, 7, -6, 5, -3, 2, 0]
        withAnimation(.easeOut(duration: 0.08)) { crumblePop = true }
        for (i, dx) in pattern.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05 * Double(i)) {
                withAnimation(.easeInOut(duration: 0.05)) { shake = dx }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            withAnimation(.easeIn(duration: 0.2)) { crumblePop = false }
        }
    }

    private func playCompletionAnimation() {
        withAnimation(.easeOut(duration: 0.4)) { completionGlow = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(.easeIn(duration: 0.5)) { completionGlow = false }
        }
    }

    // MARK: Formatters

    private func formatHMS(_ total: Int) -> String {
        let s = max(0, total)
        let h = s / 3600
        let m = (s % 3600) / 60
        let r = s % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, r) }
        return String(format: "%02d:%02d", m, r)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        if s >= 3600 {
            let h = s / 3600, m = (s % 3600) / 60
            return m == 0 ? "\(h)h" : "\(h)h \(m)m"
        }
        return "\(s / 60)m"
    }

    private func formatDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d · HH:mm"
        return f.string(from: d)
    }
}
