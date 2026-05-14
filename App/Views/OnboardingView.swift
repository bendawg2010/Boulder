// OnboardingView.swift
//
// First-launch sheet. Asks for the user's first name (required) and
// gives them an optional name for their rock. Both go into
// BoulderModel and persist forever. The first-name shows up on the
// share page; if blank, the share page just says "Someone grew this
// rock" — we don't bug them every session.

import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var store: BoulderStore
    @Environment(\.dismiss) private var dismiss

    @State private var firstName: String = ""
    @State private var rockName: String = ""
    @FocusState private var firstNameFocused: Bool

    private var trimmedName: String {
        firstName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0x0A0518), Color(hex: 0x1C1338)],
                startPoint: .top, endPoint: .bottom
            ).ignoresSafeArea()

            VStack(spacing: 22) {
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
                        subtitle: "Optional. \"Granite\", \"Mt. Deadline\", \"Steve\" — up to you.",
                        text: $rockName,
                        placeholder: "(optional)"
                    )
                }
                .frame(maxWidth: 340)

                Button(action: save) {
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

                Text("You can change these anytime in Settings.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.35))
            }
            .padding(40)
        }
        .frame(width: 440, height: 540)
        .onAppear { firstNameFocused = true }
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

    private func save() {
        let name = trimmedName
        guard !name.isEmpty else { return }
        store.setIdentity(firstName: name, rockName: rockName.trimmingCharacters(in: .whitespacesAndNewlines))
        dismiss()
    }
}
