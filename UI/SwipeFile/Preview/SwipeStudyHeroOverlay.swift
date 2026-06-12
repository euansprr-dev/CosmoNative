import SwiftUI

struct SwipeStudyHero: Equatable {
    let model: SwipeCardModel
    let sourceFrame: CGRect?
}

/// The zoom-through into Swipe Study: the clicked card's media expands toward the
/// window while the focus layer mounts above it (MainView's notification swap),
/// so card → panel → studio reads as one continuous outward motion. Purely
/// decorative — it never intercepts clicks and is removed once the study is opaque.
struct SwipeStudyHeroOverlay: View {
    let hero: SwipeStudyHero
    let expanded: Bool

    var body: some View {
        GeometryReader { proxy in
            let full = CGRect(origin: .zero, size: proxy.size)
            let collapsed = hero.sourceFrame ?? full.insetBy(
                dx: proxy.size.width * 0.06,
                dy: proxy.size.height * 0.06
            )
            let frame = expanded ? full : collapsed

            ZStack(alignment: .topLeading) {
                DS.swipeLibraryBackground
                    .opacity(expanded ? 1 : 0)
                    .ignoresSafeArea()

                heroMedia
                    .frame(width: frame.width, height: frame.height)
                    .clipShape(RoundedRectangle(cornerRadius: expanded ? 0 : 14, style: .continuous))
                    .position(x: frame.midX, y: frame.midY)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var heroMedia: some View {
        if hero.model.aspect == .paper {
            Text(hero.model.paperText ?? hero.model.hookText)
                .font(DS.body)
                .foregroundStyle(DS.textSecondary)
                .lineSpacing(4)
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(DS.glassSectionFill)
        } else {
            CachedAsyncImage(url: hero.model.mediaURL, stableKey: hero.model.mediaStableKey) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .empty, .failure:
                    Rectangle().fill(DS.glassSectionFill)
                }
            }
        }
    }
}
