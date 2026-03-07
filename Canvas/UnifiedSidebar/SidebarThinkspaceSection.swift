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
        VStack(spacing: 0) {
            // Section header
            sectionHeader

            if !isCollapsed {
                Group {
                    // Filter chips
                    if !projects.isEmpty {
                        filterChipsRow
                            .padding(.top, 4)
                    }

                    // Creation field
                    if isCreatingThinkspace {
                        newThinkspaceRow
                            .padding(.horizontal, 12)
                            .padding(.top, 6)
                    }

                    // Thinkspace list
                    thinkspaceList
                        .padding(.top, 4)
                }
                .transition(.opacity.combined(with: .move(edge: .leading)))
            }
        }
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
                // Icon-only mode
                Image(systemName: "rectangle.3.group")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(DS.textSecondary)
                    .frame(width: 32, height: 32)
                    .frame(maxWidth: .infinity)
            } else {
                Text("THINKSPACES")
                    .font(DS.sectionLabel)
                    .foregroundColor(DS.textMuted)
                    .tracking(0.88)

                Spacer()

                Button {
                    withAnimation(ProMotionSprings.snappy) {
                        isCreatingThinkspace = true
                        newName = ""
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isNameFieldFocused = true
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(DS.accent)
                        .frame(width: 20, height: 20)
                        .background(DS.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .help("New ThinkSpace")
            }
        }
        .padding(.horizontal, isCollapsed ? 8 : 16)
        .padding(.vertical, 6)
    }

    // MARK: - Filter Chips Row

    private var filterChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                filterChip(label: "All", color: DS.accent, isSelected: selectedProjectFilter == nil) {
                    withAnimation(ProMotionSprings.snappy) {
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
                        withAnimation(ProMotionSprings.snappy) {
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
            .padding(.horizontal, 12)
        }
    }

    @ViewBuilder
    private func filterChip(label: String, color: Color, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Circle()
                    .fill(color)
                    .frame(width: 5, height: 5)

                Text(label)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? color : DS.textSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(isSelected ? color.opacity(0.12) : Color.clear)
            )
            .overlay(
                Capsule().stroke(isSelected ? color.opacity(0.25) : Color.clear, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - New Thinkspace Row

    private var newThinkspaceRow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(DS.accent.opacity(0.15))
                .frame(width: 22, height: 22)
                .overlay(
                    Image(systemName: "rectangle.3.group")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(DS.accent)
                )

            TextField("Name", text: $newName)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(DS.text)
                .focused($isNameFieldFocused)
                .onSubmit { createThinkspace() }

            Button {
                withAnimation(ProMotionSprings.snappy) {
                    isCreatingThinkspace = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(DS.textMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(DS.accent.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(DS.accent.opacity(0.25), lineWidth: 0.5)
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
        if items.isEmpty && !isCollapsed {
            thinkspaceEmptyState
        } else {
            VStack(spacing: 1) {
                ForEach(items) { thinkspace in
                    thinkspaceRow(thinkspace)
                }
            }
            .padding(.horizontal, isCollapsed ? 6 : 8)
        }
    }

    private func thinkspaceRow(_ thinkspace: Thinkspace) -> some View {
        let isActive = activeThinkspaceId == thinkspace.id
        let isHovered = hoveredThinkspaceId == thinkspace.id
        let isExpanded = expandedThinkspaces.contains(thinkspace.id)

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                selectThinkspace(thinkspace)
            } label: {
                thinkspaceRowLabel(thinkspace, isActive: isActive, isExpanded: isExpanded)
            }
            .buttonStyle(.plain)

            // Child docs
            if isExpanded && !isCollapsed {
                childDocsSection(for: thinkspace)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(crossThinkspaceHighlight(for: thinkspace, isActive: isActive, isHovered: isHovered))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(
                    crossDragManager.hoveredThinkspaceId == thinkspace.id
                        ? DS.accent.opacity(0.5)
                        : Color.clear,
                    lineWidth: 1.5
                )
        )
        .scaleEffect(crossDragManager.hoveredThinkspaceId == thinkspace.id
                      ? 1.0 + 0.04 * blinkPulse(crossDragManager.hoverProgress)
                      : 1.0)
        .opacity(crossDragManager.hoveredThinkspaceId == thinkspace.id
                 ? 1.0 - 0.4 * blinkPulse(crossDragManager.hoverProgress)
                 : 1.0)
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
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .animation(.linear(duration: 0.05), value: crossDragManager.hoverProgress)
    }

    @ViewBuilder
    private func thinkspaceRowLabel(_ thinkspace: Thinkspace, isActive: Bool, isExpanded: Bool) -> some View {
        if isCollapsed {
            // Collapsed: just icon
            let project = projectFor(thinkspace)
            let color = project.map { projectColor(for: $0) } ?? DS.textMuted
            Circle()
                .fill(isActive ? DS.accent.opacity(0.2) : color.opacity(0.15))
                .frame(width: 28, height: 28)
                .overlay(
                    Text(String(thinkspace.name.prefix(1)).uppercased())
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(isActive ? DS.accent : color)
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .help(thinkspace.name)
        } else {
            // Expanded: full row
            HStack(spacing: 6) {
                // Active indicator
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(isActive ? DS.accent : Color.clear)
                    .frame(width: 3, height: 16)

                // Expand chevron
                Button {
                    toggleExpand(thinkspace)
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(DS.textMuted)
                        .frame(width: 12, height: 12)
                }
                .buttonStyle(.plain)

                // Project color dot
                let project = projectFor(thinkspace)
                if let project = project {
                    Circle()
                        .fill(projectColor(for: project))
                        .frame(width: 5, height: 5)
                }

                // Name
                Text(thinkspace.name)
                    .font(.system(size: 12, weight: isActive ? .semibold : .medium))
                    .foregroundColor(isActive ? DS.text : DS.textSecondary)
                    .lineLimit(1)

                Spacer()

                // Block count
                Text("\(thinkspace.blockCount)")
                    .font(.system(size: 10))
                    .foregroundColor(DS.textMuted)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
    }

    // MARK: - Child Docs

    @ViewBuilder
    private func childDocsSection(for thinkspace: Thinkspace) -> some View {
        let docs = manager.childDocsCache[thinkspace.id] ?? []
        let isLoading = childDocsLoading.contains(thinkspace.id)

        VStack(alignment: .leading, spacing: 0) {
            if isLoading {
                HStack(spacing: 6) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: DS.accent))
                        .scaleEffect(0.5)
                    Text("Loading...")
                        .font(.system(size: 10))
                        .foregroundColor(DS.textMuted)
                }
                .padding(.leading, 28)
                .padding(.vertical, 4)
            } else if docs.isEmpty {
                Text("No blocks")
                    .font(.system(size: 10))
                    .foregroundColor(DS.textMuted)
                    .padding(.leading, 28)
                    .padding(.vertical, 4)
            } else {
                ForEach(docs) { doc in
                    sidebarChildDocRow(doc, thinkspaceId: thinkspace.id)
                }
            }
        }
        .padding(.bottom, 2)
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
            HStack(spacing: 4) {
                Rectangle()
                    .fill(DS.borderActive)
                    .frame(width: 1)
                    .padding(.leading, 22)

                Rectangle()
                    .fill(DS.borderActive)
                    .frame(width: 6, height: 1)

                RoundedRectangle(cornerRadius: 3)
                    .fill(doc.entityType.color.opacity(0.15))
                    .frame(width: 16, height: 16)
                    .overlay(
                        Image(systemName: doc.entityType.icon)
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(doc.entityType.color)
                    )

                Text(doc.title)
                    .font(.system(size: 11))
                    .foregroundColor(DS.textSecondary)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isHovered ? DS.surfaceHover : Color.clear)
            )
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
        VStack(spacing: 6) {
            Image(systemName: "rectangle.3.group")
                .font(.system(size: 16))
                .foregroundColor(DS.textMuted)

            Text("No ThinkSpaces")
                .font(.system(size: 11))
                .foregroundColor(DS.textMuted)

            Text("Tap + to create")
                .font(.system(size: 10))
                .foregroundColor(DS.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    // MARK: - Actions

    private func selectThinkspace(_ thinkspace: Thinkspace) {
        // Only set destination — MainView's onChange handles the actual switchTo()
        withAnimation(ProMotionSprings.snappy) {
            currentDestination = .thinkspace(id: thinkspace.id)
        }
    }

    private func toggleExpand(_ thinkspace: Thinkspace) {
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
                withAnimation(ProMotionSprings.snappy) {
                    currentDestination = .thinkspace(id: thinkspace.id)
                }
            }
            withAnimation(ProMotionSprings.snappy) {
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
        if isCreatingThinkspace {
            withAnimation(ProMotionSprings.snappy) {
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

    // MARK: - Cross-Thinkspace Drag Helpers

    /// Background fill for thinkspace rows, accounting for cross-thinkspace drag highlight
    private func crossThinkspaceHighlight(for thinkspace: Thinkspace, isActive: Bool, isHovered: Bool) -> some ShapeStyle {
        if crossDragManager.hoveredThinkspaceId == thinkspace.id {
            return AnyShapeStyle(DS.accent.opacity(0.15))
        } else if isActive {
            return AnyShapeStyle(DS.accent.opacity(0.10))
        } else if isHovered {
            return AnyShapeStyle(DS.surfaceHover)
        } else {
            return AnyShapeStyle(Color.clear)
        }
    }

    /// Generates a 3-pulse blink wave from progress 0→1
    /// Returns 0→1→0 three times across the progress range
    private func blinkPulse(_ progress: CGFloat) -> CGFloat {
        guard progress > 0 && progress < 1 else { return 0 }
        // 3 pulses: sin wave with 3 full cycles
        let wave = sin(progress * .pi * 3)
        return max(0, wave)
    }
}
