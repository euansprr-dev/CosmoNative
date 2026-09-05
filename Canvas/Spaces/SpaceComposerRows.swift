// CosmoOS/Canvas/Spaces/SpaceComposerRows.swift
// The composer's rows: identity (mark well + name), the emoji picker
// popover, the accent swatches (lifted from the workbench composer's tint
// row), and the parent picker menu. Plus the one cell chrome every
// selectable tile/chip in the sheet wears.

import SwiftUI
import AppKit

// MARK: - Cell chrome

/// The glyph-cell idiom from the workbench composer: warm card fill at rest,
/// input-focus fill on hover, accent-soft wash + tint hairline when selected.
struct SpaceComposerCellChrome: ViewModifier {
    let isSelected: Bool
    let isHovered: Bool
    let tint: Color
    let cornerRadius: CGFloat

    private var fill: Color {
        if isSelected { return DS.accentSoft }
        return isHovered ? DS.glassInputFillFocused : DS.glassCardFill
    }

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(isSelected ? tint.opacity(0.5) : DS.glassBorder, lineWidth: 0.5)
            )
            .animation(ProMotionSprings.hover, value: isHovered)
            .animation(ProMotionSprings.snappy, value: isSelected)
    }
}

extension View {
    func spaceComposerCell(
        isSelected: Bool,
        isHovered: Bool,
        tint: Color = DS.accent,
        cornerRadius: CGFloat = 8
    ) -> some View {
        modifier(SpaceComposerCellChrome(
            isSelected: isSelected,
            isHovered: isHovered,
            tint: tint,
            cornerRadius: cornerRadius
        ))
    }
}

// MARK: - Identity row

/// Mark well + name field. The hero of the sheet.
struct SpaceIdentityRow: View {
    @Bindable var model: SpaceComposerModel
    var nameFocused: FocusState<Bool>.Binding
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            SpaceEmojiWell(model: model)
            TextField("Space name", text: $model.draft.name)
                .textFieldStyle(.plain)
                .font(DS.callout)
                .foregroundStyle(DS.text)
                .focused(nameFocused)
                .onSubmit(onSubmit)
                .padding(.horizontal, 12)
                .frame(height: 44)
                .dsGlassInput(isFocused: nameFocused.wrappedValue, cornerRadius: 12)
                .accessibilityLabel("Space name")
        }
    }
}

/// The 44pt mark button; opens the emoji picker popover.
struct SpaceEmojiWell: View {
    @Bindable var model: SpaceComposerModel
    @State private var isHovered = false

    var body: some View {
        Button {
            model.isEmojiPickerPresented.toggle()
        } label: {
            SpaceIdentityMarkPreview(
                emoji: model.identityPreviewEmoji,
                kind: model.draft.kind,
                accent: model.accentColor,
                size: 36
            )
            .frame(width: 44, height: 44)
            .dsGlassInput(isFocused: isHovered || model.isEmojiPickerPresented, cornerRadius: 12)
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .scaleEffect(isHovered ? 1.02 : 1)
        .animation(ProMotionSprings.hover, value: isHovered)
        .help("Change the mark")
        .accessibilityLabel("Identity mark")
        .accessibilityValue(model.identityPreviewEmoji ?? model.draft.kind.title)
        .popover(isPresented: $model.isEmojiPickerPresented, arrowEdge: .bottom) {
            SpaceEmojiPicker(model: model)
        }
    }
}

// MARK: - Emoji picker

/// Suggestion chips, a one-character field (validated with the shared
/// `CollectionEmoji.isEmoji`), the system palette, and a way back to the
/// automatic mark.
struct SpaceEmojiPicker: View {
    @Bindable var model: SpaceComposerModel
    @State private var typed = ""
    @FocusState private var typedFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SpaceEmojiSuggestionGrid(model: model)
            HStack(spacing: 10) {
                typedField
                Button("System picker") {
                    typedFocused = true
                    NSApp.orderFrontCharacterPalette(nil)
                }
                .buttonStyle(.plain)
                .font(DS.footnote.weight(.medium))
                .foregroundStyle(DS.accent)
                .help("Open the macOS emoji palette")
                Spacer(minLength: 0)
                Button(model.isCreate ? "Automatic" : "Use none") { model.setEmoji(nil) }
                    .buttonStyle(.plain)
                    .font(DS.footnote)
                    .foregroundStyle(DS.textSecondary)
                    .help(model.isCreate ? "Let the name or kind choose the mark" : "Show the kind's glyph instead")
            }
        }
        .padding(16)
        .frame(width: 280)
    }

    private var typedField: some View {
        TextField("", text: $typed, prompt: Text("…").foregroundStyle(DS.textMuted))
            .textFieldStyle(.plain)
            .font(DS.callout)
            .multilineTextAlignment(.center)
            .focused($typedFocused)
            .frame(width: 44, height: 32)
            .dsGlassInput(isFocused: typedFocused, cornerRadius: 8)
            .onChange(of: typed) { _, value in acceptTyped(value) }
            .help("Type or paste one emoji")
            .accessibilityLabel("Type an emoji")
    }

    /// The last character wins when it is an emoji; anything else is dropped.
    private func acceptTyped(_ value: String) {
        guard let last = value.last else { return }
        if CollectionEmoji.isEmoji(last) { model.setEmoji(String(last)) }
        typed = ""
    }
}

