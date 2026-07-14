// CosmoOS/UI/CommandK/CommandKPremiumChrome.swift
// Shared Greenhouse chrome for the Command-K overlay

import SwiftUI

enum CommandKMetrics {
    static let overlayCornerRadius: CGFloat = 28
    static let searchBarHeight: CGFloat = 64
    static let tabBarHeight: CGFloat = 44
    static let contentPadding: CGFloat = 24
    static let toolbarSpacing: CGFloat = 12
    static let toolbarChipHeight: CGFloat = 32
    static let toolbarChipRadius: CGFloat = 10
    static let cardCornerRadius: CGFloat = 18
    static let sectionCornerRadius: CGFloat = 18
    static let cardSpacing: CGFloat = 18

    // Cortex mode metrics
    static let compactWidth: CGFloat = 1130
    static let searchWidth: CGFloat = 1120
    static let expandedWidth: CGFloat = 1120
    static let compactSearchWidth: CGFloat = 680
    static let expandedSearchWidth: CGFloat = 760
    static let domainBubbleSize: CGFloat = 56
    static let domainCardWidth: CGFloat = 244
    static let domainCardHeight: CGFloat = 196
    static let recentCardMinWidth: CGFloat = 196
    static let compactMaxHeight: CGFloat = 600
    static let railWidth: CGFloat = 360

    // Expanded-domain masthead title placement
    static let mastheadTitleLeadingWide: CGFloat = 46
    static let mastheadTitleLeadingTight: CGFloat = 34
    static let mastheadTitleTopDefault: CGFloat = 42
    static let mastheadTitleTopIdeas: CGFloat = 48
    static let mastheadDatabaseTitleTop: CGFloat = 36
}

/// The ⌘K preview register. Light themes read as honest paper: white page,
/// document ink, parchment swipe panels. Dark chrome flips the WHOLE register
/// to dark surfaces + light ink — document ink typeset on the dark pane was
/// unreadable, and white micro-pages / parchment panels glowed against the
/// dark palette. Fill and text tokens must always be swapped as a pair.
enum CommandKPreviewPaper {
    private static var darkChrome: Bool { DS.usesImmersiveFocusAppearance }

    static var fill: Color { darkChrome ? DS.surfaceCard : Color.white }
    static var text: Color { darkChrome ? DS.text : DS.documentText }
    static var textSecondary: Color { darkChrome ? DS.textSecondary : DS.documentTextSecondary }
    static var textMuted: Color { darkChrome ? DS.textMuted : DS.documentTextMuted }

    /// Swipe-preview chrome: parchment panel with a recessed vellum stage in
    /// light themes; elevated dark surface over the page background in dark.
    static var panelFill: Color { darkChrome ? DS.surfaceElevated : DS.vellum }
    static var stageFill: Color { darkChrome ? DS.bg : DS.vellumDeep }
    static var hairline: Color { darkChrome ? DS.border : DS.sepiaSubtle }
}

enum CommandKExpandedLayout {
    static func panelHeight(forAvailableHeight availableHeight: CGFloat) -> CGFloat {
        min(max(availableHeight - 180, 540), 860)
    }
}

enum CommandKAnimationPolicy {
    static let maxEntranceAnimationItems = 24
    static let entranceBaseDelay: TimeInterval = 0.018

    static func entranceAnimation(
        index: Int,
        limit: Int = maxEntranceAnimationItems,
        baseDelay: TimeInterval = entranceBaseDelay
    ) -> Animation? {
        guard index >= 0, index < limit else { return nil }
        return ProMotionSprings.cardEntrance.delay(Double(index) * baseDelay)
    }
}

enum CommandKDomainTransitionPolicy {
    static let browserMountDelay: TimeInterval = 0.16
    static let dataHydrationDelay: TimeInterval = 0.20
    static let collapseCommitDelay: TimeInterval = 0.07
    static let closeNotificationDelay: TimeInterval = 0.26
}

