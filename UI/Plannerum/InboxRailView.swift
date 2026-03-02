// CosmoOS/UI/Plannerum/InboxRailView.swift
// Plannerium Inbox Rail - Left panel with all inbox streams
// Includes Overdue section, filters, and ATOM integration

import SwiftUI
import Combine

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - INBOX RAIL VIEW
// ═══════════════════════════════════════════════════════════════════════════════

/// The left rail in Plannerium showing all inbox streams.
///
/// Visual Layout:
/// ```
/// ┌──────────────────────────┐
/// │  INBOXES           ↻     │
/// │  ═══════════════════     │
/// │                          │
/// │  ┌────────────────────┐  │
/// │  │ ⚠ Overdue       (2)│  │  ← Warning section at top
/// │  │   └ Client call    │  │
/// │  │   └ Invoice #891   │  │
/// │  └────────────────────┘  │
/// │                          │
/// │  [All] [Tasks] [Ideas]   │  ← Filter chips
/// │                          │
/// │  ┌────────────────────┐  │
/// │  │ ◆ Ideas        (12)│  │
/// │  │   └ New landing... │  │
/// │  └────────────────────┘  │
/// │                          │
/// │  ┌────────────────────┐  │
/// │  │ ◇ Tasks         (8)│  │
/// │  └────────────────────┘  │
/// │                          │
/// │  ─────── PROJECTS ────── │
/// │                          │
/// │  ┌────────────────────┐  │
/// │  │ ⬡ Cosmo         (5)│  │
/// │  └────────────────────┘  │
/// │                          │
/// │  23 items across all     │
/// └──────────────────────────┘
/// ```
public struct InboxRailView: View {

    // MARK: - State

    @StateObject private var viewModel = InboxRailViewModel()
    @State private var hoveredStream: InboxStreamType?
    @State private var expandedStreams: Set<String> = []
    @State private var activeFilter: InboxFilter = .all
    @Binding var selectedItem: UncommittedItemViewModel?

    // Quick Add state
    @State private var showingQuickAdd = false
    @State private var quickAddTargetStream: InboxStreamType?

    // MARK: - Initialization

    public init(selectedItem: Binding<UncommittedItemViewModel?>) {
        self._selectedItem = selectedItem
    }

    // MARK: - Body

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Floating title (no container)
            floatingTitle

