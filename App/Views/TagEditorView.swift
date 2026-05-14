// TagEditorView.swift
//
// Modal form for creating or editing a FocusTag. The user picks an
// emoji, a name, a description, and selects a rock preset to recolor
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
    @State private var hoveredPreset: String? = nil

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
            Divider().overlay(Color.white.opacity(0.06))
            form
            Divider().overlay(Color.white.opacity(0.06))
            footer
        }
        .frame(width: 440, height: 520)
    }

    /// Premium header: large emoji, name, and a smooth 20-cell
    /// palette stripe that previews the rock's full tonal range.
    private var header: some View {
        VStack(spacing: 10) {
            Text(emoji.isEmpty ? "🪨" : emoji)
                .font(.system(size: 52))
                .shadow(color: selectedPreset.swatch.opacity(0.5), radius: 14)
                .animation(.easeOut(duration: 0.25), value: hue)

            Text(name.isEmpty ? "Untitled tag" : name)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white.opacity(name.isEmpty ? 0.4 : 0.95))
                .tracking(0.2)

            // Palette stripe: 20 shades stitched into one continuous
            // gradient bar, framed in a subtle capsule.
            HStack(spacing: 0) {
                ForEach(0..<previewPalette.count, id: \.self) { i in
                    Rectangle()
                        .fill(previewPalette[i])
                }
            }
            .frame(width: 220, height: 14)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(Color.white.opacity(0.10), lineWidth: 0.8)
            )
            .shadow(color: selectedPreset.swatch.opacity(0.35), radius: 8, y: 2)
            .animation(.easeOut(duration: 0.25), value: hue)
        }
        .padding(.top, 22)
        .padding(.bottom, 18)
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
                    .frame(height: 60)
                    .font(.body)
            }
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Rock type")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .tracking(0.3)
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4),
                        spacing: 12
                    ) {
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
        HStack(spacing: 10) {
            if existing != nil {
                Button(role: .destructive) {
                    if let id = existing?.id { store.deleteTag(id: id) }
                    dismiss()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text("Delete")
                            .font(.callout.weight(.semibold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(hex: 0xFF6B6B).opacity(0.18))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color(hex: 0xFF6B6B).opacity(0.55), lineWidth: 1)
                            )
                    )
                    .foregroundStyle(Color(hex: 0xFF6B6B))
                }
                .buttonStyle(.plain)
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
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    /// Delightful rock preset button: hover scale, soft glow, and a
    /// brand-tinted ring when selected.
    private func rockButton(_ preset: RockPreset) -> some View {
        let isSelected = abs(hue - preset.hue) < 0.0001
        let isHovered  = hoveredPreset == preset.name
        return Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                hue = preset.hue
            }
        } label: {
            VStack(spacing: 5) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(preset.swatch)
                        .frame(height: 32)
                        .shadow(
                            color: preset.swatch.opacity(isSelected ? 0.55 : 0),
                            radius: isSelected ? 8 : 0,
                            y: 1
                        )
                    if isSelected {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(Color.white.opacity(0.95), lineWidth: 1.6)
                            .frame(height: 32)
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(preset.swatch.opacity(0.6), lineWidth: 2)
                            .frame(height: 34)
                            .blur(radius: 3)
                    }
                }
                Text(preset.name)
                    .font(.caption2.weight(isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .scaleEffect(isHovered ? 1.06 : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.75), value: isHovered)
            .animation(.spring(response: 0.32, dampingFraction: 0.78), value: isSelected)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredPreset = hovering ? preset.name : nil
        }
    }

    private var selectedPreset: RockPreset {
        FocusTag.rockPresets.min(by: {
            abs($0.hue - hue) < abs($1.hue - hue)
        }) ?? FocusTag.rockPresets[0]
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
