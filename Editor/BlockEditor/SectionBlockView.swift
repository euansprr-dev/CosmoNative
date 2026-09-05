import AppKit
import SwiftUI

/// The Section block: a titled, tinted, collapsible box of blocks — the
/// "Section 1 — Change begins with clarity" container. Draws through the same
/// `ContainerBlockSurface` as Elements (one container grammar). The TITLE is
/// the block's own text row (injected by `BlockListView`, so typing, undo,
/// mentions, and Return/Backspace boundaries ride the block pipeline); the
/// body is a nested `BlockListView` over the block's children, exactly like
/// an Element body.
struct SectionBlockView<Title: View>: View {
    @Binding var block: RichBlock

    let focusCoordinator: BlockFocusCoordinator
    var fontSize: CGFloat = 17
    var fontDesign: NSFontDescriptor.SystemDesign = .default
    var lineSpacingAdjustment: CGFloat = 0
    var blockGap: CGFloat = DS.space6
    var darkMode: Bool = false
    var overrideTextColor: NSColor? = nil
    var allowSlashCommands: Bool = true
    var allowMentions: Bool = true
    var allowSelectionMenu: Bool = true
    var allowImages: Bool = true
    var typewriterMode: Bool = false
    var editorTargetID: String? = nil
    var navigationTargetID: UUID? = nil
    var onSelectionChanged: ((EditorSelectionSnapshot) -> Void)? = nil
    /// Style writes (tone, appearance, icon, collapse) — the host registers
    /// them as one undoable step without moving focus.
    var onStyleChange: (RichSectionStyle) -> Void
    /// Return on the empty last child — the host inserts a paragraph after
    /// the section and focuses it.
    var onExitBody: (() -> Void)? = nil
    var onSectionChange: (() -> Void)? = nil
    @ViewBuilder var title: () -> Title

    @State private var isHovered = false

    var body: some View {
        ContainerBlockSurface(chrome: chrome, isCollapsed: style.isCollapsed) {
            VStack(alignment: .leading, spacing: 0) {
                SectionBlockHeader(
                    style: style,
                    tone: tone,
                    darkMode: darkMode,
                    isHovered: isHovered,
                    childCount: block.children.count,
                    onToggleCollapse: toggleCollapse,
                    onStyleChange: onStyleChange,
                    title: title
                )
                if !style.isCollapsed {
                    bodyContent
                        .transition(.asymmetric(insertion: .opacity, removal: .opacity))
                }
            }
        }
        .onHover { isHovered = $0 }
        .onAppear { focusCoordinator.register(block.id) }
        .onDisappear { focusCoordinator.unregister(block.id) }
    }

    private var bodyContent: some View {
        BlockListView(
            document: childDocumentBinding,
            fontSize: fontSize,
            fontDesign: fontDesign,
            lineSpacingAdjustment: lineSpacingAdjustment,
            blockGap: blockGap,
            placeholder: "",
            darkMode: darkMode,
            overrideTextColor: overrideTextColor,
            allowSlashCommands: allowSlashCommands,
            allowMentions: allowMentions,
            allowSelectionMenu: allowSelectionMenu,
            allowImages: allowImages,
            typewriterMode: typewriterMode,
            editorTargetID: editorTargetID,
            navigationTargetID: navigationTargetID,
            focusCoordinator: focusCoordinator,
            providesNavigationOrder: false,
            onSelectionChanged: onSelectionChanged,
            onExitFinalEmptyTextRegion: exitBody,
            onDocumentChange: { _, _ in onSectionChange?() }
        )
        .padding(.horizontal, DS.space10)
        .padding(.top, DS.space4)
        .padding(.bottom, DS.space10)
    }

    private var style: RichSectionStyle {
        block.section ?? .default
    }

    /// nil = the untinted "none" tone (parchment).
    private var tone: NoteInkTone? {
        SectionToneResolver.tone(for: style)
    }

    private var chrome: ContainerBlockChrome {
        ContainerBlockChrome(
            appearance: ContainerAppearance(style.appearance),
            tone: tone,
            darkMode: darkMode,
            isHovered: isHovered
        )
    }

    private var childDocumentBinding: Binding<RichDocument> {
        Binding(
            get: { RichDocument(blocks: block.children) },
            set: { nextDocument in
                block.children = nextDocument.blocks
                onSectionChange?()
            }
        )
    }

    private func toggleCollapse() {
        var next = style
        next.isCollapsed.toggle()
        onStyleChange(next)
    }

