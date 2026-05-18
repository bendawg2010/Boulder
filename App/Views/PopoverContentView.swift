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
import AppKit

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
    @State private var focusFieldHovered: Bool = false
    @State private var shareJustCopied: Bool = false
    @State private var shareFailed: Bool = false
    @State private var showOnboarding: Bool = false
    @FocusState private var descriptionFocused: Bool

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
        .alert("Stop early?", isPresented: $showGiveUpConfirm) {
            Button("Keep going", role: .cancel) { }
            Button("Stop the session") {
                store.giveUpEarly()
            }
        } message: {
            Text("You committed to \(formatDuration(store.session(forID: store.currentSessionID)?.plannedDuration ?? 0)). Stopping now is fine — every grain you've earned is banked. You can claim them anytime.")
        }
        .onAppear {
            // Onboarding is its own NSWindow now (managed by
            // AppDelegate). If the user reopens the popover before
            // finishing onboarding, nudge the window forward.
            if store.model.userFirstName == nil {
                appDelegate.showOnboarding()
            }
        }
    }

    // MARK: Boulder stage

    private var boulderStage: some View {
        VStack(spacing: 8) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 16)

            canvas

            if !store.model.pixels.isEmpty {
                actionRow
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
            }

            tierProgressBar
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 12)
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.78), value: store.pendingPixelCount)
        .animation(.spring(response: 0.45, dampingFraction: 0.78), value: store.flushState)
    }

    private var claimVisible: Bool {
        store.pendingPixelCount > 0 && !store.isFocusing && store.flushState == nil
    }

    /// Always-visible row directly under the rock canvas: Claim (left,
    /// when pending) + Share (right, always). When there's nothing to
    /// claim, Share stretches to fill the row.
    private var actionRow: some View {
        HStack(spacing: 10) {
            if claimVisible {
                claimGrainsButton
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
            shareRockButton(compact: claimVisible)
                .transition(.scale(scale: 0.92).combined(with: .opacity))
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.78), value: store.pendingPixelCount)
        .animation(.spring(response: 0.45, dampingFraction: 0.78), value: store.flushState)
        .animation(.spring(response: 0.45, dampingFraction: 0.78), value: store.isFocusing)
    }

    /// Big celebratory button — shows up after a session ends with
    /// pending grains in escrow. Pressing it fires the slow pour-in.
    private var claimGrainsButton: some View {
        Button(action: { store.claimGrains() }) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .heavy))
                Text("Claim \(store.pendingPixelCount) grain\(store.pendingPixelCount == 1 ? "" : "s")")
                    .font(.system(size: 14, weight: .heavy))
                    .tracking(0.3)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                LinearGradient(
                    colors: [Color(hex: 0xFFD960), Color(hex: 0xFF6B6B), Color(hex: 0xC147FF)],
                    startPoint: .leading, endPoint: .trailing
                )
            )
            .clipShape(Capsule())
            .foregroundStyle(.black.opacity(0.85))
            .shadow(color: Color(hex: 0xFFD960).opacity(0.45), radius: 12, y: 2)
        }
        .buttonStyle(.plain)
    }

    /// Always-on Share button. Compact icon-pill when sharing space
    /// with Claim; full pill when alone.
    private func shareRockButton(compact: Bool) -> some View {
        Button(action: shareRock) {
            HStack(spacing: 8) {
                Image(systemName: shareIconName)
                    .font(.system(size: 13, weight: .heavy))
                if !compact {
                    Text(shareLabel)
                        .font(.system(size: 14, weight: .heavy))
                        .tracking(0.3)
                }
            }
            .frame(maxWidth: compact ? nil : .infinity)
            .padding(.horizontal, compact ? 14 : 16)
            .padding(.vertical, 12)
            .background(
                LinearGradient(
                    colors: shareGradient,
                    startPoint: .leading, endPoint: .trailing
                )
            )
            .clipShape(Capsule())
            .foregroundStyle(.white)
            .shadow(color: Color(hex: 0xC147FF).opacity(0.40), radius: 10, y: 2)
            .contentShape(Capsule())   // ensure the full pill is clickable, not just the icon
        }
        .buttonStyle(.plain)
        .help(shareLabel)
        .animation(.easeInOut(duration: 0.18), value: shareJustCopied)
        .animation(.easeInOut(duration: 0.18), value: shareFailed)
    }

    private var shareIconName: String {
        if shareJustCopied { return "checkmark.circle.fill" }
        if shareFailed     { return "exclamationmark.triangle.fill" }
        return "square.and.arrow.up"
    }
    private var shareLabel: String {
        if shareJustCopied { return "Link copied!" }
        if shareFailed     { return "Couldn't copy — try again" }
        return "Share your rock"
    }
    private var shareGradient: [Color] {
        if shareFailed { return [Color(hex: 0xFF6B6B), Color(hex: 0xFFD960)] }
        return [Color(hex: 0xFF6B6B), Color(hex: 0xC147FF)]
    }

    /// Copy a sharable link to the clipboard. Resilient to rare URL-
    /// construction edge cases (huge payloads, weird names) — falls
    /// back to a hand-built URL string if URLComponents bails. Uses
    /// @State Bools (not a date-based computed property) so the
    /// "Copied!" pill always animates reliably.
    private func shareRock() {
        let urlString: String?
        if let url = BoulderShareEncoder.shareURL(for: store.model) {
            urlString = url.absoluteString
        } else {
            // Manual fallback. The payload chars are all URL-safe
            // base64 ([-_A-Za-z0-9]) so we can splice them into the
            // hash directly without further encoding.
            let payload = BoulderShareEncoder.encode(
                pixels: store.model.pixels,
                tags: store.model.tags
            )
            var qs: [String] = []
            if let n = store.model.userFirstName,
               !n.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let encoded = n.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? n
                qs.append("by=\(encoded)")
            }
            if let r = store.model.rockName,
               !r.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let encoded = r.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? r
                qs.append("name=\(encoded)")
            }
            let query = qs.isEmpty ? "" : "?" + qs.joined(separator: "&")
            urlString = "\(BoulderShareEncoder.shareBase)\(query)#\(payload)"
        }

        guard let s = urlString else {
            NSLog("Boulder: share failed — no URL string")
            flashShareFailed()
            return
        }

        let pb = NSPasteboard.general
        pb.clearContents()
        let ok = pb.setString(s, forType: .string)
        if !ok {
            NSLog("Boulder: share failed — pasteboard setString returned false")
            flashShareFailed()
            return
        }

        shareJustCopied = true
        shareFailed = false
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            shareJustCopied = false
        }
    }

    private func flashShareFailed() {
        shareFailed = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            shareFailed = false
        }
    }

    /// Tier name + momentum pill + pixel count. Designed as a three-band
    /// header — title left, momentum chip center (only when focusing),
    /// pixel count right. The momentum pill consolidates the previous
    /// dot + label + multiplier into a single tinted capsule.
    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(store.model.tier.rawValue)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white.opacity(0.94))
                    .tracking(0.2)
                Text(tierSubtitle)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.45))
            }
            Spacer(minLength: 6)
            if store.isFocusing {
                momentumPill
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
            if store.pendingPixelCount > 0 && store.isFocusing {
                pendingBadge
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
            }
            Text("\(store.model.pixelCount) grains")
                .font(.caption.monospacedDigit().weight(.medium))
                .foregroundStyle(.white.opacity(0.55))
        }
        .animation(.easeOut(duration: 0.2), value: store.isFocusing)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: store.pendingPixelCount)
    }

    /// "+N pending" badge that floats next to the momentum pill while
    /// pixels accumulate during a session. Pixels don't land on the
    /// rock until you stop — this is the user's only indication they're
    /// banking up. Pulses gently on each increment.
    private var pendingBadge: some View {
        Text("+\(store.pendingPixelCount) banked")
            .font(.caption2.monospacedDigit().weight(.heavy))
            .foregroundStyle(Color(hex: 0xFFD960))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(Color(hex: 0xFFD960).opacity(0.12))
                    .overlay(
                        Capsule().stroke(Color(hex: 0xFFD960).opacity(0.35), lineWidth: 0.8)
                    )
            )
    }

    private var tierSubtitle: String {
        let next = nextTierName
        let remaining = max(0, pixelsToNextTier)
        if remaining == 0 { return "Mountain reached — release when ready" }
        return "\(remaining) grains to \(next)"
    }

    private var nextTierName: String {
        let tiers = SizeTier.allCases
        guard let idx = tiers.firstIndex(of: store.model.tier),
              idx + 1 < tiers.count else { return "Mountain" }
        return tiers[idx + 1].rawValue
    }

    private var pixelsToNextTier: Int {
        let tiers = SizeTier.allCases
        guard let idx = tiers.firstIndex(of: store.model.tier),
              idx + 1 < tiers.count else { return 0 }
        return tiers[idx + 1].thresholdPixels - store.model.pixelCount
    }

    private var momentumPill: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color(hex: 0x2EE6A0))
                .frame(width: 5, height: 5)
                .shadow(color: Color(hex: 0x2EE6A0).opacity(0.6), radius: 3)
            Text(store.momentumTierLabel)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
            Text(String(format: "×%.1f", store.currentMultiplier))
                .font(.caption2.monospacedDigit().weight(.heavy))
                .foregroundStyle(Color(hex: 0xFFD960))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color(hex: 0x2EE6A0).opacity(0.10))
                .overlay(
                    Capsule().stroke(Color(hex: 0x2EE6A0).opacity(0.25), lineWidth: 0.8)
                )
        )
    }

    /// Boulder canvas. Wrapped in a subtle radial vignette so the rock
    /// reads as sitting IN the popover, not floating on it.
    private var canvas: some View {
        ZStack {
            // Vignette — gradient + inner stroke gives the rock a stage.
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.04),
                            Color.black.opacity(0.0),
                            Color.black.opacity(0.18)
                        ],
                        center: .center,
                        startRadius: 30,
                        endRadius: 180
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.05), lineWidth: 1)
                )
                .padding(.horizontal, 12)

            if store.model.pixels.isEmpty {
                emptyRockState
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
            } else {
                BoulderRenderer(
                    pixels: store.model.pixels,
                    paletteFor: { store.palette(for: $0) },
                    onPixelTap: handlePixelTap,
                    flushState: store.flushState
                )
                .frame(maxWidth: .infinity)
                .frame(height: 180)
                // Aggressive zoom-in during the pour-in so each new
                // pixel feels weighty. 1.0 → 1.30 over 0.55s easeOut,
                // hold at 1.30 while pixels stagger in, ease back to
                // 1.0 at the tail.
                .scaleEffect(store.flushState == nil ? 1.0 : 1.30)
                .animation(
                    store.flushState == nil
                        ? .easeIn(duration: 0.5)
                        : .easeOut(duration: 0.55),
                    value: store.flushState
                )
                .offset(x: shake)
            }
            if crumblePop {
                Text("−3 grains")
                    .font(.headline.bold())
                    .foregroundStyle(Color(hex: 0xFF6B6B))
                    .shadow(color: Color(hex: 0xFF6B6B).opacity(0.6), radius: 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.bottom, 70)
            }
            if let inspector { inspectorOverlay(inspector) }
        }
    }

    /// Refined tier progress bar with subdivision ticks for upcoming
    /// tiers and a smoothly-animated fill.
    private var tierProgressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Track
                Capsule()
                    .fill(Color.white.opacity(0.06))
                // Fill
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0xC147FF), Color(hex: 0xFF6B6B)],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(width: max(2, geo.size.width * CGFloat(store.model.tierProgress)))
                    .animation(.easeOut(duration: 0.6), value: store.model.tierProgress)
                // Subdivision ticks for the upcoming tier(s).
                ForEach(upcomingTierTicks, id: \.self) { t in
                    Rectangle()
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 1, height: 6)
                        .offset(x: geo.size.width * CGFloat(t) - 0.5)
                }
            }
        }
        .frame(height: 6)
    }

    /// Tick positions within the current tier-progress range. Currently
    /// just a midpoint marker — keeps the bar from feeling featureless
    /// without overcrowding it.
    private var upcomingTierTicks: [Double] {
        store.model.tier == .mountain ? [] : [0.5]
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
        VStack(alignment: .leading, spacing: 6) {
            Text(store.isFocusing
                 ? "Currently focusing on"
                 : "What are you focusing on?")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.45))
                .tracking(0.3)
            TextField(
                "e.g. \"Refactoring the boulder renderer\"",
                text: store.isFocusing
                    ? .constant(currentSessionBlurb)
                    : $store.draftBlurb
            )
            .textFieldStyle(.plain)
            .font(.body)
            .foregroundStyle(.white)
            .focused($descriptionFocused)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(descriptionFocused ? 0.10 : 0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        descriptionFocused
                            ? (store.selectedTag?.chipColor ?? Color(hex: 0xC147FF)).opacity(0.65)
                            : Color.white.opacity(0.05),
                        lineWidth: 1.2
                    )
            )
            .animation(.easeOut(duration: 0.18), value: descriptionFocused)
            .disabled(store.isFocusing)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    private var currentSessionBlurb: String {
        store.session(forID: store.currentSessionID)?.blurb ?? ""
    }

    // MARK: Tag picker / empty state

    @ViewBuilder
    private var tagPickerOrEmpty: some View {
        if store.model.tags.isEmpty {
            VStack(spacing: 10) {
                Button {
                    editingTag = nil
                    presentTagEditor = true
                } label: {
                    Label("Create your first tag", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 11)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(hex: 0xC147FF))
                                .shadow(color: Color(hex: 0xC147FF).opacity(0.45), radius: 10, y: 3)
                        )
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                Text("Tags decide your pixel colors and let you click your rock to see what you were doing.")
                    .multilineTextAlignment(.center)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.horizontal, 28)
            }
            .padding(.vertical, 16)
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
                    VStack(spacing: 3) {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .bold))
                        Text("New").font(.caption2.weight(.semibold))
                    }
                    .frame(width: 56, height: 54)
                    .background(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .stroke(Color.white.opacity(0.15),
                                    style: StrokeStyle(lineWidth: 1, dash: [3]))
                    )
                    .foregroundStyle(.white.opacity(0.55))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private func tagChip(_ tag: FocusTag) -> some View {
        let isSelected = store.selectedTagID == tag.id
        return Button {
            store.selectedTagID = tag.id
        } label: {
            VStack(spacing: 4) {
                Text(tag.emoji).font(.system(size: 17))
                Text(tag.name)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
            }
            .frame(width: 64, height: 54)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(
                        isSelected
                            ? tag.chipColor.opacity(0.28)
                            : Color.white.opacity(0.05)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(
                        isSelected ? tag.chipColor.opacity(0.85) : Color.white.opacity(0.06),
                        lineWidth: isSelected ? 1.4 : 1
                    )
            )
            .overlay(alignment: .bottom) {
                // A thin tinted bar at the bottom edge — replaces the
                // 3px detached stripe with something that reads as
                // chip styling rather than a separate element.
                RoundedRectangle(cornerRadius: 0, style: .continuous)
                    .fill(tag.chipColor.opacity(isSelected ? 0.9 : 0.4))
                    .frame(height: 2)
                    .clipShape(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 0,
                            bottomLeadingRadius: 11,
                            bottomTrailingRadius: 11,
                            topTrailingRadius: 0
                        )
                    )
            }
            .foregroundStyle(.white.opacity(0.92))
            .shadow(
                color: isSelected ? tag.chipColor.opacity(0.4) : .clear,
                radius: isSelected ? 6 : 0,
                y: isSelected ? 1 : 0
            )
        }
        .buttonStyle(.plain)
        .disabled(store.isFocusing)
        .opacity(store.isFocusing && !isSelected ? 0.4 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isSelected)
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
    /// you want), encoded as seconds=0 so we can distinguish "user
    /// explicitly picked Open" from "user hasn't picked anything".
    private let durationOptions: [(label: String, seconds: TimeInterval)] = [
        ("15 m",   15 * 60),
        ("25 m",   25 * 60),
        ("45 m",   45 * 60),
        ("1 h",    60 * 60),
        ("Open",   0)
    ]

    private var durationPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(durationPickerHeading)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.45))
                    .tracking(0.3)
                Spacer()
                if !store.isFocusing, let d = store.draftDuration, d > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9))
                        Text("Committed")
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(Color(hex: 0xFFD960))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(
                        Capsule().fill(Color(hex: 0xFFD960).opacity(0.12))
                    )
                }
            }
            HStack(spacing: 6) {
                ForEach(durationOptions, id: \.label) { opt in
                    durationChip(label: opt.label, seconds: opt.seconds)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var durationPickerHeading: String {
        if store.isFocusing {
            if let d = store.session(forID: store.currentSessionID)?.plannedDuration, d > 0 {
                return "COMMITTED TO"
            }
            return "OPEN SESSION"
        }
        return "PICK A DURATION (OPTIONAL)"
    }

    private func durationChip(label: String, seconds: TimeInterval) -> some View {
        let isSelected: Bool
        if store.isFocusing {
            let committed = store.session(forID: store.currentSessionID)?.plannedDuration ?? 0
            isSelected = (committed == seconds)
        } else {
            isSelected = (store.draftDuration == seconds)
        }
        // The "Open" chip is the only non-committed option — give it
        // a visually quieter neutral treatment vs the gold "lock" set.
        let isOpen = (seconds == 0)
        let activeTint = isOpen ? Color.white : Color(hex: 0xFFD960)
        return Button {
            // Toggle off if tapping the already-selected chip — lets
            // the user back out without picking a different option.
            if store.draftDuration == seconds {
                store.draftDuration = nil
            } else {
                store.draftDuration = seconds
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(
                        isSelected
                            ? activeTint.opacity(isOpen ? 0.13 : 0.20)
                            : Color.white.opacity(0.05)
                    )
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(
                        isSelected ? activeTint.opacity(0.65) : Color.white.opacity(0.04),
                        lineWidth: isSelected ? 1.3 : 1
                    )
                HStack(spacing: 4) {
                    if isSelected && !isOpen {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 8, weight: .bold))
                    }
                    Text(label)
                        .font(.caption.weight(.semibold))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 32)
            .foregroundStyle(isSelected ? activeTint : .white.opacity(0.7))
        }
        .buttonStyle(.plain)
        .disabled(store.isFocusing)
        .animation(.easeOut(duration: 0.12), value: isSelected)
    }

    // MARK: Timer row

    private var timerRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(timerText)
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .tracking(-0.5)
                    .foregroundStyle(timerColor)
                    .contentTransition(.numericText())
                if store.isFocusing, let remaining = store.timeRemaining {
                    Text("\(formatDuration(remaining)) left")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.4))
                } else if !store.isFocusing {
                    Text(timerHint)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
            Spacer()
            focusButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var timerHint: String {
        if store.selectedTag == nil { return "Pick a tag to focus" }
        if let d = store.draftDuration, d > 0 {
            return "Tap Focus to commit"
        }
        return "Ready when you are"
    }

    private var timerText: String {
        if store.isFocusing, let remaining = store.timeRemaining {
            return formatHMS(Int(remaining))
        }
        // Pre-focus: show the picked duration as a countdown PREVIEW
        // so the user can see "15:00" before hitting Focus, then it
        // counts down from there. Was showing 00:00 → looked broken.
        if !store.isFocusing, let d = store.draftDuration, d > 0 {
            return formatHMS(Int(d))
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
                .font(.system(size: 14, weight: .semibold))
                .tracking(0.3)
                .frame(width: 112, height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 19, style: .continuous)
                        .fill(focusButtonFill)
                        .shadow(
                            color: focusButtonFill.opacity(0.55),
                            radius: 10,
                            y: 3
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 19, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
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
                            .font(.system(size: 11))
                        Text("Block apps that break your focus")
                            .font(.caption)
                    }
                    .foregroundStyle(.white.opacity(0.42))
                    .padding(.horizontal, 16).padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            } else {
                HStack(spacing: 8) {
                    Text("Blocking")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.45))
                        .tracking(0.3)
                    blockedIconCluster
                    Spacer()
                    Button("Edit") { appDelegate.openSettings() }
                        .buttonStyle(.plain)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
            }
        }
    }

    /// Overlapped row of blocked-app icons (Slack-avatar style).
    /// Caps at 6 visible, then "+N" pill for the rest.
    private var blockedIconCluster: some View {
        let apps = Array(store.model.blockedApps.prefix(6))
        let overflow = store.model.blockedApps.count - apps.count
        return HStack(spacing: -6) {
            ForEach(Array(apps.enumerated()), id: \.element.id) { (idx, app) in
                Image(nsImage: app.icon)
                    .resizable()
                    .frame(width: 18, height: 18)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(Color(hex: 0x0A0518), lineWidth: 1.5)
                    )
                    .zIndex(Double(apps.count - idx))
                    .help(app.displayName)
            }
            if overflow > 0 {
                Text("+\(overflow)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 18, height: 18)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.12))
                            .overlay(Circle().stroke(Color(hex: 0x0A0518), lineWidth: 1.5))
                    )
                    .padding(.leading, 2)
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 8) {
            footerButton(label: "Gallery", icon: "mountain.2.fill") {
                appDelegate.openGallery()
            }
            if store.model.canRelease {
                releaseFooterButton
            }
            Spacer()
            footerButton(label: "Settings", icon: "gearshape.fill") {
                appDelegate.openSettings()
            }
            footerButton(label: "Quit", icon: nil, isQuit: true) {
                appDelegate.quit(nil)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .padding(.top, 4)
    }

    private func footerButton(label: String, icon: String?, isQuit: Bool = false,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .semibold))
                }
                Text(label)
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.white.opacity(isQuit ? 0.05 : 0.08))
            )
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.04), lineWidth: 1)
            )
            .foregroundStyle(.white.opacity(isQuit ? 0.55 : 0.85))
        }
        .buttonStyle(.plain)
    }

    /// Bright pill calling attention to the once-in-a-while Release
    /// action. Subtle pulse keeps it readable as "do this if you want".
    private var releaseFooterButton: some View {
        Button { store.isReleasing = true } label: {
            HStack(spacing: 5) {
                Image(systemName: "wind")
                    .font(.system(size: 10, weight: .bold))
                Text("Release")
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: 0x2EE6A0).opacity(0.20),
                                Color(hex: 0x47A0FF).opacity(0.20)
                            ],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
            )
            .overlay(
                Capsule().stroke(Color(hex: 0x2EE6A0).opacity(0.35), lineWidth: 1)
            )
            .foregroundStyle(Color(hex: 0x2EE6A0))
        }
        .buttonStyle(.plain)
        .help("Retire this Boulder into your Mountain Range and start fresh")
    }

    // MARK: Pixel inspector

    private struct PixelInspection {
        let tag: FocusTag?
        let session: FocusSession?
        /// The exact moment this pixel was earned. Falls back to the
        /// session's startedAt for legacy pixels (pre-v1.4.3) that
        /// don't carry their own date.
        let earnedAt: Date?
    }

    private func handlePixelTap(_ index: Int?) {
        guard let i = index, i < store.model.pixels.count else {
            inspector = nil; return
        }
        let p = store.model.pixels[i]
        let session = store.session(forID: p.sessionID)
        let info = PixelInspection(
            tag: store.tag(forID: p.tagID),
            session: session,
            earnedAt: p.earnedAt ?? session?.startedAt
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
            // Date — every pixel now stamps its earned-at on creation.
            if let when = info.earnedAt {
                Text(formatPixelDate(when))
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Color(hex: 0xFFD960))
            }
            if let session = info.session {
                Text(session.blurb.isEmpty ? "(no description)" : session.blurb)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.85))
                if session.gaveUp {
                    Text("gave up early")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color(hex: 0xFF6B6B))
                }
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

    /// Relative + absolute date for a single pixel ("2h ago · May 12,
    /// 8:34 PM"). Recent pixels read as recent; old ones get a full
    /// date so the user can see how long Boulder has been growing.
    private func formatPixelDate(_ d: Date) -> String {
        let now = Date()
        let interval = now.timeIntervalSince(d)
        let absFmt = DateFormatter()
        if interval < 60 * 60 * 24 {
            absFmt.dateFormat = "h:mm a"
        } else if interval < 60 * 60 * 24 * 7 {
            absFmt.dateFormat = "EEE · h:mm a"
        } else {
            absFmt.dateFormat = "MMM d, yyyy · h:mm a"
        }
        let rel = RelativeDateTimeFormatter()
        rel.unitsStyle = .short
        return "\(rel.localizedString(for: d, relativeTo: now)) · \(absFmt.string(from: d))"
    }

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
