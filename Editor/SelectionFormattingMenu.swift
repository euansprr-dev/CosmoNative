// CosmoOS/Editor/SelectionFormattingMenu.swift
// The quill bar — floating formatting capsule for text selections.
// One glass capsule: B I U S̶ · Aa ▾ · ✦, with a styles panel (headings + lists)
// and an AI mode (Expand/Condense/Rephrase + custom prompt).
//
// Positioning is owned here: the host passes the selection rect (`anchor`) and
// its own bounds (`container`); the bar measures itself, clamps horizontally,
// and flips below the selection when there is no headroom above — so it can
// never be cut off by margins, rails, or container edges.

import SwiftUI

struct SelectionFormattingMenu: View {
    /// Selection rect in the host's coordinate space.
    let anchor: CGRect
    /// Host bounds the bar must stay inside.
    let container: CGSize
    var traits: SelectionFormattingTraits = .none
    var compact: Bool = false
    var darkMode: Bool = false
    let onDismiss: () -> Void
    var onAIAction: ((AIWritingAction) -> Void)? = nil
    var onCustomPrompt: ((String) -> Void)? = nil
    var onWritingAIRequest: (() -> Void)? = nil

    @State private var mode: MenuMode = .formatting
    @State private var showStylePanel = false
    @State private var showCustomPrompt = false
    @State private var customPromptText = ""
    @State private var barSize: CGSize = .zero

    private enum MenuMode {
        case formatting, ai
    }

    /// Estimated size before the first geometry pass lands.
    private var effectiveBarSize: CGSize {
        barSize == .zero ? CGSize(width: compact ? 220 : 300, height: 44) : barSize
    }

    /// Clamp into the container; flip below the selection when the bar would
    /// rise past the container's top edge (Google-Docs behavior). The clamp
    /// padding reserves room for the chrome's drop shadow — the container is
    /// usually a clipped column, and a body-only clamp slices the shadow into
    /// a hard line at the clip edge.
    private var resolvedPosition: CGPoint {
        let pad: CGFloat = CosmoMenuChrome.shadowClearance
        let gap: CGFloat = 10
        let size = effectiveBarSize
        let half = size.width / 2

        let x: CGFloat
        if container.width < size.width + pad * 2 {
            x = container.width / 2
        } else {
            x = min(max(anchor.midX, half + pad), container.width - half - pad)
        }

        let fitsAbove = anchor.minY - size.height - gap >= 0
        let y = fitsAbove
            ? anchor.minY - size.height / 2 - gap
            : anchor.maxY + size.height / 2 + gap
        return CGPoint(x: x, y: y)
    }

    /// Attached panels (styles, custom prompt) grow away from the selection.
    private var panelsGrowDownward: Bool {
        anchor.minY - effectiveBarSize.height - 10 >= 0
    }

    var body: some View {
        VStack(spacing: DS.space6) {
            if !panelsGrowDownward { attachedPanels }
            bar
                .onGeometryChange(for: CGSize.self) { proxy in
                    proxy.size
                } action: { newValue in
                    barSize = newValue
                }
            if panelsGrowDownward { attachedPanels }
        }
        .fixedSize()
        .animation(ProMotionSprings.snappy, value: mode)
        .animation(ProMotionSprings.snappy, value: showStylePanel)
        .animation(ProMotionSprings.snappy, value: showCustomPrompt)
        .position(resolvedPosition)
        .animation(ProMotionSprings.snappy, value: anchor)
    }

    // MARK: - The capsule

