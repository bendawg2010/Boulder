// OnboardingView.swift
//
// First-launch sheet. Manual name entry + optional rock name.
//
// We previously tried Sign in with Apple, but it requires the
// `com.apple.developer.applesignin` entitlement to be *granted at
// runtime* — which Apple only does for builds signed by a paid
// Developer Program identity. Boulder ships ad-hoc-signed (free, MIT),
// so the SIWA button always failed in practice. Removing it removes
// the dishonest UI.
//
// Cross-device sync is provided by the auto-generated sync_id UUID
// the store stamps on completion + the Pair Device QR in Settings.

import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var store: BoulderStore
    var onDismiss: () -> Void = {}

    @State private var firstName: String = ""
    @State private var rockName: String = ""
    @State private var contribute: Bool = false
    @State private var pairing: Bool = false
    @State private var pairSyncID: String = ""
    @State private var pairError: String? = nil
    @State private var pairBusy: Bool = false
    @FocusState private var firstNameFocused: Bool
    @FocusState private var pairFieldFocused: Bool

    private var trimmedName: String {
        firstName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0x0A0518), Color(hex: 0x1C1338)],
                startPoint: .top, endPoint: .bottom
            ).ignoresSafeArea()

            if pairing {
                pairForm
            } else {
                newRockForm
            }
        }
        .frame(width: 440, height: 560)
        .onAppear { firstNameFocused = true }
    }

    private var newRockForm: some View {
        VStack(spacing: 20) {
                Text("🪨")
                    .font(.system(size: 64))
                    .shadow(color: Color(hex: 0xC147FF).opacity(0.5), radius: 18)

                VStack(spacing: 4) {
                    Text("Welcome to Boulder")
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    Text("A pet rock for your focus.")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.55))
                }

                VStack(alignment: .leading, spacing: 14) {
                    field(
                        label: "Your first name",
                        subtitle: "Shown on rocks you share. Required.",
                        text: $firstName,
                        placeholder: "Ben"
                    )
                    .focused($firstNameFocused)

                    field(
                        label: "Name your rock",
                        subtitle: "Optional. \"Granite\", \"Mt. Deadline\", \"Steve\".",
                        text: $rockName,
                        placeholder: "(optional)"
                    )
                }
                .frame(maxWidth: 340)

                Button(action: saveManual) {
                    Text("Start growing")
                        .font(.system(size: 15, weight: .heavy))
                        .tracking(0.4)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(
                            LinearGradient(
                                colors: trimmedName.isEmpty
                                    ? [Color.gray.opacity(0.4), Color.gray.opacity(0.35)]
                                    : [Color(hex: 0xFFD960), Color(hex: 0xFF6B6B), Color(hex: 0xC147FF)],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .clipShape(Capsule())
                        .foregroundStyle(.black.opacity(0.85))
                        .shadow(color: Color(hex: 0xFFD960).opacity(trimmedName.isEmpty ? 0 : 0.45), radius: 12, y: 2)
                }
                .buttonStyle(.plain)
                .disabled(trimmedName.isEmpty)
                .frame(maxWidth: 340)

                Toggle(isOn: $contribute) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Contribute to the Community Rock")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white.opacity(0.85))
                        Text("Each grain you claim appears on boulder-43p.pages.dev/community. Others can see your first name + what you were doing. Off by default — change anytime in Settings.")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.42))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.switch)
                .tint(Color(hex: 0xC147FF))
                .frame(maxWidth: 340)
                .padding(.top, 4)

                Button {
                    pairing = true
                    pairFieldFocused = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "qrcode.viewfinder")
                        Text("Already have a rock on another device?")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)

                Text("Cross-device sync is on by default. You can also pair later in Settings → Cloud sync.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.40))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
            }
            .padding(40)
    }

    private var pairForm: some View {
        VStack(spacing: 18) {
            Text("🔗")
                .font(.system(size: 56))
                .shadow(color: Color(hex: 0x47A0FF).opacity(0.5), radius: 18)

            VStack(spacing: 4) {
                Text("Pair existing rock")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text("Paste the sync ID from your other device.")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
            }

            Text("On the other device, open Settings → Cloud sync and copy the sync ID. Or scan the QR code at boulder-43p.pages.dev/app from the same browser.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.45))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)

            VStack(alignment: .leading, spacing: 6) {
                Text("Sync ID")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.78))
                    .tracking(0.3)
                TextField("12345678-90ab-cdef-1234-567890abcdef", text: $pairSyncID)
                    .focused($pairFieldFocused)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .medium).monospaced())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                            )
                    )
                if let err = pairError {
                    Text(err)
                        .font(.caption2)
                        .foregroundStyle(Color(hex: 0xFF6B6B))
                }
            }
            .frame(maxWidth: 340)

            Button(action: confirmPair) {
                HStack(spacing: 8) {
                    if pairBusy {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.black.opacity(0.85))
                    }
                    Text(pairBusy ? "Pulling rock…" : "Pair this device")
                        .font(.system(size: 15, weight: .heavy))
                        .tracking(0.4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(
                    LinearGradient(
                        colors: parsedSyncID == nil
                            ? [Color.gray.opacity(0.4), Color.gray.opacity(0.35)]
                            : [Color(hex: 0x2EE6A0), Color(hex: 0x47A0FF), Color(hex: 0xC147FF)],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .clipShape(Capsule())
                .foregroundStyle(.black.opacity(0.85))
                .shadow(color: Color(hex: 0x47A0FF).opacity(parsedSyncID == nil ? 0 : 0.45), radius: 12, y: 2)
            }
            .buttonStyle(.plain)
            .disabled(parsedSyncID == nil || pairBusy)
            .frame(maxWidth: 340)

            Button("Or start a new rock instead") {
                pairing = false
                firstNameFocused = true
                pairError = nil
            }
            .buttonStyle(.plain)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.6))
            .padding(.top, 4)
        }
        .padding(40)
    }

    private var parsedSyncID: UUID? {
        UUID(uuidString: pairSyncID.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func field(label: String, subtitle: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.78))
                .tracking(0.3)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                )
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.42))
        }
    }

    private func saveManual() {
        let name = trimmedName
        guard !name.isEmpty else { return }
        store.setIdentity(firstName: name, rockName: rockName.trimmingCharacters(in: .whitespacesAndNewlines))
        store.setCloudSyncEnabled(true)
        store.setContributeToCommunity(contribute)
        onDismiss()
    }

    private func confirmPair() {
        guard let id = parsedSyncID else {
            pairError = "That doesn't look like a sync ID (expecting a UUID)."
            return
        }
        pairError = nil
        pairBusy = true
        Task { @MainActor in
            let remote = await BoulderSync.shared.pull(syncID: id)
            pairBusy = false
            guard let model = remote else {
                pairError = "No rock found for that sync ID. Double-check and try again."
                return
            }
            store.adoptPairedModel(model, syncID: id)
            onDismiss()
        }
    }
}
