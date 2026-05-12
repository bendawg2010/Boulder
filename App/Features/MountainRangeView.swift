// MountainRangeView.swift
//
// The horizontal panorama of every Boulder you've ever released.
// Each retired Boulder draws as a small frozen silhouette, in order.
// Together they form your mountain range — the skyline of your years.

import SwiftUI

struct MountainRangeView: View {
    @EnvironmentObject var store: BoulderStore

    var body: some View {
        ZStack {
            // Sky → sea gradient backdrop.
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
                                BoulderRenderer(pixels: rb.pixels, cellSize: 1.5, groundLine: false)
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

    private func formatRange(_ rb: RetiredBoulder) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM yyyy"
        return "\(rb.dominantType.emoji)  \(f.string(from: rb.startedAt)) → \(f.string(from: rb.releasedAt))"
    }
}
