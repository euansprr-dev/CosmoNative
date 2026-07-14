import SwiftUI

// MARK: - Card surface

/// Card surface for the rebuilt swipe surfaces: warm glass fill, a barely-there
/// neutral wash, focus-aware hairline, and ONE static resting shadow. Hover reads
/// through the border + tint + the caller's 1.01 scale — shadow parameters never
/// animate (re-blurring hundreds of cards was the old grid's biggest GPU cost).
/// The wash is deliberately neutral for every card: identity colors belong on
/// identity surfaces (quick look header), never sprayed across a grid.
struct SwipeCardSurfaceModifier: ViewModifier {
    var isHovered = false
    var isSelected = false
    var tint: Color = DS.entitySwipe
    var cornerRadius: CGFloat = 14

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let isDark = DS.palette.isDark
        return content
            .background(tint.opacity(isHovered ? 0.07 : 0.04), in: shape)
            .background(DS.glassCardFill, in: shape)
            .clipShape(shape)
            .overlay(
                shape.strokeBorder(
                    isSelected ? DS.accent.opacity(0.55) : (isHovered ? DS.glassBorderFocused : DS.glassBorder),
                    lineWidth: isSelected ? 2 : (isHovered ? 1 : 0.5)
                )
            )
            .shadow(color: .black.opacity(isDark ? 0.28 : 0.05), radius: isDark ? 5 : 10, x: 0, y: 2)
    }
}

extension View {
    func swipeCardSurface(
        isHovered: Bool = false,
        isSelected: Bool = false,
        tint: Color = DS.entitySwipe,
        cornerRadius: CGFloat = 14
    ) -> some View {
        modifier(SwipeCardSurfaceModifier(
            isHovered: isHovered,
            isSelected: isSelected,
            tint: tint,
            cornerRadius: cornerRadius
        ))
    }
}

// MARK: - Masthead (the editorial page voice)

/// A bare page title (the masthead law): counts are never masthead marginalia
/// — they live in shelf headers and the context pill. `detail` is reserved
/// for a rare load-bearing editorial line, never data.
struct SwipeMasthead: View {
    let title: String
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(DS.pageTitle)
                .foregroundStyle(DS.text)
            if let detail {
                Text(detail)
                    .font(DS.dateSerif)
                    .foregroundStyle(DS.giltMuted)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(ProMotionSprings.gentle, value: detail)
            }
        }
    }
}

// MARK: - Context pill (orientation never dies)

/// Blurs in at the top when the masthead scrolls away — the large-title→inline
/// collapse in the swipe surfaces' grammar. Tap scrolls home.
struct SwipeContextPill: View {
    let title: String
    var detail: String?
    let visible: Bool
    let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Text(title)
                    .font(DS.subheadline.weight(.semibold))
                    .foregroundStyle(DS.text)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(DS.caption.monospacedDigit())
                        .foregroundStyle(DS.textMuted)
                        .contentTransition(.numericText())
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 30)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular, in: .capsule)
        .opacity(visible ? 1 : 0)
        .blur(radius: visible || reduceMotion ? 0 : 8)
        .offset(y: visible ? 0 : -6)
        .animation(ProMotionSprings.gentle, value: visible)
        .allowsHitTesting(visible)
        .help("Back to top")
        .accessibilityLabel("\(title). Scrolls back to the top.")
        .accessibilityHidden(!visible)
    }
}

// MARK: - Section header (the one header voice)

