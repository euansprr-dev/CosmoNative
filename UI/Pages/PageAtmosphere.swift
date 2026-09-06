import SwiftUI

/// A Page's full-bleed personality: its paper, and the cover wash that pours
/// from the top edge and fades into that paper. One value describes it, so
/// the Page can paint it inside its own bounds or hand it to a host that
/// paints it under the floating chrome (sidebar, chrome row) — the glass
/// lenses the color instead of the page wearing a rounded block.
struct PageAtmosphere: Equatable {
    var paper: Color?
    var cover: Color?

    init(style: NoteDocumentStyle, darkMode: Bool) {
        paper = style.paperTone.pageColor(darkMode: darkMode)
        cover = style.cover.washColor(tone: style.paperTone, darkMode: darkMode)
    }
}

/// One eased fade for every cover renderer — the page, its sections, the
/// canvas card, the library tile. A two-stop linear gradient reads as a
/// painted block; these stops fall off like light.
struct PageCoverWash: View {
    let color: Color

    var body: some View {
        LinearGradient(stops: Self.stops(for: color), startPoint: .top, endPoint: .bottom)
            .accessibilityHidden(true)
    }

    static func stops(for color: Color) -> [Gradient.Stop] {
        [
            .init(color: color, location: 0),
            .init(color: color.opacity(0.88), location: 0.18),
            .init(color: color.opacity(0.62), location: 0.42),
            .init(color: color.opacity(0.30), location: 0.68),
            .init(color: color.opacity(0.10), location: 0.88),
            .init(color: color.opacity(0), location: 1),
        ]
    }
}

/// Paints an atmosphere across the full bounds it's given: paper (or the app
/// ground) under everything, the wash pouring from the top edge. Hosts apply
/// it OUTSIDE any leading inset so the wash runs under the sidebar.
struct PageAtmosphereBackground: View {
    let atmosphere: PageAtmosphere
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                (atmosphere.paper ?? DS.bg)
                if let cover = atmosphere.cover {
                    PageCoverWash(color: cover)
                        .frame(height: Self.washHeight(in: geometry.size.height))
                        .transition(.opacity)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .animation(reduceMotion ? nil : ProMotionSprings.gentle, value: atmosphere)
    }

    /// The wash reaches past the title into the first lines, then is gone.
    static func washHeight(in height: CGFloat) -> CGFloat {
        min(max(300, height * 0.42), 460)
    }
}

/// The hosted Page publishes its atmosphere; the host paints it.
struct PageAtmospherePreferenceKey: PreferenceKey {
    static let defaultValue: PageAtmosphere? = nil
    static func reduce(value: inout PageAtmosphere?, nextValue: () -> PageAtmosphere?) {
        if let next = nextValue() { value = next }
    }
}

private struct PageAtmosphereHostedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True under a host that paints the Page's atmosphere itself, under its
    /// floating chrome. The Page then publishes instead of painting.
    var pageAtmosphereHosted: Bool {
        get { self[PageAtmosphereHostedKey.self] }
        set { self[PageAtmosphereHostedKey.self] = newValue }
    }
}

extension View {
    /// Paints the hosted Page's atmosphere across this view's full bounds and
    /// tells the Page to publish rather than paint. Apply after any leading
    /// inset — the background must span the sidebar's column too. Nothing
    /// paints until a Page publishes, so hosts keep their own ground.
    func pageAtmosphereHost(isActive: Bool = true) -> some View {
        environment(\.pageAtmosphereHosted, isActive)
            .backgroundPreferenceValue(PageAtmospherePreferenceKey.self) { atmosphere in
                if isActive, let atmosphere { PageAtmosphereBackground(atmosphere: atmosphere) }
            }
    }
}
