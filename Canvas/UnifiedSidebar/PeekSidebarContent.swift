// CosmoOS/Canvas/UnifiedSidebar/PeekSidebarContent.swift
// Collapsed rail content for peek sidebar overlay
// Reuses existing collapsed UI from SidebarNavSection & SidebarThinkspaceSection

import SwiftUI

struct PeekSidebarContent: View {
    @Binding var currentDestination: SidebarDestination
    @ObservedObject var thinkspaceManager: ThinkspaceManager

    var body: some View {
        VStack(spacing: 0) {
            peekHeader
                .frame(height: UnifiedSidebarMetrics.headerHeight)

            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    UnifiedSidebarSection(isCollapsed: true, showsDivider: true) {
                        SidebarNavSection(
                            currentDestination: $currentDestination,
                            isCollapsed: true
                        )
                    }

                    UnifiedSidebarSection(isCollapsed: true, showsDivider: false) {
                        SidebarThinkspaceSection(
                            manager: thinkspaceManager,
                            currentDestination: $currentDestination,
                            isCollapsed: true
                        )
                    }
                }
                .padding(.horizontal, UnifiedSidebarMetrics.collapsedOuterPadding)
                .padding(.vertical, UnifiedSidebarMetrics.contentVerticalPadding)
            }
            .scrollIndicators(.hidden)

            peekFooter
                .frame(height: UnifiedSidebarMetrics.footerHeight)
        }
    }

    private var peekHeader: some View {
        Image("CosmoLogo")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: UnifiedSidebarMetrics.railHitTarget, height: UnifiedSidebarMetrics.railHitTarget)
            .frame(maxWidth: .infinity)
    }

    private var peekFooter: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(DS.glassBorder)
                .frame(height: 0.5)
                .padding(.horizontal, UnifiedSidebarMetrics.collapsedOuterPadding)

            Button("Settings", systemImage: "gearshape") {
                NotificationCenter.default.post(name: .showSettings, object: nil)
            }
            .labelStyle(.iconOnly)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(DS.textSecondary)
            .frame(width: UnifiedSidebarMetrics.railHitTarget, height: UnifiedSidebarMetrics.railHitTarget)
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .frame(height: UnifiedSidebarMetrics.footerHeight)
        }
    }
}
