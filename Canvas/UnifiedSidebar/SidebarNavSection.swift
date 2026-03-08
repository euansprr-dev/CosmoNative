// CosmoOS/Canvas/UnifiedSidebar/SidebarNavSection.swift
// Command Center + Inbox navigation rows
// March 2026 — Command Center navigation

import SwiftUI

struct SidebarNavSection: View {
    @Binding var currentDestination: SidebarDestination
    let isCollapsed: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var hoveredItem: String?

    private var actionAnimation: Animation? {
        reduceMotion ? .easeOut(duration: 0.15) : ProMotionSprings.snappy
    }

    var body: some View {
        VStack(spacing: isCollapsed ? 8 : 6) {
            navRow(
                id: "commandCenter",
                icon: "hexagon",
                label: "Command Center",
                destination: .commandCenter,
                badge: nil
            )
            .contextMenu {
                Button {
                    NotificationCenter.default.post(
                        name: CosmoNotification.Navigation.openAsPane,
                        object: nil,
                        userInfo: ["commandCenter": true]
                    )
                } label: {
                    Label("Open as Pane", systemImage: "rectangle.split.2x1")
                }
            }

            navRow(
                id: "inbox",
                icon: "tray",
                label: "Inbox",
                destination: .inbox,
                badge: inboxUnreadCount
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Nav Row

    private func navRow(
        id: String,
        icon: String,
        label: String,
        destination: SidebarDestination,
        badge: Int?
    ) -> some View {
        let isActive = currentDestination == destination
        let isHovered = hoveredItem == id

        return Button {
            withAnimation(actionAnimation) {
                currentDestination = destination
            }
        } label: {
            Group {
                if isCollapsed {
                    collapsedRowContent(
                        icon: icon,
                        isActive: isActive,
                        badge: badge,
                        isHovered: isHovered
                    )
                } else {
                    expandedRowContent(
                        icon: icon,
                        label: label,
                        isActive: isActive,
                        badge: badge,
                        isHovered: isHovered
                    )
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hoveredItem = $0 ? id : nil }
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    @ViewBuilder
    private func expandedRowContent(
        icon: String,
        label: String,
        isActive: Bool,
        badge: Int?,
        isHovered: Bool
    ) -> some View {
        let activeIcon = icon == "hexagon" ? icon : "\(icon).fill"

        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isActive ? DS.accent.opacity(0.14) : DS.surface)

                Image(systemName: isActive ? activeIcon : icon)
                    .font(.system(size: UnifiedSidebarMetrics.iconSize, weight: .medium))
                    .foregroundColor(isActive ? DS.accent : DS.textSecondary)
            }
            .frame(width: 32, height: 32)

            Text(label)
                .font(.system(size: 14, weight: isActive ? .semibold : .medium))
                .foregroundColor(isActive ? DS.text : DS.textSecondary)
                .lineLimit(1)

            Spacer(minLength: 8)

            if let count = badge, count > 0 {
                Text("\(count)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(DS.accent)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(DS.accentSoft, in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(DS.accent.opacity(0.12), lineWidth: 1)
                    )
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: UnifiedSidebarMetrics.standardRowHeight, alignment: .leading)
        .unifiedSidebarRowChrome(isActive: isActive, isHovered: isHovered)
    }

    @ViewBuilder
    private func collapsedRowContent(
        icon: String,
        isActive: Bool,
        badge: Int?,
        isHovered: Bool
    ) -> some View {
        let activeIcon = icon == "hexagon" ? icon : "\(icon).fill"

        ZStack(alignment: .topTrailing) {
            Image(systemName: isActive ? activeIcon : icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(isActive ? DS.accent : DS.textSecondary)
                .frame(
                    width: UnifiedSidebarMetrics.railHitTarget,
                    height: UnifiedSidebarMetrics.railHitTarget
                )
                .unifiedSidebarRowChrome(
                    isActive: isActive,
                    isHovered: isHovered,
                    cornerRadius: 10
                )

            if let count = badge, count > 0 {
                Circle()
                    .fill(DS.accent)
                    .frame(width: 7, height: 7)
                    .offset(x: 2, y: -1)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Inbox Count

    private var inboxUnreadCount: Int? {
        // TODO: Connect to actual inbox data
        nil
    }
}
