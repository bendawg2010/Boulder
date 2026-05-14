// ReleaseCeremonyView.swift
//
// Cinematic 5.5s release ceremony.
//   0.0s   pre-roll: Boulder lifts 18px off the baseline (gravity hint)
//   1.0s   roll-right: 1.6s easeIn, 540° spin, dust puffs trailing
//   2.6s   splash: 3 concentric wave rings expand at the impact point
//   3.6s   silence
//   4.1s   headline "Boulder released." chunky + "Your mountain range grew." quieter
//   5.0s   store.releaseBoulder() — fresh pebble fades in
//
// All animations are calm easeOut / spring (damping 0.7-0.85).

import SwiftUI

struct ReleaseCeremonyView: View {
    @EnvironmentObject var store: BoulderStore

    // Boulder motion
    @State private var liftOffset: CGFloat = 0          // negative = up
    @State private var rollOffset: CGFloat = 0
    @State private var rollRotation: Angle = .zero
    @State private var boulderOpacity: Double = 1.0

    // Dust puffs (trailing the rolling boulder)
    @State private var dustEmitAt: Date? = nil

    // Splash rings (3 concentric)
    @State private var ring1Scale: CGFloat = 0.3
    @State private var ring2Scale: CGFloat = 0.3
    @State private var ring3Scale: CGFloat = 0.3
    @State private var ring1Opacity: Double = 0
    @State private var ring2Opacity: Double = 0
    @State private var ring3Opacity: Double = 0

    // Headline reveal
    @State private var titleOpacity: Double = 0
    @State private var subtitleOpacity: Double = 0
    @State private var titleOffset: CGFloat = 8

    // Fresh pebble
    @State private var showPebble: Bool = false
    @State private var pebbleScale: CGFloat = 0.6

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Sea-horizon backdrop.
                LinearGradient(
                    colors: [Color(hex: 0x0E0824), Color(hex: 0x1B1840), Color(hex: 0x2B3F66)],
                    startPoint: .top, endPoint: .bottom
                ).ignoresSafeArea()

                // Dust puffs ride underneath the boulder.
                DustTrailLayer(
                    triggerAt: dustEmitAt,
                    rollOffset: rollOffset,
                    baseX: geo.size.width / 2,
                    baseY: geo.size.height - 80 + 40
                )
                .allowsHitTesting(false)

                // The rolling Boulder.
                BoulderRenderer(
                    pixels: store.model.pixels,
                    paletteFor: { store.palette(for: $0) },
                    cellSize: 2.5,
                    autoScale: false
                )
                .frame(width: 240, height: 240)
                .rotationEffect(rollRotation)
                .offset(x: rollOffset, y: 40 + liftOffset)
                .opacity(boulderOpacity)

                // Splash rings: 3 concentric ripples expanding outward.
                ZStack {
                    splashRing(scale: ring1Scale, opacity: ring1Opacity, width: 110)
                    splashRing(scale: ring2Scale, opacity: ring2Opacity, width: 140)
                    splashRing(scale: ring3Scale, opacity: ring3Opacity, width: 170)
                }
                .position(x: geo.size.width - 40, y: geo.size.height - 80)