/// Small-caps gilt label + live muted monospaced count + hairline rule.
struct SwipeSectionHeader: View {
    let label: String
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(DS.smallCaps)
                .foregroundStyle(DS.giltMuted)
            Text("\(count)")
                .font(DS.caption.monospacedDigit())
                .foregroundStyle(DS.textMuted)
                .contentTransition(.numericText())
            Rectangle()
                .fill(DS.glassBorder)
                .frame(height: 0.5)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Content measure

extension View {
    /// The catalog measure: swipe page content never runs edge-to-edge on wide
    /// displays — margins grow with the window, the grid stays a readable column.
    func swipeContentMeasure() -> some View {
        frame(maxWidth: 1180, alignment: .leading)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - Shelf (the App Store row)

/// Live shelf scroll geometry, stored outside observation — continuous scrolling
/// never invalidates the view tree; only the can-page threshold crossings do.
private final class SwipeShelfScrollMetrics {
    var rawOffsetX: CGFloat = 0
    var normalizedOffsetX: CGFloat = 0
    var viewportWidth: CGFloat = 0
    var contentWidth: CGFloat = 0
}

/// The App Store row shell: section-voice header with a docked "See All ›",
/// horizontal view-aligned scroller whose clip bounds extend past the measure
/// (shadows and hover lift never get guillotined at the column edge), and bare
/// paging chevrons that live in the page margins — hover-revealed, washed out
/// when a direction is unavailable.
struct SwipeShelfRow<Content: View>: View {
    let label: String
    var count: Int?
    var onSeeAll: (() -> Void)?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            header
            SwipeShelfScroller(content: content)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            SwipeSectionHeader(label: label, count: count ?? 0)
            if let onSeeAll {
                Button(action: onSeeAll) {
                    HStack(spacing: 3) {
                        Text("See All")
                            .font(DS.caption.weight(.medium))
                        Image(systemName: "chevron.right")
                            .font(DS.caption2.weight(.semibold))
                    }
                    .foregroundStyle(DS.textSecondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("See all")
                .accessibilityLabel("See all \(label.lowercased())")
            }
        }
    }
}

/// The shelf's scroller, header-agnostic — the view-aligned horizontal
/// scroller with the outset clip and the hover-revealed margin chevrons.
/// SwipeShelfRow wraps it in the small-caps header voice; the Ideas surface
/// pairs it with the editorial CosmoShelfHeader.
struct SwipeShelfScroller<Content: View>: View {
    @ViewBuilder let content: () -> Content

    /// How far the clip boundary extends past the measure column — sized for
    /// shadows only (radius 10 / y 2 + the 1.01 hover lift), so no readable
    /// card sliver ever renders into the gutter where the arrows live.
    private let clipOutset: CGFloat = 14
    private let verticalOutset: CGFloat = 12
    /// Arrows sit fully beyond the clip boundary, over clean page background.
    private var arrowOffset: CGFloat { clipOutset + 4 + arrowWidth }
    private let arrowWidth: CGFloat = 28
    /// The hit box runs from the glyph's outer edge all the way back to the
    /// shelf boundary, so the pointer never crosses dead space that would drop
    /// the hover and hide the arrow before it can be clicked.
    private var arrowHitWidth: CGFloat { arrowOffset }

    @State private var scrollPosition = ScrollPosition()
    @State private var isHovering = false
    @State private var isHoveringArrow = false
    @State private var canPageBack = false
    @State private var canPageForward = false
    @State private var metrics = SwipeShelfScrollMetrics()

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 14) {
                content()
            }
            .padding(.vertical, verticalOutset)
            .scrollTargetLayout()
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { metrics.contentWidth = $0 }
        }
        .scrollPosition($scrollPosition)
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.never)
        .contentMargins(.horizontal, clipOutset, for: .scrollContent)
        .onScrollGeometryChange(for: SwipeShelfScrollState.self, of: { geo in
            SwipeShelfScrollState(
                rawOffset: geo.contentOffset.x,
                normalizedOffset: geo.contentOffset.x + geo.contentInsets.leading,
                viewport: geo.containerSize.width - geo.contentInsets.leading - geo.contentInsets.trailing
            )
        }) { _, new in
            metrics.rawOffsetX = new.rawOffset
            metrics.normalizedOffsetX = new.normalizedOffset
            metrics.viewportWidth = new.viewport
            let back = new.normalizedOffset > 4
            let forward = new.normalizedOffset + new.viewport < metrics.contentWidth - 4
            if back != canPageBack { canPageBack = back }
            if forward != canPageForward { canPageForward = forward }
        }
        .padding(.horizontal, -clipOutset)
        .padding(.vertical, -verticalOutset)
        .overlay(alignment: .leading) {
            pagingChevron("chevron.compact.left", canPage: canPageBack) { page(-1) }
                .offset(x: -arrowOffset)
        }
        .overlay(alignment: .trailing) {
            pagingChevron("chevron.compact.right", canPage: canPageForward) { page(1) }
                .offset(x: arrowOffset)
        }
        .onHover { isHovering = $0 }
        .onDisappear {
            isHovering = false
            isHoveringArrow = false
        }
    }

    /// Tall thin chevrons in the margins — the App Store grammar. Washed out
    /// (never hidden) when the direction is unavailable, invisible until hover.
    /// The glyph hugs the outer edge of a hit box that spans the full shelf
    /// height and reaches back into the shelf, and each arrow tracks its own
    /// hover — the shelf's hover region ends at the clip boundary, so without
    /// this the arrow would vanish the moment the pointer reached it.
    private func pagingChevron(_ icon: String, canPage: Bool, action: @escaping () -> Void) -> some View {
        let isLeft = icon.contains("left")
        let visible = isHovering || isHoveringArrow
        return Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(DS.textSecondary)
                .frame(width: arrowWidth)
                .frame(maxHeight: .infinity)
                .frame(width: arrowHitWidth, alignment: isLeft ? .leading : .trailing)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(visible ? (canPage ? 0.9 : 0.22) : 0)
        .animation(ProMotionSprings.hover, value: visible)
        .animation(ProMotionSprings.hover, value: canPage)
        .allowsHitTesting(canPage)
        .onHover { isHoveringArrow = $0 }
        .help(isLeft ? "Previous" : "Next")
        .accessibilityLabel(isLeft ? "Scroll back" : "Scroll forward")
        .accessibilityHidden(!visible)
    }

    private func page(_ direction: CGFloat) {
        let step = direction * metrics.viewportWidth * 0.9
        let maxRaw = metrics.rawOffsetX + (metrics.contentWidth - metrics.normalizedOffsetX - metrics.viewportWidth)
        let minRaw = metrics.rawOffsetX - metrics.normalizedOffsetX
        let target = max(minRaw, min(maxRaw, metrics.rawOffsetX + step))
        withAnimation(ProMotionSprings.focusTransition) {
            scrollPosition.scrollTo(x: target)
        }
    }
}