    /// Return on the empty LAST child exits the section. Only the last child
    /// qualifies — an empty paragraph mid-body splits like any other row (the
    /// boundary command reports no block, so the focused row is the witness:
    /// `handleBoundaryCommand` focuses the emitting row first).
    private func exitBody() -> Bool {
        guard let last = block.children.last,
              focusCoordinator.focusedBlockID == last.id,
              last.isEmptyParagraph else { return false }
        if block.children.count > 1 {
            block.children.removeLast()
            onSectionChange?()
        }
        onExitBody?()
        return true
    }
}

/// Maps a section's tone id onto the palette, honouring the explicit "none"
/// (the palette's lenient lookup would otherwise hand back moss).
enum SectionToneResolver {
    static func tone(for style: RichSectionStyle) -> NoteInkTone? {
        guard style.isTinted else { return nil }
        return NoteInkPalette.tone(style.toneID)
    }
}

/// Icon seat identity: an SF Symbol name or a single emoji grapheme.
enum SectionIconGlyph {
    static func isEmoji(_ icon: String) -> Bool {
        guard icon.count == 1, let scalar = icon.unicodeScalars.first else { return false }
        if icon.unicodeScalars.contains(where: { $0.value == 0xFE0F || $0.value == 0x200D }) { return true }
        return scalar.properties.isEmojiPresentation
    }

    /// The first emoji grapheme in typed text, or nil.
    static func emoji(from text: String) -> String? {
        for character in text where isEmoji(String(character)) {
            return String(character)
        }
        return nil
    }
}

// MARK: - Header

/// Chevron · optional icon seat · title row · trailing count (collapsed
/// only) · style affordance. The title is the block's own text row.
private struct SectionBlockHeader<Title: View>: View {
    let style: RichSectionStyle
    let tone: NoteInkTone?
    let darkMode: Bool
    let isHovered: Bool
    let childCount: Int
    let onToggleCollapse: () -> Void
    let onStyleChange: (RichSectionStyle) -> Void
    @ViewBuilder let title: () -> Title

    @State private var isStylePopoverPresented = false
    @State private var chevronHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Centre-aligned: the title is a live editor row with its own text
        // insets, so a top alignment parks the chevron a line above it.
        HStack(alignment: .center, spacing: DS.space8) {
            collapseButton
            if let icon = style.icon {
                iconSeat(icon)
            }
            title()
                .frame(maxWidth: .infinity, alignment: .leading)
            if style.isCollapsed, childCount > 0 {
                collapsedCount
            }
            if style.icon == nil {
                styleDot
            }
        }
        .padding(.horizontal, DS.space10)
        .frame(minHeight: ContainerBlockChrome.headerHeight, alignment: .center)
        .popover(isPresented: $isStylePopoverPresented, arrowEdge: .bottom) {
            SectionStylePopover(style: style, darkMode: darkMode, onChange: onStyleChange)
        }
    }

    private var collapseButton: some View {
        Button(action: onToggleCollapse) {
            Image(systemName: "chevron.right")
                .font(DS.caption2.weight(.semibold))
                .foregroundStyle(chevronColor)
                .rotationEffect(.degrees(style.isCollapsed ? 0 : 90))
                .animation(reduceMotion ? nil : ProMotionSprings.snappy, value: style.isCollapsed)
                .frame(width: 18, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 1)
        .onHover { chevronHovered = $0 }
        .help(style.isCollapsed ? "Expand section" : "Collapse section")
        .accessibilityLabel(style.isCollapsed ? "Expand section" : "Collapse section")
    }

    /// The tone lives on a small tinted seat carrying the section's own mark
    /// — identity, not decoration. Hidden entirely when there is no icon.
    private func iconSeat(_ icon: String) -> some View {
        Button { isStylePopoverPresented = true } label: {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(seatFill)
                .frame(width: 20, height: 20)
                .overlay(iconGlyph(icon))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 3)
        .opacity(isHovered || isStylePopoverPresented ? 1 : 0.92)
        .help("Section style")
        .accessibilityLabel("Section style")
    }

    @ViewBuilder
    private func iconGlyph(_ icon: String) -> some View {
        if SectionIconGlyph.isEmoji(icon) {
            Text(icon)
                .font(DS.caption)
        } else {
            Image(systemName: DocumentElementSymbol.validName(icon))
                .font(DS.caption.weight(.medium))
                .foregroundStyle(seatInk)
        }
    }

    /// With no icon, the style affordance is a quiet swatch that appears on
    /// hover — the box's colour, offered where the icon would sit.
    private var styleDot: some View {
        Button { isStylePopoverPresented = true } label: {
            Circle()
                .fill(tone?.ink(darkMode: darkMode) ?? Color.clear)
                .overlay(Circle().strokeBorder(seatInk.opacity(tone == nil ? 0.6 : 0), lineWidth: 1))
                .frame(width: 10, height: 10)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 3)
        .opacity(isHovered || isStylePopoverPresented ? 1 : 0)
        .animation(reduceMotion ? nil : ProMotionSprings.hover, value: isHovered)
        .help("Section style")
        .accessibilityLabel("Section style")
    }

    private var collapsedCount: some View {
        Text("\(childCount) block\(childCount == 1 ? "" : "s")")
            .font(DS.caption)
            .monospacedDigit()
            .foregroundStyle(mutedColor)
            .contentTransition(.numericText())
            .lineLimit(1)
            .layoutPriority(1)
            .padding(.top, 5)
    }

    private var seatFill: Color {
        tone?.wash(darkMode: darkMode) ?? DS.glassSectionFill
    }

    private var seatInk: Color {
        tone?.ink(darkMode: darkMode) ?? mutedColor
    }

    private var chevronColor: Color {
        if chevronHovered {
            return darkMode ? DS.focusImmersiveTextSecondary : DS.documentTextSecondary
        }
        return mutedColor
    }

    private var mutedColor: Color {
        darkMode ? DS.focusImmersiveTextMuted : DS.documentTextMuted
    }
}

