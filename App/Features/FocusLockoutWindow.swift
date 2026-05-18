// FocusLockoutWindow.swift
//
// Two modes:
//   • WARNING  — 3-second countdown overlay shown when a blocked app
//     gets focus during a session. Includes an "I'm back" button.
//     Posts .boulderResumeFocus if pressed → FocusBlocker cancels its
//     pending termination + grain forfeit.
//   • BLOCKED  — final "X was closed, N grains lost" toast shown if
//     the warning timer expires without the user dismissing.
//
// Uses NSPanel at .screenSaver level + .nonactivatingPanel + the
// .fullScreenAuxiliary collection behavior so the overlay sits above
// fullscreen games and doesn't steal focus from Boulder's popover.

import AppKit
import SwiftUI

@MainActor
enum FocusLockoutWindow {
    private static var current: NSPanel?
    private static var dismissWork: DispatchWorkItem?

    static func showWarning(appName: String, seconds: Int) {
        present(view: AnyView(
            LockoutWarningView(appName: appName, seconds: seconds)
        ), autoDismissAfter: nil)
    }

    static func showBlocked(appName: String, grainsLost: Int) {
        present(view: AnyView(
            LockoutBlockedView(appName: appName, grainsLost: grainsLost)
        ), autoDismissAfter: 2.0)
    }

    /// Legacy entry — keeps the old call signature working.
    static func show(appName: String, pixelsLost: Int) {
        showBlocked(appName: appName, grainsLost: pixelsLost)
    }

    static func dismiss() {
        dismissWork?.cancel()
        current?.orderOut(nil)
    }

    private static func present(view: AnyView, autoDismissAfter: TimeInterval?) {
        dismissWork?.cancel()

        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 520, height: 280)

        let panel: NSPanel
        if let existing = current {
            panel = existing
            panel.contentView = host
        } else {
            panel = NSPanel(
                contentRect: host.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            // .screenSaver sits above fullscreen apps (games, Spaces).
            panel.level = .screenSaver
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.isMovableByWindowBackground = false
            panel.ignoresMouseEvents = false
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            panel.contentView = host
            current = panel
        }

        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            let w = panel.frame.width, h = panel.frame.height
            panel.setFrame(
                NSRect(x: f.midX - w / 2, y: f.midY - h / 2, width: w, height: h),
                display: true
            )
        }
        panel.orderFrontRegardless()

        if let d = autoDismissAfter {
            let work = DispatchWorkItem { current?.orderOut(nil) }
            dismissWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + d, execute: work)
        }
    }
}

// MARK: Warning view — countdown + "I'm back" button.

private struct LockoutWarningView: View {
    let appName: String
    let seconds: Int

    @State private var remaining: Int
    @State private var appeared = false
    @State private var ticker: Timer?

    init(appName: String, seconds: Int) {
        self.appName = appName
        self.seconds = seconds
        self._remaining = State(initialValue: seconds)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.black.opacity(0.88))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color(hex: 0xFFD960).opacity(0.55), lineWidth: 2)
                )
                .shadow(color: Color.black.opacity(0.6), radius: 30)

            VStack(spacing: 12) {
                Text("🪨  HEADS UP")
                    .font(.system(size: 32, weight: .black))
                    .tracking(1.5)
                    .foregroundStyle(Color(hex: 0xFFD960))
                Text("You opened \(appName).")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.88))
                Text("Returning to Boulder in \(remaining)…")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
                    .monospacedDigit()

                Button(action: resume) {
                    Text("I'm back — keep focusing")
                        .font(.system(size: 14, weight: .heavy))
                        .tracking(0.4)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(
                            LinearGradient(
                                colors: [Color(hex: 0x2EE6A0), Color(hex: 0x47A0FF)],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .clipShape(Capsule())
                        .foregroundStyle(.black.opacity(0.85))
                }
                .buttonStyle(.plain)
                .padding(.top, 6)

                Text("If you don't, \(appName) closes and you forfeit this session's banked grains.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
            .padding(28)
        }
        .frame(width: 520, height: 280)
        .scaleEffect(appeared ? 1.0 : 0.92)
        .opacity(appeared ? 1.0 : 0.0)
        .onAppear {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.7)) { appeared = true }
            // SwiftUI Timer in @State so we don't leak.
            ticker = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                Task { @MainActor in
                    if remaining > 0 { remaining -= 1 }
                    if remaining <= 0 { ticker?.invalidate() }
                }
            }
        }
        .onDisappear { ticker?.invalidate() }
    }

    private func resume() {
        ticker?.invalidate()
        NotificationCenter.default.post(name: .boulderResumeFocus, object: nil)
    }
}

// MARK: Blocked view — final "you lost N grains" toast.

private struct LockoutBlockedView: View {
    let appName: String
    let grainsLost: Int

    @State private var appeared = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.black.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color(hex: 0xFF6B6B).opacity(0.55), lineWidth: 2)
                )
                .shadow(color: Color.black.opacity(0.6), radius: 30)

            VStack(spacing: 14) {
                Text("🪨  BLOCKED")
                    .font(.system(size: 42, weight: .black))
                    .tracking(1.5)
                    .foregroundStyle(Color(hex: 0xFF6B6B))
                Text("\(appName) was closed.")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.88))
                if grainsLost > 0 {
                    Text("Forfeited \(grainsLost) banked grain\(grainsLost == 1 ? "" : "s").")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.65))
                }
                Text("Your rock is safe. Get back to it.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.top, 2)
            }
            .padding(36)
        }
        .frame(width: 520, height: 240)
        .scaleEffect(appeared ? 1.0 : 0.92)
        .opacity(appeared ? 1.0 : 0.0)
        .onAppear {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.7)) { appeared = true }
        }
    }
}
