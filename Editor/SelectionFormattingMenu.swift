// CosmoOS/Editor/SelectionFormattingMenu.swift
// The quill bar — floating formatting capsule for text selections.
// One glass capsule: B I U S̶ · A• Aa ▾ · ✦, with a colour panel (ink +
// highlight + link), a styles panel (headings + lists) and an AI mode
// (Expand/Condense/Rephrase + custom prompt).
//
// Positioning is owned here: the host passes the selection rect (`anchor`) and
// its own bounds (`container`); the bar measures itself, clamps horizontally,
// and flips below the selection when there is no headroom above — so it can
// never be cut off by margins, rails, or container edges.

import SwiftUI

/// Ink / highlight / link carried by the whole selection (or the caret's
/// typing attributes). Nil on the menu = the host does not know yet — the
/// swatches then show no selection ring and the glyph dot stays muted.
struct SelectionInlineColorState: Equatable {
    var inkID: String? = nil
    var highlightID: String? = nil
    var href: String? = nil
}

struct SelectionFormattingMenu: View {
    /// Selection rect in the host's coordinate space.
    let anchor: CGRect
    /// Host bounds the bar must stay inside.
    let container: CGSize
    var traits: SelectionFormattingTraits = .none
    var inlineColor: SelectionInlineColorState? = nil
    var compact: Bool = false
    var darkMode: Bool = false
    let onDismiss: () -> Void
    var onAIAction: ((AIWritingAction) -> Void)? = nil
    var onCustomPrompt: ((String) -> Void)? = nil
    var onWritingAIRequest: (() -> Void)? = nil