                // Headline + subtitle (centered).
                VStack(spacing: 6) {
                    Text("Boulder released.")
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .tracking(-0.3)
                        .shadow(color: Color(hex: 0x2EE6A0).opacity(0.4), radius: 12)
                        .opacity(titleOpacity)
                        .offset(y: titleOffset)
                    Text("Your mountain range grew.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.65))
                        .tracking(0.2)
                        .opacity(subtitleOpacity)
                        .offset(y: titleOffset)
                }
                .position(x: geo.size.width / 2, y: geo.size.height / 2 - 20)

                // Fresh pebble (appears after release call).
                if showPebble {
                    Text("🪨")
                        .font(.system(size: 40))
                        .scaleEffect(pebbleScale)
                        .position(x: geo.size.width / 2, y: geo.size.height / 2 + 80)
                        .transition(.opacity)
                }
            }
            .onAppear { runCeremony(width: geo.size.width) }
        }
        .frame(height: 320)
    }

    /// One ripple ring with a soft brand-tinted outline.
    private func splashRing(scale: CGFloat, opacity: Double, width: CGFloat) -> some View {
        Circle()
            .stroke(
                LinearGradient(
                    colors: [
                        Color(hex: 0x47A0FF).opacity(0.85),
                        Color(hex: 0x2EE6A0).opacity(0.6)
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ),
                lineWidth: 2
            )
            .frame(width: width, height: width)
            .scaleEffect(scale)
            .opacity(opacity)
    }

    private func runCeremony(width: CGFloat) {
        // 0.0s → 1.0s : lift-off (gravity hint)
        withAnimation(.easeOut(duration: 0.55).delay(0.05)) {
            liftOffset = -18
        }
        withAnimation(.easeIn(duration: 0.4).delay(0.6)) {
            liftOffset = -6
        }

        // 1.0s → 2.6s : roll right, dust starts emitting
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            dustEmitAt = Date()
            withAnimation(.easeIn(duration: 1.6)) {
                rollOffset = width / 2 + 200
                rollRotation = .degrees(540)
                liftOffset = 0
            }
        }

        // 2.55s : boulder fades just before splash peaks
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.55) {
            withAnimation(.easeOut(duration: 0.25)) {
                boulderOpacity = 0
            }
        }

        // 2.6s : splash — 3 rings stagger outward
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
            withAnimation(.easeOut(duration: 0.75)) {
                ring1Scale = 1.6
                ring1Opacity = 1
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.75) {
            withAnimation(.easeOut(duration: 0.85)) {
                ring2Scale = 1.7
                ring2Opacity = 0.85
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.9) {
            withAnimation(.easeOut(duration: 0.95)) {
                ring3Scale = 1.8
                ring3Opacity = 0.65
            }
        }
        // Rings fade
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
            withAnimation(.easeOut(duration: 0.6)) {
                ring1Opacity = 0
                ring2Opacity = 0
                ring3Opacity = 0
            }
        }

        // 3.6s → 4.1s : silence

        // 4.1s : headline fades in
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.1) {
            withAnimation(.easeOut(duration: 0.55)) {
                titleOpacity = 1
                titleOffset = 0
            }
        }
        // 4.4s : subtitle follows
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.4) {
            withAnimation(.easeOut(duration: 0.5)) {
                subtitleOpacity = 1
            }
        }

        // 5.0s : release boulder + pebble reveal
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            store.releaseBoulder()
            showPebble = true
            withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) {
                pebbleScale = 1.0
            }
        }
    }
}

/// Trailing dust-puff layer. Spawns ~8 small puffs over the roll
/// window and fades them out behind the boulder.
private struct DustTrailLayer: View {
    let triggerAt: Date?
    let rollOffset: CGFloat
    let baseX: CGFloat
    let baseY: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            Canvas { ctx, _ in
                guard let trigger = triggerAt else { return }
                let elapsed = timeline.date.timeIntervalSince(trigger)
                // Roll runs 1.6s; emit one puff every 0.18s.
                let puffs = 9
                for i in 0..<puffs {
                    let emitAt = Double(i) * 0.18
                    let age = elapsed - emitAt
                    guard age > 0, age < 1.4 else { continue }
                    let progress = age / 1.4
                    let x = baseX + CGFloat(emitAt / 1.6) * rollOffset * 0.5
                    let y = baseY + CGFloat(sin(age * 4)) * 2
                    let radius = 4 + CGFloat(progress) * 10
                    let alpha = 0.35 * (1 - progress)
                    let rect = CGRect(
                        x: x - radius, y: y - radius,
                        width: radius * 2, height: radius * 2
                    )
                    ctx.fill(
                        Path(ellipseIn: rect),
                        with: .color(.white.opacity(alpha))
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