enum CommandKIconVisualScale {
    case rail
    case detail

    var iconSize: CGFloat {
        switch self {
        case .rail: return 18
        case .detail: return 52
        }
    }

    var strokeWidth: CGFloat {
        switch self {
        case .rail: return 0.5
        case .detail: return 0.8
        }
    }
}

struct CommandKIconVisualTile: View {
    let identity: CommandKVisualIdentity
    let accent: Color
    var scale: CommandKIconVisualScale = .rail

    var body: some View {
        Group {
            switch identity.style {
            // The honest miniatures stay — they're object identity already.
            case .swipeFile:
                CommandKSwipeReelMotif(accent: accent, scale: scale)
            case .swipeShelf:
                CommandKSwipeShelfMotif(accent: accent, scale: scale)
            case .swipeGalleryPage:
                CommandKSwipeGalleryPageMotif(accent: accent, scale: scale)
            // Everything else: the compact identity chip (Raycast's register)
            // — solid tint, small white glyph. The old pastel wash + big
            // filled symbol read bulky.
            default:
                CosmoIdentityChip(
                    systemName: identity.symbolName,
                    tint: accent,
                    size: scale == .rail ? 26 : 44
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .accessibilityLabel(identity.title)
    }
}

// MARK: - Favicon (URL-backed rows carry their site's own mark)

/// Raycast's trick: a URL-backed row shows the site's favicon, not a type
/// glyph. DuckDuckGo's icon service over Google s2 (less tracking surface);
/// any failure falls back to the caller-provided identity mark.
struct CommandKFavicon<Fallback: View>: View {
    let host: String
    var size: CGFloat = 26
    @ViewBuilder var fallback: () -> Fallback

    var body: some View {
        CachedAsyncImage(
            url: URL(string: "https://icons.duckduckgo.com/ip3/\(host).ico"),
            stableKey: "favicon-\(host)"
        ) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
            case .empty, .failure:
                fallback()
            }
        }
    }
}

// MARK: - Swipe motifs (the swipe-card grammar in miniature)

/// Shared ink for the swipe miniatures. A swipe is media with the hook
/// riding a bottom scrim — the same grammar as the real cards on both
/// platforms, so the motif is an honest miniature, not an icon collage.
private enum CommandKSwipeMotifInk {
    static let media = Color(white: 0.24)
    static let mediaDeep = Color(white: 0.10)
    static let hookLine = Color.white.opacity(0.85)
    static let hookLineSoft = Color.white.opacity(0.48)
    static let playWash = Color.white.opacity(0.20)

    static var mediaFill: LinearGradient {
        LinearGradient(colors: [media, mediaDeep], startPoint: .top, endPoint: .bottom)
    }
}

/// One miniature reel card: dark media, bottom hook lines, optional play seal.
private struct CommandKMiniReelCard: View {
    let accent: Color
    let width: CGFloat
    let height: CGFloat
    var hookLines: Int = 2
    var showsPlay: Bool = false

    private var cornerRadius: CGFloat { max(3, height * 0.09) }

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(CommandKSwipeMotifInk.mediaFill)
            .overlay(alignment: .bottomLeading) { hookScrim }
            .overlay { if showsPlay { playSeal } }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(accent.opacity(0.28), lineWidth: 0.5)
            )
            .frame(width: width, height: height)
    }

    private var hookScrim: some View {
        VStack(alignment: .leading, spacing: max(1.5, height * 0.03)) {
            ForEach(0..<hookLines, id: \.self) { line in
                Capsule(style: .continuous)
                    .fill(line == 0 ? CommandKSwipeMotifInk.hookLine : CommandKSwipeMotifInk.hookLineSoft)
                    .frame(width: width * (line == 0 ? 0.62 : 0.4), height: max(1.5, height * 0.032))
            }
        }
        .padding(.leading, width * 0.14)
        .padding(.bottom, height * 0.1)
    }

    private var playSeal: some View {
        Circle()
            .fill(CommandKSwipeMotifInk.playWash)
            .frame(width: height * 0.26, height: height * 0.26)
            .overlay(
                Image(systemName: "play.fill")
                    .font(.system(size: height * 0.11, weight: .bold))
                    .foregroundStyle(CommandKSwipeMotifInk.hookLine)
                    .offset(x: height * 0.012)
            )
            .offset(y: -height * 0.08)
    }
}

