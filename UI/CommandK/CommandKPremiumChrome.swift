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
}

enum CommandKPreviewPaper {
    static var fill: Color { Color.white }
    static var text: Color { DS.documentText }
    static var textSecondary: Color { DS.documentTextSecondary }
    static var textMuted: Color { DS.documentTextMuted }
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
        ZStack {
            background
            visualMotif
        }
        .accessibilityLabel(identity.title)
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: scale == .rail ? 8 : DS.radiusMedium, style: .continuous)
            .fill(accent.opacity(scale == .rail ? 0.10 : 0.08))
            .overlay(
                RoundedRectangle(cornerRadius: scale == .rail ? 8 : DS.radiusMedium, style: .continuous)
                    .strokeBorder(accent.opacity(0.24), lineWidth: scale.strokeWidth)
            )
    }

    @ViewBuilder
    private var visualMotif: some View {
        switch identity.style {
        case .browser:
            browserMotif
        case .swipeFile:
            swipeMotif
        case .cosmo:
            cosmoMotif
        default:
            defaultMotif
        }
    }

    private var browserMotif: some View {
        VStack(spacing: scale == .rail ? 3 : DS.space12) {
            RoundedRectangle(cornerRadius: scale == .rail ? 2 : 5, style: .continuous)
                .fill(accent.opacity(0.18))
                .frame(height: scale == .rail ? 5 : 16)
                .overlay(alignment: .leading) {
                    Circle()
                        .fill(accent.opacity(0.38))
                        .frame(width: scale == .rail ? 2 : 5, height: scale == .rail ? 2 : 5)
                        .padding(.leading, scale == .rail ? 4 : 10)
                }

            Image(systemName: identity.symbolName)
                .font(.system(size: scale.iconSize, weight: .semibold))
                .foregroundStyle(accent)

            if scale == .detail {
                Text(identity.badge)
                    .font(DS.smallCaps)
                    .foregroundStyle(accent.opacity(0.78))
            }
        }
        .padding(scale == .rail ? 5 : DS.space20)
    }

    private var swipeMotif: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: scale == .rail ? 4 : 10, style: .continuous)
                    .fill(index == 2 ? accent.opacity(0.18) : CommandKPreviewPaper.fill.opacity(0.72))
                    .overlay(
                        RoundedRectangle(cornerRadius: scale == .rail ? 4 : 10, style: .continuous)
                            .strokeBorder(accent.opacity(0.18), lineWidth: scale.strokeWidth)
                    )
                    .frame(
                        width: scale == .rail ? 20 : 86,
                        height: scale == .rail ? 28 : 116
                    )
                    .offset(
                        x: CGFloat(index - 1) * (scale == .rail ? 4 : 16),
                        y: CGFloat(1 - index) * (scale == .rail ? 2 : 7)
                    )
            }

            Image(systemName: identity.symbolName)
                .font(.system(size: scale.iconSize, weight: .bold))
                .foregroundStyle(accent)
        }
        .padding(scale == .rail ? 4 : DS.space20)
    }

    private var cosmoMotif: some View {
        ZStack {
            Circle()
                .stroke(accent.opacity(0.22), lineWidth: scale == .rail ? 1 : 2)
                .frame(width: scale == .rail ? 28 : 116, height: scale == .rail ? 28 : 116)

            Circle()
                .fill(accent.opacity(0.10))
                .frame(width: scale == .rail ? 22 : 88, height: scale == .rail ? 22 : 88)

            Image(systemName: identity.symbolName)
                .font(.system(size: scale.iconSize, weight: .semibold))
                .foregroundStyle(accent)

            if scale == .detail {
                Image(systemName: "rectangle.split.2x1")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(accent.opacity(0.72))
                    .offset(x: 50, y: 42)
            }
        }
        .padding(scale == .rail ? 4 : DS.space20)
    }

    private var defaultMotif: some View {
        VStack(spacing: scale == .rail ? 0 : DS.space10) {
            Image(systemName: identity.symbolName)
                .font(.system(size: scale.iconSize, weight: .semibold))
                .foregroundStyle(accent)

            if scale == .detail {
                Text(identity.badge)
                    .font(DS.smallCaps)
                    .foregroundStyle(accent.opacity(0.78))
            }
        }
        .padding(scale == .rail ? 4 : DS.space20)
    }
}

struct CommandKActionVisualPreview: View {
    let action: CommandKAction
    let identity: CommandKVisualIdentity

    var body: some View {
        ZStack {
            DS.vellum

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
        case .swipeFile:
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
        case .document, .commandCenter, .domain, .app, .search:
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
                    .stroke(isActive ? activeBorder : DS.sepiaSubtle, lineWidth: 0.5)
            )
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
                        isSelected ? DS.gilt.opacity(0.4) : (isHovered ? DS.sepiaBorder : DS.sepiaSubtle),
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
    func body(content: Content) -> some View {
        CosmoGlassPanel(
            sceneMaterial: .neutral,
            role: .globalSidebar,
            cornerRadius: CommandKMetrics.searchBarHeight / 2
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

                Button(role: .destructive) {
                    Task { try? await AtomRepository.shared.delete(uuid: uuid) }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    func commandKSectionChrome(
        cornerRadius: CGFloat = CommandKMetrics.sectionCornerRadius
    ) -> some View {
        modifier(CommandKSectionModifier(cornerRadius: cornerRadius))
    }

    func cortexSearchBarPanel() -> some View {
        modifier(CortexSearchBarPanelModifier())
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
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }
}
