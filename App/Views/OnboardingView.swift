// OnboardingView.swift
//
// First-launch sheet. Two paths to identity:
//
//   1. Sign in with Apple (preferred) — pulls the user's first name
//      automatically and stamps a stable userID we can use as the
//      cloud-sync row key. Honored at runtime only on builds signed
//      with a real Apple Developer ID (paid program); ad-hoc builds
//      surface an error and fall back gracefully.
//   2. Manual name entry — first name required, rock name optional.
//      Generates its own sync UUID locally; cloud sync stays opt-in.

import SwiftUI
import AuthenticationServices

struct OnboardingView: View {
    @EnvironmentObject var store: BoulderStore
    @Environment(\.dismiss) private var dismiss

    @State private var firstName: String = ""
    @State private var rockName: String = ""
    @State private var siwaError: String? = nil
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

            VStack(spacing: 18) {
                Text("🪨")
                    .font(.system(size: 56))
                    .shadow(color: Color(hex: 0xC147FF).opacity(0.5), radius: 18)

                VStack(spacing: 4) {
                    Text("Welcome to Boulder")
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    Text("A pet rock for your focus.")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.55))
                }

                // Sign in with Apple — provides identity + cloud sync.
                SignInWithAppleButton(.signIn,
                    onRequest: { req in
                        req.requestedScopes = [.fullName]
                    },
                    onCompletion: handleSIWA
                )
                .signInWithAppleButtonStyle(.white)
                .frame(width: 320, height: 44)
                .cornerRadius(22)

                if let err = siwaError {
                    Text(err)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.45))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
                }

                HStack(spacing: 10) {
                    Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
                    Text("OR")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white.opacity(0.35))
                        .tracking(0.6)
                    Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
                }
                .frame(maxWidth: 320)

                VStack(alignment: .leading, spacing: 12) {
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
                .frame(maxWidth: 320)

                Button(action: saveManual) {
                    Text("Start growing")
                        .font(.system(size: 15, weight: .heavy))
                        .tracking(0.4)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
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
                .frame(maxWidth: 320)

                Text("You can change these anytime in Settings.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.35))
            }
            .padding(32)
        }
        .frame(width: 440, height: 620)
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

    private func handleSIWA(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let error):
            // Common case on ad-hoc builds: SIWA isn't actually
            // granted at runtime → error 1000 ("unknown"). Tell the
            // user to use the manual form and don't make a fuss.
            let nsErr = error as NSError
            if nsErr.code == ASAuthorizationError.canceled.rawValue {
                siwaError = nil
            } else {
                // Quiet, non-alarming copy. Most users hitting this
                // are on the free ad-hoc build where Apple's runtime
                // entitlement check fails. The fallback form is right
                // below — no reason to make it look like an error.
                siwaError = "Sign in with the form below to keep going."
            }
            return
        case .success(let auth):
            guard let cred = auth.credential as? ASAuthorizationAppleIDCredential else {
                siwaError = "Unexpected credential type."
                return
            }
            let userID = cred.user
            let given = cred.fullName?.givenName?.trimmingCharacters(in: .whitespacesAndNewlines)
            store.completeAppleSignIn(userID: userID, firstName: given)
            // If Apple didn't return a name (returning user), fall
            // back to whatever the user typed in the form.
            if store.model.userFirstName == nil || store.model.userFirstName?.isEmpty == true {
                if !trimmedName.isEmpty {
                    store.setIdentity(firstName: trimmedName, rockName: rockName)
                }
            }
            siwaError = nil
            dismiss()
        }
    }

    private func saveManual() {
        let name = trimmedName
        guard !name.isEmpty else { return }
        store.setIdentity(firstName: name, rockName: rockName.trimmingCharacters(in: .whitespacesAndNewlines))
        dismiss()
    }
}