/// A single swipe: one reel card, the honest object.
struct CommandKSwipeReelMotif: View {
    let accent: Color
    let scale: CommandKIconVisualScale

    var body: some View {
        CommandKMiniReelCard(
            accent: accent,
            width: scale == .rail ? 24 : 64,
            height: scale == .rail ? 38 : 104,
            showsPlay: true
        )
        .padding(scale == .rail ? 4 : DS.space16)
    }
}

/// Browse Swipes: a masonry shelf — three staggered reel cards, the thing
/// you actually flick through inside Command-K.
struct CommandKSwipeShelfMotif: View {
    let accent: Color
    let scale: CommandKIconVisualScale

    private var cardWidth: CGFloat { scale == .rail ? 8.5 : 38 }
    private var heights: [CGFloat] {
        scale == .rail ? [28, 38, 23] : [80, 104, 66]
    }

    var body: some View {
        HStack(alignment: .top, spacing: scale == .rail ? 2 : DS.space8) {
            CommandKMiniReelCard(accent: accent, width: cardWidth, height: heights[0], hookLines: 1)
            CommandKMiniReelCard(
                accent: accent,
                width: cardWidth,
                height: heights[1],
                showsPlay: scale == .detail
            )
            CommandKMiniReelCard(accent: accent, width: cardWidth, height: heights[2], hookLines: 1)
        }
        .padding(scale == .rail ? 4 : DS.space16)
    }
}

/// Open Swipe Gallery: the full-screen page in miniature — a paper sheet
/// with its masthead and a two-column masonry inside.
struct CommandKSwipeGalleryPageMotif: View {
    let accent: Color
    let scale: CommandKIconVisualScale

    private var pageWidth: CGFloat { scale == .rail ? 30 : 118 }
    private var pageHeight: CGFloat { scale == .rail ? 42 : 106 }
    private var inset: CGFloat { scale == .rail ? 3 : 9 }
    private var gutter: CGFloat { scale == .rail ? 2 : 6 }

    var body: some View {
        VStack(alignment: .leading, spacing: gutter) {
            masthead
            masonryColumns
        }
        .padding(inset)
        .frame(width: pageWidth, height: pageHeight)
        .background(
            RoundedRectangle(cornerRadius: scale == .rail ? 4 : 10, style: .continuous)
                .fill(CommandKPreviewPaper.fill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: scale == .rail ? 4 : 10, style: .continuous)
                .strokeBorder(accent.opacity(0.28), lineWidth: 0.5)
        )
        .padding(scale == .rail ? 4 : DS.space16)
    }

    private var masthead: some View {
        HStack(spacing: gutter) {
            Image(systemName: "bolt.fill")
                .font(.system(size: scale == .rail ? 3.5 : 7, weight: .semibold))
                .foregroundStyle(accent)
            Capsule(style: .continuous)
                .fill(accent.opacity(0.30))
                .frame(width: pageWidth * 0.34, height: scale == .rail ? 1.5 : 3.5)
            Spacer(minLength: 0)
        }
    }

    private var masonryColumns: some View {
        let cardWidth = (pageWidth - inset * 2 - gutter) / 2
        let tall = pageHeight * 0.36
        let short = pageHeight * 0.23
        return HStack(alignment: .top, spacing: gutter) {
            VStack(spacing: gutter) {
                CommandKMiniReelCard(accent: accent, width: cardWidth, height: tall, hookLines: 1)
                CommandKMiniReelCard(accent: accent, width: cardWidth, height: short, hookLines: 1)
            }
            VStack(spacing: gutter) {
                CommandKMiniReelCard(accent: accent, width: cardWidth, height: short, hookLines: 1)
                CommandKMiniReelCard(accent: accent, width: cardWidth, height: tall, hookLines: 1)
            }
        }
    }
}

