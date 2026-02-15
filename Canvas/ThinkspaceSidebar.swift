// CosmoOS/Canvas/ThinkspaceSidebar.swift
// Left-edge hover sidebar for browsing Projects and ThinkSpaces
// December 2025 - Project System Architecture (Two-Section Design)
// Apple-level polish: Keyboard nav, context menus, accessibility

import SwiftUI

// MARK: - Thinkspace Sidebar

/// Left-edge sidebar with two sections: Projects (expandable) + Unassigned ThinkSpaces
/// Features: Keyboard navigation, right-click context menus, full accessibility
struct ThinkspaceSidebar: View {
    @ObservedObject var manager: ThinkspaceManager
    @Binding var isVisible: Bool  // Local binding for CanvasView

    // Lock state - persisted to UserDefaults
    @AppStorage("thinkspaceSidebarLocked") private var isLocked: Bool = false

    // Internal hover tracking for close behavior
    @State private var isHovering: Bool = false

    /// Computed: Update manager's sidebar visibility for other views to observe
    private func updateManagerVisibility(_ visible: Bool) {
        manager.isSidebarVisible = visible
    }

    // Projects data
    @State private var projects: [Atom] = []
    @State private var expandedProjects: Set<String> = []

    // Creation state
    @State private var isCreatingThinkspace = false
    @State private var isCreatingSubThinkspace = false
    @State private var parentForNewThinkspace: Thinkspace?
    @State private var newName = ""
    @FocusState private var isNameFieldFocused: Bool

    // Hover states
    @State private var hoveredThinkspaceId: String?
    @State private var hoveredProjectId: String?
    @State private var closeTimer: Timer?

    // Keyboard navigation
    @State private var selectedIndex: Int = 0
    @State private var isKeyboardNavigating: Bool = false
    @FocusState private var isSidebarFocused: Bool

    // Loading state
    @State private var isLoading: Bool = false
    @State private var loadError: String?

    // Rename state
    @State private var renamingThinkspaceId: String?
    @State private var renameText: String = ""
    @FocusState private var isRenameFieldFocused: Bool

    // Drop state for project creation
    @State private var isDropTargetActive: Bool = false

    private let sidebarWidth: CGFloat = 280
    private let repository = AtomRepository.shared

    /// Whether sidebar should be visible
    /// Stays open if locked, visible via trigger, or being hovered
    var shouldShowSidebar: Bool {
        isLocked || isVisible || isHovering
    }