    private var bar: some View {
        HStack(spacing: 2) {
            if mode == .formatting {
                formattingContent
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                aiContent
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .padding(.horizontal, DS.space8)
        .frame(height: 44)
        .cosmoMenuChrome(cornerRadius: 22, darkMode: darkMode)
    }

    @ViewBuilder
    private var attachedPanels: some View {
        if showStylePanel && mode == .formatting {
            stylePanel
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: panelsGrowDownward ? .top : .bottom)))
        }
        if showCustomPrompt && mode == .ai {
            customPromptField
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: panelsGrowDownward ? .top : .bottom)))
        }
    }

    // MARK: - Formatting mode

    @ViewBuilder
    private var formattingContent: some View {
        QuillGlyphButton(
            icon: "bold", isActive: traits.isBold, hint: "Bold (⌘B)"
        ) { EditorCommandBus.shared.toggleFormatting(.bold) }
        QuillGlyphButton(
            icon: "italic", isActive: traits.isItalic, hint: "Italic (⌘I)"
        ) { EditorCommandBus.shared.toggleFormatting(.italic) }
        QuillGlyphButton(
            icon: "underline", isActive: traits.isUnderline, hint: "Underline (⌘U)"
        ) { EditorCommandBus.shared.toggleFormatting(.underline) }
        if !compact {
            QuillGlyphButton(
                icon: "strikethrough", isActive: traits.isStrikethrough, hint: "Strikethrough"
            ) { EditorCommandBus.shared.toggleFormatting(.strikethrough) }
        }

        quillDividerDot

        styleChip

        if onWritingAIRequest != nil || onAIAction != nil {
            quillDividerDot
            QuillGlyphButton(
                icon: "sparkles", isActive: mode == .ai, tint: DS.accent, hint: "Writing AI"
            ) {
                if let onWritingAIRequest {
                    onWritingAIRequest()
                } else {
                    showStylePanel = false
                    mode = .ai
                }
            }
        }
    }

    /// The Aa chip — names the current block style and opens the styles panel.
    private var styleChip: some View {
        QuillChipButton(
            label: currentStyleLabel,
            isActive: showStylePanel || traits.headingLevel != nil || traits.listKind != .none,
            hint: "Text style"
        ) {
            showStylePanel.toggle()
        }
    }

    private var currentStyleLabel: String {
        if let level = traits.headingLevel { return "H\(level)" }
        switch traits.listKind {
        case .bullet: return "• List"
        case .numbered: return "1. List"
        case .checklist: return "☑ List"
        case .quote, .none: return "Aa"
        }
    }

    // MARK: - Styles panel (headings + lists)

    private var stylePanel: some View {
        VStack(alignment: .leading, spacing: 2) {
            styleRow("Body", active: traits.headingLevel == nil && traits.listKind == .none) {
                // Re-applying the current heading level toggles it off.
                if let level = traits.headingLevel {
                    EditorCommandBus.shared.toggleFormatting(headingType(for: level))
                }
            }
            styleRow("Heading 1", active: traits.headingLevel == 1, glyphFont: DS.headline) {
                EditorCommandBus.shared.toggleFormatting(.heading1)
            }
            styleRow("Heading 2", active: traits.headingLevel == 2, glyphFont: DS.callout.weight(.semibold)) {
                EditorCommandBus.shared.toggleFormatting(.heading2)
            }
            styleRow("Heading 3", active: traits.headingLevel == 3, glyphFont: DS.subheadline.weight(.medium)) {
                EditorCommandBus.shared.toggleFormatting(.heading3)
            }

            Rectangle()
                .fill(DS.glassBorder)
                .frame(height: 0.5)
                .padding(.vertical, DS.space4)

            listRow("Bulleted list", icon: "list.bullet", active: traits.listKind == .bullet) {
                EditorCommandBus.shared.toggleFormatting(.bulletList)
            }
            listRow("Numbered list", icon: "list.number", active: traits.listKind == .numbered) {
                EditorCommandBus.shared.toggleFormatting(.numberedList)
            }
            listRow("Checklist", icon: "checklist", active: traits.listKind == .checklist) {
                EditorCommandBus.shared.toggleFormatting(.checklist)
            }
        }
        .padding(DS.space6)
        .frame(width: 190)
        .cosmoMenuChrome(cornerRadius: 14, darkMode: darkMode)
    }

    private func headingType(for level: Int) -> FormattingType {
        switch level {
        case 1: return .heading1
        case 2: return .heading2
        default: return .heading3
        }
    }

    private func styleRow(
        _ label: String,
        active: Bool,
        glyphFont: Font = DS.callout,
        action: @escaping () -> Void
    ) -> some View {
        QuillPanelRow(active: active) {
            action()
            showStylePanel = false
        } content: {
            Text(label)
                .font(glyphFont)
        }
    }

    private func listRow(
        _ label: String,
        icon: String,
        active: Bool,
        action: @escaping () -> Void
    ) -> some View {
        QuillPanelRow(active: active) {
            action()
            showStylePanel = false
        } content: {
            HStack(spacing: DS.space8) {
                Image(systemName: icon)
                    .font(DS.caption)
                    .frame(width: 16)
                Text(label)
                    .font(DS.callout)
            }
        }
    }

    // MARK: - AI mode

    @ViewBuilder
    private var aiContent: some View {
        QuillGlyphButton(icon: "chevron.left", hint: "Back to formatting") {
            showCustomPrompt = false
            mode = .formatting
        }

        quillDividerDot

        QuillChipButton(label: "Expand", icon: "arrow.up.left.and.arrow.down.right", hint: "Expand selection") {
            onAIAction?(.expand)
        }
        QuillChipButton(label: "Condense", icon: "arrow.down.right.and.arrow.up.left", hint: "Condense selection") {
            onAIAction?(.condense)
        }
        QuillChipButton(label: "Rephrase", icon: "arrow.triangle.2.circlepath", hint: "Rephrase selection") {
            onAIAction?(.rephrase)
        }

        if onCustomPrompt != nil {
            quillDividerDot
            QuillGlyphButton(icon: "ellipsis", isActive: showCustomPrompt, hint: "Custom instruction") {
                showCustomPrompt.toggle()
            }
        }
    }

    // MARK: - Custom prompt

    private var customPromptField: some View {
        HStack(spacing: DS.space6) {
            Image(systemName: "text.bubble")
                .font(DS.caption)
                .foregroundStyle(DS.accent.opacity(0.7))

            TextField("Custom instruction…", text: $customPromptText)
                .textFieldStyle(.plain)
                .font(DS.callout)
                .foregroundStyle(DS.text)
                .onSubmit { submitCustomPrompt() }

            Button(action: submitCustomPrompt) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(DS.headline)
                    .foregroundStyle(DS.accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Send custom instruction")
        }
        .padding(.horizontal, DS.space10)
        .padding(.vertical, DS.space8)
        .frame(width: 260)
        .cosmoMenuChrome(cornerRadius: 14, darkMode: darkMode)
    }

    private func submitCustomPrompt() {
        let text = customPromptText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        onCustomPrompt?(text)
        customPromptText = ""
        showCustomPrompt = false
    }

    private var quillDividerDot: some View {
        Circle()
            .fill(DS.glassBorder)
            .frame(width: 3, height: 3)
            .padding(.horizontal, DS.space4)
    }
}

