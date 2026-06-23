import AppKit
import SwiftUI

/// Per-note document styling (Craft-style): font family, text size, and page
/// width travel with the note in its atom metadata, so every note can have
/// its own voice.
struct NoteDocumentStyle: Codable, Equatable {
    enum FontFamily: String, Codable, CaseIterable, Identifiable {
        case sans
        case serif
        case rounded
        case mono

        var id: String { rawValue }

        var label: String {
            switch self {
            case .sans: return "Sans"
            case .serif: return "Serif"
            case .rounded: return "Round"
            case .mono: return "Mono"
            }
        }

        var design: NSFontDescriptor.SystemDesign {
            switch self {
            case .sans: return .default
            case .serif: return .serif
            case .rounded: return .rounded
            case .mono: return .monospaced
            }
        }

        var swiftUIDesign: Font.Design {
            switch self {
            case .sans: return .default
            case .serif: return .serif
            case .rounded: return .rounded
            case .mono: return .monospaced
            }
        }
    }

    enum TextSize: String, Codable, CaseIterable, Identifiable {
        case compact
        case standard
        case large

        var id: String { rawValue }

        var label: String {
            switch self {
            case .compact: return "Compact"
            case .standard: return "Standard"
            case .large: return "Large"
            }
        }

        var pointSize: CGFloat {
            switch self {
            case .compact: return 15
            case .standard: return 17
            case .large: return 19
            }
        }
    }

    enum PageWidth: String, Codable, CaseIterable, Identifiable {
        case standard
        case wide

        var id: String { rawValue }

        var label: String {
            switch self {
            case .standard: return "Standard"
            case .wide: return "Wide"
            }
        }

        var readingWidth: CGFloat {
            switch self {
            case .standard: return CosmoTypography.optimalReadingWidth
            case .wide: return 940
            }
        }
    }

    enum LineSpacing: String, Codable, CaseIterable, Identifiable {
        case compact
        case standard
        case airy

        var id: String { rawValue }

        var label: String {
            switch self {
            case .compact: return "Compact"
            case .standard: return "Standard"
            case .airy: return "Airy"
            }
        }

        /// Delta applied to the editor's base body leading. Standard keeps
        /// today's rhythm (~140% at 17pt); Airy reaches Dropbox Paper's
        /// celebrated 1.625 ratio; Compact tightens for dense notes.
        var lineSpacingDelta: CGFloat {
            switch self {
            case .compact: return -3
            case .standard: return 0
            case .airy: return 4
            }
        }

        /// The gap between block rows scales with the leading so the page
        /// keeps one vertical rhythm.
        var blockGap: CGFloat {
            switch self {
            case .compact: return 4
            case .standard: return 6
            case .airy: return 9
            }
        }
    }

    var fontFamily: FontFamily = .sans
    var textSize: TextSize = .standard
    var pageWidth: PageWidth = .standard
    var lineSpacing: LineSpacing = .standard

    static let `default` = NoteDocumentStyle()

    init() {}

    // Decoding stays lenient: styles persisted before a field existed (or
    // after one is renamed) must never reset a note's voice to defaults.
    private enum CodingKeys: String, CodingKey {
        case fontFamily, textSize, pageWidth, lineSpacing
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fontFamily = (try? container.decodeIfPresent(FontFamily.self, forKey: .fontFamily)) ?? .sans
        textSize = (try? container.decodeIfPresent(TextSize.self, forKey: .textSize)) ?? .standard
        pageWidth = (try? container.decodeIfPresent(PageWidth.self, forKey: .pageWidth)) ?? .standard
        lineSpacing = (try? container.decodeIfPresent(LineSpacing.self, forKey: .lineSpacing)) ?? .standard
    }

    // MARK: - Metadata Persistence

    static let metadataKey = "note_document_style"

    static func load(fromMetadata metadata: String?) -> NoteDocumentStyle {
        guard let metadata,
              let data = metadata.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = dict[Self.metadataKey],
              JSONSerialization.isValidJSONObject(value),
              let styleData = try? JSONSerialization.data(withJSONObject: value),
              let style = try? JSONDecoder().decode(NoteDocumentStyle.self, from: styleData) else {
            return .default
        }
        return style
    }

    func write(intoMetadata metadata: String?) -> String? {
        var dict: [String: Any] = [:]
        if let metadata,
           let data = metadata.data(using: .utf8),
           let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            dict = decoded
        }

        if let data = try? JSONEncoder().encode(self),
           let object = try? JSONSerialization.jsonObject(with: data) {
            dict[Self.metadataKey] = object
        }

        guard JSONSerialization.isValidJSONObject(dict),
              let data = try? JSONSerialization.data(withJSONObject: dict),
              let string = String(data: data, encoding: .utf8) else {
            return metadata
        }
        return string
    }
}

/// The "Aa" style popover for the Notes focus mode — the document's voice
/// lives here: font family, text size, page width, typewriter mode.
struct NoteStyleMenuView: View {
    @Binding var style: NoteDocumentStyle
    @Binding var typewriterMode: Bool
    @Binding var paragraphFocus: Bool