    /// All navigable items for keyboard navigation
    private var allNavigableItems: [NavigableItem] {
        var items: [NavigableItem] = []

        // Add project items
        for project in projects {
            items.append(.project(project))
            if expandedProjects.contains(project.uuid) {
                for thinkspace in manager.thinkspacesForProject(project.uuid) {
                    items.append(.thinkspace(thinkspace, projectId: project.uuid))
                }
            }
        }

        // Add unassigned thinkspaces
        for thinkspace in manager.unassignedThinkspaces() {
            items.append(.thinkspace(thinkspace, projectId: nil))
        }

        return items
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with lock button
            header

            Divider()
                .background(Color.white.opacity(0.1))

            // Main content
            ScrollView {
                VStack(spacing: 16) {
                    // Loading indicator
                    if isLoading {
                        loadingView
                    } else if let error = loadError {
                        errorView(error)
                    } else {
                        // Projects Section
                        projectsSection

                        // Divider
                        sectionDivider

                        // Unassigned ThinkSpaces Section
                        unassignedSection

                        // Divider before trash
                        sectionDivider

                        // Recently Deleted Section
                        RecentlyDeletedSection()
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
        }
        .frame(width: sidebarWidth)
        .background(sidebarBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.4), radius: 20, x: 5, y: 0)
        .offset(x: shouldShowSidebar ? 0 : -sidebarWidth - 20)
        .animation(ProMotionSprings.snappy, value: shouldShowSidebar)
        .onHover { hovering in
            handleHover(hovering)
        }
        .focused($isSidebarFocused)
        .focusable()
        .focusEffectDisabled()  // Disable purple focus ring
        .onKeyPress(.downArrow) { handleKeyDown(); return .handled }
        .onKeyPress(.upArrow) { handleKeyUp(); return .handled }
        .onKeyPress(.return) {
            // Don't intercept return when text field is active
            if isCreatingThinkspace || isCreatingSubThinkspace || renamingThinkspaceId != nil {
                return .ignored  // Let TextField handle it
            }
            handleKeyReturn()
            return .handled
        }
        .onKeyPress(.escape) { handleKeyEscape(); return .handled }
        .onKeyPress(.rightArrow) { handleKeyRight(); return .handled }
        .onKeyPress(.leftArrow) { handleKeyLeft(); return .handled }
        .task {
            await loadProjects()
        }
        .onReceive(NotificationCenter.default.publisher(for: .atomsDidChange)) { _ in
            Task { await loadProjects() }
        }
        .onChange(of: shouldShowSidebar) { _, newValue in
            updateManagerVisibility(newValue)
        }
        .onAppear {
            // Sync initial state
            updateManagerVisibility(shouldShowSidebar)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("ThinkSpaces sidebar")
        .accessibilityHint("Navigate with arrow keys, press Return to select")
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: CosmoColors.thinkspacePurple))
                .scaleEffect(0.8)

            Text("Loading...")
                .font(.system(size: 12))
                .foregroundColor(Color.white.opacity(0.5))
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
                .foregroundColor(Color.white.opacity(0.8))

            Text(error)
                .font(.system(size: 11))
                .foregroundColor(Color.white.opacity(0.4))
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
                .foregroundColor(CosmoColors.thinkspacePurple)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(CosmoColors.thinkspacePurple.opacity(0.15), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, minHeight: 100)
        .padding()
        .accessibilityLabel("Error loading ThinkSpaces: \(error)")
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("THINKSPACES")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(Color.white.opacity(0.5))
                .tracking(1.2)

            Spacer()

            // Lock button
            Button {
                withAnimation(ProMotionSprings.snappy) {
                    isLocked.toggle()
                }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isLocked ? .white : Color.white.opacity(0.4))
                    .padding(6)
                    .background(
                        isLocked
                            ? Color(hex: "#1A1A25")
                            : Color.clear,
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
                    parentForNewThinkspace = nil
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
                .foregroundColor(CosmoColors.thinkspacePurple)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    CosmoColors.thinkspacePurple.opacity(0.15),
                    in: Capsule()
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Projects Section

    private var projectsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section header with count - also a drop target
            HStack {
                Text("PROJECTS")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(isDropTargetActive ? CosmoColors.thinkspacePurple : Color.white.opacity(0.5))
                    .tracking(1)

                if !projects.isEmpty {
                    Text("\(projects.count)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.3))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.08), in: Capsule())
                }

                Spacer()

                // Drop hint when dragging
                if isDropTargetActive {
                    Text("Drop to create project")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(CosmoColors.thinkspacePurple)
                        .transition(.opacity)
                }
            }
            .padding(.leading, 4)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isDropTargetActive ? CosmoColors.thinkspacePurple.opacity(0.15) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isDropTargetActive ? CosmoColors.thinkspacePurple.opacity(0.5) : Color.clear, lineWidth: 1)
                    )
            )
            .animation(ProMotionSprings.snappy, value: isDropTargetActive)
            .dropDestination(for: String.self) { items, location in
                // Create a new project from the dropped ThinkSpace
                guard let thinkspaceId = items.first else { return false }
                Task {
                    await createProjectFromThinkspace(thinkspaceId: thinkspaceId)
                }
                return true
            } isTargeted: { isTargeted in
                withAnimation(ProMotionSprings.snappy) {
                    isDropTargetActive = isTargeted
                }
            }
            .accessibilityLabel("Projects section, \(projects.count) projects. Drop a ThinkSpace here to create a project")

