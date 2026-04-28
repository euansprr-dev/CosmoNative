// CosmoOS/Canvas/UnifiedSidebar/SidebarThinkspaceSection.swift
// Thinkspace list with project folders, keyboard nav, creation flow
// Migrated from ThinkspaceSidebar.swift patterns
// March 2026 — Command Center navigation

import SwiftUI

// MARK: - Sidebar Thinkspace Section

private struct ThinkspaceInquirySidebarSummary: Equatable {
    var activeSessionCount: Int = 0
    var questionCount: Int = 0
    var sourceCount: Int = 0
    var claimCount: Int = 0
    var conceptCount: Int = 0
    var outputCount: Int = 0
    var unmappedCount: Int = 0

    var hasVisibleSignal: Bool {
        activeSessionCount + questionCount + sourceCount + claimCount + conceptCount + outputCount + unmappedCount > 0
    }

    var compactLabel: String {
        if unmappedCount > 0 { return "\(unmappedCount)" }
        if activeSessionCount > 0 { return "\(activeSessionCount)" }
        return "\(questionCount + sourceCount + claimCount)"
    }
}

struct SidebarThinkspaceSection: View {
    @ObservedObject var manager: ThinkspaceManager
    @Binding var currentDestination: SidebarDestination
    let isCollapsed: Bool
    var onNavigate: () -> Void = {}
    @EnvironmentObject var crossDragManager: CrossThinkspaceDragManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Data
    @State private var projects: [Atom] = []
    @State private var selectedProjectFilter: String? = nil

    // Creation
    @State private var isCreatingThinkspace = false
    @State private var creatingChildOfThinkspace: Thinkspace?
    @State private var newName = ""
    @FocusState private var isNameFieldFocused: Bool

    // Hover
    @State private var hoveredThinkspaceId: String?
    @State private var hoveredChildDocId: String?

    // Rename
    @State private var renamingThinkspaceId: String?
    @State private var renameText: String = ""
    @FocusState private var isRenameFieldFocused: Bool

    // Child docs expand
    @State private var expandedThinkspaces: Set<String> = []
    @State private var expandedCanvasItemGroups: Set<String> = []
    @State private var childDocsLoading: Set<String> = []
    @State private var inquirySummaries: [String: ThinkspaceInquirySidebarSummary] = [:]

    // Keyboard
    @State private var selectedIndex: Int = 0
    @State private var isKeyboardNavigating: Bool = false
    @FocusState private var isSectionFocused: Bool

    private let repository = AtomRepository.shared

    private let projectColorPalette = [
        "#A8CCE8", "#CAB8E8", "#F4AFA0", "#8FC7A2",
        "#F5E6C8", "#E8B8A8", "#A8D8E8", "#D8A8E8",
    ]

    private var hoverAnimation: Animation? {
        reduceMotion ? .easeOut(duration: 0.15) : ProMotionSprings.hover
    }

    private var actionAnimation: Animation? {
        reduceMotion ? .easeOut(duration: 0.15) : ProMotionSprings.snappy
    }

    // MARK: - Filtered Thinkspaces

    private var filteredThinkspaces: [Thinkspace] {
        if let projectId = selectedProjectFilter {
            return manager.rootThinkspacesForProject(projectId)
        }
        return manager.sidebarThinkspaces
            .filter { $0.parentThinkspaceId == nil }
            .sorted { $0.lastOpened > $1.lastOpened }
    }

    // MARK: - Navigable Items

    private var allNavigableItems: [ThinkspaceNavigatorItem] {
        var items: [ThinkspaceNavigatorItem] = []
        for thinkspace in filteredThinkspaces {
            appendNavigationItems(from: thinkspace, level: 0, into: &items)
        }
        return items
    }

    // MARK: - Active Thinkspace ID

    private var activeThinkspaceId: String? {
        if case .thinkspace(let id) = currentDestination {
            return id
        }
        return nil
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: isCollapsed ? 10 : 12) {
            sectionHeader

            if isCollapsed {
                collapsedThinkspaceStack
            } else {
                if !projects.isEmpty {
                    filterChipsRow
                }

                if isCreatingThinkspace && creatingChildOfThinkspace == nil {
                    newThinkspaceRow
                }

                thinkspaceList
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .focused($isSectionFocused)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.downArrow) { guard !isCollapsed else { return .ignored }; handleKeyDown(); return .handled }
        .onKeyPress(.upArrow) { guard !isCollapsed else { return .ignored }; handleKeyUp(); return .handled }
        .onKeyPress(.return) {
            guard !isCollapsed, !isCreatingThinkspace else { return .ignored }
            handleKeyReturn(); return .handled
        }
        .onKeyPress(.escape) { guard !isCollapsed else { return .ignored }; handleKeyEscape(); return .handled }
        .onKeyPress(.rightArrow) { guard !isCollapsed else { return .ignored }; handleKeyRight(); return .handled }
        .onKeyPress(.leftArrow) { guard !isCollapsed else { return .ignored }; handleKeyLeft(); return .handled }
        .task { await loadProjects() }
        .onReceive(NotificationCenter.default.publisher(for: .atomsDidChange)) { _ in
            Task {
                await loadProjects()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .sidebarCreateThinkspace)) { _ in
            withAnimation(actionAnimation) {
                isCreatingThinkspace = true
                creatingChildOfThinkspace = nil
                newName = ""
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isNameFieldFocused = true
            }
        }
        .onPreferenceChange(ThinkspaceRowFrameKey.self) { frames in
            crossDragManager.thinkspaceRowFrames = frames
        }
    }

