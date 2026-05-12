// PopoverContentView.swift
//
// The popover hung off the menubar 🪨. Layout (top → bottom):
//   • Tier label + pixel count
//   • Big Boulder canvas (this is the same rock as in the menubar)
//   • Tier progress bar
//   • Focus-type chips
//   • Timer + Focus/Stop button
//   • Blocked-apps strip (icons only)
//   • Footer: Gallery / Release / Settings / Quit
//
// On crumble, the entire stage shakes briefly + a red "−N" floats up.

import SwiftUI

struct PopoverContentView: View {
    @EnvironmentObject var store: BoulderStore
    @EnvironmentObject var appDelegate: AppDelegate

    @State private var shake: CGFloat = 0
    @State private var crumblePop: Bool = false

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
                    controls
                    blockedAppsStrip
                    footer
                }
            }
        }
        .frame(width: 380, height: 560)
        .onChange(of: store.crumbleFlashAt) { _, newValue in
            guard newValue != nil else { return }
            playCrumbleAnimation()
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
                        .opacity(0.9)
                    Text("Focusing")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(hex: 0x2EE6A0))
                }
                Spacer()
                Text("\(store.model.pixelCount) px")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.55))
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            ZStack {
                BoulderRenderer(pixels: store.model.pixels)
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
                    .offset(x: shake)

                if crumblePop {
                    Text("−3 px")
                        .font(.headline.bold())
                        .foregroundStyle(Color(hex: 0xFF6B6B))
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .padding(.bottom, 70)
                }
            }

            ProgressView(value: store.model.tierProgress)
                .progressViewStyle(.linear)
                .tint(Color(hex: 0xC147FF))
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
        }
    }

    private func playCrumbleAnimation() {
        // 6 shakes, then settle. Total ≈ 0.4s.
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

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: 14) {
            HStack(spacing: 6) {
                ForEach(FocusType.allCases) { type in
                    Button {
                        store.selectedFocusType = type
                    } label: {
                        VStack(spacing: 2) {
                            Text(type.emoji).font(.system(size: 18))
                            Text(type.rawValue)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(store.selectedFocusType == type
                                      ? Color.white.opacity(0.16)
                                      : Color.white.opacity(0.05))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)

            Text(store.selectedFocusType.subtitle)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))

            HStack(spacing: 12) {
                Text(formatElapsed(store.sessionElapsed))
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    if store.isFocusing { store.stopFocus() } else { store.startFocus() }
                } label: {
                    Text(store.isFocusing ? "Stop" : "Focus")
                        .font(.headline)
                        .frame(width: 96, height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(store.isFocusing
                                      ? Color(hex: 0xFF6B6B)
                                      : Color(hex: 0xC147FF))
                        )
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 14)
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
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
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
                            .frame(width: 18, height: 18)
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
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
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
        .padding(.bottom, 12)
    }

    private func footerButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.white.opacity(0.07)))
                .foregroundStyle(.white.opacity(0.85))
        }
        .buttonStyle(.plain)
    }

    private func formatElapsed(_ t: TimeInterval) -> String {
        let total = Int(t)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }
}
