// CosmoOS/Canvas/ThinkspaceSidebar.swift
// Flat sidebar with project filter chips — one-click ThinkSpace switching
// March 2026 - Flat Design (replaces two-section hierarchy)

import SwiftUI

// MARK: - Thinkspace Sidebar

struct ThinkspaceSidebar: View {
    @ObservedObject var manager: ThinkspaceManager
    @Binding var isVisible: Bool

    @AppStorage("thinkspaceSidebarLocked") private var isLocked: Bool = false

    @State private var isHovering: Bool = false
    @State private var closeTimer: Timer?

    // Data
    @State private var projects: [Atom] = []
    @State private var selectedProjectFilter: String? = nil

    // Creation
    @State private var isCreatingThinkspace = false
    @State private var newName = ""
    @FocusState private var isNameFieldFocused: Bool

    // Project creation
    @State private var isCreatingProject = false
    @State private var newProjectName = ""
    @FocusState private var isProjectNameFieldFocused: Bool

    // Project rename
    @State private var renamingProjectId: String?
    @State private var renameProjectText: String = ""
    @FocusState private var isProjectRenameFieldFocused: Bool

    // Hover
    @State private var hoveredThinkspaceId: String?
    @State private var hoveredChildDocId: String?

    // Child docs expand
    @State private var expandedThinkspaces: Set<String> = []
    @State private var childDocsLoading: Set<String> = []

    // Keyboard
    @State private var selectedIndex: Int = 0
    @State private var isKeyboardNavigating: Bool = false
    @FocusState private var isSidebarFocused: Bool

    // Loading
    @State private var isLoading: Bool = false
    @State private var loadError: String?

    private let sidebarWidth: CGFloat = 280
    private let repository = AtomRepository.shared

    // Project color palette (matches ProjectCreationModal)
    private let projectColorPalette = [
        "#A8CCE8", "#CAB8E8", "#F4AFA0", "#8FC7A2",
        "#F5E6C8", "#E8B8A8", "#A8D8E8", "#D8A8E8",
    ]

    private func updateManagerVisibility(_ visible: Bool) {
        manager.isSidebarVisible = visible
    }

    var shouldShowSidebar: Bool {
        isLocked || isVisible || isHovering
    }

    // MARK: - Filtered Thinkspaces