    // MARK: - Section Header

    private var sectionHeader: some View {
        HStack(spacing: 6) {
            if isCollapsed {
                Image(systemName: "rectangle.3.group")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(DS.textSecondary)
                    .frame(width: UnifiedSidebarMetrics.railHitTarget, height: UnifiedSidebarMetrics.railHitTarget)
                    .frame(maxWidth: .infinity)
            } else {
                Text("Thinkspaces")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.text)

                Spacer()

                createThinkspaceButton
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Filter Chips Row

    private var filterChipsRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                filterChip(label: "All", color: DS.accent, isSelected: selectedProjectFilter == nil) {
                    withAnimation(actionAnimation) {
                        selectedProjectFilter = nil
                    }
                }

                ForEach(projects, id: \.uuid) { project in
                    let color = projectColor(for: project)
                    filterChip(
                        label: project.title ?? "Untitled",
                        color: color,
                        isSelected: selectedProjectFilter == project.uuid
                    ) {
                        withAnimation(actionAnimation) {
                            selectedProjectFilter = project.uuid
                        }
                    }
                    .contextMenu {
                        Button {
                            Task { await deleteProject(project) }
                        } label: {
                            Label("Delete Project", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .scrollIndicators(.never)
    }

    @ViewBuilder
    private func filterChip(label: String, color: Color, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)

                Text(label)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? color : DS.textSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                Capsule().fill(isSelected ? color.opacity(0.12) : DS.bg)
            )
            .overlay(
                Capsule().stroke(isSelected ? color.opacity(0.22) : DS.borderSubtle, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - New Thinkspace Row

    private var newThinkspaceRow: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(DS.accent.opacity(0.14))
                .frame(width: 28, height: 28)
                .overlay(
                    Image(systemName: "rectangle.3.group")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DS.accent)
                )

            TextField("Name", text: $newName, prompt: Text("Name").foregroundStyle(DS.textMuted))
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DS.text)
                .focused($isNameFieldFocused)
                .onSubmit { createThinkspace() }

            Button("Cancel", systemImage: "xmark") {
                cancelCreateThinkspace()
            }
            .labelStyle(.iconOnly)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(DS.textMuted)
            .frame(width: 24, height: 24)
            .background(DS.bg, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: UnifiedSidebarMetrics.rowRadius, style: .continuous)
                .fill(DS.bg)
                .overlay(
                    RoundedRectangle(cornerRadius: UnifiedSidebarMetrics.rowRadius, style: .continuous)
                        .stroke(DS.accent.opacity(0.22), lineWidth: 1)
                )
        )
        .transition(.asymmetric(
            insertion: .scale(scale: 0.95).combined(with: .opacity),
            removal: .opacity
        ))
    }

    // MARK: - Thinkspace List

    @ViewBuilder
    private var thinkspaceList: some View {
        let items = filteredThinkspaces
        if items.isEmpty {
            thinkspaceEmptyState
        } else {
            VStack(spacing: 6) {
                ForEach(items) { thinkspace in
                    thinkspaceRow(thinkspace, level: 0)
                }
            }
        }
    }

    @ViewBuilder
    private var collapsedThinkspaceStack: some View {
        let items = Array(filteredThinkspaces.prefix(4))

        VStack(spacing: 8) {
            if items.isEmpty {
                EmptyView()
            } else {
                ForEach(items) { thinkspace in
                    thinkspaceRow(thinkspace, level: 0)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func thinkspaceRow(_ thinkspace: Thinkspace, level: Int) -> some View {
        let isActive = activeThinkspaceId == thinkspace.id
        let isHovered = hoveredThinkspaceId == thinkspace.id
        let isExpanded = expandedThinkspaces.contains(thinkspace.id)
        let isRenaming = renamingThinkspaceId == thinkspace.id
        let isDropTarget =
            crossDragManager.isDragging &&
            crossDragManager.isOverSidebar &&
            crossDragManager.hoveredThinkspaceId == thinkspace.id
        let springLoadPulse = crossDragManager.pulseForThinkspace(thinkspace.id)
        let isSpringLoading = springLoadPulse > 0

        return VStack(alignment: .leading, spacing: 0) {
            if isRenaming && !isCollapsed {
                thinkspaceRenameRow(thinkspace)
            } else {
                thinkspaceRowLabel(
                    thinkspace,
                    isActive: isActive,
                    isHovered: isHovered,
                    isExpanded: isExpanded,
                    level: level
                )
            }

            if isExpanded && !isCollapsed {
                childDocsSection(for: thinkspace, level: level)
            }
        }
        .modifier(ThinkspaceRowChrome(
            thinkspaceId: thinkspace.id,
            isActive: isActive,
            isHovered: isHovered,
            isDropTarget: isDropTarget,
            isSpringLoading: isSpringLoading,
            springLoadPulse: springLoadPulse,
            fillColor: thinkspaceRowFill(isActive: isActive, isHovered: isHovered, isDropTarget: isDropTarget)
        ))
        .onHover { hoveredThinkspaceId = $0 ? thinkspace.id : nil }
        .contextMenu {
            thinkspaceContextMenu(thinkspace)
        }
        .animation(hoverAnimation, value: isHovered)
        .animation(hoverAnimation, value: isDropTarget)
        .animation(.linear(duration: 0.08), value: springLoadPulse)
    }

    @ViewBuilder
    private func thinkspaceRowLabel(
        _ thinkspace: Thinkspace,
        isActive: Bool,
        isHovered: Bool,
        isExpanded: Bool,
        level: Int
    ) -> some View {
        let project = projectFor(thinkspace)
        let color = project.map { projectColor(for: $0) } ?? DS.accent
        let isExpandable = thinkspaceIsExpandable(thinkspace)
        let rowHeight = level > 0 ? CGFloat(34) : UnifiedSidebarMetrics.thinkspaceRowHeight
        let textSize = level > 0 ? CGFloat(12) : CGFloat(13)
        let rowLeadingPadding = level > 0 ? CGFloat(0) : CGFloat(8)

        if isCollapsed {
            Button {
                selectThinkspace(thinkspace)
            } label: {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isActive ? DS.accentSoft : Color.clear)
                    .frame(width: UnifiedSidebarMetrics.railHitTarget, height: UnifiedSidebarMetrics.railHitTarget)
                    .overlay(
                        Image(systemName: isActive ? "folder.fill" : "folder")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(isActive ? DS.accent : color)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .help(thinkspace.name)
            .accessibilityLabel(thinkspace.name)
            .accessibilityAddTraits(isActive ? .isSelected : [])
        } else {
            HStack(spacing: 8) {
                if level > 0 {
                    Rectangle()
                        .fill(DS.borderSubtle.opacity(isActive ? 0.78 : 0.56))
                        .frame(width: 10, height: 1)
                }

                thinkspaceAvatarButton(
                    thinkspace,
                    color: color,
                    isActive: isActive,
                    isHovered: isHovered,
                    isExpanded: isExpanded,
                    isExpandable: isExpandable,
                    level: level
                )

                Button {
                    selectThinkspace(thinkspace)
                } label: {
                    HStack(spacing: 8) {
                        Text(thinkspace.name)
                            .font(.system(size: textSize, weight: isActive ? .semibold : .medium))
                            .foregroundStyle(isActive ? DS.text : DS.textSecondary)
                            .lineLimit(1)

                        Spacer()

                        HStack(spacing: 8) {
                            let nestedCount = manager.childThinkspaces(of: thinkspace.id).count
                            if nestedCount > 0 && level == 0 {
                                Label("\(nestedCount)", systemImage: "rectangle.stack")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(DS.textMuted)
                            }

                            Text("\(thinkspace.blockCount)")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(DS.textMuted)
                                .frame(minWidth: 22, alignment: .trailing)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: rowHeight, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, rowLeadingPadding)
            .padding(.trailing, 8)
            .frame(maxWidth: .infinity, minHeight: rowHeight, alignment: .leading)
        }
    }

    @ViewBuilder
    private func thinkspaceAvatarButton(
        _ thinkspace: Thinkspace,
        color: Color,
        isActive: Bool,
        isHovered: Bool,
        isExpanded: Bool,
        isExpandable: Bool,
        level: Int
    ) -> some View {
        let avatarFill = isActive ? DS.accent.opacity(0.14) : color.opacity(0.14)
        let avatarForeground = isActive ? DS.accent : color
        let showsDisclosure = isExpandable && isHovered
        let avatarSize = level > 0 ? CGFloat(22) : CGFloat(24)
        let avatarRadius = level > 0 ? CGFloat(7) : CGFloat(8)

        Button {
            guard isExpandable else { return }
            toggleExpand(thinkspace)
        } label: {
            RoundedRectangle(cornerRadius: avatarRadius, style: .continuous)
                .fill(avatarFill)
                .frame(width: avatarSize, height: avatarSize)
                .overlay {
                    ZStack {
                        Image(systemName: isExpanded ? "folder.fill" : "folder")
                            .font(.system(size: level > 0 ? 11 : 12, weight: .semibold))
                            .foregroundStyle(avatarForeground)
                            .opacity(showsDisclosure ? 0 : 1)
                            .scaleEffect(showsDisclosure ? 0.84 : 1)

                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(avatarForeground)
                            .opacity(showsDisclosure ? 1 : 0)
                            .scaleEffect(showsDisclosure ? 1 : 0.8)
                    }
                    .animation(hoverAnimation, value: showsDisclosure)
                    .animation(hoverAnimation, value: isExpanded)
                }
        }
        .buttonStyle(.plain)
        .disabled(!isExpandable)
        .accessibilityLabel(
            isExpandable
                ? "\(isExpanded ? "Collapse" : "Expand") \(thinkspace.name)"
                : thinkspace.name
        )
        .help(
            isExpandable
                ? (isExpanded ? "Collapse contents" : "Expand contents")
                : thinkspace.name
        )
    }

    // MARK: - Rename Row

    private func thinkspaceRenameRow(_ thinkspace: Thinkspace) -> some View {
        let project = projectFor(thinkspace)
        let color = project.map { projectColor(for: $0) } ?? DS.accent

        return HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(color.opacity(0.14))
                .frame(width: 24, height: 24)
                .overlay(
                    Image(systemName: "folder")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(color)
                )

            TextField("Name", text: $renameText)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DS.text)
                .focused($isRenameFieldFocused)
                .onSubmit { commitRename(thinkspace) }
                .onExitCommand { cancelRename() }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: UnifiedSidebarMetrics.thinkspaceRowHeight, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: UnifiedSidebarMetrics.rowRadius, style: .continuous)
                .fill(DS.bg)
                .overlay(
                    RoundedRectangle(cornerRadius: UnifiedSidebarMetrics.rowRadius, style: .continuous)
                        .stroke(DS.accent.opacity(0.22), lineWidth: 1)
                )
        )
    }

    // MARK: - Child Docs

    @ViewBuilder
    private func childDocsSection(for thinkspace: Thinkspace, level: Int) -> some View {
        let childThinkspaces = manager.childThinkspaces(of: thinkspace.id)
        let isCreatingChild = creatingChildOfThinkspace?.id == thinkspace.id
        let hasChildBranch = isCreatingChild || !childThinkspaces.isEmpty

        HStack(alignment: .top, spacing: 10) {
            Rectangle()
                .fill(DS.borderSubtle)
                .frame(width: 1)

            VStack(alignment: .leading, spacing: 4) {
                if hasChildBranch {
                    childThinkspaceRows(
                        childThinkspaces,
                        parent: thinkspace,
                        level: level
                    )
                }
            }
        }
        .padding(.leading, level == 0 ? 30 : 48)
        .padding(.top, 4)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private func childThinkspaceRows(_ childThinkspaces: [Thinkspace], parent: Thinkspace, level: Int) -> some View {
        if creatingChildOfThinkspace?.id == parent.id {
            childThinkspaceCreationRow(parent: parent, level: level + 1)
        }

        ForEach(childThinkspaces) { childThinkspace in
            AnyView(thinkspaceRow(childThinkspace, level: level + 1))
        }
    }

    @ViewBuilder
    private func parentCanvasItemsGroup(_ docs: [ChildDoc], thinkspace: Thinkspace, level: Int, shouldCollapse: Bool) -> some View {
        if !docs.isEmpty {
            if shouldCollapse {
                canvasItemsDisclosureRow(thinkspace: thinkspace, count: docs.count)

                if expandedCanvasItemGroups.contains(thinkspace.id) {
                    ForEach(docs) { doc in
                        sidebarChildDocRow(doc, level: level + 2)
                    }
                }
            } else {
                ForEach(docs) { doc in
                    sidebarChildDocRow(doc, level: level + 1)
                }
            }
        }
    }

    private var emptyChildState: some View {
        Text("No blocks")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(DS.textMuted)
    }

    private func branchGroupLabel(_ title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .textCase(.uppercase)
                .foregroundStyle(DS.textMuted)

            Text("\(count)")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(DS.textMuted.opacity(0.82))

            Spacer()
        }
        .padding(.leading, 2)
        .padding(.top, 2)
        .frame(maxWidth: .infinity, minHeight: 18, alignment: .leading)
    }

    private func canvasItemsDisclosureRow(thinkspace: Thinkspace, count: Int) -> some View {
        let isExpanded = expandedCanvasItemGroups.contains(thinkspace.id)

        return Button {
            withAnimation(actionAnimation) {
                if isExpanded {
                    expandedCanvasItemGroups.remove(thinkspace.id)
                } else {
                    expandedCanvasItemGroups.insert(thinkspace.id)
                }
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(DS.textMuted)
                    .frame(width: 10)

                Image(systemName: "square.stack.3d.down.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(DS.textMuted)
                    .frame(width: 14)

                Text("\(thinkspace.name) Items")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(1)

                Spacer()

                Text("\(count)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(DS.textMuted)
            }
            .padding(.leading, 2)
            .padding(.trailing, 8)
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(isExpanded ? "Collapse" : "Expand") canvas items in \(thinkspace.name)")
    }

    private func childThinkspaceCreationRow(parent: Thinkspace, level: Int) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(DS.accent.opacity(0.14))
                .frame(width: 22, height: 22)
                .overlay(
                    Image(systemName: "rectangle.stack.badge.plus")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(DS.accent)
                )

            TextField("Child thinkspace name", text: $newName, prompt: Text("Name").foregroundStyle(DS.textMuted))
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DS.text)
                .focused($isNameFieldFocused)
                .onSubmit { createThinkspace() }
                .onExitCommand { cancelCreateThinkspace() }

            Button("Cancel", systemImage: "xmark") {
                cancelCreateThinkspace()
            }
            .labelStyle(.iconOnly)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(DS.textMuted)
            .frame(width: 22, height: 22)
            .background(DS.bg, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .buttonStyle(.plain)
        }
        .padding(.leading, 8 + CGFloat(max(level - 1, 0)) * 18)
        .padding(.trailing, 8)
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(DS.bg)
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(DS.accent.opacity(0.22), lineWidth: 1)
                )
        )
        .transition(.asymmetric(
            insertion: .scale(scale: 0.96).combined(with: .opacity),
            removal: .opacity
        ))
        .accessibilityLabel("Create child Thinkspace under \(parent.name)")
    }

    private func inquiryBadge(_ summary: ThinkspaceInquirySidebarSummary) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "sparkles")
                .font(.system(size: 9, weight: .semibold))
            Text(summary.compactLabel)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(summary.unmappedCount > 0 ? DS.orange : DS.accent)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background((summary.unmappedCount > 0 ? DS.orange : DS.accent).opacity(0.12), in: Capsule())
    }

    private func inquirySections(_ summary: ThinkspaceInquirySidebarSummary) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            sidebarInquiryRow(icon: "rectangle.split.3x1", title: "Active Inquiry", count: summary.activeSessionCount)
            sidebarInquiryRow(icon: "questionmark.bubble", title: "Questions", count: summary.questionCount)
            sidebarInquiryRow(icon: "doc.text.magnifyingglass", title: "Sources", count: summary.sourceCount)
            sidebarInquiryRow(icon: "exclamationmark.bubble", title: "Claims", count: summary.claimCount)
            sidebarInquiryRow(icon: "point.3.connected.trianglepath.dotted", title: "Concepts", count: summary.conceptCount)
            sidebarInquiryRow(icon: "paperplane", title: "Outputs", count: summary.outputCount)
            sidebarInquiryRow(icon: "tray.and.arrow.down", title: "Unmapped", count: summary.unmappedCount, tint: summary.unmappedCount > 0 ? DS.orange : DS.textMuted)
        }
        .padding(.vertical, 3)
    }

    private func sidebarInquiryRow(icon: String, title: String, count: Int, tint: Color = DS.textMuted) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 14)
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DS.textSecondary)
            Spacer()
            Text("\(count)")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
        .padding(.leading, 8)
        .padding(.trailing, 8)
    }

    private func sidebarChildDocRow(_ doc: ChildDoc, level: Int) -> some View {
        let isHovered = hoveredChildDocId == doc.id

        return Button {
            NotificationCenter.default.post(
                name: .enterFocusMode,
                object: nil,
                userInfo: ["type": doc.entityType, "id": doc.entityId]
            )
            onNavigate()
        } label: {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(doc.entityType.color.opacity(0.14))
                    .frame(width: 20, height: 20)
                    .overlay(
                        Image(systemName: doc.entityType.icon)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(doc.entityType.color)
                    )

                Text(doc.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(1)

                Spacer()

                if doc.outlineReferenceCount > 0 {
                    Text("\(doc.outlineReferenceCount)")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(DS.textMuted)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(DS.borderSubtle, in: Capsule())
                }
            }
            .padding(.leading, 8 + CGFloat(max(level - 1, 0)) * 18)
            .padding(.trailing, 8)
            .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            .unifiedSidebarRowChrome(isActive: false, isHovered: isHovered, cornerRadius: 8, hoverFill: DS.bg)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hoveredChildDocId = $0 ? doc.id : nil }
    }

    // MARK: - Inquiry Summaries

    private func refreshInquirySummaries() async {
        let ids = Set(filteredThinkspaces.map(\.id) + expandedThinkspaces)
        for id in ids {
            await loadInquirySummary(for: id, force: true)
        }
    }

    private func loadInquirySummary(for thinkspaceId: String, force: Bool = false) async {
        if !force, inquirySummaries[thinkspaceId] != nil { return }
        do {
            let profiles = try await InquiryRepository.shared.fetchDeepDives(in: thinkspaceId)
            guard let profile = profiles.first else {
                inquirySummaries[thinkspaceId] = ThinkspaceInquirySidebarSummary()
                return
            }

            let questions = (try? await InquiryRepository.shared.fetchQuestions(forDeepDive: profile.uuid)) ?? []
            let extracts = (try? await InquiryRepository.shared.fetchExtracts(forDeepDive: profile.uuid)) ?? []
            let lexicon = (try? await InquiryRepository.shared.fetchLexicon(forDeepDive: profile.uuid)) ?? []
            let sessions = (try? await InquiryRepository.shared.fetchSessions(forDeepDive: profile.uuid)) ?? []
            let deepDiveSources = (try? await InquiryRepository.shared.fetchSources(forDeepDive: profile)) ?? []
            let connections = (try? await InquiryRepository.shared.fetchConnections(forDeepDive: profile)) ?? []

            var sessionSourceUUIDs = Set<String>()
            var unmappedCount = 0
            for session in sessions {
                if let sourceRefs = session.inquirySessionStructured?.sourceRefs {
                    sessionSourceUUIDs.formUnion(sourceRefs.map(\.sourceUUID))
                }
                if let operations = session.inquirySessionStructured?.crystallizationResult?.canvasProjection?.operations {
                    unmappedCount += operations.filter { op in
                        op.status == .pending || op.status == .edited || op.status == .deferred
                    }.count
                }
            }

            let summary = ThinkspaceInquirySidebarSummary(
                activeSessionCount: sessions.filter { $0.inquirySessionMetadata?.status == .active }.count,
                questionCount: questions.filter { ($0.questionMetadata?.status ?? .open) != .archived }.count,
                sourceCount: Set(deepDiveSources.map(\.uuid)).union(sessionSourceUUIDs).count,
                claimCount: extracts.filter { $0.extractMetadata?.kind.isClaimLike == true }.count,
                conceptCount: connections.count + lexicon.filter { $0.lexiconMetadata?.maturity == .promotedToConnection || $0.lexiconMetadata?.maturity == .entry }.count,
                outputCount: profile.deepDiveStructured?.outputAngles.count ?? 0,
                unmappedCount: unmappedCount
            )

            inquirySummaries[thinkspaceId] = summary
        } catch {
            inquirySummaries[thinkspaceId] = ThinkspaceInquirySidebarSummary()
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func thinkspaceContextMenu(_ thinkspace: Thinkspace) -> some View {
        Button {
            selectThinkspace(thinkspace)
        } label: {
            Label("Open", systemImage: "arrow.right.circle")
        }

        Button {
            NotificationCenter.default.post(
                name: CosmoNotification.Navigation.openAsPane,
                object: nil,
                userInfo: ["thinkspaceId": thinkspace.id]
            )
        } label: {
            Label("Open as Pane", systemImage: "rectangle.split.2x1")
        }

        Divider()

        Button {
            renameText = thinkspace.name
            renamingThinkspaceId = thinkspace.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isRenameFieldFocused = true
            }
        } label: {
            Label("Rename", systemImage: "pencil")
        }

        Button {
            startCreatingChildThinkspace(parent: thinkspace)
        } label: {
            Label("New Child Thinkspace", systemImage: "rectangle.stack.badge.plus")
        }

        if !projects.isEmpty {
            Menu("Assign to Project") {
                ForEach(projects, id: \.uuid) { project in
                    Button {
                        Task { await manager.assignThinkspace(thinkspace.id, to: project.uuid) }
                    } label: {
                        HStack {
                            Text(project.title ?? "Untitled")
                            if thinkspace.projectUuid == project.uuid {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }

                if thinkspace.projectUuid != nil {
                    Divider()
                    Button {
                        Task { await manager.unassignThinkspace(thinkspace.id) }
                    } label: {
                        Label("Remove from Project", systemImage: "xmark.circle")
                    }
                }
            }
        }

        Divider()

        Button(role: .destructive) {
            Task { await manager.delete(thinkspace) }
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: - Empty State

    private var thinkspaceEmptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "rectangle.3.group")
                .font(.system(size: 18))
                .foregroundStyle(DS.textMuted)

            Text("No thinkspaces yet")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DS.textSecondary)

            Text("Create one to start organizing the canvas.")
                .font(.system(size: 11))
                .foregroundStyle(DS.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }

    private var createThinkspaceButton: some View {
        Button("New thinkspace", systemImage: "plus") {
            withAnimation(actionAnimation) {
                isCreatingThinkspace = true
                creatingChildOfThinkspace = nil
                newName = ""
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isNameFieldFocused = true
            }
        }
        .labelStyle(.iconOnly)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(DS.accent)
        .frame(width: 28, height: 28)
        .background(DS.accentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(DS.accent.opacity(0.12), lineWidth: 1)
        )
        .buttonStyle(.plain)
        .help("New ThinkSpace")
    }

    private func thinkspaceRowFill(isActive: Bool, isHovered: Bool, isDropTarget: Bool) -> Color {
        if isDropTarget {
            return DS.accentSoft
        }
        if isActive {
            return DS.accentSoft
        }
        if isHovered {
            return DS.bg
        }
        return .clear
    }

    // MARK: - Actions

    private func selectThinkspace(_ thinkspace: Thinkspace) {
        // Only set destination — MainView's onChange handles the actual switchTo()
        withAnimation(actionAnimation) {
            currentDestination = .thinkspace(id: thinkspace.id)
        }
        onNavigate()
    }

    private func commitRename(_ thinkspace: Thinkspace) {
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != thinkspace.name else {
            cancelRename()
            return
        }
        Task {
            await manager.rename(thinkspace, to: trimmed)
        }
        withAnimation(actionAnimation) {
            renamingThinkspaceId = nil
        }
    }

    private func cancelRename() {
        withAnimation(actionAnimation) {
            renamingThinkspaceId = nil
            renameText = ""
        }
    }

    private func toggleExpand(_ thinkspace: Thinkspace) {
        withAnimation(actionAnimation) {
            if expandedThinkspaces.contains(thinkspace.id) {
                expandedThinkspaces.remove(thinkspace.id)
            } else {
                expandedThinkspaces.insert(thinkspace.id)
            }
        }
    }

    private func createThinkspace() {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            withAnimation(actionAnimation) {
                isCreatingThinkspace = false
                creatingChildOfThinkspace = nil
            }
            return
        }
        Task {
            let createdThinkspace: Thinkspace?
            if let parent = creatingChildOfThinkspace {
                createdThinkspace = await manager.createSubThinkspace(name: trimmedName, parent: parent)
            } else {
                createdThinkspace = await manager.createThinkspace(
                    name: trimmedName,
                    projectUuid: selectedProjectFilter
                )
            }

            if let thinkspace = createdThinkspace {
                await manager.switchTo(thinkspace)
                withAnimation(actionAnimation) {
                    currentDestination = .thinkspace(id: thinkspace.id)
                    if let parent = creatingChildOfThinkspace {
                        expandedThinkspaces.insert(parent.id)
                    }
                }
                onNavigate()
            }
            withAnimation(actionAnimation) {
                isCreatingThinkspace = false
                creatingChildOfThinkspace = nil
            }
        }
    }

    private func startCreatingChildThinkspace(parent: Thinkspace) {
        withAnimation(actionAnimation) {
            creatingChildOfThinkspace = parent
            isCreatingThinkspace = true
            newName = ""
            expandedThinkspaces.insert(parent.id)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isNameFieldFocused = true
        }
    }

    private func cancelCreateThinkspace() {
        withAnimation(actionAnimation) {
            isCreatingThinkspace = false
            creatingChildOfThinkspace = nil
            newName = ""
        }
    }

    private func loadProjects() async {
        do {
            projects = try await repository.fetchAll(type: .project)
                .sorted { ($0.title ?? "") < ($1.title ?? "") }
        } catch {
            print("Failed to load projects: \(error)")
        }
    }

    private func deleteProject(_ project: Atom) async {
        do {
            try await repository.softDeleteProject(project.uuid)
            if selectedProjectFilter == project.uuid {
                selectedProjectFilter = nil
            }
            await loadProjects()
        } catch {
            print("Failed to delete project: \(error)")
        }
    }

    // MARK: - Keyboard Handlers

    private func handleKeyDown() {
        isKeyboardNavigating = true
        let items = allNavigableItems
        guard !items.isEmpty else { return }
        withAnimation(actionAnimation) {
            selectedIndex = min(selectedIndex + 1, items.count - 1)
            updateHoverFromKeyboard()
        }
    }

    private func handleKeyUp() {
        isKeyboardNavigating = true
        let items = allNavigableItems
        guard !items.isEmpty else { return }
        withAnimation(actionAnimation) {
            selectedIndex = max(selectedIndex - 1, 0)
            updateHoverFromKeyboard()
        }
    }

    private func handleKeyReturn() {
        if let thinkspace = activeRenamingThinkspace() {
            commitRename(thinkspace)
            return
        }

        let items = allNavigableItems
        guard selectedIndex < items.count else { return }
        switch items[selectedIndex] {
        case .thinkspace(let thinkspace, _):
            selectThinkspace(thinkspace)
        case .block(let doc, _, _):
            NotificationCenter.default.post(
                name: .enterFocusMode,
                object: nil,
                userInfo: ["type": doc.entityType, "id": doc.entityId]
            )
            onNavigate()
        }
    }

    private func activeRenamingThinkspace() -> Thinkspace? {
        guard let renamingThinkspaceId else { return nil }
        return manager.thinkspaces.first { $0.id == renamingThinkspaceId } ??
            allNavigableItems.compactMap { item in
                if case .thinkspace(let thinkspace, _) = item,
                   thinkspace.id == renamingThinkspaceId {
                    return thinkspace
                }
                return nil
            }
            .first
    }

    private func handleKeyEscape() {
        if renamingThinkspaceId != nil {
            cancelRename()
        } else if isCreatingThinkspace {
            withAnimation(actionAnimation) {
                isCreatingThinkspace = false
            }
        }
    }

    private func handleKeyRight() {
        let items = allNavigableItems
        guard selectedIndex < items.count else { return }
        if case .thinkspace(let thinkspace, _) = items[selectedIndex] {
            toggleExpand(thinkspace)
        }
    }

    private func handleKeyLeft() {
        let items = allNavigableItems
        guard selectedIndex < items.count else { return }
        if case .thinkspace(let thinkspace, _) = items[selectedIndex] {
            withAnimation(actionAnimation) {
                _ = expandedThinkspaces.remove(thinkspace.id)
            }
        }
    }

    private func updateHoverFromKeyboard() {
        let items = allNavigableItems
        guard selectedIndex < items.count else { return }
        switch items[selectedIndex] {
        case .thinkspace(let thinkspace, _):
            hoveredThinkspaceId = thinkspace.id
            hoveredChildDocId = nil
        case .block(let doc, _, _):
            hoveredChildDocId = doc.id
            hoveredThinkspaceId = nil
        }
    }

    // MARK: - Helpers

    private func projectColor(for project: Atom) -> Color {
        if let metadata = project.metadataValue(as: ProjectMetadata.self),
           let colorHex = metadata.color {
            return Color(hex: colorHex)
        }
        return DS.accent
    }

    private func projectFor(_ thinkspace: Thinkspace) -> Atom? {
        guard let projectUuid = thinkspace.projectUuid else { return nil }
        return projects.first { $0.uuid == projectUuid }
    }

    private func thinkspaceIsExpandable(_ thinkspace: Thinkspace) -> Bool {
        thinkspace.hasChildren ||
            !manager.childThinkspaces(of: thinkspace.id).isEmpty ||
            creatingChildOfThinkspace?.id == thinkspace.id
    }

    private func appendNavigationItems(
        from thinkspace: Thinkspace,
        level: Int,
        into items: inout [ThinkspaceNavigatorItem]
    ) {
        items.append(.thinkspace(thinkspace, level: level))

        guard expandedThinkspaces.contains(thinkspace.id) else { return }

        for childThinkspace in manager.childThinkspaces(of: thinkspace.id) {
            appendNavigationItems(from: childThinkspace, level: level + 1, into: &items)
        }
    }
}

private enum ThinkspaceNavigatorItem {
    case thinkspace(Thinkspace, level: Int)
    case block(ChildDoc, thinkspaceId: String, level: Int)
}

// MARK: - Thinkspace Row Chrome

/// Extracted ViewModifier to reduce opaque type nesting depth in thinkspaceRow().
/// The Swift compiler can stack-overflow resolving deeply chained overlays + backgrounds.
private struct ThinkspaceRowChrome: ViewModifier {
    let thinkspaceId: String
    let isActive: Bool
    let isHovered: Bool
    let isDropTarget: Bool
    let isSpringLoading: Bool
    let springLoadPulse: Double
    let fillColor: Color

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: UnifiedSidebarMetrics.rowRadius, style: .continuous)
                    .fill(fillColor)
            )
            .overlay(springLoadFill)
            .overlay(strokeOverlay)
            .shadow(
                color: (isDropTarget || isSpringLoading)
                    ? DS.accentGlow.opacity(0.18 + springLoadPulse * 0.34)
                    : .clear,
                radius: 10 + springLoadPulse * 8,
                x: 0,
                y: 0
            )
            .background(frameTracker)
    }

    private var springLoadFill: some View {
        RoundedRectangle(cornerRadius: UnifiedSidebarMetrics.rowRadius, style: .continuous)
            .fill(DS.accent.opacity(0.06 + springLoadPulse * 0.16))
            .opacity(isSpringLoading ? 1 : 0)
    }

    private var strokeOverlay: some View {
        RoundedRectangle(cornerRadius: UnifiedSidebarMetrics.rowRadius, style: .continuous)
            .strokeBorder(
                isSpringLoading
                    ? DS.accent.opacity(0.18 + springLoadPulse * 0.34)
                    : (isDropTarget ? DS.accent.opacity(0.26) : Color.clear),
                lineWidth: (isDropTarget || isSpringLoading) ? 1.5 : 1
            )
    }

    private var frameTracker: some View {
        GeometryReader { geo in
            Color.clear
                .preference(
                    key: ThinkspaceRowFrameKey.self,
                    value: [thinkspaceId: geo.frame(in: .global)]
                )
        }
    }
}