struct SpaceEmojiSuggestionGrid: View {
    @Bindable var model: SpaceComposerModel
    private static let columns = Array(repeating: GridItem(.fixed(36), spacing: 6), count: 6)

    var body: some View {
        LazyVGrid(columns: Self.columns, alignment: .leading, spacing: 6) {
            ForEach(model.emojiSuggestions, id: \.self) { emoji in
                SpaceEmojiChip(emoji: emoji, isSelected: model.draft.emoji == emoji) {
                    model.setEmoji(emoji)
                }
            }
        }
    }
}

struct SpaceEmojiChip: View {
    let emoji: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(emoji)
                .font(DS.title3)
                .frame(width: 36, height: 32)
                .spaceComposerCell(isSelected: isSelected, isHovered: isHovered, cornerRadius: 8)
                .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel("Mark \(emoji)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Accent swatches

/// Eight palette swatches, selected ring — the workbench composer's tint row.
struct AccentSwatchRow: View {
    @Binding var selectedHex: String

    /// Names in `ThinkspaceManager.accentColorPalette` order (tooltips + a11y).
    static let paletteNames = ["Moss", "Sky", "Clay", "Violet", "Ochre", "Teal", "Rose", "Cobalt"]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(ThinkspaceManager.accentColorPalette.prefix(8).enumerated()), id: \.element) { index, hex in
                AccentSwatch(
                    hex: hex,
                    name: Self.paletteNames.indices.contains(index) ? Self.paletteNames[index] : "Accent \(index + 1)",
                    isSelected: Self.matches(selectedHex, hex)
                ) {
                    withAnimation(ProMotionSprings.snappy) { selectedHex = hex }
                }
            }
            Spacer(minLength: 0)
        }
    }

    static func matches(_ lhs: String, _ rhs: String) -> Bool {
        normalize(lhs) == normalize(rhs)
    }

    private static func normalize(_ hex: String) -> String {
        hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted).uppercased()
    }
}

struct AccentSwatch: View {
    let hex: String
    let name: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color(hex: hex))
                .frame(width: 22, height: 22)
                .overlay(Circle().strokeBorder(.white.opacity(isSelected ? 0.9 : 0), lineWidth: 2))
                .overlay(Circle().strokeBorder(DS.glassBorder, lineWidth: 0.5))
                .scaleEffect(isSelected ? 1.12 : (isHovered ? 1.06 : 1))
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(ProMotionSprings.hover, value: isHovered)
        .help(name)
        .accessibilityLabel("\(name) accent")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Parent picker

/// "Inside · Top level" / "Inside · <parent>" — a menu over the sidebar
/// tree, indented by depth, checkmark on the current choice.
struct SpaceParentPicker: View {
    @Bindable var model: SpaceComposerModel
    @State private var isHovered = false

    var body: some View {
        Menu {
            parentToggle(id: nil, title: "Top level", depth: 0)
            if !model.parentOptions.isEmpty { Divider() }
            ForEach(model.parentOptions) { option in
                parentToggle(
                    id: option.id,
                    title: option.thinkspace.identityLabel,
                    emoji: option.thinkspace.identityEmoji,
                    depth: option.depth
                )
            }
        } label: {
            menuLabel
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { isHovered = $0 }
        .help("Where the space lives in the sidebar")
        .accessibilityLabel("Parent space")
        .accessibilityValue(model.parentLabel)
    }

    private var menuLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.turn.down.right")
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
            Text(model.parentLabel)
                .font(DS.footnote.weight(.medium))
                .foregroundStyle(DS.textSecondary)
                .lineLimit(1)
            Image(systemName: "chevron.up.chevron.down")
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(Capsule().fill(isHovered ? DS.glassInputFillFocused : DS.glassInputFill))
        .overlay(Capsule().strokeBorder(DS.glassBorder, lineWidth: 0.5))
        .animation(ProMotionSprings.hover, value: isHovered)
    }

    private func parentToggle(id: String?, title: String, emoji: String? = nil, depth: Int) -> some View {
        let indent = String(repeating: "    ", count: depth)
        let label = emoji.map { "\($0) \(title)" } ?? title
        return Toggle(indent + label, isOn: Binding(
            get: { model.draft.parentThinkspaceId == id },
            set: { isOn in if isOn { model.draft.parentThinkspaceId = id } }
        ))
    }
}