struct CommandKActionVisualPreview: View {
    let action: CommandKAction
    let identity: CommandKVisualIdentity

    var body: some View {
        ZStack {
            VStack(spacing: DS.space16) {
                CommandKIconVisualTile(identity: identity, accent: accent, scale: .detail)
                    .frame(width: 188, height: 148)

                VStack(spacing: DS.space4) {
                    Text(identity.title)
                        .font(DS.headline)
                        .foregroundStyle(DS.text)
                    Text(surfaceLabel)
                        .font(DS.caption)
                        .foregroundStyle(DS.textMuted)
                }
            }
        }
    }

    private var surfaceLabel: String {
        switch action.kind {
        case .openCosmoPane:
            return "Open as pane"
        case .openCosmoWindow:
            return "Open as floating window"
        case .openBrowser:
            return "Open as browser pane"
        case .openSwipeGallery:
            return "Open All Swipes full screen"
        case .captureSwipe, .captureSwipeWithIdea:
            return "Capture to Swipe File"
        case .openDomain:
            return "Open Command-K place"
        default:
            return action.subtitle ?? identity.subtitle
        }
    }

    private var accent: Color {
        switch identity.style {
        case .swipeFile, .swipeShelf, .swipeGalleryPage:
            return DS.entitySwipe
        case .cosmo:
            return DS.gilt
        case .browser, .research:
            return DS.entityResearch
        case .idea:
            return DS.entityIdea
        case .task:
            return DS.entityTask
        case .content:
            return DS.entityContent
        case .connection, .thinkspace:
            return DS.entityConnection
        case .image:
            return DS.entityImage
        case .readwise:
            return DS.entityReadwise
        case .document, .commandCenter, .domain, .app, .search, .calculator:
            return DS.accent
        }
    }
}

private struct CommandKToolbarChipModifier: ViewModifier {
    let isActive: Bool
    let activeFill: Color
    let activeBorder: Color
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .frame(height: CommandKMetrics.toolbarChipHeight)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isActive ? activeFill : DS.vellum)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(isActive ? activeBorder : DS.commandChromeSeparator, lineWidth: 0.5)
            )
    }
}

struct CommandKSectionLabel: View {
    let label: String
    /// Live count — every section header carries one (the surfaces law);
    /// ticks with `.numericText()` as results settle.
    var count: Int? = nil

    var body: some View {
        HStack(spacing: DS.space8) {
            Text(label)
                .font(DS.smallCaps)
                .tracking(1.6)
                .foregroundStyle(DS.commandCenterOrnamentText)
                .fixedSize()
            if let count {
                Text("\(count)")
                    .font(DS.caption2.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(DS.textMuted)
                    .contentTransition(.numericText())
            }
            Rectangle()
                .fill(DS.commandChromeSeparatorStrong)
                .frame(height: 0.5)
                .frame(maxWidth: .infinity)
                .padding(.leading, DS.space4)
        }
    }
}

private struct CommandKToolbarGroupModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(DS.glassCardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(DS.glassBorder, lineWidth: 0.5)
            )
    }
}

private struct CommandKGalleryCardModifier: ViewModifier {
    let isHovered: Bool
    let isSelected: Bool
    let accentColor: Color
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(DS.glassCardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isSelected ? accentColor.opacity(0.05) : Color.clear)
                    .allowsHitTesting(false)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        isSelected ? DS.gilt.opacity(0.4) : (isHovered ? DS.commandChromeSeparatorStrong : DS.commandChromeSeparator),
                        lineWidth: 0.5
                    )
                    .allowsHitTesting(false)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(
                color: .black.opacity(isHovered ? 0.07 : 0.04),
                radius: isHovered ? 20 : 8,
                x: 0,
                y: isHovered ? 6 : 2
            )
            .shadow(
                color: .black.opacity(isHovered ? 0.04 : 0.02),
                radius: isHovered ? 6 : 2,
                x: 0,
                y: isHovered ? 2 : 1
            )
    }
}

