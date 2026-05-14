// MountainRangeView.swift
//
// Horizontal panorama of every retired Boulder. Each thumbnail
// renders frozen pixels colored from the tag snapshot taken at
// release time, so historical Boulders display correctly even after
// the user has edited or deleted tags in the live library.

import SwiftUI

struct MountainRangeView: View {
    @EnvironmentObject var store: BoulderStore
    @State private var scrollOffset: CGFloat = 0

    var body: some View {
        ZStack {
            // Backdrop with a parallax orb that drifts as the user
            // scrolls horizontally. Subtle — it just adds depth.
            backdrop

            if store.model.range.isEmpty {
                emptyState
            } else {
                rangeScroll
            }
        }
    }

    // MARK: Backdrop

    private var backdrop: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hex: 0x06010F),
                    Color(hex: 0x1A1230),
                    Color(hex: 0x2B2244)
                ],
                startPoint: .top, endPoint: .bottom
            ).ignoresSafeArea()

            // Parallax orb — drifts opposite the scroll, slow.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(hex: 0xC147FF).opacity(0.18),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 10,
                        endRadius: 240
                    )
                )
                .frame(width: 480, height: 480)
                .offset(x: -scrollOffset * 0.25 - 80, y: -60)
                .allowsHitTesting(false)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(hex: 0x47A0FF).opacity(0.14),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 10,
                        endRadius: 200
                    )
                )
                .frame(width: 380, height: 380)
                .offset(x: -scrollOffset * 0.45 + 220, y: 120)
                .allowsHitTesting(false)
        }
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 22) {
            // Ghost silhouette row — pebbles fading into the distance.
            HStack(alignment: .bottom, spacing: 18) {
                ForEach(0..<6, id: \.self) { i in
                    let scale = 1.0 - Double(i) * 0.13
                    let opacity = 0.22 - Double(i) * 0.03
                    Capsule()
                        .fill(Color.white.opacity(max(0.04, opacity)))
                        .frame(width: 70 * scale, height: 44 * scale)
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(opacity * 0.9),
                                        style: StrokeStyle(lineWidth: 1, dash: [2.5, 3]))
                        )
                }
            }
            VStack(spacing: 6) {
                Text("Your mountain range is empty.")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.88))
                Text("Grow a Boulder to Mountain size, then release it.")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    // MARK: Range scroll

    private var rangeScroll: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .bottom, spacing: 28) {
                ForEach(store.model.range) { rb in
                    boulderCard(rb)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 32)
            .background(
                // Read scroll offset for the parallax orb.
                GeometryReader { geo in
                    Color.clear
                        .preference(
                            key: ScrollOffsetKey.self,
                            value: -geo.frame(in: .named("rangeScroll")).origin.x
                        )
                }
            )
        }
        .coordinateSpace(name: "rangeScroll")
        .onPreferenceChange(ScrollOffsetKey.self) { value in
            scrollOffset = value
        }
    }

    private func boulderCard(_ rb: RetiredBoulder) -> some View {
        let accent = dominantTagColor(in: rb)
        return VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.025))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(accent.opacity(0.45), lineWidth: 1.2)
                    )
                    .shadow(color: accent.opacity(0.18), radius: 12, y: 4)
                BoulderRenderer(
                    pixels: rb.pixels,
                    paletteFor: { p in palette(for: p, in: rb) },
                    cellSize: 1.5,
                    autoScale: false,
                    groundLine: false
                )
            }
            .frame(width: 220, height: 220)

            VStack(spacing: 2) {
                Text(formatRange(rb))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Text(metaLine(rb))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.42))
            }
        }
    }

    /// "N grains · M sessions" caption.
    private func metaLine(_ rb: RetiredBoulder) -> String {
        let px = rb.pixels.count
        let sessionIDs = Set(rb.pixels.compactMap { $0.sessionID })
        let count = sessionIDs.count
        let suffix = count == 1 ? "session" : "sessions"
        return "\(px) grains · \(count) \(suffix)"
    }

    /// Dominant tag's chip color (for the card's border accent).
    /// Falls back to the dominant FocusType's primary color if no
    /// tag snapshot survived.
    private func dominantTagColor(in rb: RetiredBoulder) -> Color {
        var counts: [UUID: Int] = [:]
        for p in rb.pixels {
            if let id = p.tagID { counts[id, default: 0] += 1 }
        }
        if let topID = counts.max(by: { $0.value < $1.value })?.key,
           let tag = rb.tagSnapshot.first(where: { $0.id == topID }) {
            return tag.chipColor
        }
        return Color(hex: 0xC147FF)
    }

    /// Look up a pixel's color in the retired Boulder's tag snapshot,
    /// falling back to legacyType then a neutral grey.
    private func palette(for pixel: BoulderPixel, in rb: RetiredBoulder) -> [Color] {
        if let id = pixel.tagID, let tag = rb.tagSnapshot.first(where: { $0.id == id }) {
            return tag.palette
        }
        if let t = pixel.legacyType { return t.palette }
        return BoulderRenderer.fallbackPalette
    }

    private func formatRange(_ rb: RetiredBoulder) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM yyyy"
        return "\(rb.dominantType.emoji)  \(f.string(from: rb.startedAt)) → \(f.string(from: rb.releasedAt))"
    }
}

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