    @State private var mode: MenuMode = .formatting
    @State private var showStylePanel = false
    @State private var showColorPanel = false
    @State private var showCustomPrompt = false
    @State private var customPromptText = ""
    @State private var linkText = ""
    @State private var barSize: CGSize = .zero
    @FocusState private var linkFieldFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        .animation(reduceMotion ? nil : ProMotionSprings.snappy, value: showColorPanel)
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
        if showColorPanel && mode == .formatting {
            colorPanel
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

        colorButton
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
                    showColorPanel = false
                    mode = .ai
                }
            }
        }
    }

    /// The colour control — a `textformat` glyph over a dot in the current
    /// ink (muted while the host has not reported the selection's colour).
    private var colorButton: some View {
        QuillColorButton(
            dotColor: currentInkDot,
            isActive: showColorPanel || inlineColor?.inkID != nil || inlineColor?.highlightID != nil
        ) {
            showStylePanel = false
            if !showColorPanel { linkText = inlineColor?.href ?? "" }
            showColorPanel.toggle()
        }
    }

    private var currentInkDot: Color {
        guard let inkID = inlineColor?.inkID, RichInlineColor.isKnownTone(inkID) else {
            return DS.textMuted
        }
        return NoteInkPalette.tone(inkID).ink(darkMode: darkMode)
    }

    /// The Aa chip — names the current block style and opens the styles panel.
    private var styleChip: some View {
        QuillChipButton(
            label: currentStyleLabel,
            isActive: showStylePanel || traits.headingLevel != nil || traits.listKind != .none,
            hint: "Text style"
        ) {
            showColorPanel = false
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
            // Specimen ladder mirrors the document's real ladder order —
            // H3 rendered BELOW body size in the old picker.
            styleRow("Heading 1", active: traits.headingLevel == 1, glyphFont: DS.title2) {
                EditorCommandBus.shared.toggleFormatting(.heading1)
            }
            styleRow("Heading 2", active: traits.headingLevel == 2, glyphFont: DS.headline) {
                EditorCommandBus.shared.toggleFormatting(.heading2)
            }
            styleRow("Heading 3", active: traits.headingLevel == 3, glyphFont: DS.rowTitle) {
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

    // MARK: - Colour panel (ink + highlight + link)

    /// Attached exactly like the styles panel: same chrome, same spring,
    /// no popover window (one would take first responder from the text
    /// view and drop the selection the colour is meant for).
    private var colorPanel: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: DS.space8) {
                inkRow
                highlightRow
                Rectangle()
                    .fill(DS.glassBorder)
                    .frame(height: 0.5)
                linkRow
            }
            .padding(DS.space8)
            QuillKeycapFooter(darkMode: darkMode)
        }
        .frame(width: 280)
        .cosmoMenuChrome(cornerRadius: 14, darkMode: darkMode)
        .onChange(of: inlineColor?.href) { _, href in
            if !linkFieldFocused { linkText = href ?? "" }
        }
    }

    private var inkRow: some View {
        HStack(spacing: DS.space6) {
            swatchRowLabel("Ink")
            ForEach(NoteInkPalette.tones) { tone in
                QuillSwatch(
                    outline: .circle,
                    fill: tone.ink(darkMode: darkMode),
                    isSelected: inlineColor?.inkID == tone.id,
                    hint: "\(tone.label) ink"
                ) { EditorCommandBus.shared.applyInk(tone.id) }
            }
            QuillSwatch(
                outline: .circle,
                fill: DS.documentText,
                isSelected: inlineColor != nil && inlineColor?.inkID == nil,
                hint: "Default ink"
            ) { EditorCommandBus.shared.applyInk(nil) }
        }
    }

    private var highlightRow: some View {
        HStack(spacing: DS.space6) {
            swatchRowLabel("Highlight")
            ForEach(NoteInkPalette.tones) { tone in
                QuillSwatch(
                    outline: .square,
                    fill: tone.ink(darkMode: darkMode).opacity(0.28),
                    isSelected: inlineColor?.highlightID == tone.id,
                    hint: "\(tone.label) highlight"
                ) { EditorCommandBus.shared.applyHighlight(tone.id) }
            }
            QuillSwatch(
                outline: .square,
                fill: .clear,
                hairlineOnly: true,
                isSelected: inlineColor != nil && inlineColor?.highlightID == nil,
                hint: "No highlight"
            ) { EditorCommandBus.shared.applyHighlight(nil) }
        }
    }

    /// Small caps from a sentence-case source (`.smallCaps()` on UPPERCASE
    /// is a no-op); menus carry `textMuted` — the one small-caps dialect.
    private func swatchRowLabel(_ label: String) -> some View {
        Text(label)
            .font(DS.smallCaps)
            .tracking(DS.smallCapsTracking)
            .foregroundStyle(DS.textMuted)
            .frame(width: 52, alignment: .leading)
    }

    /// One field, one verb: the chip reads "Apply" while the field holds a
    /// URL and "Remove" when it is empty — Return does whatever the chip says.
    private var linkRow: some View {
        HStack(spacing: DS.space6) {
            swatchRowLabel("Link")
            linkField
            QuillChipButton(
                label: linkText.isEmpty ? "Remove" : "Apply",
                isActive: !linkText.isEmpty,
                hint: linkText.isEmpty ? "Remove link" : "Apply link (↩)"
            ) { commitLink() }
            .frame(width: 60)
        }
    }

    private var linkField: some View {
        HStack(spacing: DS.space4) {
            Image(systemName: "link")
                .font(DS.caption2.weight(.medium))
                .foregroundStyle(linkFieldFocused ? DS.accent : DS.textMuted)
            TextField("Paste a link", text: $linkText)
                .textFieldStyle(.plain)
                .font(DS.callout)
                .foregroundStyle(DS.text)
                .focused($linkFieldFocused)
                .onSubmit { commitLink() }
                .onKeyPress(.escape) {
                    showColorPanel = false
                    return .handled
                }
                .accessibilityLabel("Link URL")
        }
        .padding(.horizontal, DS.space8)
        .frame(height: 26)
        .dsGlassInput(isFocused: linkFieldFocused, cornerRadius: 8)
        .animation(ProMotionSprings.hover, value: linkFieldFocused)
    }

    private func commitLink() {
        EditorCommandBus.shared.applyLink(QuillLinkField.normalized(linkText))
        showColorPanel = false
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

// MARK: - Colour button (glyph over a tone dot)

/// `textformat` over a 6pt dot that wears the selection's ink — the
/// Craft/Pages register. Visual 30pt circle like its siblings; the hit
/// frame is the full 44pt target, with negative padding so the bar's 2pt
/// glyph rhythm stays intact (hit slop, not layout).
private struct QuillColorButton: View {
    let dotColor: Color
    let isActive: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: "textformat")
                    .font(DS.buttonText.weight(.semibold))
                Circle()
                    .fill(dotColor)
                    .frame(width: 6, height: 6)
            }
            .foregroundStyle(isActive ? DS.accent : (isHovered ? DS.text : DS.textSecondary))
            .frame(width: 30, height: 30)
            .background(
                isActive ? AnyShapeStyle(DS.accentSoft) :
                    (isHovered ? AnyShapeStyle(DS.glassCardFill) : AnyShapeStyle(.clear)),
                in: Circle()
            )
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .padding(.horizontal, -5)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
        .help("Text colour")
        .accessibilityLabel("Text colour")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

