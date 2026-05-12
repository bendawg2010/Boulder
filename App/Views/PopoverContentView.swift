// PopoverContentView.swift
//
// The main popover hung off the menubar. Top half: the live Boulder.
// Bottom half: focus controls (timer, type selector, start/stop) and
// a footer with gallery + settings + tip links.

import SwiftUI

struct PopoverContentView: View {
    @EnvironmentObject var store: BoulderStore
    @EnvironmentObject var appDelegate: AppDelegate

    var body: some View {
        ZStack {
            // Soft brand-tinted background.
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
                    footer
                }
            }
        }
        .frame(width: 360, height: 520)
    }

    private var boulderStage: some View {
        VStack(spacing: 4) {
            HStack {
                Text(store.model.tier.rawValue)
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.9))
                Spacer()
                Text("\(store.model.pixelCount) px")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            BoulderRenderer(pixels: store.model.pixels)
                .frame(maxWidth: .infinity)
                .frame(height: 220)

            ProgressView(value: store.model.tierProgress)
                .progressViewStyle(.linear)
                .tint(Color(hex: 0xC147FF))
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
        }
    }

    private var controls: some View {
        VStack(spacing: 14) {
            // Focus type selector — five pixel chips.
            HStack(spacing: 6) {
                ForEach(FocusType.allCases) { type in
                    Button {
                        store.selectedFocusType = type
                    } label: {
                        VStack(spacing: 2) {
                            Text(type.emoji).font(.system(size: 18))
                            Text(type.rawValue)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(store.selectedFocusType == type
                                      ? Color.white.opacity(0.15)
                                      : Color.white.opacity(0.05))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)

            Text(store.selectedFocusType.subtitle)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.45))

            // Timer + start/stop.
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

    private var footer: some View {
        HStack(spacing: 10) {
            footerButton("Gallery") { appDelegate.openGallery() }
            if store.model.canRelease {
                footerButton("Release →") { store.isReleasing = true }
            }
            Spacer()
            footerButton("⚙︎") { appDelegate.openSettings() }
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
                .background(
                    Capsule().fill(Color.white.opacity(0.07))
                )
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
