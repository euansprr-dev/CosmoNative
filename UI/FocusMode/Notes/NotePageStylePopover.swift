import AppKit
import SwiftUI

/// The unified "Aa" popover for Notes — the whole page's personality in one
/// place. Two voices: **Text** (font, size, spacing, width, writing modes)
/// and **Page** (paper tone, icon, cover, side panels). Every control writes
/// through immediately; the page responds behind the popover.
struct NotePageStylePopover: View {
    @Binding var style: NoteDocumentStyle
    @Binding var typewriterMode: Bool
    @Binding var paragraphFocus: Bool
    @Binding var leftRailVisible: Bool
    @Binding var rightRailVisible: Bool

    @State private var segment: Segment = .text
    @State private var iconQuery = ""

    private enum Segment: String, CaseIterable, Identifiable {
        case text = "Text"
        case page = "Page"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            segmentSwitcher
            switch segment {
            case .text:
                textSection
            case .page:
                NotePageStylePageSection(style: $style, leftRailVisible: $leftRailVisible, rightRailVisible: $rightRailVisible)
            }
        }
        .padding(DS.space16)
        .frame(width: 320)
        .animation(ProMotionSprings.snappy, value: segment)
    }

    private var segmentSwitcher: some View {
        HStack(spacing: DS.space4) {
            ForEach(Segment.allCases) { option in
                let isSelected = segment == option
                Button {
                    withAnimation(ProMotionSprings.snappy) { segment = option }
                } label: {
                    Text(option.rawValue)
                        .font(DS.caption.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? DS.accent : DS.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DS.space6)
                        .background(Capsule().fill(isSelected ? DS.accentSoft : DS.glassInputFill))
                        .overlay(
                            Capsule().strokeBorder(isSelected ? DS.accent.opacity(0.4) : DS.glassBorder, lineWidth: 1)
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(option.rawValue) settings")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    private var textSection: some View {
        DocumentStyleMenuView(
            fontFamily: $style.fontFamily,
            textSize: $style.textSize,
            widthOptions: NoteDocumentStyle.PageWidth.allCases,
            widthSelection: $style.pageWidth,
            widthLabel: { $0.label },
            typewriterMode: $typewriterMode,
            lineSpacing: $style.lineSpacing,
            paragraphFocus: $paragraphFocus,
            embedded: true
        )
    }
}

/// The Page segment — paper, icon, cover, panels.
private struct NotePageStylePageSection: View {
    @Binding var style: NoteDocumentStyle
    @Binding var leftRailVisible: Bool
    @Binding var rightRailVisible: Bool

    @State private var iconQuery = ""
    @Environment(\.colorScheme) private var colorScheme

    private var darkMode: Bool { DS.usesImmersiveFocusAppearance }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            section("PAPER") { paperRow }
            section("PAGE ICON") { iconPicker }
            section("COVER") { coverRow }
            Divider()
            panelsRows
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            Text(title)
                .font(DS.caption2.weight(.semibold))
                .tracking(0.8)
                .foregroundStyle(DS.textMuted)
            content()
        }
    }

    // MARK: Paper

    private var paperRow: some View {
        HStack(spacing: DS.space8) {
            ForEach(NoteDocumentStyle.PaperTone.allCases) { tone in
                paperSwatch(tone)
            }
            Spacer(minLength: 0)
        }
    }

    private func paperSwatch(_ tone: NoteDocumentStyle.PaperTone) -> some View {
        let isSelected = style.paperTone == tone
        return Button {
            withAnimation(ProMotionSprings.gentle) { style.paperTone = tone }
        } label: {
            Circle()
                .fill(tone.swatchColor(darkMode: darkMode))
                .overlay(Circle().strokeBorder(DS.glassBorder, lineWidth: 1))
                .overlay(
                    Circle()
                        .strokeBorder(isSelected ? DS.accent.opacity(0.65) : Color.clear, lineWidth: 2)
                        .padding(-3)
                )
                .frame(width: 24, height: 24)
                .frame(width: 32, height: 32)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(tone.label)
        .accessibilityLabel("\(tone.label) paper")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: Page icon

    private var iconPicker: some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            HStack(spacing: DS.space6) {
                noIconButton
                TextField("Search icons, or type an emoji", text: $iconQuery)
                    .textFieldStyle(.plain)
                    .font(DS.caption)
                    .foregroundStyle(DS.text)
                    .padding(.horizontal, DS.space8)
                    .padding(.vertical, DS.space4)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(DS.glassInputFill))
                    .onSubmit { adoptEmojiIfTyped() }
                    .accessibilityLabel("Search page icons")
            }
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(28), spacing: DS.space6), count: 8), spacing: DS.space6) {
                    ForEach(NoteElementIconCatalog.matching(iconQuery), id: \.symbol) { option in
                        iconCell(option.symbol, help: option.suggestedName)
                    }
                }
            }
            .frame(height: 66)
            .scrollBounceBehavior(.basedOnSize)
        }
        .onChange(of: iconQuery) { _, _ in adoptEmojiIfTyped() }
    }

    /// Typing or pasting an emoji into the search field sets it directly —
    /// no separate mode, the field just understands.
    private func adoptEmojiIfTyped() {
        let trimmed = iconQuery.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count <= 2,
              trimmed.unicodeScalars.contains(where: { $0.properties.isEmojiPresentation }) else { return }
        style.pageIcon = trimmed
        iconQuery = ""
    }

    private var noIconButton: some View {
        let isSelected = style.pageIcon == nil
        return Button {
            withAnimation(ProMotionSprings.snappy) { style.pageIcon = nil }
        } label: {
            Image(systemName: "slash.circle")
                .font(DS.caption.weight(.medium))
                .foregroundStyle(isSelected ? DS.accent : DS.textSecondary)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(isSelected ? DS.accentSoft : DS.glassInputFill))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("No icon")
        .accessibilityLabel("No page icon")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func iconCell(_ symbol: String, help: String) -> some View {
        let isSelected = style.pageIcon == symbol
        return Button {
            withAnimation(ProMotionSprings.snappy) { style.pageIcon = symbol }
        } label: {
            Image(systemName: DocumentElementSymbol.validName(symbol))
                .font(DS.caption.weight(.medium))
                .foregroundStyle(isSelected ? DS.accent : DS.textSecondary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? DS.accentSoft : DS.glassInputFill.opacity(0.7))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: Cover

    private var coverRow: some View {
        HStack(spacing: DS.space6) {
            ForEach(NoteDocumentStyle.Cover.allCases) { cover in
                coverCell(cover)
            }
        }
    }

    private func coverCell(_ cover: NoteDocumentStyle.Cover) -> some View {
        let isSelected = style.cover == cover
        return Button {
            withAnimation(ProMotionSprings.gentle) { style.cover = cover }
        } label: {
            VStack(spacing: DS.space2) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(coverPreviewFill(cover))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(isSelected ? DS.accent.opacity(0.5) : DS.glassBorder, lineWidth: 1)
                    )
                    .frame(width: 40, height: 24)
                Text(cover.label)
                    .font(DS.caption2)
                    .foregroundStyle(isSelected ? DS.accent : DS.textMuted)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(cover.label) cover")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func coverPreviewFill(_ cover: NoteDocumentStyle.Cover) -> AnyShapeStyle {
        guard let colors = cover.gradientColors(tone: style.paperTone, darkMode: darkMode) else {
            return AnyShapeStyle(DS.glassInputFill.opacity(0.5))
        }
        return AnyShapeStyle(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
    }

    // MARK: Panels

    private var panelsRows: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            toggleRow(icon: "list.bullet.rectangle", label: "Outline panel", binding: $leftRailVisible)
            toggleRow(icon: "point.3.connected.trianglepath.dotted", label: "Connections panel", binding: $rightRailVisible)
        }
    }

    private func toggleRow(icon: String, label: String, binding: Binding<Bool>) -> some View {
        HStack(spacing: DS.space8) {
            Image(systemName: icon)
                .font(DS.caption)
                .foregroundStyle(DS.textSecondary)
                .accessibilityHidden(true)
            Text(label)
                .font(DS.callout)
                .foregroundStyle(DS.text)
            Spacer(minLength: DS.space12)
            Toggle("", isOn: binding)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .accessibilityLabel(label)
        }
    }
}

// MARK: - Shared page-personality renderers

/// The page icon beside the title — an SF Symbol on the tone, or a literal
/// emoji. Shared by the focus page, canvas card, and library card so a
/// personalized note reads as itself everywhere.
struct NotePageIconView: View {
    let icon: String
    var style: NoteDocumentStyle = .default
    var darkMode: Bool = false
    var size: CGFloat = 24

    var body: some View {
        if NSImage(systemSymbolName: icon, accessibilityDescription: nil) != nil {
            Image(systemName: icon)
                .font(.system(size: size * 0.82, weight: .medium))
                .foregroundStyle(darkMode ? DS.focusImmersiveTextSecondary : DS.documentTextSecondary)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        } else {
            Text(icon)
                .font(.system(size: size * 0.92))
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }
}

/// The cover band above the title — pure gradient, scrolls with the page,
/// concentric with whatever container clips it.
struct NotePageCoverBand: View {
    let style: NoteDocumentStyle
    var darkMode: Bool = false
    var height: CGFloat = 110

    var body: some View {
        if let colors = style.cover.gradientColors(tone: style.paperTone, darkMode: darkMode) {
            LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
                .frame(height: height)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
                .transition(.opacity)
        }
    }
}
