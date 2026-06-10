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

    var fontFamily: FontFamily = .sans
    var textSize: TextSize = .standard
    var pageWidth: PageWidth = .standard

    static let `default` = NoteDocumentStyle()

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
/// Rendered inside a native popover (already Liquid Glass), so inner elements
/// use flat warm fills per the design system.
struct NoteStyleMenuView: View {
    @Binding var style: NoteDocumentStyle
    @Binding var typewriterMode: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            section("FONT") { fontFamilyGrid }
            section("TEXT SIZE") {
                segmentedRow(NoteDocumentStyle.TextSize.allCases, selection: $style.textSize) { $0.label }
            }
            section("PAGE WIDTH") {
                segmentedRow(NoteDocumentStyle.PageWidth.allCases, selection: $style.pageWidth) { $0.label }
            }
            Divider()
            typewriterRow
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
        let isSelected = style.fontFamily == family
        return Button {
            withAnimation(ProMotionSprings.snappy) {
                style.fontFamily = family
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
}
