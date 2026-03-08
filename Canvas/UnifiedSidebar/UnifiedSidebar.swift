// CosmoOS/Canvas/UnifiedSidebar/UnifiedSidebar.swift
// Main sidebar container — premium docked shell with persisted width
// March 2026 — Command Center navigation

import SwiftUI

// MARK: - Navigation Destination

enum SidebarDestination: Equatable, Hashable {
    case commandCenter
    case inbox
    case thinkspace(id: String)
    case dimension(LevelDimension)
}

extension SidebarDestination {
    var dimension: LevelDimension? {
        if case .dimension(let dimension) = self {
            return dimension
        }
        return nil
    }

    var isDimension: Bool {
        dimension != nil
    }
}

// MARK: - Sidebar Metrics

enum UnifiedSidebarMetrics {
    static let defaultExpandedWidth: CGFloat = 304
    static let minExpandedWidth: CGFloat = 288
    static let maxExpandedWidth: CGFloat = 336
    static let collapsedWidth: CGFloat = 56

    static let headerHeight: CGFloat = 52
    static let footerHeight: CGFloat = 52

    static let expandedOuterPadding: CGFloat = 12
    static let collapsedOuterPadding: CGFloat = 8
    static let contentVerticalPadding: CGFloat = 12
    static let moduleSpacing: CGFloat = 16
    static let modulePaddingExpanded: CGFloat = 12
    static let modulePaddingCollapsed: CGFloat = 6

    static let moduleRadius: CGFloat = 12
    static let rowRadius: CGFloat = 10

    static let commandPillHeight: CGFloat = 34
    static let standardRowHeight: CGFloat = 40
    static let thinkspaceRowHeight: CGFloat = 36
    static let dimensionRowHeight: CGFloat = 32
    static let railHitTarget: CGFloat = 32
    static let iconSize: CGFloat = 16
    static let resizeHandleWidth: CGFloat = 8

    static func clampedExpandedWidth(_ width: CGFloat) -> CGFloat {
        min(max(width, minExpandedWidth), maxExpandedWidth)
    }
}

// MARK: - Shared Sidebar Chrome

struct UnifiedSidebarSectionCard<Content: View>: View {
    let isCollapsed: Bool
    let content: Content

    init(isCollapsed: Bool, @ViewBuilder content: () -> Content) {
        self.isCollapsed = isCollapsed
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .padding(isCollapsed ? UnifiedSidebarMetrics.modulePaddingCollapsed : UnifiedSidebarMetrics.modulePaddingExpanded)
        .background(
            RoundedRectangle(cornerRadius: UnifiedSidebarMetrics.moduleRadius, style: .continuous)
                .fill(DS.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: UnifiedSidebarMetrics.moduleRadius, style: .continuous)
                .stroke(DS.border, lineWidth: 1)
        )
        .dsRestingShadow()
    }
}

private struct UnifiedSidebarRowChromeModifier: ViewModifier {
    let isActive: Bool
    let isHovered: Bool
    let cornerRadius: CGFloat
    let activeFill: Color
    let hoverFill: Color
    let activeBorder: Color

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isActive ? activeFill : (isHovered ? hoverFill : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(isActive ? activeBorder : Color.clear, lineWidth: 1)
            )
    }
}

extension View {
    func unifiedSidebarRowChrome(
        isActive: Bool,
        isHovered: Bool,
        cornerRadius: CGFloat = UnifiedSidebarMetrics.rowRadius,
        activeFill: Color = DS.accentSoft,
        hoverFill: Color = DS.surfaceHover,
        activeBorder: Color = DS.accent.opacity(0.14)
    ) -> some View {
        modifier(
            UnifiedSidebarRowChromeModifier(
                isActive: isActive,
                isHovered: isHovered,
                cornerRadius: cornerRadius,
                activeFill: activeFill,
                hoverFill: hoverFill,
                activeBorder: activeBorder
            )
        )
    }
}

// MARK: - Unified Sidebar