// MARK: - Glyph button (icon, circle wash)

private struct QuillGlyphButton: View {
    let icon: String
    var isActive: Bool = false
    var tint: Color = DS.textSecondary
    let hint: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(DS.buttonText.weight(.semibold))
                .foregroundStyle(isActive ? DS.accent : (isHovered ? DS.text : tint))
                .frame(width: 30, height: 30)
                .background(
                    isActive ? AnyShapeStyle(DS.accentSoft) :
                        (isHovered ? AnyShapeStyle(DS.glassCardFill) : AnyShapeStyle(.clear)),
                    in: Circle()
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
        .help(hint)
        .accessibilityLabel(hint)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

// MARK: - Chip button (label pill — the Aa chip and AI actions)

private struct QuillChipButton: View {
    let label: String
    var icon: String? = nil
    var isActive: Bool = false
    let hint: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.space4) {
                if let icon {
                    Image(systemName: icon)
                        .font(DS.caption2.weight(.medium))
                }
                Text(label)
                    .font(DS.caption.weight(.medium))
            }
            .foregroundStyle(isActive ? DS.accent : (isHovered ? DS.text : DS.textSecondary))
            .padding(.horizontal, DS.space8)
            .frame(height: 30)
            .background(
                isActive ? AnyShapeStyle(DS.accentSoft) :
                    (isHovered ? AnyShapeStyle(DS.glassCardFill) : AnyShapeStyle(.clear)),
                in: Capsule(style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
        .help(hint)
        .accessibilityLabel(hint)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

// MARK: - Panel row (styles panel)

private struct QuillPanelRow<Content: View>: View {
    let active: Bool
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack {
                content()
                    .foregroundStyle(active ? DS.accent : DS.text)
                Spacer(minLength: DS.space8)
                if active {
                    Image(systemName: "checkmark")
                        .font(DS.caption2.weight(.semibold))
                        .foregroundStyle(DS.accent)
                }
            }
            .padding(.horizontal, DS.space8)
            .frame(height: 28)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isHovered ? AnyShapeStyle(DS.glassCardFill) : AnyShapeStyle(.clear),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}