    private var filteredThinkspaces: [Thinkspace] {
        let all = manager.thinkspaces
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

    // MARK: - Body

    var body: some View {
        // Conditional rendering — sidebar is completely removed from the view tree when hidden.
        // This eliminates ghost hit areas from .offset() (which only moves visuals, not hit testing).
        Group {
            if shouldShowSidebar {
                VStack(spacing: 0) {
                    header

                    Rectangle()
                        .fill(DS.border)
                        .frame(height: 0.5)

                    ScrollView {
                        VStack(spacing: 12) {
                            if isLoading {
                                loadingView
                            } else if let error = loadError {
                                errorView(error)
                            } else {
                                filterChipsRow

                                if isCreatingThinkspace {
                                    newThinkspaceRow
                                }

                                thinkspaceList

                                sectionDivider

                                RecentlyDeletedSection()
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                    }
                }
                .frame(width: sidebarWidth)
                .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(DS.border, lineWidth: 1)
                )
                .dsFloatingShadow()
                .padding(.bottom, 16)
                .transition(.move(edge: .leading).combined(with: .opacity))
                .onHover { handleHover($0) }
                .focused($isSidebarFocused)
                .focusable()
                .focusEffectDisabled()
                .onKeyPress(.downArrow) { handleKeyDown(); return .handled }
                .onKeyPress(.upArrow) { handleKeyUp(); return .handled }
                .onKeyPress(.return) {
                    if isCreatingThinkspace || isCreatingProject || renamingProjectId != nil {
                        return .ignored
                    }
                    handleKeyReturn(); return .handled
                }
                .onKeyPress(.escape) { handleKeyEscape(); return .handled }
                .onKeyPress(.rightArrow) { handleKeyRight(); return .handled }
                .onKeyPress(.leftArrow) { handleKeyLeft(); return .handled }
            }
        }
        .animation(ProMotionSprings.snappy, value: shouldShowSidebar)
        .task { await loadProjects() }
        .onReceive(NotificationCenter.default.publisher(for: .atomsDidChange)) { _ in
            Task {
                await loadProjects()
                await manager.refreshChildDocs(for: expandedThinkspaces)
            }
        }
        .onChange(of: shouldShowSidebar) { _, newValue in
            updateManagerVisibility(newValue)
        }
        .onAppear { updateManagerVisibility(shouldShowSidebar) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("ThinkSpaces sidebar")
        .accessibilityHint("Navigate with arrow keys, press Return to select")
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Thinkspaces")
                .dsSmallCapsLabel()

            Spacer()

            // Lock button
            Button {
                withAnimation(ProMotionSprings.snappy) {
                    isLocked.toggle()
                }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isLocked ? DS.text : DS.textMuted)
                    .padding(6)
                    .background(
                        isLocked ? DS.glassCardFill : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6)
                    )
            }
            .buttonStyle(.plain)
            .scaleEffect(isLocked ? 1.0 : 0.95)
            .animation(ProMotionSprings.snappy, value: isLocked)
            .help(isLocked ? "Unlock sidebar (auto-hide)" : "Lock sidebar open")

            // New ThinkSpace button
            Button {
                withAnimation(ProMotionSprings.snappy) {
                    isCreatingThinkspace = true
                    newName = ""
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isNameFieldFocused = true
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                    Text("New")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(DS.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(DS.accent.opacity(0.15), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: DS.accent))
                .scaleEffect(0.8)

            Text("Loading...")
                .font(.system(size: 12))
                .foregroundColor(DS.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 100)
        .accessibilityLabel("Loading ThinkSpaces")
    }

    // MARK: - Error View

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 24))
                .foregroundColor(Color.orange.opacity(0.8))

            Text("Failed to load")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(DS.text)

            Text(error)
                .font(.system(size: 11))
                .foregroundColor(DS.textMuted)
                .multilineTextAlignment(.center)

            Button {
                Task { await loadProjects() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10))
                    Text("Retry")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(DS.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(DS.accent.opacity(0.15), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, minHeight: 100)
        .padding()
        .accessibilityLabel("Error loading ThinkSpaces: \(error)")
    }

    // MARK: - Filter Chips Row

    private var filterChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                // "All" chip
                ProjectFilterChip(
                    label: "All",
                    color: DS.accent,
                    isSelected: selectedProjectFilter == nil
                ) {
                    withAnimation(ProMotionSprings.snappy) {
                        selectedProjectFilter = nil
                    }
                }

                // Per-project chips
                ForEach(projects, id: \.uuid) { project in
                    let color = projectColor(for: project)

                    if renamingProjectId == project.uuid {
                        projectRenameField(project: project, color: color)
                    } else {
                        ProjectFilterChip(
                            label: project.title ?? "Untitled",
                            color: color,
                            isSelected: selectedProjectFilter == project.uuid
                        ) {
                            withAnimation(ProMotionSprings.snappy) {
                                selectedProjectFilter = project.uuid
                            }
                        }
                        .contextMenu {
                            Button {
                                renamingProjectId = project.uuid
                                renameProjectText = project.title ?? ""
                            } label: {
                                Label("Rename Project", systemImage: "pencil")
                            }

                            Menu {
                                ForEach(projectColorPalette, id: \.self) { colorHex in
                                    Button {
                                        Task { await updateProjectColor(project, to: colorHex) }
                                    } label: {
                                        Label {
                                            Text(colorLabel(for: colorHex))
                                        } icon: {
                                            Image(systemName: currentColorHex(for: project) == colorHex
                                                  ? "checkmark.circle.fill"
                                                  : "circle.fill")
                                        }
                                    }
                                }
                            } label: {
                                Label("Change Color", systemImage: "paintpalette")
                            }

                            Divider()

                            Button(role: .destructive) {
                                Task { await deleteProject(project) }
                            } label: {
                                Label("Delete Project", systemImage: "trash")
                            }
                        }
                        .dropDestination(for: String.self) { items, _ in
                            guard let thinkspaceId = items.first else { return false }
                            Task {
                                await manager.assignThinkspace(thinkspaceId, to: project.uuid)
                            }
                            return true
                        } isTargeted: { _ in }
                    }
                }

                // Create project button or inline field
                if isCreatingProject {
                    newProjectChipField
                } else {
                    Button {
                        withAnimation(ProMotionSprings.snappy) {
                            isCreatingProject = true
                            newProjectName = ""
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isProjectNameFieldFocused = true
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(DS.textMuted)
                            .frame(width: 24, height: 24)
                            .background(DS.glassCardFill, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("New Project")
                }
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Thinkspace List

    @ViewBuilder
    private var thinkspaceList: some View {
        let items = filteredThinkspaces
        if items.isEmpty {
            emptyState
        } else {
            VStack(spacing: 2) {
                ForEach(items) { thinkspace in
                    let project = projectFor(thinkspace)
                    ThinkspaceRow(
                        thinkspace: thinkspace,
                        isActive: manager.currentThinkspace?.id == thinkspace.id,
                        isHovered: hoveredThinkspaceId == thinkspace.id,
                        projectName: project?.title,
                        projectColor: project.map { projectColor(for: $0) } ?? DS.textMuted,
                        isExpanded: expandedThinkspaces.contains(thinkspace.id),
                        onToggleExpand: { toggleThinkspaceExpand(thinkspace) },
                        childDocs: manager.childDocsCache[thinkspace.id] ?? [],
                        isLoadingChildren: childDocsLoading.contains(thinkspace.id),
                        hoveredChildDocId: hoveredChildDocId,
                        onChildDocTap: { doc in navigateToChildDoc(doc) },
                        onHoverChildDoc: { id in hoveredChildDocId = id },
                        onSelect: { selectThinkspace(thinkspace) },
                        onDelete: {
                            Task { await manager.delete(thinkspace) }
                        },
                        onRename: { newName in
                            Task { await manager.rename(thinkspace, to: newName) }
                        },
                        availableProjects: projects.map { p in
                            ProjectOption(
                                id: p.uuid,
                                name: p.title ?? "Untitled",
                                color: projectColor(for: p)
                            )
                        },
                        currentProjectId: thinkspace.projectUuid,
                        onAssignToProject: { projectId in
                            Task { await manager.assignThinkspace(thinkspace.id, to: projectId) }
                        },
                        onUnassignFromProject: {
                            Task { await manager.unassignThinkspace(thinkspace.id) }
                        }
                    )
                    .onHover { hovering in
                        hoveredThinkspaceId = hovering ? thinkspace.id : nil
                    }
                    .draggable(thinkspace.id)
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "rectangle.3.group")
                .font(.system(size: 20))
                .foregroundColor(DS.textMuted)

            Text(selectedProjectFilter != nil
                 ? "No ThinkSpaces in this project"
                 : "No ThinkSpaces yet")
                .font(.system(size: 12))
                .foregroundColor(DS.textMuted)

            Text("Tap + New to create one")
                .font(.system(size: 10))
                .foregroundColor(DS.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - New ThinkSpace Row

    private var newThinkspaceRow: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(DS.accent.opacity(0.2))
                .frame(width: 28, height: 28)
                .overlay(
                    Image(systemName: "rectangle.3.group")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(DS.accent)
                )

            TextField("ThinkSpace name", text: $newName)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(DS.text)
                .focused($isNameFieldFocused)
                .onSubmit { createThinkspace() }

            Button {
                withAnimation(ProMotionSprings.snappy) {
                    isCreatingThinkspace = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(DS.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(DS.accent.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(DS.accent.opacity(0.3), lineWidth: 1)
                )
        )
        .transition(.asymmetric(
            insertion: .scale(scale: 0.95).combined(with: .opacity),
            removal: .opacity
        ))
    }

    // MARK: - New Project Chip Field

    private var newProjectChipField: some View {
        HStack(spacing: 4) {
            TextField("Name", text: $newProjectName)
                .textFieldStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(DS.text)
                .focused($isProjectNameFieldFocused)
                .frame(width: 80)
                .onSubmit { createNewProject() }

            Button {
                withAnimation(ProMotionSprings.snappy) {
                    isCreatingProject = false
                    newProjectName = ""
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(DS.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(DS.accent.opacity(0.1), in: Capsule())
        .overlay(Capsule().stroke(DS.accent.opacity(0.3), lineWidth: 1))
    }

    // MARK: - Project Rename Field

    private func projectRenameField(project: Atom, color: Color) -> some View {
        HStack(spacing: 4) {
            TextField("Name", text: $renameProjectText)
                .textFieldStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(DS.text)
                .focused($isProjectRenameFieldFocused)
                .frame(width: 80)
                .onSubmit { submitProjectRename(project) }

            Button { submitProjectRename(project) } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(color)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(color.opacity(0.15), in: Capsule())
        .overlay(Capsule().stroke(color.opacity(0.3), lineWidth: 1))
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isProjectRenameFieldFocused = true
            }
        }
    }

    // MARK: - Section Divider

    private var sectionDivider: some View {
        Rectangle()
            .fill(DS.border)
            .frame(height: 0.5)
            .padding(.horizontal, 4)
    }

    // MARK: - Actions

    private func handleHover(_ hovering: Bool) {
        if hovering {
            closeTimer?.invalidate()
            closeTimer = nil
            isHovering = true
        } else {
            guard !isLocked else {
                isHovering = false
                return
            }
            closeTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { _ in
                DispatchQueue.main.async {
                    withAnimation(ProMotionSprings.snappy) {
                        self.isHovering = false
                        self.isVisible = false
                    }
                }
            }
        }
    }

    private func loadProjects() async {
        isLoading = true
        loadError = nil
        do {
            projects = try await repository.fetchAll(type: .project)
                .sorted { ($0.title ?? "") < ($1.title ?? "") }
            isLoading = false
        } catch {
            isLoading = false
            loadError = error.localizedDescription
            print("❌ Failed to load projects: \(error)")
        }
    }

    private func selectThinkspace(_ thinkspace: Thinkspace) {
        Task { await manager.switchTo(thinkspace) }
        if !isLocked {
            withAnimation(ProMotionSprings.snappy) {
                isVisible = false
            }
        }
    }

    private func toggleThinkspaceExpand(_ thinkspace: Thinkspace) {
        withAnimation(ProMotionSprings.snappy) {
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

    private func navigateToChildDoc(_ doc: ChildDoc) {
        NotificationCenter.default.post(
            name: .enterFocusMode,
            object: nil,
            userInfo: ["type": doc.entityType, "id": doc.entityId]
        )
        if !isLocked {
            withAnimation(ProMotionSprings.snappy) {
                isVisible = false
            }
        }
    }

    private func createThinkspace() {
        guard !newName.isEmpty else {
            isCreatingThinkspace = false
            return
        }
        Task {
            // Auto-assign to currently filtered project
            if let thinkspace = await manager.createThinkspace(
                name: newName,
                projectUuid: selectedProjectFilter
            ) {
                await manager.switchTo(thinkspace)
            }
            withAnimation(ProMotionSprings.snappy) {
                isCreatingThinkspace = false
                if !isLocked { isVisible = false }
            }
        }
    }

    private func createNewProject() {
        let trimmed = newProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            withAnimation(ProMotionSprings.snappy) {
                isCreatingProject = false
                newProjectName = ""
            }
            return
        }
        Task {
            do {
                let nextColor = nextAvailableColor()
                let project = try await repository.createProject(title: trimmed, color: nextColor)
                await manager.loadThinkspaces()
                await loadProjects()
                withAnimation(ProMotionSprings.snappy) {
                    isCreatingProject = false
                    newProjectName = ""
                    selectedProjectFilter = project.uuid
                }
            } catch {
                print("❌ Failed to create project: \(error)")
                withAnimation(ProMotionSprings.snappy) {
                    isCreatingProject = false
                    newProjectName = ""
                }
            }
        }
    }

    private func deleteProject(_ project: Atom) async {
        do {
            let thinkspaceIds = manager.thinkspacesForProject(project.uuid).map { $0.id }

            let deletedItem = DeletedItem(
                id: UUID().uuidString,
                originalId: project.uuid,
                name: project.title ?? "Untitled Project",
                type: .project,
                deletedAt: Date(),
                associatedItems: thinkspaceIds
            )

            var deletedItems: [DeletedItem] = []
            if let data = UserDefaults.standard.data(forKey: "recentlyDeletedItems"),
               let existing = try? JSONDecoder().decode([DeletedItem].self, from: data) {
                deletedItems = existing
            }
            deletedItems.insert(deletedItem, at: 0)
            if let data = try? JSONEncoder().encode(deletedItems) {
                UserDefaults.standard.set(data, forKey: "recentlyDeletedItems")
            }

            try await repository.softDeleteProject(project.uuid)
            for id in thinkspaceIds {
                await manager.softDelete(id)
            }

            // Reset filter if we deleted the active project
            if selectedProjectFilter == project.uuid {
                selectedProjectFilter = nil
            }

            await loadProjects()
            NotificationCenter.default.post(name: .atomsDidChange, object: nil)
        } catch {
            print("❌ Failed to delete project: \(error)")
        }
    }

    private func submitProjectRename(_ project: Atom) {
        let trimmed = renameProjectText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            renamingProjectId = nil
            renameProjectText = ""
            return
        }
        Task {
            do {
                var updated = project
                updated.title = trimmed
                updated.updatedAt = ISO8601DateFormatter().string(from: Date())
                try await repository.update(updated)
                await loadProjects()
            } catch {
                print("❌ Failed to rename project: \(error)")
            }
            withAnimation(ProMotionSprings.snappy) {
                renamingProjectId = nil
                renameProjectText = ""
            }
        }
    }

    // MARK: - Keyboard Handlers

    private func handleKeyDown() {
        isKeyboardNavigating = true
        let items = allNavigableItems
        guard !items.isEmpty else { return }
        withAnimation(ProMotionSprings.snappy) {
            selectedIndex = min(selectedIndex + 1, items.count - 1)
            updateHoverFromKeyboard()
        }
    }

    private func handleKeyUp() {
        isKeyboardNavigating = true
        let items = allNavigableItems
        guard !items.isEmpty else { return }
        withAnimation(ProMotionSprings.snappy) {
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
            navigateToChildDoc(doc)
        case .project:
            break
        }
    }

    private func handleKeyEscape() {
        if isCreatingThinkspace {
            withAnimation(ProMotionSprings.snappy) {
                isCreatingThinkspace = false
            }
        } else if isCreatingProject {
            withAnimation(ProMotionSprings.snappy) {
                isCreatingProject = false
                newProjectName = ""
            }
        } else if renamingProjectId != nil {
            withAnimation(ProMotionSprings.snappy) {
                renamingProjectId = nil
                renameProjectText = ""
            }
        } else if !isLocked {
            withAnimation(ProMotionSprings.snappy) {
                isVisible = false
            }
        }
    }

    private func handleKeyRight() {
        let items = allNavigableItems
        guard selectedIndex < items.count else { return }
        if case .thinkspace(let thinkspace, _) = items[selectedIndex] {
            toggleThinkspaceExpand(thinkspace)
        }
    }

    private func handleKeyLeft() {
        let items = allNavigableItems
        guard selectedIndex < items.count else { return }
        if case .thinkspace(let thinkspace, _) = items[selectedIndex] {
            withAnimation(ProMotionSprings.snappy) {
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

    private func nextAvailableColor() -> String {
        let usedColors = Set(projects.compactMap {
            $0.metadataValue(as: ProjectMetadata.self)?.color
        })
        return projectColorPalette.first { !usedColors.contains($0) }
            ?? projectColorPalette[projects.count % projectColorPalette.count]
    }

    private func updateProjectColor(_ project: Atom, to colorHex: String) async {
        do {
            var metadata = project.metadataValue(as: ProjectMetadata.self) ?? ProjectMetadata()
            metadata.color = colorHex
            var updated = project.withMetadata(metadata)
            updated.updatedAt = ISO8601DateFormatter().string(from: Date())
            try await repository.update(updated)
            await loadProjects()
        } catch {
            print("Failed to update project color: \(error)")
        }
    }

    private func currentColorHex(for project: Atom) -> String? {
        project.metadataValue(as: ProjectMetadata.self)?.color
    }

    private func colorLabel(for hex: String) -> String {
        switch hex {
        case "#A8CCE8": return "Sky Blue"
        case "#CAB8E8": return "Lavender"
        case "#F4AFA0": return "Coral"
        case "#8FC7A2": return "Emerald"
        case "#F5E6C8": return "Cream"
        case "#E8B8A8": return "Peach"
        case "#A8D8E8": return "Cyan"
        case "#D8A8E8": return "Purple"
        default: return hex
        }
    }
}

// MARK: - Project Option

struct ProjectOption: Identifiable {
    let id: String
    let name: String
    let color: Color
}

// MARK: - Project Filter Chip

struct ProjectFilterChip: View {
    let label: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)

                Text(label)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? color : DS.textSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(isSelected
                          ? color.opacity(0.15)
                          : (isHovered ? DS.glassCardFill : Color.clear))
            )
            .overlay(
                Capsule()
                    .stroke(
                        isSelected ? color.opacity(0.3) : (isHovered ? DS.border : Color.clear),
                        lineWidth: 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - ThinkSpace Row

struct ThinkspaceRow: View {
    let thinkspace: Thinkspace
    let isActive: Bool
    let isHovered: Bool
    let projectName: String?
    let projectColor: Color

    // Child docs
    var isExpanded: Bool = false
    var onToggleExpand: () -> Void = {}
    var childDocs: [ChildDoc] = []
    var isLoadingChildren: Bool = false
    var hoveredChildDocId: String?
    var onChildDocTap: ((ChildDoc) -> Void)?
    var onHoverChildDoc: ((String?) -> Void)?

    // Actions
    let onSelect: () -> Void
    var onDelete: (() -> Void)?
    var onRename: ((String) -> Void)?

    // Project assignment
    var availableProjects: [ProjectOption] = []
    var currentProjectId: String?
    var onAssignToProject: ((String) -> Void)?
    var onUnassignFromProject: (() -> Void)?

    @State private var isRenaming = false
    @State private var renameText = ""
    @FocusState private var isRenameFieldFocused: Bool
    @State private var showDeleteConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isRenaming {
                renameRow
            } else {
                Button(action: onSelect) {
                    rowContent
                }
                .buttonStyle(.plain)
            }

            if isExpanded {
                childDocsSection
            }
        }
        .contextMenu { contextMenuContent }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .animation(ProMotionSprings.snappy, value: isRenaming)
        .animation(ProMotionSprings.snappy, value: isExpanded)
        .confirmationDialog(
            "Delete \"\(thinkspace.name)\"?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { onDelete?() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove the ThinkSpace but keep all blocks.")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("ThinkSpace: \(thinkspace.name), \(thinkspace.blockCount) blocks")
        .accessibilityHint(isActive ? "Currently active" : "Double-tap to open")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    // MARK: - Row Content

    private var rowContent: some View {
        HStack(spacing: 8) {
            // Expand chevron
            Button(action: onToggleExpand) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(DS.textMuted)
                    .frame(width: 12, height: 12)
            }
            .buttonStyle(.plain)

            // Active indicator dot
            Circle()
                .fill(isActive ? DS.accent : Color.clear)
                .frame(width: 6, height: 6)

            // Name + metadata
            VStack(alignment: .leading, spacing: 2) {
                Text(thinkspace.name)
                    .font(.system(size: 13, weight: isActive ? .semibold : .medium))
                    .foregroundColor(DS.text)
                    .lineLimit(1)

                Text("\(thinkspace.blockCount) blocks · \(thinkspace.lastOpenedFormatted)")
                    .font(.system(size: 10))
                    .foregroundColor(DS.textMuted)
            }
            .allowsHitTesting(false)

            Spacer()

            // Project tag
            if let name = projectName {
                Text(name)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(projectColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(projectColor.opacity(0.12), in: Capsule())
                    .allowsHitTesting(false)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isActive
                      ? DS.accent.opacity(0.12)
                      : (isHovered ? DS.glassCardFill : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isActive ? DS.accent.opacity(0.25) : Color.clear, lineWidth: 0.5)
        )
        .contentShape(Rectangle())
    }

    // MARK: - Rename Row

    private var renameRow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(DS.accent.opacity(0.2))
                .frame(width: 28, height: 28)
                .overlay(
                    Image(systemName: "pencil")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(DS.accent)
                )

            TextField("Name", text: $renameText)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(DS.text)
                .focused($isRenameFieldFocused)
                .onSubmit { submitRename() }

            Button { submitRename() } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(DS.accent)
            }
            .buttonStyle(.plain)

            Button {
                isRenaming = false
                renameText = ""
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(DS.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(DS.accent.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(DS.accent.opacity(0.3), lineWidth: 1)
                )
        )
    }

    // MARK: - Child Docs Section

    @ViewBuilder
    private var childDocsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isLoadingChildren {
                HStack(spacing: 8) {
                    Rectangle()
                        .fill(DS.borderActive)
                        .frame(width: 1)
                        .padding(.leading, 25)

                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: DS.accent))
                        .scaleEffect(0.6)

                    Text("Loading...")
                        .font(.system(size: 10))
                        .foregroundColor(DS.textMuted)
                }
                .padding(.vertical, 6)
            } else if childDocs.isEmpty {
                HStack(spacing: 8) {
                    Rectangle()
                        .fill(DS.borderActive)
                        .frame(width: 1)
                        .padding(.leading, 25)

                    Text("No blocks")
                        .font(.system(size: 10))
                        .foregroundColor(DS.textMuted)
                }
                .padding(.vertical, 6)
            } else {
                ForEach(childDocs) { doc in
                    ChildDocRow(
                        doc: doc,
                        isHovered: hoveredChildDocId == doc.id,
                        onTap: { onChildDocTap?(doc) }
                    )
                    .onHover { hovering in
                        onHoverChildDoc?(hovering ? doc.id : nil)
                    }
                }
            }
        }
        .padding(.leading, 8)
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var contextMenuContent: some View {
        Button {
            onSelect()
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
            isRenaming = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isRenameFieldFocused = true
            }
        } label: {
            Label("Rename", systemImage: "pencil")
        }

        // Assign to project submenu
        if !availableProjects.isEmpty {
            Menu("Assign to Project") {
                ForEach(availableProjects) { project in
                    Button {
                        onAssignToProject?(project.id)
                    } label: {
                        HStack {
                            Text(project.name)
                            if currentProjectId == project.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }

                if currentProjectId != nil {
                    Divider()

                    Button {
                        onUnassignFromProject?()
                    } label: {
                        Label("Remove from Project", systemImage: "xmark.circle")
                    }
                }
            }
        }

        if let _ = onDelete {
            Divider()

            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Actions

    private func submitRename() {
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            isRenaming = false
            renameText = ""
            return
        }
        onRename?(trimmed)
        isRenaming = false
        renameText = ""
    }
}

// MARK: - Sidebar Trigger Zone

struct ThinkspaceSidebarTrigger: View {
    @Binding var isVisible: Bool

    @State private var dwellTimer: Timer?

    var body: some View {
        // 1px edge-hugging trigger with 400ms dwell — only fires when cursor is right at the edge
        Color.clear
            .frame(width: 1)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    dwellTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { _ in
                        DispatchQueue.main.async {
                            withAnimation(ProMotionSprings.snappy) {
                                isVisible = true
                            }
                        }
                    }
                } else {
                    dwellTimer?.invalidate()
                    dwellTimer = nil
                }
            }
            .onDisappear {
                dwellTimer?.invalidate()
                dwellTimer = nil
            }
    }
}

// MARK: - Child Doc Row

struct ChildDocRow: View {
    let doc: ChildDoc
    let isHovered: Bool
    var isCompact: Bool = false
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                // Tree connector line
                Rectangle()
                    .fill(DS.borderActive)
                    .frame(width: 1)
                    .padding(.leading, isCompact ? 16 : 21)

                // Horizontal connector
                Rectangle()
                    .fill(DS.borderActive)
                    .frame(width: 8, height: 1)

                // Entity type icon
                RoundedRectangle(cornerRadius: 4)
                    .fill(doc.entityType.color.opacity(0.2))
                    .frame(width: 20, height: 20)
                    .overlay(
                        Image(systemName: doc.entityType.icon)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(doc.entityType.color)
                    )

                // Title
                Text(doc.title)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(DS.text)
                    .lineLimit(1)

                Spacer()

                // Entity type label on hover
                if isHovered {
                    Text(doc.entityType.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(DS.textMuted)
                        .transition(.opacity)
                }
            }
            .padding(.trailing, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? DS.glassCardFill : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(doc.entityType.rawValue): \(doc.title)")
        .accessibilityHint("Double-tap to open in focus mode")
    }
}

// MARK: - Navigable Item

enum NavigableItem {
    case project(Atom)
    case thinkspace(Thinkspace, projectId: String?)
    case childDoc(ChildDoc, thinkspaceId: String)

    var id: String {
        switch self {
        case .project(let atom):
            return "project-\(atom.uuid)"
        case .thinkspace(let thinkspace, _):
            return "thinkspace-\(thinkspace.id)"
        case .childDoc(let doc, _):
            return "childDoc-\(doc.id)"
        }
    }
}

// MARK: - Recently Deleted Section

struct RecentlyDeletedSection: View {
    @State private var deletedItems: [DeletedItem] = []
    @State private var isExpanded = false
    @State private var hoveredItemId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section header
            Button {
                withAnimation(ProMotionSprings.snappy) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(DS.textMuted)
                        .frame(width: 10)

                    AnimatedTrashIcon(isExpanded: isExpanded)

                    Text("Recently Deleted")
                        .dsSmallCapsLabel()

                    if !deletedItems.isEmpty {
                        Text("\(deletedItems.count)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(DS.textMuted)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(DS.glassCardFill, in: Capsule())
                    }

                    Spacer()

                    if !deletedItems.isEmpty && isExpanded {
                        Button {
                            emptyTrash()
                        } label: {
                            Text("Empty")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(Color(hex: "FF5F57").opacity(0.8))
                        }
                        .buttonStyle(.plain)
                        .transition(.opacity)
                    }
                }
                .padding(.leading, 4)
            }
            .buttonStyle(.plain)

            // Deleted items list
            if isExpanded {
                if deletedItems.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "trash.slash")
                            .font(.system(size: 16))
                            .foregroundColor(DS.textMuted)

                        Text("Trash is empty")
                            .font(.system(size: 11))
                            .foregroundColor(DS.textMuted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                } else {
                    ForEach(deletedItems) { item in
                        DeletedItemRow(
                            item: item,
                            isHovered: hoveredItemId == item.id,
                            onRestore: { restoreItem(item) },
                            onDeletePermanently: { permanentlyDelete(item) }
                        )
                        .onHover { hovering in
                            hoveredItemId = hovering ? item.id : nil
                        }
                    }
                }
            }
        }
        .task {
            await loadDeletedItems()
        }
    }

    private func loadDeletedItems() async {
        if let data = UserDefaults.standard.data(forKey: "recentlyDeletedItems"),
           let items = try? JSONDecoder().decode([DeletedItem].self, from: data) {
            let cutoff = Date().addingTimeInterval(-30 * 24 * 60 * 60)
            deletedItems = items.filter { $0.deletedAt > cutoff }
                .sorted { $0.deletedAt > $1.deletedAt }
        }
    }

    private func restoreItem(_ item: DeletedItem) {
        Task {
            switch item.type {
            case .thinkspace:
                await ThinkspaceManager.shared.restoreThinkspace(item.originalId)
            case .project:
                await restoreProject(item.originalId)
            }
            deletedItems.removeAll { $0.id == item.id }
            saveDeletedItems()
        }
    }

    private func permanentlyDelete(_ item: DeletedItem) {
        Task {
            switch item.type {
            case .thinkspace:
                await ThinkspaceManager.shared.permanentlyDelete(item.originalId)
            case .project:
                try? await AtomRepository.shared.permanentlyDeleteProject(item.originalId)
            }
            deletedItems.removeAll { $0.id == item.id }
            saveDeletedItems()
        }
    }

    private func emptyTrash() {
        Task {
            for item in deletedItems {
                await permanentlyDeleteAsync(item)
            }
            deletedItems.removeAll()
            saveDeletedItems()
        }
    }

    private func permanentlyDeleteAsync(_ item: DeletedItem) async {
        switch item.type {
        case .thinkspace:
            await ThinkspaceManager.shared.permanentlyDelete(item.originalId)
        case .project:
            try? await AtomRepository.shared.permanentlyDeleteProject(item.originalId)
        }
    }

    private func restoreProject(_ projectId: String) async {
        try? await AtomRepository.shared.restoreProject(projectId)
    }

    private func saveDeletedItems() {
        if let data = try? JSONEncoder().encode(deletedItems) {
            UserDefaults.standard.set(data, forKey: "recentlyDeletedItems")
        }
    }
}

// MARK: - Animated Trash Icon

struct AnimatedTrashIcon: View {
    let isExpanded: Bool

    @State private var isHovered = false

    var body: some View {
        ZStack {
            Image(systemName: "trash")
                .font(.system(size: 12))
                .foregroundColor(isHovered ? Color(hex: "FF5F57") : DS.textMuted)

            if isHovered || isExpanded {
                RoundedRectangle(cornerRadius: 1)
                    .fill(isHovered ? Color(hex: "FF5F57") : DS.textMuted)
                    .frame(width: 10, height: 2)
                    .offset(y: -5)
                    .rotationEffect(
                        .degrees(isHovered ? -20 : (isExpanded ? -10 : 0)),
                        anchor: .leading
                    )
            }
        }
        .onHover { hovering in
            withAnimation(ProMotionSprings.snappy) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Animated Trash Button

struct AnimatedTrashButton: View {
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Image(systemName: "trash")
                    .font(.system(size: 10))
                    .foregroundColor(isHovered ? Color(hex: "FF5F57") : DS.textMuted)
                    .opacity(isHovered ? 0 : 1)

                Image(systemName: "trash")
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "FF5F57"))
                    .opacity(isHovered ? 1 : 0)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(Color(hex: "FF5F57"))
                            .frame(width: 8, height: 2)
                            .offset(y: -1)
                            .rotationEffect(.degrees(isHovered ? -15 : 0), anchor: .leading)
                            .opacity(isHovered ? 1 : 0)
                    }
            }
            .scaleEffect(isHovered ? 1.15 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(ProMotionSprings.snappy) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Deleted Item Row

struct DeletedItemRow: View {
    let item: DeletedItem
    let isHovered: Bool
    let onRestore: () -> Void
    let onDeletePermanently: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.type == .project ? "folder" : "rectangle.3.group")
                .font(.system(size: 10))
                .foregroundColor(DS.textMuted)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 12))
                    .foregroundColor(DS.textSecondary)
                    .lineLimit(1)
                    .strikethrough(true, color: DS.textMuted)

                Text(item.daysRemaining)
                    .font(.system(size: 10))
                    .foregroundColor(DS.textMuted)
            }
            .allowsHitTesting(false)

            Spacer()

            if isHovered {
                HStack(spacing: 6) {
                    Button {
                        onRestore()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 10))
                            .foregroundColor(DS.accent)
                    }
                    .buttonStyle(.plain)
                    .help("Restore")

                    AnimatedTrashButton {
                        onDeletePermanently()
                    }
                    .help("Delete permanently")
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? DS.glassCardFill : Color.clear)
        )
        .contentShape(Rectangle())
    }
}

// MARK: - Deleted Item Model

struct DeletedItem: Identifiable, Codable {
    let id: String
    let originalId: String
    let name: String
    let type: DeletedItemType
    let deletedAt: Date
    var associatedItems: [String]

    var daysRemaining: String {
        let remaining = 30 - Calendar.current.dateComponents([.day], from: deletedAt, to: Date()).day!
        if remaining <= 0 {
            return "Expiring soon"
        } else if remaining == 1 {
            return "1 day left"
        } else {
            return "\(remaining) days left"
        }
    }
}

enum DeletedItemType: String, Codable {
    case thinkspace
    case project
}

// MARK: - Preview

#if DEBUG
struct ThinkspaceSidebar_Previews: PreviewProvider {
    @State static var isVisible = true

    static var previews: some View {
        ZStack {
            DS.canvas
                .ignoresSafeArea()

            HStack {
                ThinkspaceSidebar(
                    manager: ThinkspaceManager.shared,
                    isVisible: $isVisible
                )
                Spacer()
            }
        }
        .frame(width: 800, height: 600)
    }
}
#endif