            if projects.isEmpty {
                // Enhanced empty state - also a drop target
                VStack(spacing: 8) {
                    Image(systemName: isDropTargetActive ? "folder.fill.badge.plus" : "folder.badge.plus")
                        .font(.system(size: 20))
                        .foregroundColor(isDropTargetActive ? CosmoColors.thinkspacePurple : Color.white.opacity(0.2))

                    Text(isDropTargetActive ? "Drop to create project" : "No projects yet")
                        .font(.system(size: 12))
                        .foregroundColor(isDropTargetActive ? CosmoColors.thinkspacePurple : Color.white.opacity(0.3))

                    if !isDropTargetActive {
                        Text("Drag a ThinkSpace here to create a project")
                            .font(.system(size: 10))
                            .foregroundColor(Color.white.opacity(0.2))
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isDropTargetActive ? CosmoColors.thinkspacePurple.opacity(0.1) : Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(
                                    isDropTargetActive ? CosmoColors.thinkspacePurple.opacity(0.5) : Color.white.opacity(0.05),
                                    style: StrokeStyle(lineWidth: 1, dash: isDropTargetActive ? [] : [4, 4])
                                )
                        )
                )
                .animation(ProMotionSprings.snappy, value: isDropTargetActive)
                .dropDestination(for: String.self) { items, location in
                    guard let thinkspaceId = items.first else { return false }
                    Task {
                        await createProjectFromThinkspace(thinkspaceId: thinkspaceId)
                    }
                    return true
                } isTargeted: { isTargeted in
                    withAnimation(ProMotionSprings.snappy) {
                        isDropTargetActive = isTargeted
                    }
                }
                .accessibilityLabel("No projects. Drag a ThinkSpace here to create a project")
            } else {
                ForEach(projects, id: \.uuid) { project in
                    ProjectTreeItem(
                        project: project,
                        thinkspaces: manager.thinkspacesForProject(project.uuid),
                        isExpanded: expandedProjects.contains(project.uuid),
                        currentThinkspaceId: manager.currentThinkspace?.id,
                        hoveredThinkspaceId: hoveredThinkspaceId,
                        onToggleExpand: {
                            withAnimation(ProMotionSprings.snappy) {
                                if expandedProjects.contains(project.uuid) {
                                    expandedProjects.remove(project.uuid)
                                } else {
                                    expandedProjects.insert(project.uuid)
                                }
                            }
                        },
                        onSelectThinkspace: { thinkspace in
                            selectThinkspace(thinkspace)
                        },
                        onCreateSubThinkspace: { parentThinkspace in
                            withAnimation(ProMotionSprings.snappy) {
                                isCreatingSubThinkspace = true
                                parentForNewThinkspace = parentThinkspace
                                newName = ""
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                isNameFieldFocused = true
                            }
                        },
                        onHoverThinkspace: { id in
                            hoveredThinkspaceId = id
                        },
                        onDeleteProject: { projectToDelete in
                            Task {
                                await deleteProject(projectToDelete)
                            }
                        }
                    )
                }
            }
        }
    }

    // MARK: - Section Divider

    private var sectionDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.1))
            .frame(height: 1)
            .padding(.horizontal, 4)
    }

    // MARK: - Unassigned Section

    private var unassignedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section header with count
            HStack {
                Text("UNASSIGNED")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.5))
                    .tracking(1)

                let unassigned = manager.unassignedThinkspaces()
                if !unassigned.isEmpty {
                    Text("\(unassigned.count)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.3))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.08), in: Capsule())
                }
            }
            .padding(.leading, 4)
            .accessibilityLabel("Unassigned section, \(manager.unassignedThinkspaces().count) ThinkSpaces")

            // New ThinkSpace creation row
            if isCreatingThinkspace && parentForNewThinkspace == nil {
                newThinkspaceRow
            }

            let unassigned = manager.unassignedThinkspaces()
            if unassigned.isEmpty && !isCreatingThinkspace {
                // Enhanced empty state
                VStack(spacing: 8) {
                    Image(systemName: "rectangle.3.group")
                        .font(.system(size: 20))
                        .foregroundColor(Color.white.opacity(0.2))

                    Text("No loose ThinkSpaces")
                        .font(.system(size: 12))
                        .foregroundColor(Color.white.opacity(0.3))

                    Text("Drag ThinkSpaces here to unassign from projects")
                        .font(.system(size: 10))
                        .foregroundColor(Color.white.opacity(0.2))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .accessibilityLabel("No unassigned ThinkSpaces")
            } else {
                ForEach(unassigned) { thinkspace in
                    ThinkspaceCard(
                        thinkspace: thinkspace,
                        isActive: manager.currentThinkspace?.id == thinkspace.id,
                        isHovered: hoveredThinkspaceId == thinkspace.id,
                        showAddButton: true,
                        onSelect: {
                            selectThinkspace(thinkspace)
                        },
                        onAddSubThinkspace: {
                            withAnimation(ProMotionSprings.snappy) {
                                isCreatingSubThinkspace = true
                                parentForNewThinkspace = thinkspace
                                newName = ""
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                isNameFieldFocused = true
                            }
                        },
                        onDelete: {
                            Task {
                                await manager.delete(thinkspace)
                            }
                        }
                    )
                    .onHover { hovering in
                        hoveredThinkspaceId = hovering ? thinkspace.id : nil
                    }
                    .draggable(thinkspace.id) // Enable drag for unassigned
                }
            }
        }
    }

    // MARK: - New ThinkSpace Row

    private var newThinkspaceRow: some View {
        HStack(spacing: 10) {
            // Icon
            Circle()
                .fill(CosmoColors.thinkspacePurple.opacity(0.2))
                .frame(width: 28, height: 28)
                .overlay(
                    Image(systemName: "rectangle.3.group")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(CosmoColors.thinkspacePurple)
                )

            // Text field
            TextField("Thinkspace name", text: $newName)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .focused($isNameFieldFocused)
                .onSubmit {
                    createThinkspace()
                }

            // Cancel button
            Button {
                withAnimation(ProMotionSprings.snappy) {
                    isCreatingThinkspace = false
                    isCreatingSubThinkspace = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(CosmoColors.thinkspacePurple.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(CosmoColors.thinkspacePurple.opacity(0.3), lineWidth: 1)
                )
        )
        .transition(.asymmetric(
            insertion: .scale(scale: 0.95).combined(with: .opacity),
            removal: .opacity
        ))
    }

    // MARK: - Background

    private var sidebarBackground: some View {
        ZStack {
            Color(hex: "#0D0D14")  // Darker than canvas

            // Subtle gradient
            LinearGradient(
                colors: [
                    CosmoColors.thinkspacePurple.opacity(0.03),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    // MARK: - Actions

    private func handleHover(_ hovering: Bool) {
        if hovering {
            // Cancel any pending close
            closeTimer?.invalidate()
            closeTimer = nil
            isHovering = true
        } else {
            // Don't close if locked
            guard !isLocked else {
                isHovering = false
                return
            }

            // Delay close to prevent flicker when moving between trigger and sidebar
            // Use a longer delay (300ms) to allow smooth transitions
            closeTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { _ in
                DispatchQueue.main.async {
                    // Only close if still not hovering
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

    // MARK: - Keyboard Navigation Handlers

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

        let item = items[selectedIndex]
        switch item {
        case .project(let project):
            // Toggle expand/collapse
            withAnimation(ProMotionSprings.snappy) {
                if expandedProjects.contains(project.uuid) {
                    expandedProjects.remove(project.uuid)
                } else {
                    expandedProjects.insert(project.uuid)
                }
            }
        case .thinkspace(let thinkspace, _):
            selectThinkspace(thinkspace)
        }
    }

    private func handleKeyEscape() {
        if isCreatingThinkspace || isCreatingSubThinkspace {
            withAnimation(ProMotionSprings.snappy) {
                isCreatingThinkspace = false
                isCreatingSubThinkspace = false
            }
        } else if renamingThinkspaceId != nil {
            withAnimation(ProMotionSprings.snappy) {
                renamingThinkspaceId = nil
                renameText = ""
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

        let item = items[selectedIndex]
        if case .project(let project) = item {
            _ = withAnimation(ProMotionSprings.snappy) {
                expandedProjects.insert(project.uuid)
            }
        }
    }

    private func handleKeyLeft() {
        let items = allNavigableItems
        guard selectedIndex < items.count else { return }

        let item = items[selectedIndex]
        if case .project(let project) = item {
            _ = withAnimation(ProMotionSprings.snappy) {
                expandedProjects.remove(project.uuid)
            }
        }
    }

    private func updateHoverFromKeyboard() {
        let items = allNavigableItems
        guard selectedIndex < items.count else { return }

        switch items[selectedIndex] {
        case .project(let project):
            hoveredProjectId = project.uuid
            hoveredThinkspaceId = nil
        case .thinkspace(let thinkspace, _):
            hoveredThinkspaceId = thinkspace.id
            hoveredProjectId = nil
        }
    }

    private func selectThinkspace(_ thinkspace: Thinkspace) {
        Task {
            await manager.switchTo(thinkspace)
        }

        // Only close if not locked
        if !isLocked {
            withAnimation(ProMotionSprings.snappy) {
                isVisible = false
            }
        }
    }

    private func createThinkspace() {
        guard !newName.isEmpty else {
            isCreatingThinkspace = false
            isCreatingSubThinkspace = false
            return
        }

        Task {
            if let parent = parentForNewThinkspace {
                // Create sub-ThinkSpace
                if let newThinkspace = await manager.createSubThinkspace(name: newName, parent: parent) {
                    await manager.switchTo(newThinkspace)
                }
            } else {
                // Create unassigned ThinkSpace
                if let thinkspace = await manager.createThinkspace(name: newName) {
                    await manager.switchTo(thinkspace)
                }
            }

            withAnimation(ProMotionSprings.snappy) {
                isCreatingThinkspace = false
                isCreatingSubThinkspace = false
                if !isLocked {
                    isVisible = false
                }
            }
        }
    }

    /// Delete a project and move it to Recently Deleted
    /// Also moves all associated ThinkSpaces to Recently Deleted
    private func deleteProject(_ project: Atom) async {
        do {
            // Get all ThinkSpaces for this project
            let thinkspaceIds = manager.thinkspacesForProject(project.uuid).map { $0.id }

            // Create deleted item record
            let deletedItem = DeletedItem(
                id: UUID().uuidString,
                originalId: project.uuid,
                name: project.title ?? "Untitled Project",
                type: .project,
                deletedAt: Date(),
                associatedItems: thinkspaceIds
            )

            // Save to deleted items list
            var deletedItems: [DeletedItem] = []
            if let data = UserDefaults.standard.data(forKey: "recentlyDeletedItems"),
               let existingItems = try? JSONDecoder().decode([DeletedItem].self, from: data) {
                deletedItems = existingItems
            }
            deletedItems.insert(deletedItem, at: 0)
            if let data = try? JSONEncoder().encode(deletedItems) {
                UserDefaults.standard.set(data, forKey: "recentlyDeletedItems")
            }

            // Mark project as deleted (soft delete)
            try await repository.softDeleteProject(project.uuid)

            // Mark all associated ThinkSpaces as deleted
            for thinkspaceId in thinkspaceIds {
                await manager.softDelete(thinkspaceId)
            }

            // Refresh projects list
            await loadProjects()

            // Notify other views about the deletion
            NotificationCenter.default.post(name: .atomsDidChange, object: nil)

            print("✅ Deleted project '\(project.title ?? "")' and \(thinkspaceIds.count) ThinkSpaces")
        } catch {
            print("❌ Failed to delete project: \(error)")
        }
    }

    /// Create a new project from a ThinkSpace
    /// The ThinkSpace becomes the root ThinkSpace of the new project (no duplicate created)
    private func createProjectFromThinkspace(thinkspaceId: String) async {
        // Find the thinkspace
        guard let thinkspace = manager.unassignedThinkspaces().first(where: { $0.id == thinkspaceId }) else {
            print("⚠️ ThinkSpace not found for project creation: \(thinkspaceId)")
            return
        }

        do {
            // Create project using the existing thinkspace as root
            // This avoids creating a duplicate - the thinkspace becomes the root
            let project = try await repository.createProjectFromThinkspace(
                thinkspaceUuid: thinkspaceId,
                thinkspaceName: thinkspace.name,
                color: "#8B5CF6"  // Purple
            )

            // Reload thinkspaces to reflect the change
            await manager.loadThinkspaces()

            // Refresh projects list
            await loadProjects()

            // Expand the new project
            _ = withAnimation(ProMotionSprings.snappy) {
                expandedProjects.insert(project.uuid)
            }

            print("✅ Created project '\(thinkspace.name)' from ThinkSpace (as root)")
        } catch {
            print("❌ Failed to create project from ThinkSpace: \(error)")
        }
    }
}

// MARK: - Project Tree Item

struct ProjectTreeItem: View {
    let project: Atom
    let thinkspaces: [Thinkspace]
    let isExpanded: Bool
    let currentThinkspaceId: String?
    let hoveredThinkspaceId: String?
    let onToggleExpand: () -> Void
    let onSelectThinkspace: (Thinkspace) -> Void
    let onCreateSubThinkspace: (Thinkspace) -> Void
    let onHoverThinkspace: (String?) -> Void
    var onDeleteProject: ((Atom) -> Void)?

    @State private var isHovered = false
    @State private var showDeleteConfirm = false

    private var projectColor: Color {
        if let metadata = project.metadataValue(as: ProjectMetadata.self),
           let colorHex = metadata.color {
            return Color(hex: colorHex)
        }
        return CosmoColors.thinkspacePurple
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Project header row
            Button(action: onToggleExpand) {
                HStack(spacing: 8) {
                    // Disclosure arrow
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.4))
                        .frame(width: 12)

                    // Project icon/emoji
                    Text(projectIcon)
                        .font(.system(size: 14))

                    // Project name - disable hit testing to prevent text cursor
                    Text(project.title ?? "Untitled Project")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .allowsHitTesting(false)

                    Spacer()

                    // ThinkSpace count
                    Text("\(thinkspaces.count)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.4))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.08), in: Capsule())
                        .allowsHitTesting(false)

                    // Hover actions
                    if isHovered {
                        HStack(spacing: 4) {
                            // Add button
                            if let rootThinkspace = thinkspaces.first(where: { $0.isRootThinkspace }) {
                                Button {
                                    onCreateSubThinkspace(rootThinkspace)
                                } label: {
                                    Image(systemName: "plus")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(Color.white.opacity(0.5))
                                }
                                .buttonStyle(.plain)
                            }

                            // Delete available via right-click context menu
                        }
                        .transition(.opacity)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isHovered ? Color.white.opacity(0.05) : Color.clear)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isHovered = hovering
            }
            .contextMenu {
                projectContextMenu
            }
            .confirmationDialog(
                "Delete \"\(project.title ?? "Untitled Project")\"?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    onDeleteProject?(project)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This project and all its ThinkSpaces will be moved to Recently Deleted for 30 days.")
            }

            // Child ThinkSpaces (when expanded)
            if isExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(thinkspaces) { thinkspace in
                        HStack(spacing: 6) {
                            // Tree line
                            Rectangle()
                                .fill(Color.white.opacity(0.1))
                                .frame(width: 1)
                                .padding(.leading, 16)

                            ThinkspaceCard(
                                thinkspace: thinkspace,
                                isActive: currentThinkspaceId == thinkspace.id,
                                isHovered: hoveredThinkspaceId == thinkspace.id,
                                showAddButton: true,
                                isCompact: true,
                                accentColor: projectColor,
                                onSelect: {
                                    onSelectThinkspace(thinkspace)
                                },
                                onAddSubThinkspace: {
                                    onCreateSubThinkspace(thinkspace)
                                },
                                onDelete: nil  // Can't delete from project view (only root)
                            )
                            .onHover { hovering in
                                onHoverThinkspace(hovering ? thinkspace.id : nil)
                            }
                        }
                    }
                }
                .padding(.leading, 8)
            }
        }
        .dropDestination(for: String.self) { items, location in
            // Handle drop of ThinkSpace onto project
            guard let thinkspaceId = items.first else { return false }
            Task {
                await ThinkspaceManager.shared.assignThinkspace(thinkspaceId, to: project.uuid)
            }
            return true
        } isTargeted: { isTargeted in
            // Show drop target feedback
            if isTargeted {
                isHovered = true
            }
        }
    }

    private var projectIcon: String {
        // Could parse from project metadata in future
        "💼"
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var projectContextMenu: some View {
        Button {
            onToggleExpand()
        } label: {
            Label(isExpanded ? "Collapse" : "Expand", systemImage: isExpanded ? "chevron.up" : "chevron.down")
        }

        Divider()

        if let rootThinkspace = thinkspaces.first(where: { $0.isRootThinkspace }) {
            Button {
                onCreateSubThinkspace(rootThinkspace)
            } label: {
                Label("New ThinkSpace", systemImage: "plus.rectangle.on.rectangle")
            }
        }

        Divider()

        if onDeleteProject != nil {
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("Delete Project", systemImage: "trash")
            }
        }
    }
}

// MARK: - ThinkSpace Card

struct ThinkspaceCard: View {
    let thinkspace: Thinkspace
    let isActive: Bool
    let isHovered: Bool
    let showAddButton: Bool
    var isCompact: Bool = false
    var accentColor: Color = CosmoColors.thinkspacePurple
    let onSelect: () -> Void
    var onAddSubThinkspace: (() -> Void)?
    var onDelete: (() -> Void)?
    var onRename: ((String) -> Void)?
    var onDuplicate: (() -> Void)?

    @State private var showDeleteConfirm = false
    @State private var isRenaming = false
    @State private var renameText = ""
    @FocusState private var isRenameFieldFocused: Bool

    var body: some View {
        Group {
            if isRenaming {
                // Inline rename field
                HStack(spacing: 8) {
                    Circle()
                        .fill(accentColor.opacity(0.2))
                        .frame(width: isCompact ? 24 : 28, height: isCompact ? 24 : 28)
                        .overlay(
                            Image(systemName: "pencil")
                                .font(.system(size: isCompact ? 10 : 11, weight: .medium))
                                .foregroundColor(accentColor)
                        )

                    TextField("Name", text: $renameText)
                        .textFieldStyle(.plain)
                        .font(.system(size: isCompact ? 12 : 13, weight: .medium))
                        .foregroundColor(.white)
                        .focused($isRenameFieldFocused)
                        .onSubmit {
                            submitRename()
                        }

                    Button {
                        submitRename()
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(accentColor)
                    }
                    .buttonStyle(.plain)

                    Button {
                        isRenaming = false
                        renameText = ""
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, isCompact ? 8 : 10)
                .padding(.vertical, isCompact ? 6 : 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(accentColor.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(accentColor.opacity(0.3), lineWidth: 1)
                        )
                )
            } else {
                // Normal card view
                Button(action: onSelect) {
                    cardContent
                }
                .buttonStyle(.plain)
                .contextMenu {
                    contextMenuContent
                }
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .animation(ProMotionSprings.snappy, value: isRenaming)
        .confirmationDialog(
            "Delete \"\(thinkspace.name)\"?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                onDelete?()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove the Thinkspace but keep all blocks.")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityHint(isActive ? "Currently active" : "Double-tap to open")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    // MARK: - Card Content

    private var cardContent: some View {
        HStack(spacing: 8) {
            // Active indicator
            if !isCompact {
                Circle()
                    .fill(isActive ? accentColor : Color.clear)
                    .frame(width: 5, height: 5)
            }

            // Icon
            Circle()
                .fill(isActive
                      ? accentColor.opacity(0.2)
                      : Color.white.opacity(0.05))
                .frame(width: isCompact ? 24 : 28, height: isCompact ? 24 : 28)
                .overlay(
                    Image(systemName: thinkspace.isRootThinkspace ? "rectangle.3.group.fill" : "rectangle.3.group")
                        .font(.system(size: isCompact ? 10 : 11, weight: .medium))
                        .foregroundColor(isActive ? accentColor : Color.white.opacity(0.5))
                )

            // Text - disable hit testing to prevent text cursor
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(thinkspace.name)
                        .font(.system(size: isCompact ? 12 : 13, weight: isActive ? .semibold : .medium))
                        .foregroundColor(isActive ? .white : Color.white.opacity(0.8))
                        .lineLimit(1)

                    if thinkspace.isRootThinkspace {
                        Text("Root")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(accentColor.opacity(0.8))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(accentColor.opacity(0.15), in: Capsule())
                    }
                }

                if !isCompact {
                    Text("\(thinkspace.blockCount) blocks · \(thinkspace.lastOpenedFormatted)")
                        .font(.system(size: 10))
                        .foregroundColor(Color.white.opacity(0.4))
                }
            }
            .allowsHitTesting(false)  // Prevent text cursor on hover

            Spacer()

            // Hover actions
            if isHovered && !thinkspace.isRootThinkspace {
                HStack(spacing: 4) {
                    // Add sub-thinkspace
                    if showAddButton, let onAdd = onAddSubThinkspace {
                        Button {
                            onAdd()
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(Color.white.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                        .help("Add sub-ThinkSpace")
                    }

                    // Delete available via right-click context menu
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, isCompact ? 8 : 10)
        .padding(.vertical, isCompact ? 6 : 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isActive
                      ? accentColor.opacity(0.15)
                      : (isHovered ? Color.white.opacity(0.05) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isActive ? accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())  // Ensure full card is clickable
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var contextMenuContent: some View {
        Button {
            onSelect()
        } label: {
            Label("Open", systemImage: "arrow.right.circle")
        }

        Divider()

        if !thinkspace.isRootThinkspace {
            Button {
                renameText = thinkspace.name
                isRenaming = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isRenameFieldFocused = true
                }
            } label: {
                Label("Rename", systemImage: "pencil")
            }
        }

        if let onDuplicate = onDuplicate {
            Button {
                onDuplicate()
            } label: {
                Label("Duplicate", systemImage: "doc.on.doc")
            }
        }

        if showAddButton, let onAdd = onAddSubThinkspace {
            Button {
                onAdd()
            } label: {
                Label("New Sub-ThinkSpace", systemImage: "plus.rectangle.on.rectangle")
            }
        }

        if !thinkspace.isRootThinkspace, let _ = onDelete {
            Divider()

            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Accessibility

    private var accessibilityDescription: String {
        var desc = "ThinkSpace: \(thinkspace.name)"
        if thinkspace.isRootThinkspace {
            desc += ", Root canvas"
        }
        desc += ", \(thinkspace.blockCount) blocks"
        desc += ", last opened \(thinkspace.lastOpenedFormatted)"
        return desc
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

/// Invisible zone at left edge that triggers sidebar appearance
struct ThinkspaceSidebarTrigger: View {
    @Binding var isVisible: Bool  // Keep API compatible with existing usage

    private let triggerWidth: CGFloat = 20

    var body: some View {
        Color.clear
            .frame(width: triggerWidth)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    withAnimation(ProMotionSprings.snappy) {
                        isVisible = true
                    }
                }
            }
    }
}

// MARK: - Navigable Item (for keyboard navigation)

/// Represents an item in the sidebar that can be navigated to with keyboard
enum NavigableItem {
    case project(Atom)
    case thinkspace(Thinkspace, projectId: String?)

    var id: String {
        switch self {
        case .project(let atom):
            return "project-\(atom.uuid)"
        case .thinkspace(let thinkspace, _):
            return "thinkspace-\(thinkspace.id)"
        }
    }
}

// MARK: - Animated Trash Button

/// Trash can button with hover animation - lid opens and turns red
struct AnimatedTrashButton: View {
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                // Trash can base
                Image(systemName: "trash")
                    .font(.system(size: 10))
                    .foregroundColor(isHovered ? Color(hex: "FF5F57") : Color.white.opacity(0.4))
                    .opacity(isHovered ? 0 : 1)

                // Trash can with open lid (shown on hover)
                Image(systemName: "trash")
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "FF5F57"))
                    .opacity(isHovered ? 1 : 0)
                    .overlay(alignment: .top) {
                        // Animated lid that tilts open
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

// MARK: - Recently Deleted Section

/// Section showing recently deleted items with 30-day retention
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
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.4))
                        .frame(width: 10)

                    AnimatedTrashIcon(isExpanded: isExpanded)

                    Text("RECENTLY DELETED")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.5))
                        .tracking(1)

                    if !deletedItems.isEmpty {
                        Text("\(deletedItems.count)")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.3))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.08), in: Capsule())
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
                            .foregroundColor(Color.white.opacity(0.2))

                        Text("Trash is empty")
                            .font(.system(size: 11))
                            .foregroundColor(Color.white.opacity(0.3))
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
        // Load from UserDefaults or database
        if let data = UserDefaults.standard.data(forKey: "recentlyDeletedItems"),
           let items = try? JSONDecoder().decode([DeletedItem].self, from: data) {
            // Filter out items older than 30 days
            let cutoff = Date().addingTimeInterval(-30 * 24 * 60 * 60)
            deletedItems = items.filter { $0.deletedAt > cutoff }
                .sorted { $0.deletedAt > $1.deletedAt }
        }
    }

    private func restoreItem(_ item: DeletedItem) {
        Task {
            // Restore based on type
            switch item.type {
            case .thinkspace:
                await ThinkspaceManager.shared.restoreThinkspace(item.originalId)
            case .project:
                await restoreProject(item.originalId)
            }

            // Remove from deleted list
            deletedItems.removeAll { $0.id == item.id }
            saveDeletedItems()
        }
    }

    private func permanentlyDelete(_ item: DeletedItem) {
        Task {
            // Actually delete from database
            switch item.type {
            case .thinkspace:
                await ThinkspaceManager.shared.permanentlyDelete(item.originalId)
            case .project:
                try? await AtomRepository.shared.permanentlyDeleteProject(item.originalId)
            }

            // Remove from list
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
        // Unmark as deleted in database
        try? await AtomRepository.shared.restoreProject(projectId)
    }

    private func saveDeletedItems() {
        if let data = try? JSONEncoder().encode(deletedItems) {
            UserDefaults.standard.set(data, forKey: "recentlyDeletedItems")
        }
    }
}

// MARK: - Animated Trash Icon (for section header)

struct AnimatedTrashIcon: View {
    let isExpanded: Bool

    @State private var isHovered = false

    var body: some View {
        ZStack {
            // Base trash icon
            Image(systemName: "trash")
                .font(.system(size: 12))
                .foregroundColor(isHovered ? Color(hex: "FF5F57") : Color.white.opacity(0.4))

            // Lid overlay that animates
            if isHovered || isExpanded {
                // Custom lid animation
                RoundedRectangle(cornerRadius: 1)
                    .fill(isHovered ? Color(hex: "FF5F57") : Color.white.opacity(0.4))
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

// MARK: - Deleted Item Row

struct DeletedItemRow: View {
    let item: DeletedItem
    let isHovered: Bool
    let onRestore: () -> Void
    let onDeletePermanently: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            // Type icon
            Image(systemName: item.type == .project ? "folder" : "rectangle.3.group")
                .font(.system(size: 10))
                .foregroundColor(Color.white.opacity(0.4))
                .frame(width: 16)

            // Name and time
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 12))
                    .foregroundColor(Color.white.opacity(0.6))
                    .lineLimit(1)
                    .strikethrough(true, color: Color.white.opacity(0.3))

                Text(item.daysRemaining)
                    .font(.system(size: 9))
                    .foregroundColor(Color.white.opacity(0.3))
            }
            .allowsHitTesting(false)

            Spacer()

            // Hover actions
            if isHovered {
                HStack(spacing: 6) {
                    Button {
                        onRestore()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 10))
                            .foregroundColor(CosmoColors.thinkspacePurple)
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
                .fill(isHovered ? Color.white.opacity(0.03) : Color.clear)
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
    var associatedItems: [String]  // IDs of items deleted with this (e.g., ThinkSpaces in a project)

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
            CosmoColors.thinkspaceVoid
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
