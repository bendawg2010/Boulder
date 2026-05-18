// PairDeviceSheet.swift
//
// Modal that shows a QR code encoding the Boulder web-app URL with
// this user's sync_id. Scan from a phone -> opens boulder-43p.pages.dev/app/
// with the sync_id pre-applied -> same rock everywhere.

import SwiftUI
import AppKit

struct PairDeviceSheet: View {
    @EnvironmentObject var store: BoulderStore
    @Environment(\.dismiss) private var dismiss

    private var pairURL: String {
        let id = (store.model.syncID ?? UUID()).uuidString.lowercased()
        return "https://boulder-43p.pages.dev/app/#sync=\(id)"
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0x0A0518), Color(hex: 0x1C1338)],
                startPoint: .top, endPoint: .bottom
            ).ignoresSafeArea()

            VStack(spacing: 18) {
                HStack {
                    Text("Pair another device")
                        .font(.system(size: 19, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    .buttonStyle(.plain)
                }

                Text("Scan with your phone camera. Boulder opens in the browser and your same rock loads.")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                qrTile

                VStack(spacing: 8) {
                    Text("Or copy the link:")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.5))
                        .tracking(0.3)
                    HStack(spacing: 8) {
                        Text(pairURL)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .padding(.horizontal, 10).padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.white.opacity(0.05))
                            )
                        Button("Copy") { copyURL() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    }
                }

                Text("Anyone with the link can grow this rock. Keep it private.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.42))
                    .multilineTextAlignment(.center)
            }
            .padding(28)
        }
        .frame(width: 420, height: 540)
    }

    private var qrTile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color(hex: 0xC147FF).opacity(0.45), lineWidth: 1.2)
                )

            if let img = QRCodeImage.make(from: pairURL, size: 240) {
                Image(nsImage: img)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 220, height: 220)
                    .shadow(color: Color(hex: 0xC147FF).opacity(0.35), radius: 18, y: 4)
            } else {
                Text("Couldn't generate QR")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .frame(width: 260, height: 260)
    }

    private func copyURL() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(pairURL, forType: .string)
    }
}