    var body: some View {
        DocumentStyleMenuView(
            fontFamily: $style.fontFamily,
            textSize: $style.textSize,
            widthOptions: NoteDocumentStyle.PageWidth.allCases,
            widthSelection: $style.pageWidth,
            widthLabel: { $0.label },
            typewriterMode: $typewriterMode,
            lineSpacing: $style.lineSpacing,
            paragraphFocus: $paragraphFocus
        )
    }
}

/// The shared "Aa" style popover body — one source of truth for the
/// document-voice menu, so Notes and Content focus modes read identically.
/// Page-width options are generic because each surface has its own widths.
/// Rendered inside a native popover (already Liquid Glass), so inner elements
/// use flat warm fills per the design system.
struct DocumentStyleMenuView<WidthOption: Identifiable & Equatable>: View {
    @Binding var fontFamily: NoteDocumentStyle.FontFamily
    @Binding var textSize: NoteDocumentStyle.TextSize
    let widthOptions: [WidthOption]
    @Binding var widthSelection: WidthOption
    let widthLabel: (WidthOption) -> String
    @Binding var typewriterMode: Bool
    /// Surfaces that support per-document leading pass a binding; others
    /// leave it nil and the section stays hidden.
    var lineSpacing: Binding<NoteDocumentStyle.LineSpacing>? = nil
    /// Paragraph focus (dim everything but the caret's block) — Notes only.
    var paragraphFocus: Binding<Bool>? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            section("FONT") { fontFamilyGrid }
            section("TEXT SIZE") {
                segmentedRow(NoteDocumentStyle.TextSize.allCases, selection: $textSize) { $0.label }
            }
            if let lineSpacing {
                section("LINE SPACING") {
                    segmentedRow(NoteDocumentStyle.LineSpacing.allCases, selection: lineSpacing) { $0.label }
                }
            }
            section("PAGE WIDTH") {
                segmentedRow(widthOptions, selection: $widthSelection, label: widthLabel)
            }
            Divider()
            typewriterRow
            if let paragraphFocus {
                focusRow(paragraphFocus)
            }
        }
        .padding(DS.space16)
        .frame(width: 296)
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

    private var fontFamilyGrid: some View {
        HStack(spacing: DS.space6) {
            ForEach(NoteDocumentStyle.FontFamily.allCases) { family in
                fontFamilyCard(family)
            }
        }
    }

    private func fontFamilyCard(_ family: NoteDocumentStyle.FontFamily) -> some View {
        let isSelected = fontFamily == family
        return Button {
            withAnimation(ProMotionSprings.snappy) {
                fontFamily = family
            }
        } label: {
            VStack(spacing: DS.space4) {
                Text("Ag")
                    .font(DS.title2)
                    .fontDesign(family.swiftUIDesign)
                    .foregroundStyle(isSelected ? DS.accent : DS.text)
                Text(family.label)
                    .font(DS.caption2)
                    .foregroundStyle(isSelected ? DS.accent : DS.textMuted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.space8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? DS.accentSoft : DS.glassInputFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? DS.accent.opacity(0.4) : DS.glassBorder, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(family.label) font")
        .accessibilityLabel("\(family.label) font")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func segmentedRow<Option: Identifiable & Equatable>(
        _ options: [Option],
        selection: Binding<Option>,
        label: @escaping (Option) -> String
    ) -> some View {
        HStack(spacing: DS.space4) {
            ForEach(options) { option in
                let isSelected = selection.wrappedValue == option
                Button {
                    withAnimation(ProMotionSprings.snappy) {
                        selection.wrappedValue = option
                    }
                } label: {
                    Text(label(option))
                        .font(DS.caption.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? DS.accent : DS.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DS.space6)
                        .background(
                            Capsule().fill(isSelected ? DS.accentSoft : DS.glassInputFill)
                        )
                        .overlay(
                            Capsule().strokeBorder(isSelected ? DS.accent.opacity(0.4) : DS.glassBorder, lineWidth: 1)
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(label(option))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    private var typewriterRow: some View {
        HStack(spacing: DS.space8) {
            Image(systemName: "keyboard")
                .font(DS.caption)
                .foregroundStyle(DS.textSecondary)
                .accessibilityHidden(true)
            Text("Typewriter mode")
                .font(DS.callout)
                .foregroundStyle(DS.text)
            Spacer(minLength: DS.space12)
            Toggle("", isOn: $typewriterMode)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .accessibilityLabel("Typewriter mode")
        }
    }

    private func focusRow(_ binding: Binding<Bool>) -> some View {
        HStack(spacing: DS.space8) {
            Image(systemName: "paragraphsign")
                .font(DS.caption)
                .foregroundStyle(DS.textSecondary)
                .accessibilityHidden(true)
            Text("Paragraph focus")
                .font(DS.callout)
                .foregroundStyle(DS.text)
            Spacer(minLength: DS.space12)
            Toggle("", isOn: binding)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .accessibilityLabel("Paragraph focus")
        }
        .help("Fade everything but the paragraph you're writing")
    }
}
