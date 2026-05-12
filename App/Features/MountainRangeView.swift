// MountainRangeView.swift
//
// Horizontal panorama of every retired Boulder. Each thumbnail
// renders frozen pixels colored from the tag snapshot taken at
// release time, so historical Boulders display correctly even after
// the user has edited or deleted tags in the live library.

import SwiftUI

struct MountainRangeView: View {
    @EnvironmentObject var store: BoulderStore

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hex: 0x06010F),
                    Color(hex: 0x1A1230),
                    Color(hex: 0x2B2244)
                ],
                startPoint: .top, endPoint: .bottom
            ).ignoresSafeArea()

            if store.model.range.isEmpty {
                VStack(spacing: 10) {
                    Text("Your mountain range is empty")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                    Text("Grow a Boulder to Mountain size, then release it.\nEach Boulder you release joins the skyline.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.55))
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .bottom, spacing: 28) {
                        ForEach(store.model.range) { rb in
                            VStack(spacing: 6) {
                                BoulderRenderer(
                                    pixels: rb.pixels,
                                    paletteFor: { p in palette(for: p, in: rb) },
                                    cellSize: 1.5,
                                    autoScale: false,
                                    groundLine: false
                                )
                                .frame(width: 220, height: 220)
                                Text(formatRange(rb))
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.55))
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 32)
                }
            }
        }
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