            // Scrollable content - each card floats independently
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 10) {
                    // Overdue section (always at top if items exist)
                    if !viewModel.overdueItems.isEmpty {
                        overdueSection
                    }

                    // Core inbox streams - each is its own floating card
                    ForEach(viewModel.coreStreams, id: \.type.id) { stream in
                        floatingInboxCard(for: stream)
                    }

                    // Projects section title (floating)
                    if !viewModel.projectStreams.isEmpty {
                        projectsTitle
                    }

                    // Project streams - each is its own floating card
                    ForEach(viewModel.projectStreams, id: \.type.id) { stream in
                        floatingInboxCard(for: stream)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        // NO outer container background - cards float on realm background
        .onAppear {
            Task { await viewModel.loadData() }
        }
        .sheet(isPresented: $showingQuickAdd) {
            if let targetStream = quickAddTargetStream {
                QuickAddSheet(
                    streamType: targetStream,
                    onSave: { title in
                        Task {
                            await saveQuickAdd(title: title, to: targetStream)
                        }
                    },
                    onDismiss: {
                        showingQuickAdd = false
                        quickAddTargetStream = nil
                    }
                )
            }
        }
    }

    // MARK: - Quick Add Save

    private func saveQuickAdd(title: String, to streamType: InboxStreamType) async {
        guard !title.isEmpty else { return }

        do {
            switch streamType {
            case .ideas:
                _ = try await AtomRepository.shared.createIdea(title: title, content: "")
            case .tasks:
                _ = try await AtomRepository.shared.createTask(title: title)
            case .project(let uuid, _):
                _ = try await AtomRepository.shared.createTask(title: title, projectUuid: uuid)
            default:
                _ = try await AtomRepository.shared.createIdea(title: title, content: "")
            }

            // Reload data
            await viewModel.loadData()
        } catch {
            print("❌ QuickAdd failed: \(error)")
        }
    }

    // MARK: - Floating Title (no container)

    private var floatingTitle: some View {
        HStack {
            Text("INBOXES")
                .font(.system(size: 10, weight: .heavy))
                .foregroundColor(PlannerumColors.textMuted)
                .tracking(2)

            Spacer()

            // Refresh button
            Button(action: { Task { await viewModel.loadData() } }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(PlannerumColors.textMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Projects Title (floating)

    private var projectsTitle: some View {
        Text("PROJECTS")
            .font(.system(size: 9, weight: .heavy))
            .foregroundColor(PlannerumColors.textMuted.opacity(0.6))
            .tracking(1.5)
            .padding(.top, 8)
            .padding(.horizontal, 4)
    }

    // MARK: - Floating Inbox Card

    private func floatingInboxCard(for stream: InboxStream) -> some View {
        InboxStreamRow(
            stream: stream,
            isHovered: hoveredStream == stream.type,
            isExpanded: expandedStreams.contains(stream.type.id),
            onTap: { toggleStream(stream.type) },
            onItemSelect: { item in selectedItem = item },
            onQuickAdd: {
                quickAddTargetStream = stream.type
                showingQuickAdd = true
            }
        )
        .background(
            // Each card gets its own glass background
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .onHover { hovering in
            withAnimation(PlannerumSprings.hover) {
                hoveredStream = hovering ? stream.type : nil
            }
        }
    }

    // MARK: - Filtered Streams

    private var filteredCoreStreams: [InboxStream] {
        switch activeFilter {
        case .all:
            return viewModel.coreStreams
        case .tasks:
            return viewModel.coreStreams.filter { $0.type == .tasks }
        case .ideas:
            return viewModel.coreStreams.filter { $0.type == .ideas }
        }
    }

    // MARK: - Section Header

    private var sectionHeader: some View {
        HStack {
            // Title with subtle tracking
            Text("I N B O X E S")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(PlannerumColors.textSecondary)
                .tracking(3)

            Spacer()

            // Refresh button
            Button(action: {
                Task { await viewModel.loadData() }
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(PlannerumColors.textMuted)
                    .rotationEffect(.degrees(viewModel.isLoading ? 360 : 0))
                    .animation(
                        viewModel.isLoading
                            ? .linear(duration: 1).repeatForever(autoreverses: false)
                            : .default,
                        value: viewModel.isLoading
                    )
            }
            .buttonStyle(.plain)
            .opacity(viewModel.isLoading ? 0.6 : 1)
        }
        .padding(.horizontal, PlannerumLayout.spacingMD)
        .padding(.top, PlannerumLayout.spacingLG)
        .padding(.bottom, PlannerumLayout.spacingMD)
    }

    // MARK: - Overdue Section

    private var overdueSection: some View {
        VStack(spacing: 0) {
            // Overdue header
            Button {
                withAnimation(PlannerumSprings.expand) {
                    if expandedStreams.contains("overdue") {
                        expandedStreams.remove("overdue")
                    } else {
                        expandedStreams.insert("overdue")
                    }
                }
            } label: {
                HStack(spacing: PlannerumLayout.spacingSM) {
                    // Warning icon with glow
                    ZStack {
                        Circle()
                            .fill(PlannerumColors.overdueGlow)
                            .frame(width: 28, height: 28)
                            .blur(radius: 4)

                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(PlannerumColors.overdue)
                    }
                    .frame(width: 28, height: 28)

                    Text("Overdue")
                        .font(PlannerumTypography.inboxTitle)
                        .foregroundColor(PlannerumColors.overdue)

                    Spacer()

                    // Count badge
                    Text("\(viewModel.overdueItems.count)")
                        .font(PlannerumTypography.inboxCount)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(PlannerumColors.overdue)
                        .clipShape(Capsule())

                    // Expand indicator
                    Image(systemName: expandedStreams.contains("overdue") ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(PlannerumColors.overdue.opacity(0.7))
                }
                .padding(PlannerumLayout.spacingSM)
                .background(
                    RoundedRectangle(cornerRadius: PlannerumLayout.cornerRadiusSM)
                        .fill(PlannerumColors.overdue.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: PlannerumLayout.cornerRadiusSM)
                                .strokeBorder(PlannerumColors.overdue.opacity(0.3), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)

            // Expanded overdue items
            if expandedStreams.contains("overdue") {
                VStack(spacing: 2) {
                    ForEach(viewModel.overdueItems.prefix(PlannerumLayout.overdueMaxItems)) { item in
                        overdueItemRow(item)
                    }

                    if viewModel.overdueItems.count > PlannerumLayout.overdueMaxItems {
                        moreOverdueButton
                    }
                }
                .padding(.leading, 36)
                .padding(.trailing, PlannerumLayout.spacingSM)
                .padding(.bottom, PlannerumLayout.spacingSM)
            }
        }
        .padding(.bottom, PlannerumLayout.spacingSM)
    }

    private func overdueItemRow(_ item: UncommittedItemViewModel) -> some View {
        Button(action: { selectedItem = item }) {
            HStack(spacing: 6) {
                Circle()
                    .fill(PlannerumColors.overdue)
                    .frame(width: 6, height: 6)

                Text(item.title)
                    .font(.system(size: 12))
                    .foregroundColor(PlannerumColors.textSecondary)
                    .lineLimit(1)

                Spacer()

                if let days = item.daysOverdue, days > 0 {
                    Text("\(days)d")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(PlannerumColors.overdue)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, PlannerumLayout.spacingSM)
            .background(
                RoundedRectangle(cornerRadius: PlannerumLayout.cornerRadiusSM)
                    .fill(Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var moreOverdueButton: some View {
        Button(action: {
            // TODO: Show full overdue modal
        }) {
            HStack {
                Text("+ \(viewModel.overdueItems.count - PlannerumLayout.overdueMaxItems) more")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(PlannerumColors.overdue)

                Spacer()

                Image(systemName: "arrow.right")
                    .font(.system(size: 10))
                    .foregroundColor(PlannerumColors.overdue.opacity(0.6))
            }
            .padding(.vertical, 6)
            .padding(.horizontal, PlannerumLayout.spacingSM)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Filter Chips

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: PlannerumLayout.spacingXS) {
                ForEach(InboxFilter.allCases, id: \.self) { filter in
                    filterChip(filter)
                }
            }
            .padding(.horizontal, PlannerumLayout.spacingSM)
        }
        .padding(.vertical, PlannerumLayout.spacingSM)
    }

    private func filterChip(_ filter: InboxFilter) -> some View {
        Button(action: {
            withAnimation(PlannerumSprings.select) {
                activeFilter = filter
            }
        }) {
            Text(filter.rawValue)
                .font(.system(size: 11, weight: activeFilter == filter ? .semibold : .medium))
                .foregroundColor(
                    activeFilter == filter
                        ? PlannerumColors.textPrimary
                        : PlannerumColors.textTertiary
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(
                            activeFilter == filter
                                ? PlannerumColors.primary.opacity(0.2)
                                : PlannerumColors.glassPrimary
                        )
                )
                .overlay(
                    Capsule()
                        .strokeBorder(
                            activeFilter == filter
                                ? PlannerumColors.primary.opacity(0.4)
                                : PlannerumColors.glassBorder,
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Project Divider (soft, floating aesthetic per plan)

    private var projectDivider: some View {
        HStack(spacing: PlannerumLayout.spacingSM) {
            // Soft gradient fade instead of hard line
            LinearGradient(
                colors: [Color.clear, PlannerumColors.glassBorder.opacity(0.5), Color.clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 1)

            Text("PROJECTS")
                .font(.system(size: 9, weight: .heavy))
                .foregroundColor(PlannerumColors.textMuted.opacity(0.8))
                .tracking(1)

            LinearGradient(
                colors: [Color.clear, PlannerumColors.glassBorder.opacity(0.5), Color.clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 1)
        }
        .padding(.horizontal, PlannerumLayout.spacingSM)
        .padding(.vertical, PlannerumLayout.spacingMD)
    }

    // MARK: - Footer

    private var footerView: some View {
        VStack(spacing: PlannerumLayout.spacingSM) {
            // Total count - only show if there are items
            if viewModel.totalCount > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "tray.full.fill")
                        .font(.system(size: 11))
                    Text("\(viewModel.totalCount) items across all inboxes")
                        .font(.system(size: 11))
                }
                .foregroundColor(PlannerumColors.textMuted)
            }
            // Removed "All clear" empty state - user can see empty inboxes visually
        }
        .padding(.horizontal, PlannerumLayout.spacingMD)
        .padding(.vertical, PlannerumLayout.spacingMD)
        .background(PlannerumColors.glassSecondary.opacity(0.3))
    }

    // MARK: - Actions

    private func toggleStream(_ type: InboxStreamType) {
        withAnimation(PlannerumSprings.expand) {
            if expandedStreams.contains(type.id) {
                expandedStreams.remove(type.id)
            } else {
                expandedStreams.insert(type.id)
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - INBOX FILTER
// ═══════════════════════════════════════════════════════════════════════════════

/// Filter options for inbox streams
/// Note: Content removed - Ideas encompasses content ideas
public enum InboxFilter: String, CaseIterable {
    case all = "All"
    case tasks = "Tasks"
    case ideas = "Ideas"
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - INBOX STREAM MODEL
// ═══════════════════════════════════════════════════════════════════════════════

/// A stream of inbox items with metadata
public struct InboxStream: Identifiable {
    public var id: String { type.id }
    public let type: InboxStreamType
    public var items: [UncommittedItemViewModel]
    public var count: Int { items.count }

    public init(type: InboxStreamType, items: [UncommittedItemViewModel]) {
        self.type = type
        self.items = items
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - UNCOMMITTED ITEM VIEW MODEL
// ═══════════════════════════════════════════════════════════════════════════════

/// View model for an uncommitted item in the inbox
public struct UncommittedItemViewModel: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let body: String?
    public let inferredType: String?
    public let captureMethod: String?
    public let assignmentStatus: String?
    public let projectUuid: String?
    public let projectName: String?
    public let createdAt: Date
    public let dueDate: Date?

    public init(
        id: String,
        title: String,
        body: String? = nil,
        inferredType: String? = nil,
        captureMethod: String? = nil,
        assignmentStatus: String? = nil,
        projectUuid: String? = nil,
        projectName: String? = nil,
        createdAt: Date = Date(),
        dueDate: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.inferredType = inferredType
        self.captureMethod = captureMethod
        self.assignmentStatus = assignmentStatus
        self.projectUuid = projectUuid
        self.projectName = projectName
        self.createdAt = createdAt
        self.dueDate = dueDate
    }

    public var displayIcon: String {
        switch inferredType {
        case "idea": return "lightbulb.fill"
        case "task": return "checkmark.circle.fill"
        case "content": return "doc.text.fill"
        default: return "questionmark.circle"
        }
    }

    public var displayColor: Color {
        switch inferredType {
        case "idea": return PlannerumColors.ideasInbox
        case "task": return PlannerumColors.tasksInbox
        case "content": return PlannerumColors.contentInbox
        default: return PlannerumColors.textTertiary
        }
    }

    public var timeAgo: String {
        PlannerumTimeUtils.relativeTime(from: createdAt)
    }

    public var isOverdue: Bool {
        guard let due = dueDate else { return false }
        return due < Date()
    }

    public var daysOverdue: Int? {
        guard let due = dueDate, isOverdue else { return nil }
        return Calendar.current.dateComponents([.day], from: due, to: Date()).day
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - INBOX RAIL VIEW MODEL
// ═══════════════════════════════════════════════════════════════════════════════

/// View model for the inbox rail
@MainActor
public class InboxRailViewModel: ObservableObject {

    @Published public var coreStreams: [InboxStream] = []
    @Published public var projectStreams: [InboxStream] = []
    @Published public var overdueItems: [UncommittedItemViewModel] = []
    @Published public var isLoading = false
    @Published public var error: String?

    public var totalCount: Int {
        coreStreams.reduce(0) { $0 + $1.count } +
        projectStreams.reduce(0) { $0 + $1.count }
    }

    private var cancellables = Set<AnyCancellable>()

    public init() {
        // Listen for atom changes
        NotificationCenter.default.publisher(for: .atomsDidChange)
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                Task { await self?.loadData() }
            }
            .store(in: &cancellables)
    }

    public func loadData() async {
        isLoading = true
        defer { isLoading = false }

        do {
            // Fetch uncommitted items
            let items = try await AtomRepository.shared.fetchAll(type: .uncommittedItem)
                .filter { !$0.isDeleted }

            // Fetch projects for mapping
            let projects = try await AtomRepository.shared.projects()
            let projectMap = Dictionary(uniqueKeysWithValues: projects.map { ($0.uuid, $0.title ?? "Untitled") })

            // Convert to view models
            let viewModels = items.map { atom -> UncommittedItemViewModel in
                let metadata: UncommittedItemMetadata? = atom.metadataValue(as: UncommittedItemMetadata.self)
                let projectUuid = atom.link(ofType: "project")?.uuid

                return UncommittedItemViewModel(
                    id: atom.uuid,
                    title: atom.title ?? "Untitled",
                    body: atom.body,
                    inferredType: metadata?.inferredType,
                    captureMethod: metadata?.captureMethod,
                    assignmentStatus: metadata?.assignmentStatus,
                    projectUuid: projectUuid,
                    projectName: projectUuid.flatMap { projectMap[$0] },
                    createdAt: PlannerumFormatters.iso8601.date(from: atom.createdAt) ?? Date(),
                    dueDate: nil  // UncommittedItems don't have due dates
                )
            }

            // Extract overdue items
            overdueItems = viewModels
                .filter { $0.isOverdue }
                .sorted { ($0.dueDate ?? Date()) < ($1.dueDate ?? Date()) }

            // Build core streams (Ideas and Tasks only - Content merged into Ideas)
            var ideas: [UncommittedItemViewModel] = []
            var tasks: [UncommittedItemViewModel] = []

            for item in viewModels where !item.isOverdue {
                switch item.inferredType {
                case "idea", "content": ideas.append(item) // Content merged into Ideas
                case "task": tasks.append(item)
                default: ideas.append(item)
                }
            }

            // Sort by creation date (newest first)
            ideas.sort { $0.createdAt > $1.createdAt }
            tasks.sort { $0.createdAt > $1.createdAt }

            coreStreams = [
                InboxStream(type: .ideas, items: ideas),
                InboxStream(type: .tasks, items: tasks)
            ]

            // Build project streams - show ALL projects, even empty ones
            var projectItems: [String: [UncommittedItemViewModel]] = [:]

            // Initialize with all projects (so empty ones still show)
            for project in projects {
                projectItems[project.uuid] = []
            }

            // Add items to their respective projects
            for item in viewModels where !item.isOverdue {
                if let projectUuid = item.projectUuid {
                    projectItems[projectUuid, default: []].append(item)
                }
            }

            // Create streams for all projects (including empty ones)
            projectStreams = projects.compactMap { project in
                let items = projectItems[project.uuid] ?? []
                return InboxStream(type: .project(uuid: project.uuid, name: project.title ?? "Untitled"), items: items)
            }.sorted { ($0.count, $0.type.displayName) > ($1.count, $1.type.displayName) }

        } catch {
            self.error = error.localizedDescription
            print("❌ InboxRailViewModel: Failed to load - \(error)")
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - NOTIFICATION EXTENSION
// ═══════════════════════════════════════════════════════════════════════════════

extension Notification.Name {
    public static let atomsDidChange = Notification.Name("atomsDidChange")
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - QUICK ADD SHEET
// ═══════════════════════════════════════════════════════════════════════════════

/// A minimal quick add sheet for adding items to an inbox.
/// Matches the glass morphism aesthetic of Plannerum.
struct QuickAddSheet: View {

    let streamType: InboxStreamType
    let onSave: (String) -> Void
    let onDismiss: () -> Void

    @State private var title: String = ""
    @FocusState private var isFocused: Bool

    private var placeholder: String {
        switch streamType {
        case .ideas:
            return "What's your idea?"
        case .tasks:
            return "What needs to be done?"
        case .project(_, let name):
            return "Add to \(name)..."
        default:
            return "Enter title..."
        }
    }

    private var accentColor: Color {
        streamType.color
    }

    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                // Icon
                ZStack {
                    Circle()
                        .fill(accentColor.opacity(0.15))
                        .frame(width: 40, height: 40)

                    Image(systemName: streamType.icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(accentColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Quick Add")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)

                    Text(streamType.displayName)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Close button
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 32, height: 32)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            // Input field
            TextField(placeholder, text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.primary.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(
                                    isFocused ? accentColor.opacity(0.5) : Color.secondary.opacity(0.2),
                                    lineWidth: 1
                                )
                        )
                )
                .focused($isFocused)
                .onSubmit {
                    saveAndDismiss()
                }

            // Action buttons
            HStack(spacing: 12) {
                // Cancel
                Button(action: onDismiss) {
                    Text("Cancel")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.secondary.opacity(0.1))
                        )
                }
                .buttonStyle(.plain)

                // Save
                Button(action: saveAndDismiss) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Add")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(title.isEmpty ? accentColor.opacity(0.4) : accentColor)
                    )
                }
                .buttonStyle(.plain)
                .disabled(title.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 360)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            isFocused = true
        }
    }

    private func saveAndDismiss() {
        guard !title.isEmpty else { return }
        onSave(title)
        onDismiss()
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - PREVIEW
// ═══════════════════════════════════════════════════════════════════════════════

#if DEBUG
struct InboxRailView_Previews: PreviewProvider {
    static var previews: some View {
        InboxRailView(selectedItem: .constant(nil))
            .frame(height: 700)
            .background(PlannerumColors.voidPrimary)
            .preferredColorScheme(.dark)
    }
}
#endif
