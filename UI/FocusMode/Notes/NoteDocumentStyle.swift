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
            readingWidth(for: .standard)
        }

        /// The measure follows the type size (ems, not points): a fixed 680
        /// ran 98 characters per line at Compact and 80 at Large — the preset
        /// picked to fit more read worst. ×36 holds ~78–80 CPL at every size
        /// (jury round 1, typography chair); Wide keeps its meaning at ×46.
        func readingWidth(for size: TextSize) -> CGFloat {
            switch self {
            case .standard: return (size.pointSize * 36).rounded()
            case .wide: return (size.pointSize * 46).rounded()
            }
        }
    }

    /// The page's paper — a quiet tint under everything. Parchment is the
    /// theme's own surface; the rest are curated washes with light and
    /// immersive variants so every theme family stays coherent.
    enum PaperTone: String, Codable, CaseIterable, Identifiable {
        case parchment
        case cream
        case linen
        case mist
        case sage
        case dusk

        var id: String { rawValue }

        var label: String {
            switch self {
            case .parchment: return "Parchment"
            case .cream: return "Cream"
            case .linen: return "Linen"
            case .mist: return "Mist"
            case .sage: return "Sage"
            case .dusk: return "Dusk"
            }
        }

        /// nil ⇒ use the theme's own document surface (Parchment).
        func pageColor(darkMode: Bool) -> Color? {
            switch self {
            case .parchment: return nil
            case .cream: return Color(hex: darkMode ? "272216" : "FAF4E6")
            case .linen: return Color(hex: darkMode ? "241F1B" : "F7F1EA")
            case .mist: return Color(hex: darkMode ? "1B2126" : "F1F4F7")
            case .sage: return Color(hex: darkMode ? "1C231D" : "F0F5EE")
            case .dusk: return Color(hex: darkMode ? "211E27" : "F3F0F7")
            }
        }

        /// The swatch face shown in the picker (always resolvable).
        func swatchColor(darkMode: Bool) -> Color {
            pageColor(darkMode: darkMode)
                ?? (darkMode ? Color(hex: "1E1D1A") : Color(hex: "F8F7F4"))
        }
    }

    /// A cover band above the title — Craft-style page identity.
    enum Cover: String, Codable, CaseIterable, Identifiable {
        case none
        case wash
        case dawn
        case meadow
        case dusk
        case ink

        var id: String { rawValue }

        var label: String {
            switch self {
            case .none: return "None"
            case .wash: return "Wash"
            case .dawn: return "Dawn"
            case .meadow: return "Meadow"
            case .dusk: return "Dusk"
            case .ink: return "Ink"
            }
        }

        /// Gradient stops per cover. `wash` derives from the page's tone so
        /// the band always belongs to its paper.
        func gradientColors(tone: PaperTone, darkMode: Bool) -> [Color]? {
            switch self {
            case .none:
                return nil
            case .wash:
                let base = tone.swatchColor(darkMode: darkMode)
                return [base.opacity(darkMode ? 0.9 : 1), base.opacity(0.0)]
            case .dawn:
                return [Color(hex: darkMode ? "4A3A33" : "F2D8C2"), Color(hex: darkMode ? "2A2320" : "FAF0E4").opacity(0)]
            case .meadow:
                return [Color(hex: darkMode ? "2F4234" : "CFE3CE"), Color(hex: darkMode ? "20281F" : "EFF6EC").opacity(0)]
            case .dusk:
                return [Color(hex: darkMode ? "3A3347" : "D8D0E8"), Color(hex: darkMode ? "252031" : "F1EDF8").opacity(0)]
            case .ink:
                return [Color(hex: darkMode ? "31373D" : "C9D2DA"), Color(hex: darkMode ? "22262A" : "EDF1F4").opacity(0)]
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
    var paperTone: PaperTone = .parchment
    /// SF Symbol name or a literal emoji rendered beside the title.
    var pageIcon: String? = nil
    var cover: Cover = .none

    static let `default` = NoteDocumentStyle()

    init() {}

    // Decoding stays lenient: styles persisted before a field existed (or
    // after one is renamed) must never reset a note's voice to defaults.
    private enum CodingKeys: String, CodingKey {
        case fontFamily, textSize, pageWidth, lineSpacing, paperTone, pageIcon, cover
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fontFamily = (try? container.decodeIfPresent(FontFamily.self, forKey: .fontFamily)) ?? .sans
        textSize = (try? container.decodeIfPresent(TextSize.self, forKey: .textSize)) ?? .standard
        pageWidth = (try? container.decodeIfPresent(PageWidth.self, forKey: .pageWidth)) ?? .standard
        lineSpacing = (try? container.decodeIfPresent(LineSpacing.self, forKey: .lineSpacing)) ?? .standard
        paperTone = (try? container.decodeIfPresent(PaperTone.self, forKey: .paperTone)) ?? .parchment
        pageIcon = (try? container.decodeIfPresent(String.self, forKey: .pageIcon)) ?? nil
        cover = (try? container.decodeIfPresent(Cover.self, forKey: .cover)) ?? .none
    }

    // MARK: - Metadata Persistence

    static let metadataKey = "note_document_style"

    /// Last-decode memo for `load(fromMetadata:)`. NoteFocusModeView.init
    /// re-runs the load on every SwiftUI re-init, re-parsing the whole
    /// metadata JSON (often hundreds of KB) each time — and the hot case is
    /// the SAME atom string decoded back-to-back, so one entry suffices.
    /// Exact-equality semantics: `==` short-circuits on the count check
    /// before comparing bytes. Lock-guarded to mirror
    /// Atom.DecodedColumnCache's shape (call sites include nonisolated
    /// test contexts, so no actor annotation).
    private final class StyleDecodeMemo: @unchecked Sendable {
        static let shared = StyleDecodeMemo()
        private let lock = NSLock()
        private var lastDecode: (source: String, style: NoteDocumentStyle)?

        func style(for source: String, decode: () -> NoteDocumentStyle) -> NoteDocumentStyle {
            lock.lock()
            if let cached = lastDecode, cached.source.count == source.count, cached.source == source {
                let hit = cached.style
                lock.unlock()
                return hit
            }
            lock.unlock()

            let decoded = decode()
            lock.lock()
            lastDecode = (source, decoded)
            lock.unlock()
            return decoded
        }
    }

    static func load(fromMetadata metadata: String?) -> NoteDocumentStyle {
        guard let metadata else { return .default }
        return StyleDecodeMemo.shared.style(for: metadata) {
            decodeStyle(fromMetadata: metadata)
        }
    }

    private static func decodeStyle(fromMetadata metadata: String) -> NoteDocumentStyle {
        guard let data = metadata.data(using: .utf8),
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

/// Per-note page styles for chrome that only knows an atom UUID (library
/// cards). Read-through: `style(for:)` returns the cached value and quietly
/// fetches when missing — the observing view re-renders when it lands. A
/// note save (`.noteFocusStateDidChange`) drops that note's entry, so the
/// next read refetches and personalization stays live.
@MainActor
@Observable
final class NotePageStyleCache {
    static let shared = NotePageStyleCache()

    private(set) var styles: [String: NoteDocumentStyle] = [:]
    @ObservationIgnored private var inflight: Set<String> = []
    @ObservationIgnored private var saveObserver: NSObjectProtocol?

    private init() {
        saveObserver = NotificationCenter.default.addObserver(
            forName: .noteFocusStateDidChange,
            object: nil,
            queue: .main
        ) { notification in
            let uuid = notification.userInfo?["atomUUID"] as? String
            Task { @MainActor in
                if let uuid {
                    NotePageStyleCache.shared.invalidate(uuid)
                }
            }
        }
    }

    func style(for atomUUID: String) -> NoteDocumentStyle? {
        guard !atomUUID.isEmpty else { return nil }
        if let cached = styles[atomUUID] {
            return cached
        }
        fetchIfNeeded(atomUUID)
        return nil
    }

    func invalidate(_ atomUUID: String) {
        styles[atomUUID] = nil
    }

    private func fetchIfNeeded(_ atomUUID: String) {
        guard !inflight.contains(atomUUID) else { return }
        inflight.insert(atomUUID)
        Task { @MainActor in
            let atom = try? await AtomRepository.shared.fetch(uuid: atomUUID)
            styles[atomUUID] = NoteDocumentStyle.load(fromMetadata: atom?.metadata)
            inflight.remove(atomUUID)
        }
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
    /// True when hosted inside another popover body (the Notes page-style
    /// popover) that owns padding and width.
    var embedded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            section("Font") { fontFamilyGrid }
            section("Text size") {
                segmentedRow(NoteDocumentStyle.TextSize.allCases, selection: $textSize) { $0.label }
            }
            if let lineSpacing {
                section("Line spacing") {
                    segmentedRow(NoteDocumentStyle.LineSpacing.allCases, selection: lineSpacing) { $0.label }
                }
            }
            section("Page width") {
                segmentedRow(widthOptions, selection: $widthSelection, label: widthLabel)
            }
            Divider()
            typewriterRow
            if let paragraphFocus {
                focusRow(paragraphFocus)
            }
        }
        .padding(embedded ? 0 : DS.space16)
        .frame(width: embedded ? nil : 296)
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            // Sentence-case source + smallCaps() — the ONE small-caps dialect
            // (.smallCaps() on an UPPERCASE string is a no-op).
            Text(title)
                .font(DS.smallCaps)
                .tracking(DS.smallCapsTracking)
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
                    // Constant weight — selection must not re-typeset the
                    // capsule row (the labels shifted width on every pick).
                    Text(label(option))
                        .font(DS.caption)
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
                .tint(DS.accent)
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
                .tint(DS.accent)
                .controlSize(.small)
                .labelsHidden()
                .accessibilityLabel("Paragraph focus")
        }
        .help("Fade everything but the paragraph you're writing")
    }
}
