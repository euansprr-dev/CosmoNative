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
        // One compact mark per identity, shared with the sidebar and library.
        // Original symbol artwork inherits the same font metrics as SF Symbols.
        CosmoIdentityChip(
            icon: identity.icon,
            tint: accent,
            size: scale == .rail ? 26 : 44
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                // Never swallow the write with `try?`: a silently-failed delete
                // looked exactly like "sometimes it doesn't move it". Surface it
                // through PersistenceHealth so a real failure is visible.
                Button(role: .destructive) {
                    Task {
                        do {
                            try await AtomRepository.shared.delete(uuid: uuid)
                            await MainActor.run {
                                CosmoUndoManager.shared.registerAtomDeletion(
                                    uuid: uuid, actionDescription: "Delete Item"
                                )
                            }
                        } catch {
                            PersistenceHealth.note(
                                .writeFailure,
                                context: "commandK.moveToRecentlyDeleted",
                                detail: "\(uuid.prefix(8)): \(error)"
                            )
                        }
                    }
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
