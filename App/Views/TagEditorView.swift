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
        _hue   = State(initialValue: existing?.hue   ?? Double.random(in: 0...1))
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
                VStack(alignment: .leading, spacing: 6) {
                    Text("Color")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 0) {
                        ForEach(0..<24, id: \.self) { i in
                            Rectangle()
                                .fill(Color(hue: Double(i) / 24, saturation: 0.7, brightness: 0.85))
                                .frame(height: 14)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .opacity(0.7)
                    Slider(value: $hue, in: 0...1)
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