struct UnifiedSidebar: View {
    @Binding var currentDestination: SidebarDestination
    @ObservedObject var thinkspaceManager: ThinkspaceManager
    @EnvironmentObject var crossDragManager: CrossThinkspaceDragManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage("sidebarCollapsed") private var isCollapsed: Bool = false
    @State private var expandedWidth: CGFloat = UnifiedSidebarMetrics.defaultExpandedWidth
    @State private var hoveredFooterItem: String?
    @State private var hoveredHeaderItem: String?
    @State private var isResizeHandleHovered = false
    @State private var resizeStartWidth: CGFloat?

    private var sidebarWidth: CGFloat {
        isCollapsed ? UnifiedSidebarMetrics.collapsedWidth : expandedWidth
    }

    private var outerPadding: CGFloat {
        isCollapsed
            ? UnifiedSidebarMetrics.collapsedOuterPadding
            : UnifiedSidebarMetrics.expandedOuterPadding
    }

    private var motionAnimation: Animation? {
        reduceMotion ? .easeOut(duration: 0.15) : ProMotionSprings.sidebar
    }

    private var userFirstName: String {
        NSFullUserName().components(separatedBy: " ").first ?? "User"
    }

    private var monogram: String {
        String(userFirstName.prefix(1)).uppercased()
    }

    var body: some View {
        VStack(spacing: 0) {
            sidebarHeader

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: UnifiedSidebarMetrics.moduleSpacing) {
                    UnifiedSidebarSectionCard(isCollapsed: isCollapsed) {
                        SidebarNavSection(
                            currentDestination: $currentDestination,
                            isCollapsed: isCollapsed
                        )
                    }

                    UnifiedSidebarSectionCard(isCollapsed: isCollapsed) {
                        SidebarThinkspaceSection(
                            manager: thinkspaceManager,
                            currentDestination: $currentDestination,
                            isCollapsed: isCollapsed
                        )
                    }

                    UnifiedSidebarSectionCard(isCollapsed: isCollapsed) {
                        SidebarDimensionSection(
                            currentDestination: $currentDestination,
                            isCollapsed: isCollapsed
                        )
                    }
                }
                .padding(.horizontal, outerPadding)
                .padding(.vertical, UnifiedSidebarMetrics.contentVerticalPadding)
            }

