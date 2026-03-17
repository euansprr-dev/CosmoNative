// CosmoOS/Canvas/UnifiedSidebar/SidebarThinkspaceSection.swift
// Thinkspace list with project folders, keyboard nav, creation flow
// Migrated from ThinkspaceSidebar.swift patterns
// March 2026 — Command Center navigation

import SwiftUI

// MARK: - Sidebar Thinkspace Section

struct SidebarThinkspaceSection: View {
    @ObservedObject var manager: ThinkspaceManager
    @Binding var currentDestination: SidebarDestination
    let isCollapsed: Bool
    @EnvironmentObject var crossDragManager: CrossThinkspaceDragManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Data
    @State private var projects: [Atom] = []
    @State private var selectedProjectFilter: String? = nil

    // Creation
    @State private var isCreatingThinkspace = false
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
    @State private var childDocsLoading: Set<String> = []

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

                if isCreatingThinkspace {
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
                await manager.refreshChildDocs(for: expandedThinkspaces)
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
                withAnimation(actionAnimation) {
                    isCreatingThinkspace = false
                }
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
                Button {
                    selectThinkspace(thinkspace)
                } label: {
                    thinkspaceRowLabel(thinkspace, isActive: isActive, isExpanded: isExpanded, level: level)
                }
                .buttonStyle(.plain)
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
    private func thinkspaceRowLabel(_ thinkspace: Thinkspace, isActive: Bool, isExpanded: Bool, level: Int) -> some View {
        let project = projectFor(thinkspace)
        let color = project.map { projectColor(for: $0) } ?? DS.accent

        if isCollapsed {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isActive ? DS.accentSoft : Color.clear)
                .frame(width: UnifiedSidebarMetrics.railHitTarget, height: UnifiedSidebarMetrics.railHitTarget)
                .overlay(
                    Text(String(thinkspace.name.prefix(1)).uppercased())
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(isActive ? DS.accent : color)
                )
                .frame(maxWidth: .infinity)
                .help(thinkspace.name)
        } else {
            HStack(spacing: 8) {
                Button(isExpanded ? "Collapse" : "Expand", systemImage: isExpanded ? "chevron.down" : "chevron.right") {
                    toggleExpand(thinkspace)
                }
                .labelStyle(.iconOnly)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(DS.textMuted)
                .frame(width: 20, height: 20)
                .buttonStyle(.plain)

                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isActive ? DS.accent.opacity(0.14) : color.opacity(0.14))
                    .frame(width: 24, height: 24)
                    .overlay(
                        Text(String(thinkspace.name.prefix(1)).uppercased())
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(isActive ? DS.accent : color)
                    )

                Text(thinkspace.name)
                    .font(.system(size: 13, weight: isActive ? .semibold : .medium))
                    .foregroundStyle(isActive ? DS.text : DS.textSecondary)
                    .lineLimit(1)

                if level > 0 {
                    Text("Nested")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DS.textMuted)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(DS.bg, in: Capsule())
                }

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
            .padding(.leading, 8 + CGFloat(level) * 18)
            .padding(.trailing, 8)
            .frame(maxWidth: .infinity, minHeight: UnifiedSidebarMetrics.thinkspaceRowHeight, alignment: .leading)
            .contentShape(Rectangle())
        }
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
                    Text(String(thinkspace.name.prefix(1)).uppercased())
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
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
        let navigation = manager.navigationCache[thinkspace.id]
        let docs = navigation?.blockInventory ?? []
        let childThinkspaces = level == 0 ? (navigation?.childThinkspaces ?? []) : []
        let isLoading = childDocsLoading.contains(thinkspace.id)

        HStack(alignment: .top, spacing: 10) {
            Rectangle()
                .fill(DS.borderSubtle)
                .frame(width: 1)

            VStack(alignment: .leading, spacing: 4) {
                if isLoading {
                    HStack(spacing: 6) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: DS.accent))
                            .scaleEffect(0.5)
                        Text("Loading...")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(DS.textMuted)
                    }
                } else if docs.isEmpty && childThinkspaces.isEmpty {
                    Text("No blocks")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DS.textMuted)
                } else {
                    ForEach(childThinkspaces) { childThinkspace in
                        AnyView(thinkspaceRow(childThinkspace, level: level + 1))
                    }

                    ForEach(docs) { doc in
                        sidebarChildDocRow(doc, level: level + 1)
                    }
                }
            }
        }
        .padding(.leading, level == 0 ? 30 : 48)
        .padding(.top, 4)
        .padding(.bottom, 6)
    }

    private func sidebarChildDocRow(_ doc: ChildDoc, level: Int) -> some View {
        let isHovered = hoveredChildDocId == doc.id

        return Button {
            NotificationCenter.default.post(
                name: .enterFocusMode,
                object: nil,
                userInfo: ["type": doc.entityType, "id": doc.entityId]
            )
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
                if manager.navigationCache[thinkspace.id] == nil {
                    childDocsLoading.insert(thinkspace.id)
                    Task {
                        await manager.fetchNavigationData(for: thinkspace.id)
                        childDocsLoading.remove(thinkspace.id)
                    }
                }
            }
        }
    }

    private func createThinkspace() {
        guard !newName.isEmpty else {
            isCreatingThinkspace = false
            return
        }
        Task {
            if let thinkspace = await manager.createThinkspace(
                name: newName,
                projectUuid: selectedProjectFilter
            ) {
                await manager.switchTo(thinkspace)
                withAnimation(actionAnimation) {
                    currentDestination = .thinkspace(id: thinkspace.id)
                }
            }
            withAnimation(actionAnimation) {
                isCreatingThinkspace = false
            }
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
        }
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
                expandedThinkspaces.remove(thinkspace.id)
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

    private func appendNavigationItems(
        from thinkspace: Thinkspace,
        level: Int,
        into items: inout [ThinkspaceNavigatorItem]
    ) {
        items.append(.thinkspace(thinkspace, level: level))

        guard expandedThinkspaces.contains(thinkspace.id) else { return }

        let navigation = manager.navigationCache[thinkspace.id]
        if level == 0 {
            for childThinkspace in navigation?.childThinkspaces ?? [] {
                appendNavigationItems(from: childThinkspace, level: level + 1, into: &items)
            }
        }

        for doc in navigation?.blockInventory ?? [] {
            items.append(.block(doc, thinkspaceId: thinkspace.id, level: level + 1))
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
            .overlay(alignment: .leading) { leadingIndicator }
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

    private var leadingIndicator: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(DS.accent.opacity(isSpringLoading ? 0.36 + springLoadPulse * 0.42 : (isDropTarget ? 0.28 : 0)))
            .frame(width: 3)
            .padding(.vertical, 8)
            .opacity(isDropTarget || isSpringLoading ? 1 : 0)
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
