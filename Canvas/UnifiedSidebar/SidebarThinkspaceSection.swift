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
        let all = manager.sidebarThinkspaces
        let filtered: [Thinkspace]
        if let projectId = selectedProjectFilter {
            filtered = all.filter { $0.projectUuid == projectId }
        } else {
            filtered = all
        }
        return filtered.sorted { $0.lastOpened > $1.lastOpened }
    }

    // MARK: - Navigable Items

    private var allNavigableItems: [NavigableItem] {
        var items: [NavigableItem] = []
        for thinkspace in filteredThinkspaces {
            items.append(.thinkspace(thinkspace, projectId: thinkspace.projectUuid))
            if expandedThinkspaces.contains(thinkspace.id),
               let docs = manager.childDocsCache[thinkspace.id] {
                for doc in docs {
                    items.append(.childDoc(doc, thinkspaceId: thinkspace.id))
                }
            }
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
                    .foregroundColor(DS.textSecondary)
                    .frame(width: UnifiedSidebarMetrics.railHitTarget, height: UnifiedSidebarMetrics.railHitTarget)
                    .background(DS.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .frame(maxWidth: .infinity)
            } else {
                Text("Thinkspaces")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DS.text)

                Spacer()

                createThinkspaceButton
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Filter Chips Row

    private var filterChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
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
                    .foregroundColor(isSelected ? color : DS.textSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                Capsule().fill(isSelected ? color.opacity(0.12) : DS.surface)
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
                        .foregroundColor(DS.accent)
                )

            TextField("Name", text: $newName)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(DS.text)
                .focused($isNameFieldFocused)
                .onSubmit { createThinkspace() }

            Button {
                withAnimation(actionAnimation) {
                    isCreatingThinkspace = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DS.textMuted)
                    .frame(width: 24, height: 24)
                    .background(DS.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: UnifiedSidebarMetrics.rowRadius, style: .continuous)
                .fill(DS.surface)
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
                    thinkspaceRow(thinkspace)
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
                    thinkspaceRow(thinkspace)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func thinkspaceRow(_ thinkspace: Thinkspace) -> some View {
        let isActive = activeThinkspaceId == thinkspace.id
        let isHovered = hoveredThinkspaceId == thinkspace.id
        let isExpanded = expandedThinkspaces.contains(thinkspace.id)
        let isRenaming = renamingThinkspaceId == thinkspace.id
        let isDropTarget = crossDragManager.hoveredThinkspaceId == thinkspace.id

        return VStack(alignment: .leading, spacing: 0) {
            if isRenaming && !isCollapsed {
                thinkspaceRenameRow(thinkspace)
            } else {
                Button {
                    selectThinkspace(thinkspace)
                } label: {
                    thinkspaceRowLabel(thinkspace, isActive: isActive, isExpanded: isExpanded)
                }
                .buttonStyle(.plain)
            }

            // Child docs
            if isExpanded && !isCollapsed {
                childDocsSection(for: thinkspace)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: UnifiedSidebarMetrics.rowRadius, style: .continuous)
                .fill(thinkspaceRowFill(isActive: isActive, isHovered: isHovered, isDropTarget: isDropTarget))
        )
        .overlay(
            RoundedRectangle(cornerRadius: UnifiedSidebarMetrics.rowRadius, style: .continuous)
                .strokeBorder(
                    isDropTarget ? DS.accent.opacity(0.32) : (isActive ? DS.accent.opacity(0.14) : Color.clear),
                    lineWidth: isDropTarget ? 1.5 : 1
                )
        )
        .shadow(color: isDropTarget ? DS.accentGlow : .clear, radius: 12, x: 0, y: 0)
        .background(
            GeometryReader { geo in
                Color.clear
                    .preference(
                        key: ThinkspaceRowFrameKey.self,
                        value: [thinkspace.id: geo.frame(in: .global)]
                    )
            }
        )
        .onHover { hoveredThinkspaceId = $0 ? thinkspace.id : nil }
        .contextMenu {
            thinkspaceContextMenu(thinkspace)
        }
        .animation(hoverAnimation, value: isHovered)
        .animation(hoverAnimation, value: isDropTarget)
    }

    @ViewBuilder
    private func thinkspaceRowLabel(_ thinkspace: Thinkspace, isActive: Bool, isExpanded: Bool) -> some View {
        let project = projectFor(thinkspace)
        let color = project.map { projectColor(for: $0) } ?? DS.accent

        if isCollapsed {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isActive ? DS.accentSoft : DS.surface)
                .frame(width: UnifiedSidebarMetrics.railHitTarget, height: UnifiedSidebarMetrics.railHitTarget)
                .overlay(
                    Text(String(thinkspace.name.prefix(1)).uppercased())
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(isActive ? DS.accent : color)
                )
                .frame(maxWidth: .infinity)
                .help(thinkspace.name)
        } else {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(isActive ? DS.accent : Color.clear)
                    .frame(width: 3, height: 18)

                Button {
                    toggleExpand(thinkspace)
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(DS.textMuted)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)

                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isActive ? DS.accent.opacity(0.14) : color.opacity(0.14))
                    .frame(width: 24, height: 24)
                    .overlay(
                        Text(String(thinkspace.name.prefix(1)).uppercased())
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(isActive ? DS.accent : color)
                    )

                Text(thinkspace.name)
                    .font(.system(size: 13, weight: isActive ? .semibold : .medium))
                    .foregroundColor(isActive ? DS.text : DS.textSecondary)
                    .lineLimit(1)

                Spacer()

                Text("\(thinkspace.blockCount)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(DS.textMuted)
                    .frame(minWidth: 22, alignment: .trailing)
            }
            .padding(.horizontal, 8)
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
                        .foregroundColor(color)
                )

            TextField("Name", text: $renameText)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(DS.text)
                .focused($isRenameFieldFocused)
                .onSubmit { commitRename(thinkspace) }
                .onExitCommand { cancelRename() }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: UnifiedSidebarMetrics.thinkspaceRowHeight, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: UnifiedSidebarMetrics.rowRadius, style: .continuous)
                .fill(DS.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: UnifiedSidebarMetrics.rowRadius, style: .continuous)
                        .stroke(DS.accent.opacity(0.22), lineWidth: 1)
                )
        )
    }

    // MARK: - Child Docs

    @ViewBuilder
    private func childDocsSection(for thinkspace: Thinkspace) -> some View {
        let docs = manager.childDocsCache[thinkspace.id] ?? []
        let isLoading = childDocsLoading.contains(thinkspace.id)

        VStack(alignment: .leading, spacing: 4) {
            if isLoading {
                HStack(spacing: 6) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: DS.accent))
                        .scaleEffect(0.5)
                    Text("Loading...")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(DS.textMuted)
                }
            } else if docs.isEmpty {
                Text("No blocks")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DS.textMuted)
            } else {
                ForEach(docs) { doc in
                    sidebarChildDocRow(doc, thinkspaceId: thinkspace.id)
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(DS.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(DS.borderSubtle, lineWidth: 1)
        )
        .padding(.leading, 24)
        .padding(.top, 4)
        .padding(.bottom, 6)
    }

    private func sidebarChildDocRow(_ doc: ChildDoc, thinkspaceId: String) -> some View {
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
                            .foregroundColor(doc.entityType.color)
                    )

                Text(doc.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DS.textSecondary)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            .unifiedSidebarRowChrome(isActive: false, isHovered: isHovered, cornerRadius: 8, hoverFill: DS.surfaceHover)
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
                .foregroundColor(DS.textMuted)

            Text("No thinkspaces yet")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(DS.textSecondary)

            Text("Create one to start organizing the canvas.")
                .font(.system(size: 11))
                .foregroundColor(DS.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }

    private var createThinkspaceButton: some View {
        Button {
            withAnimation(actionAnimation) {
                isCreatingThinkspace = true
                newName = ""
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isNameFieldFocused = true
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(DS.accent)
                .frame(width: 28, height: 28)
                .background(DS.accentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(DS.accent.opacity(0.12), lineWidth: 1)
                )
        }
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
            return DS.surfaceHover
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
                if manager.childDocsCache[thinkspace.id] == nil {
                    childDocsLoading.insert(thinkspace.id)
                    Task {
                        await manager.fetchChildDocs(for: thinkspace.id)
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
        case .childDoc(let doc, _):
            NotificationCenter.default.post(
                name: .enterFocusMode,
                object: nil,
                userInfo: ["type": doc.entityType, "id": doc.entityId]
            )
        case .project:
            break
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
        case .childDoc(let doc, _):
            hoveredChildDocId = doc.id
            hoveredThinkspaceId = nil
        case .project:
            break
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
}
