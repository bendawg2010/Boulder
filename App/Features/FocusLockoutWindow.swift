// FocusLockoutWindow.swift
//
// Fullscreen-style lockout overlay that pops up center-screen every
// time the user activates a blocked app. Big, impossible to miss,
// auto-dismisses after 2 seconds. Uses NSPanel at .floating level
// with `.nonactivating` so it doesn't steal keyboard focus — Boulder
// itself can keep being interacted with.
//
// macOS won't grant indie apps real app-blocking entitlements, but
// this is the most aggressive friction we can ship without breaking
// system norms: the user sees a giant warning every time they tab
// to a blocked app + the app keeps hiding itself.

import AppKit
import SwiftUI

@MainActor
enum FocusLockoutWindow {
    private static var current: NSPanel?
    private static var dismissWork: DispatchWorkItem?

    static func show(appName: String, pixelsLost: Int) {
        // If a previous lockout is on-screen, refresh its content and
        // restart the dismiss timer — don't stack windows.
        dismissWork?.cancel()

        let host = NSHostingView(rootView: LockoutContentView(appName: appName, pixelsLost: pixelsLost))
        host.frame = NSRect(x: 0, y: 0, width: 520, height: 240)

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
            // .screenSaver sits above true-fullscreen apps (games,
            // Spaces). .floating gets covered. We use the highest
            // sensible non-system level so the overlay always wins.
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

        // Center on the screen with the menubar (likely the user's
        // primary). Fall back to main screen.
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            let w = panel.frame.width, h = panel.frame.height
            panel.setFrame(
                NSRect(x: f.midX - w / 2, y: f.midY - h / 2, width: w, height: h),
                display: true
            )
        }

        panel.orderFrontRegardless()

        let work = DispatchWorkItem {
            current?.orderOut(nil)
        }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
    }
}

private struct LockoutContentView: View {
    let appName: String
    let pixelsLost: Int

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
                Text("Get back to your rock.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.top, 4)
            }
            .padding(36)
        }
        .frame(width: 520, height: 240)
        .scaleEffect(appeared ? 1.0 : 0.92)
        .opacity(appeared ? 1.0 : 0.0)
        .onAppear {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.7)) {
                appeared = true
            }
        }
    }
}
