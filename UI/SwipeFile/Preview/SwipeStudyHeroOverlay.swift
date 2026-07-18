import SwiftUI

struct SwipeStudyHero: Equatable {
    let model: SwipeCardModel
    let sourceFrame: CGRect?
}

/// The zoom-through into Swipe Study: the clicked card lifts to a centered,
/// aspect-honest stage panel while the paper covers the library and the focus
/// layer fades in above (MainView's notification swap) — card → stage → studio
/// as one continuous motion, never the raw media cropped across the window.
/// Purely decorative — it never intercepts clicks; the page removes it once
/// the study reports itself on screen (`swipeStudyDidAppear`).
struct SwipeStudyHeroOverlay: View {
    let hero: SwipeStudyHero
    let expanded: Bool

    var body: some View {
        GeometryReader { proxy in
            let stage = SwipeQuickLookGeometry.panelFrame(
                in: proxy.size,
                aspect: hero.model.aspect
            )
            let collapsed = hero.sourceFrame ?? stage
            let frame = expanded ? stage : collapsed

            ZStack(alignment: .topLeading) {
                DS.swipeLibraryBackground
                    .opacity(expanded ? 1 : 0)
                    .ignoresSafeArea()

                heroMedia
                    .frame(width: frame.width, height: frame.height)
                    .clipShape(RoundedRectangle(cornerRadius: expanded ? 20 : 14, style: .continuous))
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