private struct SwipeShelfScrollState: Equatable {
    let rawOffset: CGFloat
    let normalizedOffset: CGFloat
    let viewport: CGFloat
}

/// Card-typed shelf: uniform poster cards whose cells record their frames so
/// shelf cards open the shared quick look with thumbnail continuity.
struct SwipeShelf: View {
    let label: String
    var count: Int?
    var onSeeAll: (() -> Void)?
    let models: [SwipeCardModel]
    var cardWidth: CGFloat = 200
    var hiddenItemID: String?
    var frameStore: SwipeFrameStore?
    let actions: (SwipeCardModel) -> SwipeCardActions

    var body: some View {
        SwipeShelfRow(label: label, count: count ?? models.count, onSeeAll: onSeeAll) {
            ForEach(models) { model in
                cell(model)
            }
        }
    }

    private func cell(_ model: SwipeCardModel) -> some View {
        SwipeCard(model: model, width: cardWidth, actions: actions(model))
            .opacity(hiddenItemID == model.id ? 0 : 1)
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named("swipePage")) }) { frame in
                frameStore?.frames[model.id] = frame
            }
    }
}

// MARK: - Hero card (the one editorial moment per page)

/// The App Store featured-card grammar: editorial text column beside the media
/// at its TRUE aspect ratio — a reel is a tall 9:16 panel, never a landscape
/// crop. The whole card triggers the primary CTA; Preview is the one inner
/// button and records the media panel's frame so the quick look zooms out of it.
struct SwipeHeroCard: View {
    let kicker: String
    let model: SwipeCardModel
    let ctaLabel: String
    var ctaIcon: String = "play.fill"
    var onPreview: (() -> Void)?
    var frameStore: SwipeFrameStore?
    let action: () -> Void

    @State private var isHovered = false
    @State private var previewHovered = false

