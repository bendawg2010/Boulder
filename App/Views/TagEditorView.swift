// TagEditorView.swift
//
// Modal form for creating or editing a FocusTag. The user picks an
// emoji, a name, a description, and slides a hue slider to recolor
// the tag's palette in real time. Used from the Settings → Tags
// tab and from the popover's "+ tag" button.

import SwiftUI

struct TagEditorView: View {
    @EnvironmentObject var store: BoulderStore
    @Environment(\.dismiss) var dismiss

    /// Edits an existing tag if non-nil, else creates a new one.
    let existing: FocusTag?

    @State private var name: String
    @State private var emoji: String
    @State private var blurb: String
    @State private var hue: Double

    init(existing: FocusTag? = nil) {
        self.existing = existing
        _name  = State(initialValue: existing?.name  ?? "")
        _emoji = State(initialValue: existing?.emoji ?? "🪨")
        _blurb = State(initialValue: existing?.blurb ?? "")
        // Default a brand-new tag to a random rock preset (not a
        // random hue) — keeps the aesthetic locked from creation.
        _hue   = State(initialValue: existing?.hue
                       ?? FocusTag.rockPresets.randomElement()!.hue)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            form
            Divider()
            footer
        }
        .frame(width: 420, height: 460)
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text(emoji.isEmpty ? "🪨" : emoji)
                .font(.system(size: 44))
            HStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(previewPalette[i])
                        .frame(width: 32, height: 16)
                }
            }
            Text(name.isEmpty ? "Untitled tag" : name)
                .font(.headline)
                .foregroundStyle(.white.opacity(name.isEmpty ? 0.4 : 0.9))
        }
        .padding(.top, 20)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
    }

    private var form: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                    .textFieldStyle(.roundedBorder)
                TextField("Emoji", text: $emoji)
                    .textFieldStyle(.roundedBorder)
            }
            Section("What does this tag mean to you?") {
                TextEditor(text: $blurb)
                    .frame(height: 70)
                    .font(.body)
            }
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Rock type")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                        ForEach(FocusTag.rockPresets) { preset in
                            rockButton(preset)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private var footer: some View {
        HStack {
            if existing != nil {
                Button("Delete", role: .destructive) {
                    if let id = existing?.id { store.deleteTag(id: id) }
                    dismiss()
                }
            }
            Spacer()
            Button("Cancel") { dismiss() }
            Button(existing == nil ? "Create" : "Save") {
                save()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(12)
    }

    /// Swatch button for one of the rock presets. Tapping snaps the
    /// tag's hue to this preset; we don't allow the user to dial in
    /// arbitrary hues, so the palette stays rock-like by construction.
    private func rockButton(_ preset: RockPreset) -> some View {
        let isSelected = abs(hue - preset.hue) < 0.0001
        return Button {
            withAnimation(.easeOut(duration: 0.15)) { hue = preset.hue }
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(preset.swatch)
                        .frame(height: 28)
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white, lineWidth: 2)
                            .frame(height: 28)
                    }
                }
                Text(preset.name)
                    .font(.caption2.weight(isSelected ? .bold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private var previewPalette: [Color] {
        FocusTag(
            id: UUID(),
            name: "preview", emoji: "", hue: hue, blurb: ""
        ).palette
    }

    private func save() {
        let trimmedName  = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmoji = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBlurb = blurb.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing {
            var updated = existing
            updated.name = trimmedName
            updated.emoji = trimmedEmoji.isEmpty ? "🪨" : trimmedEmoji
            updated.hue = hue
            updated.blurb = trimmedBlurb
            store.updateTag(updated)
        } else {
            store.addTag(FocusTag(
                name: trimmedName,
                emoji: trimmedEmoji.isEmpty ? "🪨" : trimmedEmoji,
                hue: hue,
                blurb: trimmedBlurb
            ))
        }
    }
}