            sidebarFooter
        }
        .frame(width: sidebarWidth)
        .background(DS.surface)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(DS.border)
                .frame(width: 1)
        }
        .overlay(alignment: .trailing) {
            if !isCollapsed {
                resizeHandle
            }
        }
        .clipped()
        .animation(motionAnimation, value: isCollapsed)
        .animation(motionAnimation, value: expandedWidth)
        .onAppear {
            let persistedWidth = UnifiedSidebarMetrics.clampedExpandedWidth(
                StatePersistence.shared.getSidebarWidth()
            )
            expandedWidth = persistedWidth
            crossDragManager.sidebarWidth = sidebarWidth
        }
        .onChange(of: isCollapsed) { _, _ in
            crossDragManager.sidebarWidth = sidebarWidth
        }
        .onChange(of: expandedWidth) { _, newWidth in
            let clamped = UnifiedSidebarMetrics.clampedExpandedWidth(newWidth)
            if clamped != newWidth {
                expandedWidth = clamped
                return
            }
            StatePersistence.shared.saveSidebarWidth(clamped)
            if !isCollapsed {
                crossDragManager.sidebarWidth = clamped
            }
        }
    }

    // MARK: - Header

    private var sidebarHeader: some View {
        HStack(spacing: 10) {
            if isCollapsed {
                Button {
                    withAnimation(motionAnimation) {
                        isCollapsed = false
                    }
                } label: {
                    Image("CosmoLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: UnifiedSidebarMetrics.railHitTarget, height: UnifiedSidebarMetrics.railHitTarget)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .help("Expand sidebar (Cmd+\\)")
            } else {
                HStack(spacing: 10) {
                    Button {
                        NotificationCenter.default.post(name: .showCommandPalette, object: nil)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(DS.textSecondary)

                            Text("Search or jump")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(DS.textSecondary)
                                .lineLimit(1)

                            Spacer(minLength: 8)

                            Text("Cmd K")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(DS.textMuted)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(DS.surface, in: Capsule())
                        }
                        .padding(.horizontal, 12)
                        .frame(height: UnifiedSidebarMetrics.commandPillHeight)
                        .background(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(hoveredHeaderItem == "search" ? DS.surfaceHover : DS.surfaceElevated)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .stroke(DS.border, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .onHover { hoveredHeaderItem = $0 ? "search" : nil }
                    .help("Search (Cmd+K)")

                    Button {
                        withAnimation(motionAnimation) {
                            isCollapsed = true
                        }
                    } label: {
                        Image(systemName: "sidebar.left")
                            .contentTransition(.symbolEffect(.replace))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(DS.textSecondary)
                            .frame(width: UnifiedSidebarMetrics.railHitTarget, height: UnifiedSidebarMetrics.railHitTarget)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(hoveredHeaderItem == "collapse" ? DS.surfaceHover : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                    .onHover { hoveredHeaderItem = $0 ? "collapse" : nil }
                    .help("Collapse sidebar (Cmd+\\)")
                }
            }
        }
        .padding(.horizontal, outerPadding)
        .frame(height: UnifiedSidebarMetrics.headerHeight)
    }

    // MARK: - Footer

    private var sidebarFooter: some View {
        HStack(spacing: 10) {
            if isCollapsed {
                Button {
                    NotificationCenter.default.post(
                        name: .showSettings,
                        object: nil
                    )
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(DS.textSecondary)
                        .frame(width: UnifiedSidebarMetrics.railHitTarget, height: UnifiedSidebarMetrics.railHitTarget)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(hoveredFooterItem == "settings" ? DS.surfaceHover : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .onHover { hoveredFooterItem = $0 ? "settings" : nil }
                .help("Settings")
            } else {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(DS.accentSoft)
                        .frame(width: 32, height: 32)
                        .overlay(
                            Text(monogram)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundColor(DS.accent)
                        )

                    Text(userFirstName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(DS.text)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Button {
                        NotificationCenter.default.post(
                            name: .showSettings,
                            object: nil
                        )
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(DS.textSecondary)
                            .frame(width: UnifiedSidebarMetrics.railHitTarget, height: UnifiedSidebarMetrics.railHitTarget)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(hoveredFooterItem == "settings" ? DS.surfaceHover : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                    .onHover { hoveredFooterItem = $0 ? "settings" : nil }
                    .help("Settings")
                }
                .padding(.horizontal, 12)
                .frame(height: 40)
                .background(
                    RoundedRectangle(cornerRadius: UnifiedSidebarMetrics.moduleRadius, style: .continuous)
                        .fill(DS.surfaceElevated)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: UnifiedSidebarMetrics.moduleRadius, style: .continuous)
                        .stroke(DS.border, lineWidth: 1)
                )
                .dsRestingShadow()
            }
        }
        .padding(.horizontal, outerPadding)
        .frame(height: UnifiedSidebarMetrics.footerHeight)
    }

    // MARK: - Resize Handle

    private var resizeHandle: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: UnifiedSidebarMetrics.resizeHandleWidth)
            .contentShape(Rectangle())
            .overlay(alignment: .center) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(isResizeHandleHovered ? DS.borderActive : DS.borderSubtle)
                    .frame(width: 2, height: 52)
                    .opacity(isResizeHandleHovered || resizeStartWidth != nil ? 1 : 0.5)
                    .padding(.trailing, 2)
            }
            .onHover { hovering in
                isResizeHandleHovered = hovering
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if resizeStartWidth == nil {
                            resizeStartWidth = expandedWidth
                        }

                        guard let startWidth = resizeStartWidth else { return }
                        expandedWidth = UnifiedSidebarMetrics.clampedExpandedWidth(
                            startWidth + value.translation.width
                        )
                    }
                    .onEnded { _ in
                        resizeStartWidth = nil
                    }
            )
    }
}