private struct CommandKSectionModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(DS.glassCardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(DS.glassBorder, lineWidth: 0.5)
            )
            .dsRestingShadow()
    }
}

private struct CortexSearchBarPanelModifier: ViewModifier {
    var glassID: String?
    var glassNamespace: Namespace.ID?

    func body(content: Content) -> some View {
        CosmoGlassPanel(
            role: .globalSidebar,
            cornerRadius: CommandKMetrics.searchBarHeight / 2,
            glassID: glassID,
            glassNamespace: glassNamespace
        ) {
            content
        }
    }
}

extension View {
    func commandKToolbarChip(
        isActive: Bool = false,
        activeFill: Color = DS.accentSoft,
        activeBorder: Color = DS.accent.opacity(0.18),
        cornerRadius: CGFloat = CommandKMetrics.toolbarChipRadius
    ) -> some View {
        modifier(
            CommandKToolbarChipModifier(
                isActive: isActive,
                activeFill: activeFill,
                activeBorder: activeBorder,
                cornerRadius: cornerRadius
            )
        )
    }

    func commandKToolbarGroup(
        cornerRadius: CGFloat = CommandKMetrics.toolbarChipRadius
    ) -> some View {
        modifier(CommandKToolbarGroupModifier(cornerRadius: cornerRadius))
    }

    func commandKGalleryCardChrome(
        isHovered: Bool,
        isSelected: Bool,
        accentColor: Color,
        cornerRadius: CGFloat = CommandKMetrics.cardCornerRadius
    ) -> some View {
        modifier(
            CommandKGalleryCardModifier(
                isHovered: isHovered,
                isSelected: isSelected,
                accentColor: accentColor,
                cornerRadius: cornerRadius
            )
        )
    }

    /// Context menu for search results (uses atomUUID, no entityId)
    func commandKSearchResultContextMenu(result: UnifiedSearchResult) -> some View {
        self.contextMenu {
            if let uuid = result.atomUUID {
                Button {
                    if result.resultKind == .thinkspace, let tid = result.thinkspaceId {
                        NotificationCenter.default.post(
                            name: CosmoNotification.Navigation.navigateToThinkspaceById,
                            object: nil,
                            userInfo: CosmoNotification.Navigation.ThinkspacePayload(thinkspaceId: tid).userInfo
                        )
                        NotificationCenter.default.post(name: CosmoNotification.NodeGraph.closeCommandK, object: nil)
                    } else {
                        NotificationCenter.default.post(
                            name: CosmoNotification.NodeGraph.openAtomFromCommandK,
                            object: nil, userInfo: ["atomUUID": uuid]
                        )
                        NotificationCenter.default.post(name: CosmoNotification.NodeGraph.hideCommandK, object: nil)
                    }
                } label: {
                    Label("Open in Focus Mode", systemImage: "arrow.up.left.and.arrow.down.right")
                }

                Button {
                    Task {
                        if let atom = try? await AtomRepository.shared.fetch(uuid: uuid),
                           let entityType = EntityType(rawValue: atom.type.rawValue) {
                            NotificationCenter.default.post(
                                name: CosmoNotification.Navigation.openAsPane,
                                object: nil,
                                userInfo: ["type": entityType, "id": atom.id ?? 0]
                            )
                        }
                        NotificationCenter.default.post(name: CosmoNotification.NodeGraph.closeCommandK, object: nil)
                    }
                } label: {
                    Label("Open as Pane", systemImage: "rectangle.split.2x1")
                }

                Button {
                    NotificationCenter.default.post(
                        name: CosmoNotification.NodeGraph.addToCanvas,
                        object: nil,
                        userInfo: ["atomUUID": uuid]
                    )
                } label: {
                    Label("Add to Canvas", systemImage: "plus.rectangle.on.rectangle")
                }

                Divider()

                // Soft delete (atoms land in Recently Deleted) — the label
                // says so, Finder-style, instead of a bare "Delete".
                Button(role: .destructive) {
                    Task { try? await AtomRepository.shared.delete(uuid: uuid) }
                } label: {
                    Label("Move to Recently Deleted", systemImage: "trash")
                }
            }
        }
    }

