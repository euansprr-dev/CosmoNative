// CosmoOS/Canvas/UnifiedSidebar/UnifiedSidebar.swift
// Main sidebar container — 260pt expanded, 48pt icon rail collapsed
// March 2026 — Command Center navigation

import SwiftUI

// MARK: - Navigation Destination

enum SidebarDestination: Equatable, Hashable {
    case commandCenter
    case inbox
    case thinkspace(id: String)
}

// MARK: - Unified Sidebar

struct UnifiedSidebar: View {
    @Binding var currentDestination: SidebarDestination
    @ObservedObject var thinkspaceManager: ThinkspaceManager
    @EnvironmentObject var crossDragManager: CrossThinkspaceDragManager

    @AppStorage("sidebarCollapsed") private var isCollapsed: Bool = false
    @State private var hoveredFooterItem: String?

    private let expandedWidth: CGFloat = 260
    private let collapsedWidth: CGFloat = 48

    private var sidebarWidth: CGFloat {
        isCollapsed ? collapsedWidth : expandedWidth
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            sidebarHeader

            Divider()
                .background(DS.borderSubtle)

            // Scrollable content
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    SidebarNavSection(
                        currentDestination: $currentDestination,
                        isCollapsed: isCollapsed
                    )

                    sectionDivider

                    SidebarThinkspaceSection(
                        manager: thinkspaceManager,
                        currentDestination: $currentDestination,
                        isCollapsed: isCollapsed
                    )

                    sectionDivider

                    SidebarDimensionSection(
                        isCollapsed: isCollapsed
                    )
                }
                .padding(.vertical, 8)
            }

            Divider()
                .background(DS.borderSubtle)

            // Footer
            sidebarFooter
        }
        .frame(width: sidebarWidth)
        .background(DS.surface)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(DS.border)
                .frame(width: 1)
        }
        .clipped()
        .animation(ProMotionSprings.sidebar, value: isCollapsed)
        .onChange(of: isCollapsed) { _, collapsed in
            crossDragManager.sidebarWidth = collapsed ? collapsedWidth : expandedWidth
        }
        .onAppear {
            crossDragManager.sidebarWidth = sidebarWidth
        }
    }

    // MARK: - Header

    private var sidebarHeader: some View {
        HStack(spacing: 8) {
            if !isCollapsed {
                Text("CosmoOS")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(DS.text)
                    .transition(.opacity.combined(with: .move(edge: .leading)))

                Spacer()

                // Cmd+K button
                Button {
                    NotificationCenter.default.post(name: CosmoNotification.NodeGraph.openCommandK, object: nil)
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DS.textSecondary)
                        .frame(width: 24, height: 24)
                        .background(DS.surfaceHover, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Search (Cmd+K)")
                .transition(.opacity)
            }

            // Collapse/expand chevron
            Button {
                withAnimation(ProMotionSprings.sidebar) {
                    isCollapsed.toggle()
                }
            } label: {
                Image(systemName: isCollapsed ? "sidebar.right" : "sidebar.left")
                    .contentTransition(.symbolEffect(.replace))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DS.textSecondary)
                    .frame(width: 24, height: 24)
                    .background(
                        (hoveredFooterItem == "collapse") ? DS.surfaceHover : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6)
                    )
            }
            .buttonStyle(.plain)
            .onHover { hoveredFooterItem = $0 ? "collapse" : nil }
            .help(isCollapsed ? "Expand sidebar (Cmd+\\)" : "Collapse sidebar (Cmd+\\)")
        }
        .padding(.horizontal, isCollapsed ? 12 : 16)
        .frame(height: 40)
    }

    // MARK: - Footer

    private var sidebarFooter: some View {
        HStack(spacing: 8) {
            Button {
                NotificationCenter.default.post(
                    name: Notification.Name("openSettings"),
                    object: nil
                )
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(DS.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(
                        (hoveredFooterItem == "settings") ? DS.surfaceHover : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6)
                    )
            }
            .buttonStyle(.plain)
            .onHover { hoveredFooterItem = $0 ? "settings" : nil }
            .help("Settings")

            if !isCollapsed {
                Text(NSFullUserName().components(separatedBy: " ").first ?? "User")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DS.textSecondary)
                    .lineLimit(1)
                    .transition(.opacity.combined(with: .move(edge: .leading)))

                Spacer()
            }
        }
        .padding(.horizontal, isCollapsed ? 10 : 16)
        .frame(height: 40)
    }

    // MARK: - Divider

    private var sectionDivider: some View {
        Rectangle()
            .fill(DS.borderSubtle)
            .frame(height: 1)
            .padding(.horizontal, isCollapsed ? 8 : 16)
            .padding(.vertical, 4)
    }
}
