// ReleaseCeremonyView.swift
//
// The animation that plays when the user releases a Mountain-sized
// Boulder. Rolls Boulder off the right edge → splash → silence →
// fresh pebble appears center stage. Calls store.releaseBoulder()
// at the end of the sequence (which retires the Boulder into the
// Mountain Range and starts a new one).

import SwiftUI

struct ReleaseCeremonyView: View {
    @EnvironmentObject var store: BoulderStore

    @State private var rollOffset: CGFloat = 0
    @State private var rollRotation: Angle = .zero
    @State private var splashOpacity: Double = 0
    @State private var splashScale: CGFloat = 0.4
    @State private var fadeOut: Double = 1.0
    @State private var showPebble: Bool = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Sea-horizon backdrop.
                LinearGradient(
                    colors: [Color(hex: 0x0E0824), Color(hex: 0x1B1840), Color(hex: 0x2B3F66)],
                    startPoint: .top, endPoint: .bottom
                ).ignoresSafeArea()

                // The rolling Boulder.
                BoulderRenderer(pixels: store.model.pixels, cellSize: 2.5)
                    .frame(width: 240, height: 240)
                    .rotationEffect(rollRotation)
                    .offset(x: rollOffset, y: 40)
                    .opacity(fadeOut)

                // Splash burst.
                Circle()
                    .stroke(Color.white.opacity(0.7), lineWidth: 3)
                    .frame(width: 120, height: 120)
                    .scaleEffect(splashScale)
                    .opacity(splashOpacity)
                    .position(x: geo.size.width - 40, y: geo.size.height - 80)

                if showPebble {
                    BoulderRenderer(pixels: [], cellSize: 4)
                        .frame(width: 80, height: 80)
                        .overlay(Text("🪨").font(.system(size: 28)))
                        .transition(.opacity)
                }
            }
            .onAppear { runCeremony(width: geo.size.width) }
        }
        .frame(height: 320)
    }

    private func runCeremony(width: CGFloat) {
        // 1) Roll right for 1.6s.
        withAnimation(.easeIn(duration: 1.6)) {
            rollOffset = width / 2 + 200
            rollRotation = .degrees(540)
        }
        // 2) Splash at 1.6s.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.55) {
            withAnimation(.easeOut(duration: 0.4)) {
                splashOpacity = 1
                splashScale = 1.6
                fadeOut = 0
            }
        }
        // 3) Fade splash 0.8s later.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
            withAnimation(.easeOut(duration: 0.6)) {
                splashOpacity = 0
            }
        }
        // 4) Reveal the fresh pebble after silence.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
            store.releaseBoulder()
            withAnimation(.easeIn(duration: 0.4)) { showPebble = true }
        }
    }
}
