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
    static let domainCardHeight: CGFloat = 288
    static let recentCardMinWidth: CGFloat = 196
    static let compactMaxHeight: CGFloat = 600
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