    func commandKSectionChrome(
        cornerRadius: CGFloat = CommandKMetrics.sectionCornerRadius
    ) -> some View {
        modifier(CommandKSectionModifier(cornerRadius: cornerRadius))
    }

    func cortexSearchBarPanel(glassID: String? = nil, in namespace: Namespace.ID? = nil) -> some View {
        modifier(CortexSearchBarPanelModifier(glassID: glassID, glassNamespace: namespace))
    }

    /// Standard right-click menu for any atom card in Command-K
    func commandKCardContextMenu(
        atomUUID: String,
        entityId: Int64,
        atomType: AtomType,
        isThinkspace: Bool = false,
        allowsSpatialGoToObject: Bool = false,
        onDelete: (() -> Void)? = nil
    ) -> some View {
        self.contextMenu {
            Button {
                if isThinkspace {
                    NotificationCenter.default.post(
                        name: CosmoNotification.Navigation.navigateToThinkspaceById,
                        object: nil,
                        userInfo: CosmoNotification.Navigation.ThinkspacePayload(thinkspaceId: atomUUID).userInfo
                    )
                    NotificationCenter.default.post(name: CosmoNotification.NodeGraph.closeCommandK, object: nil)
                } else if let entityType = EntityType(rawValue: atomType.rawValue), entityId > 0 {
                    NotificationCenter.default.post(
                        name: .enterFocusMode,
                        object: nil,
                        userInfo: ["type": entityType, "id": entityId]
                    )
                }
            } label: {
                Label(
                    isThinkspace ? "Open Thinkspace" : "Open in Focus Mode",
                    systemImage: isThinkspace ? "rectangle.3.group" : "arrow.up.left.and.arrow.down.right"
                )
            }

            Button {
                let info: [String: Any] = isThinkspace
                    ? ["thinkspaceId": atomUUID]
                    : ["type": EntityType(rawValue: atomType.rawValue) as Any, "id": entityId]
                NotificationCenter.default.post(
                    name: CosmoNotification.Navigation.openAsPane,
                    object: nil, userInfo: info
                )
                NotificationCenter.default.post(name: CosmoNotification.NodeGraph.closeCommandK, object: nil)
            } label: {
                Label("Open as Pane", systemImage: "rectangle.split.2x1")
            }

            if !isThinkspace && allowsSpatialGoToObject {
                Button {
                    NotificationCenter.default.post(
                        name: CosmoNotification.NodeGraph.goToObjectFromCommandK,
                        object: nil,
                        userInfo: ["atomUUID": atomUUID]
                    )
                    NotificationCenter.default.post(name: CosmoNotification.NodeGraph.hideCommandK, object: nil)
                } label: {
                    Label("Go to Object", systemImage: "scope")
                }

                Button {
                    NotificationCenter.default.post(
                        name: CosmoNotification.NodeGraph.addToCanvas,
                        object: nil,
                        userInfo: ["atomUUID": atomUUID]
                    )
                } label: {
                    Label("Add to Canvas", systemImage: "plus.rectangle.on.rectangle")
                }
            }

            if let onDelete {
                Divider()
                Button(role: .destructive, action: onDelete) {
                    Label("Move to Recently Deleted", systemImage: "trash")
                }
            }
        }
    }
}