// MARK: - Style popover

/// Tone · Appearance · Icon · Collapse by default. Presented in a native
/// popover (already glass), so everything inside is a flat warm fill — the
/// callout picker's pieces, laid out on one sheet.
private struct SectionStylePopover: View {
    let style: RichSectionStyle
    let darkMode: Bool
    let onChange: (RichSectionStyle) -> Void

    @State private var emojiDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            sectionLabel("Color")
            toneRow
            sectionLabel("Appearance")
            appearanceSwitcher
            sectionLabel("Icon")
            iconGrid
            emojiField
            collapseToggle
        }
        .padding(DS.space12)
        .frame(width: 252)
        .onAppear { emojiDraft = style.icon.flatMap { SectionIconGlyph.isEmoji($0) ? $0 : nil } ?? "" }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(DS.smallCaps)
            .tracking(DS.smallCapsTracking)
            .foregroundStyle(DS.textMuted)
    }

    private var toneRow: some View {
        HStack(spacing: DS.space8) {
            ForEach(NoteInkPalette.tones) { option in
                toneSwatch(option)
            }
            noneSwatch
            Spacer(minLength: 0)
        }
    }

    private func toneSwatch(_ option: NoteInkTone) -> some View {
        let isSelected = option.id == style.toneID
        return Button {
            update { $0.toneID = option.id }
        } label: {
            Circle()
                .fill(option.ink(darkMode: darkMode).opacity(isSelected ? 1 : 0.75))
                .frame(width: 18, height: 18)
                .overlay(selectionRing(isSelected, ink: option.ink(darkMode: darkMode)))
                .frame(width: 26, height: 26)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(option.label)
        .accessibilityLabel("\(option.label) color")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var noneSwatch: some View {
        let isSelected = !style.isTinted
        return Button {
            update { $0.toneID = RichSectionStyle.noneToneID }
        } label: {
            Circle()
                .fill(DS.glassCardFill)
                .overlay(Circle().strokeBorder(DS.textMuted.opacity(0.55), lineWidth: 1))
                .frame(width: 18, height: 18)
                .overlay(selectionRing(isSelected, ink: DS.textMuted))
                .frame(width: 26, height: 26)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("No color")
        .accessibilityLabel("No color")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func selectionRing(_ isSelected: Bool, ink: Color) -> some View {
        Circle()
            .strokeBorder(isSelected ? ink.opacity(0.5) : Color.clear, lineWidth: 2)
            .padding(-3)
    }

    private var appearanceSwitcher: some View {
        CosmoSegmentedSwitcher(
            options: RichSectionStyle.Appearance.allCases,
            label: { appearanceLabel($0) },
            help: { "\(appearanceLabel($0)) appearance" },
            chrome: .bare,
            selection: Binding(
                get: { style.appearance },
                set: { next in update { $0.appearance = next } }
            )
        )
    }

    private func appearanceLabel(_ appearance: RichSectionStyle.Appearance) -> String {
        switch appearance {
        case .wash: return "Wash"
        case .outline: return "Outline"
        case .bar: return "Bar"
        }
    }

    private var iconGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: DS.space6), count: 6), spacing: DS.space6) {
            noIconCell
            ForEach(CalloutIconCatalog.icons, id: \.symbol) { option in
                iconCell(option)
            }
        }
    }

    private var noIconCell: some View {
        let isSelected = style.icon == nil
        return Button {
            update { $0.icon = nil }
        } label: {
            Image(systemName: "circle.slash")
                .font(DS.subheadline.weight(.medium))
                .foregroundStyle(isSelected ? DS.text : DS.textSecondary)
                .frame(width: 30, height: 30)
                .background(cellBackground(isSelected))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("No icon")
        .accessibilityLabel("No icon")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func iconCell(_ option: CalloutIconCatalog.Option) -> some View {
        let isSelected = option.symbol == style.icon
        return Button {
            update { $0.icon = option.symbol }
        } label: {
            Image(systemName: DocumentElementSymbol.validName(option.symbol))
                .font(DS.subheadline.weight(.medium))
                .foregroundStyle(isSelected ? accentInk : DS.textSecondary)
                .frame(width: 30, height: 30)
                .background(cellBackground(isSelected))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(option.label)
        .accessibilityLabel(option.label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func cellBackground(_ isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(isSelected ? accentWash : DS.glassInputFill.opacity(0.7))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(isSelected ? accentHairline : Color.clear, lineWidth: 1)
            )
    }

    /// Emoji as identity: the first emoji typed becomes the icon.
    private var emojiField: some View {
        TextField("Or type an emoji", text: $emojiDraft)
            .textFieldStyle(.plain)
            .font(DS.callout)
            .foregroundStyle(DS.text)
            .padding(.horizontal, DS.space8)
            .padding(.vertical, DS.space4)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(DS.glassInputFill))
            .onChange(of: emojiDraft) { _, next in
                guard let emoji = SectionIconGlyph.emoji(from: next) else { return }
                if emojiDraft != emoji { emojiDraft = emoji }
                if style.icon != emoji { update { $0.icon = emoji } }
            }
            .accessibilityLabel("Emoji icon")
    }

    private var collapseToggle: some View {
        Toggle(
            "Collapse by default",
            isOn: Binding(
                get: { style.isCollapsed },
                set: { next in update { $0.isCollapsed = next } }
            )
        )
        .toggleStyle(.switch)
        .controlSize(.mini)
        .font(DS.callout)
        .foregroundStyle(DS.text)
    }

    private var tone: NoteInkTone? { SectionToneResolver.tone(for: style) }
    private var accentInk: Color { tone?.ink(darkMode: darkMode) ?? DS.text }
    private var accentWash: Color { tone?.wash(darkMode: darkMode) ?? DS.glassInputFillFocused }
    private var accentHairline: Color { tone?.hairline(darkMode: darkMode) ?? DS.glassBorder }

    private func update(_ mutate: (inout RichSectionStyle) -> Void) {
        var next = style
        mutate(&next)
        guard next != style else { return }
        onChange(next)
    }
}

private extension RichBlock {
    var isEmptyParagraph: Bool {
        guard kind == .paragraph, children.isEmpty else { return false }
        return inlines.allSatisfy { inline in
            switch inline.kind {
            case .text:
                return (inline.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            case .mention, .imageRef:
                return false
            }
        }
    }
}

// MARK: - Preview

private struct SectionBlockPreviewGrid: View {
    @State private var washed = RichBlock.section(
        title: "Change begins with clarity",
        style: RichSectionStyle(toneID: "moss", icon: "sparkles"),
        children: [.paragraph("The first box."), .paragraph("More body content...")]
    )
    @State private var outlined = RichBlock.section(
        title: "Outline",
        style: RichSectionStyle(toneID: "clay", appearance: .outline),
        children: [.paragraph("Hairline only.")]
    )
    @State private var barred = RichBlock.section(
        title: "Bar",
        style: RichSectionStyle(toneID: "none", appearance: .bar, isCollapsed: true),
        children: [.paragraph("Hidden."), .paragraph("Also hidden.")]
    )
    @State private var coordinator = BlockFocusCoordinator()

    var body: some View {
        VStack(spacing: DS.space20) {
            preview($washed)
            preview($outlined)
            preview($barred)
        }
        .padding(DS.space24)
        .frame(width: 460)
    }

    private func preview(_ block: Binding<RichBlock>) -> some View {
        SectionBlockView(
            block: block,
            focusCoordinator: coordinator,
            onStyleChange: { block.wrappedValue.section = $0 }
        ) {
            Text(block.wrappedValue.plainInlineText)
                .font(DS.body.weight(.semibold))
        }
    }
}

#Preview("Sections - Light") {
    SectionBlockPreviewGrid()
        .background(DS.documentBackground)
}

#Preview("Sections - Dark") {
    SectionBlockPreviewGrid()
        .background(Color.black)
        .environment(\.colorScheme, .dark)
}
