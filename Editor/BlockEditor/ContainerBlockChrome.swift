import SwiftUI

/// The ONE container grammar for boxed block groups. Elements and Sections
/// both draw through this so two boxes on one page are indistinguishable in
/// material (peakui Law 11): an Element is a container backed by a reusable
/// definition, a Section is an ad-hoc container — same wash, same hairline,
/// same radius, same collapse spring. The look is the Element card's,
/// extracted verbatim: a 0.55-strength tone wash, a hairline that firms on
/// hover, a 10 pt continuous radius, no drop shadow.
enum ContainerAppearance: Equatable, Hashable, Sendable {
    /// Tone wash fill + hairline — the Element look.
    case wash
    /// Hairline only, no fill.
    case outline
    /// A 4 pt left bar in the tone ink; no fill, no hairline (the quote-bar
    /// dialect for a group).
    case bar

    init(_ appearance: RichSectionStyle.Appearance) {
        switch appearance {
        case .wash: self = .wash
        case .outline: self = .outline
        case .bar: self = .bar
        }
    }
}

/// Resolved paint for one container. `tone == nil` is parchment — the
/// untinted "none" section: glass card fill + the document's subtle border.
struct ContainerBlockChrome: Equatable {
    static let cornerRadius: CGFloat = 10
    static let washOpacity: Double = 0.55
    static let restingHairlineOpacity: Double = 0.65
    static let barWidth: CGFloat = 4
    /// The header seat every container shares — chevron, icon, title.
    static let headerHeight: CGFloat = 30

    var appearance: ContainerAppearance = .wash
    var tone: NoteInkTone? = NoteInkPalette.tone(nil)
    var darkMode: Bool = false
    var isHovered: Bool = false

    var fill: Color {
        guard appearance == .wash else { return .clear }
        guard let tone else { return DS.glassCardFill }
        return tone.wash(darkMode: darkMode).opacity(Self.washOpacity)
    }

    var hairline: Color {
        guard appearance != .bar else { return .clear }
        guard let tone else {
            if darkMode { return DS.focusImmersiveBorder.opacity(isHovered ? 1 : Self.restingHairlineOpacity) }
            return isHovered ? DS.documentBorder : DS.documentBorderSubtle
        }
        return tone.hairline(darkMode: darkMode).opacity(isHovered ? 1 : Self.restingHairlineOpacity)
    }

    var barInk: Color {
        guard appearance == .bar else { return .clear }
        guard let tone else { return darkMode ? DS.focusImmersiveTextMuted : DS.documentTextMuted }
        return tone.ink(darkMode: darkMode)
    }

    /// Content clears the bar; the other appearances need no extra inset.
    var contentLeadingInset: CGFloat {
        appearance == .bar ? Self.barWidth + DS.space6 : 0
    }
}

/// The container surface itself: fill → continuous clip → hairline → bar,
/// with the collapse spring on the whole box. Callers own hover (they may
/// need it for their own affordances) and pass it through the chrome.
struct ContainerBlockSurface<Content: View>: View {
    let chrome: ContainerBlockChrome
    /// Drives the collapse spring — the one layout animation a container owns.
    var isCollapsed: Bool = false
    @ViewBuilder let content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content()
            .padding(.leading, chrome.contentLeadingInset)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(surfaceFill)
            .clipShape(.rect(cornerRadius: ContainerBlockChrome.cornerRadius, style: .continuous))
            .overlay(surfaceBorder)
            .overlay(alignment: .leading) { leadingBar }
            .animation(reduceMotion ? nil : ProMotionSprings.snappy, value: isCollapsed)
    }

    private var surfaceFill: some View {
        RoundedRectangle(cornerRadius: ContainerBlockChrome.cornerRadius, style: .continuous)
            .fill(chrome.fill)
    }

    private var surfaceBorder: some View {
        RoundedRectangle(cornerRadius: ContainerBlockChrome.cornerRadius, style: .continuous)
            .strokeBorder(chrome.hairline, lineWidth: 1)
    }

    @ViewBuilder
    private var leadingBar: some View {
        if chrome.appearance == .bar {
            Capsule()
                .fill(chrome.barInk)
                .frame(width: ContainerBlockChrome.barWidth)
                .padding(.vertical, DS.space4)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
