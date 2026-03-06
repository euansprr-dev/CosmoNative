// CosmoOS/Canvas/UnifiedSidebar/SidebarNavSection.swift
// Command Center + Inbox navigation rows
// March 2026 — Command Center navigation

import SwiftUI

struct SidebarNavSection: View {
    @Binding var currentDestination: SidebarDestination
    let isCollapsed: Bool

    @State private var hoveredItem: String?

    var body: some View {
        VStack(spacing: 2) {
            navRow(
                id: "commandCenter",
                icon: "hexagon",
                label: "Command Center",
                destination: .commandCenter,
                badge: nil
            )

            navRow(
                id: "inbox",
                icon: "tray",
                label: "Inbox",
                destination: .inbox,
                badge: inboxUnreadCount
            )
        }
        .padding(.horizontal, isCollapsed ? 6 : 12)
        .padding(.vertical, 4)
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
            withAnimation(ProMotionSprings.snappy) {
                currentDestination = destination
            }
        } label: {
            HStack(spacing: 0) {
                // Active indicator — 3pt accent left border
                if !isCollapsed {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(isActive ? DS.accent : Color.clear)
                        .frame(width: 3, height: 20)
                        .padding(.trailing, 8)
                }

                let activeIcon = (icon == "hexagon") ? icon : icon + ".fill"
                Image(systemName: isActive ? activeIcon : icon)
                    .font(.system(size: isCollapsed ? 16 : 14, weight: .medium))
                    .foregroundColor(isActive ? DS.accent : DS.textSecondary)
                    .frame(width: isCollapsed ? 32 : 20, height: isCollapsed ? 32 : 20)

                if !isCollapsed {
                    Text(label)
                        .font(.system(size: 13, weight: isActive ? .semibold : .medium))
                        .foregroundColor(isActive ? DS.text : DS.textSecondary)
                        .padding(.leading, 8)
                        .transition(.opacity.combined(with: .move(edge: .leading)))

                    Spacer()

                    // Badge
                    if let count = badge, count > 0 {
                        Text("\(count)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(DS.accent, in: Capsule())
                            .transition(.opacity.combined(with: .scale))
                    }
                } else {
                    // Badge dot in collapsed mode
                    if let count = badge, count > 0 {
                        Circle()
                            .fill(DS.accent)
                            .frame(width: 6, height: 6)
                            .offset(x: -4, y: -10)
                    }
                }
            }
            .padding(.horizontal, isCollapsed ? 0 : 8)
            .padding(.vertical, isCollapsed ? 4 : 6)
            .frame(maxWidth: .infinity, alignment: isCollapsed ? .center : .leading)
            .background(
                RoundedRectangle(cornerRadius: DS.radiusSmall)
                    .fill(isActive
                          ? DS.accent.opacity(0.10)
                          : (isHovered ? DS.surfaceHover : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hoveredItem = $0 ? id : nil }
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    // MARK: - Inbox Count

    private var inboxUnreadCount: Int? {
        // TODO: Connect to actual inbox data
        nil
    }
}