    private var isPaper: Bool { model.aspect == .paper }
    private let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
    private static let cardHeight: CGFloat = 300
    private static let inset: CGFloat = 12

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: DS.space20) {
                textColumn
                    .padding(.leading, 24)
                    .padding(.vertical, 24)
                Spacer(minLength: DS.space12)
                mediaPanel
                    .padding(Self.inset)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: Self.cardHeight)
            .background(DS.entitySwipe.opacity(0.04), in: shape)
            .background(DS.glassCardFill, in: shape)
            .clipShape(shape)
            .overlay(shape.strokeBorder(DS.glassBorder, lineWidth: 0.5))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(isHovered ? 0.09 : 0.05), radius: isHovered ? 16 : 10, x: 0, y: isHovered ? 5 : 2)
        .scaleEffect(isHovered ? 1.005 : 1)
        .animation(ProMotionSprings.hover, value: isHovered)
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(kicker). \(model.hookText). \(ctaLabel)")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Text column

    private var textColumn: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            Text(kicker)
                .font(DS.smallCaps)
                .foregroundStyle(DS.giltMuted)
            // A hero hook is content, so it speaks serif — the paired
            // `heroTitleSerif` voice the iPhone's Up Next hero ships.
            Text(model.hookText)
                .font(DS.heroTitleSerif)
                .foregroundStyle(DS.text)
                .lineSpacing(2)
                .lineLimit(4)
                .frame(maxWidth: 560, alignment: .leading)
            metaLine
            if let support = supportingExcerpt {
                // The body excerpt fills what was dead air between the hook
                // and the CTA — the card earns its height.
                Text(support)
                    .font(DS.subheadline)
                    .foregroundStyle(DS.textSecondary)
                    .lineSpacing(3)
                    .lineLimit(4)
                    .frame(maxWidth: 560, alignment: .leading)
            }
            Spacer(minLength: 0)
            ctaRow
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    /// The swipe's own text beyond the hook — shown only when it says
    /// something new (paper cards already show it in the media panel).
    private var supportingExcerpt: String? {
        guard !isPaper, let text = model.paperText else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != model.hookText else { return nil }
        return trimmed
    }

    private var metaLine: some View {
        HStack(spacing: 6) {
            SwipePlatformGlyph(source: model.platformKey)
                .frame(width: 11, height: 11)
            if let creator = model.creatorLine {
                Text(creator)
                    .font(DS.caption)
                    .lineLimit(1)
            }
            if let age = model.ageLabel {
                // The "·" is a separator between TEXT tokens — with no
                // creator line it read as an orphaned "· 6h" after the glyph.
                Text(model.creatorLine == nil ? age : "· \(age)")
                    .font(DS.caption)
            }
        }
        .foregroundStyle(DS.textMuted)
    }

    private var ctaRow: some View {
        HStack(spacing: DS.space8) {
            // Rendered as a label — the whole card is this button.
            HStack(spacing: 7) {
                Image(systemName: ctaIcon)
                    .font(DS.caption.weight(.bold))
                Text(ctaLabel)
                    .font(DS.callout.weight(.semibold))
            }
            .foregroundStyle(DS.textOnAccent)
            .padding(.horizontal, 16)
            .frame(height: 34)
            .background(DS.accent, in: Capsule())

            if let onPreview {
                Button(action: onPreview) {
                    Text("Preview")
                        .font(DS.callout.weight(.medium))
                        .foregroundStyle(previewHovered ? DS.text : DS.textSecondary)
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .background(Capsule().fill(previewHovered ? DS.glassInputFillFocused : DS.glassInputFill))
                        .overlay(Capsule().strokeBorder(DS.glassBorder, lineWidth: 0.5))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .onHover { value in withAnimation(ProMotionSprings.hover) { previewHovered = value } }
                .help("Quick look (Space)")
                .accessibilityLabel("Preview")
            }
        }
    }

    // MARK: Media panel (honest aspect)

    private var panelSize: CGSize {
        let maxHeight = Self.cardHeight - Self.inset * 2
        switch model.aspect {
        case .vertical: return CGSize(width: (maxHeight * 9 / 16).rounded(), height: maxHeight)
        case .portrait: return CGSize(width: (maxHeight * 4 / 5).rounded(), height: maxHeight)
        case .wide: return CGSize(width: 380, height: (380.0 * 9 / 16).rounded())
        case .paper: return CGSize(width: 300, height: maxHeight)
        }
    }

    @ViewBuilder
    private var mediaPanel: some View {
        let size = panelSize
        Group {
            if isPaper {
                Text(model.paperText ?? model.hookText)
                    .font(DS.callout)
                    .foregroundStyle(DS.textSecondary)
                    .lineSpacing(4)
                    .padding(16)
                    .frame(width: size.width, height: size.height, alignment: .topLeading)
                    .background(DS.glassSectionFill)
            } else {
                CachedAsyncImage(url: model.mediaURL, stableKey: model.mediaStableKey) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .empty, .failure:
                        Rectangle().fill(DS.glassSectionFill)
                    }
                }
                .frame(width: size.width, height: size.height)
                .clipped()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named("swipePage")) }) { frame in
            frameStore?.frames[model.id] = frame
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Board cover mosaic (shared by the Boards hub and the Home shelf)

struct SwipeBoardMosaic: View {
    let coverItems: [SwipeCardModel]
    let icon: String
    var height: CGFloat = 148

    private let gutter: CGFloat = 2

    private var tileHeight: CGFloat { (height - gutter) / 2 }

    var body: some View {
        GeometryReader { proxy in
            let cell = (proxy.size.width - gutter) / 2
            VStack(spacing: gutter) {
                HStack(spacing: gutter) {
                    tile(0, size: cell)
                    tile(1, size: cell)
                }
                HStack(spacing: gutter) {
                    tile(2, size: cell)
                    tile(3, size: cell)
                }
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func tile(_ index: Int, size: CGFloat) -> some View {
        if index < coverItems.count, coverItems[index].mediaURL != nil || coverItems[index].aspect == .paper {
            mosaicCell(coverItems[index], size: size)
        } else {
            Rectangle()
                .fill(DS.glassSectionFill)
                .frame(width: size, height: tileHeight)
                .overlay {
                    if index == 0 && coverItems.isEmpty {
                        Image(systemName: icon)
                            .font(DS.subheadline)
                            .foregroundStyle(DS.textMuted)
                    }
                }
        }
    }

    private func mosaicCell(_ model: SwipeCardModel, size: CGFloat) -> some View {
        Group {
            if model.aspect == .paper {
                Rectangle()
                    .fill(DS.glassSectionFill)
                    .overlay {
                        Text(model.hookText)
                            .font(DS.caption2)
                            .foregroundStyle(DS.textMuted)
                            .lineLimit(3)
                            .padding(6)
                    }
            } else {
                CachedAsyncImage(url: model.mediaURL, stableKey: model.mediaStableKey) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .empty, .failure:
                        Rectangle().fill(DS.glassSectionFill)
                    }
                }
            }
        }
        .frame(width: size, height: tileHeight)
        .clipped()
    }
}

// MARK: - Page background

struct SwipePageBackground: View {
    var body: some View {
        DS.swipeLibraryBackground
            .ignoresSafeArea()
    }
}

// MARK: - Platform brand color

extension SocialPlatform {
    /// Brand color for the tiny platform glyph — the single sanctioned place the
    /// swipe surfaces use non-DS hex. These are external brand identities that
    /// can't map to Greenhouse tokens; all other chrome uses warm DS.
    var swipeBrandColor: Color {
        switch self {
        case .instagram: return Color(hex: "#E1306C")
        case .youtube: return Color(hex: "#E0322B")
        case .linkedin: return Color(hex: "#0A66C2")
        case .facebook: return Color(hex: "#1877F2")
        case .substack: return Color(hex: "#E06A38")
        case .tiktok, .x, .twitter, .threads, .medium: return Color(hex: "#1C1C20")
        case .other: return DS.textMuted
        }
    }

    /// Maps the library's string platform keys (atom metadata) onto the shared enum.
    static func fromLibraryKey(_ key: String?) -> SocialPlatform? {
        switch key {
        case "youtube", "youtubeShort", "youtube_short": return .youtube
        case "instagram", "instagramPost", "instagram_post",
             "instagramReel", "instagram_reel",
             "instagramCarousel", "instagram_carousel": return .instagram
        case "xPost", "x_post", "twitter": return .x
        case "threads": return .threads
        case "tiktok": return .tiktok
        case "linkedin": return .linkedin
        case "substack": return .substack
        default: return nil
        }
    }
}

// MARK: - Formatting

enum SwipeFormatting {
    static func count(_ value: Int) -> String {
        let absValue = abs(value)
        if absValue >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }
        if absValue >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }
        return "\(value)"
    }

    /// "17h", "2d", "3w" — the quiet age stamp on card meta rows.
    static func compactAge(from date: Date, relativeTo now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(max(minutes, 1))m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        let days = hours / 24
        if days < 7 { return "\(days)d" }
        let weeks = days / 7
        if weeks < 5 { return "\(weeks)w" }
        let months = days / 30
        if months < 12 { return "\(max(months, 1))mo" }
        return "\(days / 365)y"
    }

    static func duration(seconds: Int) -> String {
        let minutes = seconds / 60
        let remainder = seconds % 60
        return String(format: "%d:%02d", minutes, remainder)
    }

    /// Engagement rate stored either pre-multiplied (6.4 → "6.4%") or as a raw
    /// fraction (0.064 → "6.4%"); both provider conventions render correctly.
    static func engagementRate(_ rate: Double) -> String {
        let pct = rate < 1 ? rate * 100 : rate
        return String(format: "%.1f%%", pct)
    }
}