// MARK: - Swatch (ink circle / highlight square)

/// 18pt swatch with a concentric accent ring when selected (1.5pt, 2pt
/// outside the swatch). Hover is a 1.04 whisper — never ≥ 1.05.
private struct QuillSwatch: View {
    enum Outline { case circle, square }

    let outline: Outline
    let fill: Color
    var hairlineOnly = false
    let isSelected: Bool
    let hint: String
    let action: () -> Void

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let size: CGFloat = 18
    private static let ringGap: CGFloat = 2
    private static let ringWidth: CGFloat = 1.5

    var body: some View {
        Button(action: action) {
            ZStack {
                swatch
                ring
            }
            .frame(width: 24, height: 24)
            .scaleEffect(isHovered && !reduceMotion ? 1.04 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(ProMotionSprings.snappy) { isHovered = hovering }
        }
        .help(hint)
        .accessibilityLabel(hint)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var swatch: some View {
        swatchShape(cornerRadius: 5)
            .fill(fill)
            .overlay(
                swatchShape(cornerRadius: 5)
                    .stroke(hairlineOnly ? DS.glassBorder : DS.glassBorder.opacity(0.35), lineWidth: 1)
            )
            .frame(width: Self.size, height: Self.size)
    }

    /// Ring centre-line sits gap + half the stroke outside the swatch; the
    /// square's radius grows by the same amount so the corners stay concentric.
    private var ring: some View {
        let outset = Self.ringGap + Self.ringWidth / 2
        return swatchShape(cornerRadius: 5 + outset)
            .stroke(DS.accent, lineWidth: Self.ringWidth)
            .frame(width: Self.size + outset * 2, height: Self.size + outset * 2)
            .opacity(isSelected ? 1 : 0)
            .animation(ProMotionSprings.snappy, value: isSelected)
    }

    private func swatchShape(cornerRadius: CGFloat) -> AnyShape {
        switch outline {
        case .circle: return AnyShape(Circle())
        case .square: return AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}

// MARK: - Link normalisation

enum QuillLinkField {
    /// "example.com" → "https://example.com"; schemes and mailto pass
    /// through; blank → nil (remove the link).
    static func normalized(_ raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if text.contains("://") || text.lowercased().hasPrefix("mailto:") { return text }
        return "https://" + text
    }
}

// MARK: - Keycap footer (the CosmoKeyboardFooter dialect, panel-specific hints)

private struct QuillKeycapFooter: View {
    var darkMode: Bool = false

    private var ink: Color { darkMode ? Color.white.opacity(0.5) : DS.textMuted }

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(darkMode ? Color.white.opacity(0.06) : DS.sepiaBorder.opacity(0.7))
                .frame(height: 1)
            HStack {
                Text("⌘⇧H Highlight")
                Spacer()
                Text("↩ Apply link")
                Text("⎋ Close")
            }
            .font(DS.keycap)
            .foregroundStyle(ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(darkMode ? Color.white.opacity(0.05) : DS.glassInputFill.opacity(0.24))
        }
    }
}
