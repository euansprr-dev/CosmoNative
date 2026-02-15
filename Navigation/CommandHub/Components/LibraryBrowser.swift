// CosmoOS/Navigation/CommandHub/Components/LibraryBrowser.swift
// Library Browser with Filter Tabs and Entity Cards
// Efficient LazyVGrid rendering for smooth scrolling
// December 2025 - ProMotion springs, entrance blur, staggered animations

import SwiftUI
import GRDB

// MARK: - Library Browser
struct LibraryBrowser: View {
    let query: String
    @Binding var selectedFilter: EntityType?
    let onEntitySingleTap: (LibraryEntity) -> Void
    let onEntityDoubleTap: (LibraryEntity) -> Void
    let captureState: CommandHubCaptureController.State
    let onCaptureAction: (CommandHubCaptureController.State) -> Void

    @State private var entities: [LibraryEntity] = []
    @State private var isLoading = true
    @State private var selectedEntityId: UUID?
    @State private var appearedEntities: Set<UUID> = []

    private let columns = [
        GridItem(.adaptive(minimum: 170, maximum: 200), spacing: 12)
    ]

    private let contextTracker = EditingContextTracker.shared

    var body: some View {
        VStack(spacing: 0) {
            // Filter tabs
            FilterTabsBar(selectedFilter: $selectedFilter)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

            // Entity grid
            if isLoading {
                VStack(spacing: 14) {
                    if shouldShowCaptureCard {
                        ResearchCapturePreviewCard(
                            state: captureState,
                            onAction: { onCaptureAction(captureState) }
                        )
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                    }

                    LibraryLoadingView()
                        .frame(height: 120)
                }
                .frame(maxWidth: .infinity)
            } else if entities.isEmpty {
                VStack(spacing: 16) {
                    if shouldShowCaptureCard {
                        ResearchCapturePreviewCard(
                            state: captureState,
                            onAction: { onCaptureAction(captureState) }
                        )
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                    }

                    EmptyLibraryView(filter: selectedFilter, query: query)
                        .frame(minHeight: 200)
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        if shouldShowCaptureCard {
                            ResearchCapturePreviewCard(
                                state: captureState,
                                onAction: { onCaptureAction(captureState) }
                            )
                            .opacity(appearedEntities.contains(CAPTURE_CARD_ID) ? 1 : 0)
                            .offset(y: appearedEntities.contains(CAPTURE_CARD_ID) ? 0 : 10)
                            .onAppear {
                                withAnimation(HubSprings.stagger) {
                                    _ = appearedEntities.insert(CAPTURE_CARD_ID)
                                }
                            }
                        }

                        ForEach(entities) { entity in
                            EntityPreviewCard(
                                entity: entity,
                                isSelected: selectedEntityId == entity.id,
                                onSingleTap: {
                                    selectedEntityId = entity.id
                                    onEntitySingleTap(entity)
                                },
                                onDoubleTap: {
                                    selectedEntityId = entity.id
                                    onEntityDoubleTap(entity)
                                },
                                onDelete: {
                                    handleDelete(entity)
                                }
                            )
                            // Entrance animation with blur
                            .opacity(appearedEntities.contains(entity.id) ? 1 : 0)
                            .offset(y: appearedEntities.contains(entity.id) ? 0 : 12)
                            .blur(radius: appearedEntities.contains(entity.id) ? 0 : 4)
                            .scaleEffect(appearedEntities.contains(entity.id) ? 1 : 0.96)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.95)),
                                removal: .scale(scale: 0.85).combined(with: .opacity)
                            ))
                            .onAppear {
                                // Staggered entrance animation with ProMotion springs
                                let index = entities.firstIndex(where: { $0.id == entity.id }) ?? 0
                                let captureOffset = shouldShowCaptureCard ? 1 : 0
                                withAnimation(ProMotionSprings.staggered(index: index + captureOffset)) {
                                    _ = appearedEntities.insert(entity.id)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            }
        }
        .onAppear {
            loadEntities()
        }
        .onChange(of: selectedFilter) { _, _ in
            appearedEntities.removeAll()
            loadEntities()
        }
        .onChange(of: query) { _, _ in
            loadEntities()
        }
        // Refresh when research processing completes (title gets updated)
        .onReceive(NotificationCenter.default.publisher(for: .researchProcessingComplete)) { _ in
            loadEntities()
        }
        // Also refresh when research is created
        .onReceive(NotificationCenter.default.publisher(for: .researchCreated)) { _ in
            loadEntities()
        }
    }

    // MARK: - Capture Card
    private static let CAPTURE_CARD_ID = UUID(uuidString: "5E4A39C5-9B64-4F6D-B7AE-66BB4E5E8B5F")!
    private var CAPTURE_CARD_ID: UUID { Self.CAPTURE_CARD_ID }

    private var shouldShowCaptureCard: Bool {
        switch captureState {
        case .idle:
            return false
        default:
            // Only show in All or Research tab.
            return selectedFilter == nil || selectedFilter == .research
        }
    }

    // MARK: - Load Entities
    private func loadEntities() {
        isLoading = true

        Task {
            let database = CosmoDatabase.shared
            var loadedEntities: [LibraryEntity] = []

            print("📚 LibraryBrowser: Loading entities (filter: \(selectedFilter?.rawValue ?? "all"), query: \"\(query)\")")

            // Load based on filter
            if selectedFilter == nil || selectedFilter == .idea {
                let ideas = try? await database.asyncRead { db in
                    var request = Atom
                        .filter(Column("type") == AtomType.idea.rawValue)
                        .filter(Column("is_deleted") == false)
                    if !query.isEmpty {
                        request = request.filter(
                            Column("title").like("%\(query)%") ||
                            Column("body").like("%\(query)%")
                        )
                    }
                    return try request.order(Column("updated_at").desc).limit(20).fetchAll(db).map { IdeaWrapper(atom: $0) }
                }

                let ideaList = ideas ?? []
                print("   📝 Ideas: \(ideaList.count)")
                loadedEntities += ideaList.map { (idea: IdeaWrapper) -> LibraryEntity in
                    LibraryEntity(
                        entityId: idea.id ?? -1,
                        type: .idea,
                        title: idea.title ?? "Untitled Idea",
                        preview: String(idea.content.prefix(100)),
                        metadata: ["tags": idea.tags ?? ""],
                        updatedAt: ISO8601DateFormatter().date(from: idea.updatedAt)
                    )
                }
            }

            if selectedFilter == nil || selectedFilter == .content {
                let content = try? await database.asyncRead { db in
                    var request = Atom
                        .filter(Column("type") == AtomType.content.rawValue)
                        .filter(Column("is_deleted") == false)
                    if !query.isEmpty {
                        request = request.filter(
                            Column("title").like("%\(query)%") ||
                            Column("body").like("%\(query)%")
                        )
                    }
                    return try request.order(Column("updated_at").desc).limit(20).fetchAll(db).map { ContentWrapper(atom: $0) }
                }

                loadedEntities += (content ?? []).map { (item: ContentWrapper) -> LibraryEntity in
                    let wordCount = (item.body ?? "").split(separator: " ").count
                    return LibraryEntity(
                        entityId: item.id ?? -1,
                        type: .content,
                        title: item.title ?? "Untitled",
                        preview: String((item.body ?? "").prefix(100)),
                        metadata: [
                            "wordCount": "\(wordCount)",
                            "status": item.status
                        ],
                        updatedAt: ISO8601DateFormatter().date(from: item.updatedAt)
                    )
                }
            }

            if selectedFilter == nil || selectedFilter == .research {
                let research: [ResearchWrapper] = (try? await database.asyncRead { db in
                    var request = Atom
                        .filter(Column("type") == AtomType.research.rawValue)
                        .filter(Column("is_deleted") == false)
                    if !query.isEmpty {
                        request = request.filter(
                            Column("title").like("%\(query)%")
                        )
                    }
                    return try request.order(Column("updated_at").desc).limit(20).fetchAll(db).map { ResearchWrapper(atom: $0) }
                }) ?? []

                print("   🔬 Research: \(research.count)")
                loadedEntities += research.map { (item: ResearchWrapper) -> LibraryEntity in
                    LibraryEntity(
                        entityId: item.id ?? -1,
                        type: .research,
                        title: item.title ?? "Untitled",
                        preview: item.summary ?? "",
                        metadata: [
                            "sourceType": item.sourceType?.rawValue ?? "unknown",
                            "domain": item.domain ?? "",
                            "thumbnailUrl": item.thumbnailUrl ?? "",
                            "transcriptStatus": item.richContent?.transcriptStatus ?? "",
                            "uuid": item.uuid
                        ],
                        updatedAt: ISO8601DateFormatter().date(from: item.updatedAt)
                    )
                }
            }

            if selectedFilter == nil || selectedFilter == .connection {
                let connections: [ConnectionWrapper] = (try? await database.asyncRead { db in
                    var request = Atom
                        .filter(Column("type") == AtomType.connection.rawValue)
                        .filter(Column("is_deleted") == false)
                    if !query.isEmpty {
                        request = request.filter(Column("title").like("%\(query)%"))
                    }
                    return try request.order(Column("updated_at").desc).limit(20).fetchAll(db).map { ConnectionWrapper(atom: $0) }
                }) ?? []

                loadedEntities += connections.map { (item: ConnectionWrapper) -> LibraryEntity in
                    LibraryEntity(
                        entityId: item.id ?? -1,
                        type: .connection,
                        title: item.title ?? "Untitled",
                        preview: item.mentalModelOrNew.coreIdea ?? "",
                        metadata: ["linkCount": "3"], // TODO: Calculate actual link count
                        updatedAt: ISO8601DateFormatter().date(from: item.updatedAt)
                    )
                }
            }

            if selectedFilter == nil || selectedFilter == .project {
                let projects: [ProjectWrapper] = (try? await database.asyncRead { db in
                    var request = Atom
                        .filter(Column("type") == AtomType.project.rawValue)
                        .filter(Column("is_deleted") == false)
                    if !query.isEmpty {
                        request = request.filter(Column("title").like("%\(query)%"))
                    }
                    return try request.order(Column("updated_at").desc).limit(20).fetchAll(db).map { ProjectWrapper(atom: $0) }
                }) ?? []

                loadedEntities += projects.map { (item: ProjectWrapper) -> LibraryEntity in
                    LibraryEntity(
                        entityId: item.id ?? -1,
                        type: .project,
                        title: item.title ?? "Untitled",
                        preview: item.description ?? "",
                        metadata: [
                            "status": item.status,
                            "progress": "0.5", // TODO: Calculate actual progress
                            "taskCount": "10",
                            "pendingCount": "5"
                        ],
                        updatedAt: ISO8601DateFormatter().date(from: item.updatedAt)
                    )
                }
            }

            if selectedFilter == nil || selectedFilter == .task {
                let queryCapture = query
                let tasks = try? await database.asyncRead { db in
                    var request = Atom
                        .filter(Column("type") == AtomType.task.rawValue)
                        .filter(Column("is_deleted") == false)
                    if !queryCapture.isEmpty {
                        request = request.filter(Column("title").like("%\(queryCapture)%"))
                    }
                    return try request.order(Column("updated_at").desc).limit(20).fetchAll(db).map { TaskWrapper(atom: $0) }
                }

                loadedEntities += (tasks ?? []).map { (task: TaskWrapper) -> LibraryEntity in
                    LibraryEntity(
                        entityId: task.id ?? -1,
                        type: .task,
                        title: task.title ?? "Untitled",
                        preview: "",
                        metadata: [
                            "status": task.status,
                            "dueDate": task.dueDate ?? ""
                        ],
                        updatedAt: ISO8601DateFormatter().date(from: task.updatedAt)
                    )
                }
            }

            // Load Swipe Files (filtered research items with is_swipe_file = true)
            if selectedFilter == .swipeFile {
                let queryCapture = query
                let swipeFiles = try? await database.asyncRead { db in
                    var request = Atom
                        .filter(Column("type") == AtomType.research.rawValue)
                        .filter(Column("is_deleted") == false)
                    // Note: is_swipe_file is in metadata, so we'd need to filter after fetching
                    if !queryCapture.isEmpty {
                        request = request.filter(
                            Column("title").like("%\(queryCapture)%")
                        )
                    }
                    return try request.order(Column("created_at").desc).limit(50).fetchAll(db)
                        .map { ResearchWrapper(atom: $0) }
                        .filter { $0.isSwipeFile }
                }

                loadedEntities += (swipeFiles ?? []).map { (item: ResearchWrapper) -> LibraryEntity in
                    LibraryEntity(
                        entityId: item.id ?? -1,
                        type: .swipeFile,
                        title: item.hook ?? item.title ?? "Untitled",
                        preview: item.summary ?? "",
                        metadata: [
                            "sourceType": item.researchType ?? "unknown",
                            "emotionTone": item.emotionTone ?? "",
                            "structureType": item.structureType ?? "",
                            "thumbnailUrl": item.thumbnailUrl ?? "",
                            "url": item.url ?? ""
                        ],
                        updatedAt: ISO8601DateFormatter().date(from: item.createdAt)
                    )
                }
            }

            // Check if we have editing context for context-aware sorting
            let contextSnapshot = await MainActor.run { contextTracker.snapshot() }

            if let contextVector = contextSnapshot.contextVector, !contextVector.isEmpty {
                // Focus Mode: Sort by context relevance
                loadedEntities = await sortByContextRelevance(
                    entities: loadedEntities,
                    contextVector: contextVector
                )
            } else {
                // Home Page: Sort by recency
                loadedEntities.sort { ($0.updatedAt ?? Date.distantPast) > ($1.updatedAt ?? Date.distantPast) }
            }

            print("📚 LibraryBrowser: Loaded \(loadedEntities.count) entities")
            for entity in loadedEntities.prefix(5) {
                print("   - [\(entity.type.rawValue)] \(entity.title)")
            }
            if loadedEntities.count > 5 {
                print("   ... and \(loadedEntities.count - 5) more")
            }

            await MainActor.run {
                entities = loadedEntities
                isLoading = false
            }
        }
    }

    // MARK: - Context-Aware Sorting (Telepathy Integration)

    /// Sort entities by similarity to the current editing context
    private func sortByContextRelevance(
        entities: [LibraryEntity],
        contextVector: [Float]
    ) async -> [LibraryEntity] {
        var scored: [(entity: LibraryEntity, similarity: Float)] = []

        for entity in entities {
            let similarity = await getContextSimilarity(
                entityType: entity.type,
                entityId: entity.entityId,
                contextVector: contextVector
            )
            scored.append((entity, similarity))
        }

        // Sort by similarity (highest first)
        scored.sort { $0.similarity > $1.similarity }
        return scored.map { $0.entity }
    }

    /// Get similarity between an entity and the current editing context
    private func getContextSimilarity(
        entityType: EntityType,
        entityId: Int64,
        contextVector: [Float]
    ) async -> Float {
        do {
            let results = try await VectorDatabase.shared.searchByVector(
                embedding: contextVector,
                limit: 100,
                entityTypeFilter: entityType.rawValue,
                minSimilarity: 0.0
            )

            return results.first { $0.entityId == entityId }?.similarity ?? 0
        } catch {
            return 0
        }
    }

    // MARK: - Handle Delete
    private func handleDelete(_ entity: LibraryEntity) {
        // Immediately remove from local array with animation
        withAnimation(.easeOut(duration: 0.2)) {
            entities.removeAll { $0.id == entity.id }
            appearedEntities.remove(entity.id)
        }

        // Fire-and-forget database update (non-blocking)
        Task.detached(priority: .background) {
            await deleteEntityFromDatabase(entity)
        }
    }

    // MARK: - Delete Entity from Database
    private func deleteEntityFromDatabase(_ entity: LibraryEntity) async {
        let database = CosmoDatabase.shared
        do {
            try await database.asyncWrite { db in
                switch entity.type {
                case .idea:
                    try db.execute(sql: "UPDATE ideas SET is_deleted = 1 WHERE id = ?", arguments: [entity.entityId])
                case .content:
                    try db.execute(sql: "UPDATE content SET is_deleted = 1 WHERE id = ?", arguments: [entity.entityId])
                case .connection:
                    try db.execute(sql: "UPDATE connections SET is_deleted = 1 WHERE id = ?", arguments: [entity.entityId])
                case .research, .swipeFile:
                    // Swipe files are stored in the research table
                    try db.execute(sql: "UPDATE research SET is_deleted = 1 WHERE id = ?", arguments: [entity.entityId])
                case .project:
                    try db.execute(sql: "UPDATE projects SET is_deleted = 1 WHERE id = ?", arguments: [entity.entityId])
                case .task:
                    try db.execute(sql: "UPDATE tasks SET is_deleted = 1 WHERE id = ?", arguments: [entity.entityId])
                default:
                    break
                }
            }
            print("✅ Deleted \(entity.type.rawValue): \(entity.title)")
        } catch {
            print("❌ Failed to delete entity: \(error)")
        }
    }
}

// MARK: - Filter Tabs Bar
struct FilterTabsBar: View {
    @Binding var selectedFilter: EntityType?

    private let filters: [(EntityType?, String, String, Color)] = [
        (nil, "All", "square.grid.2x2", CosmoColors.textSecondary),
        (.idea, "Ideas", "lightbulb.fill", CosmoColors.lavender),
        (.content, "Content", "doc.text.fill", CosmoColors.skyBlue),
        (.research, "Research", "magnifyingglass", CosmoColors.emerald),
        (.connection, "Connections", "link.circle.fill", CosmoMentionColors.connection),
        (.task, "Tasks", "checkmark.circle.fill", CosmoColors.coral),
        (.swipeFile, "Swipe File", "bookmark.fill", CosmoColors.coral)
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(filters, id: \.1) { filter, label, icon, color in
                    FilterChipButton(
                        label: label,
                        icon: icon,
                        color: color,
                        isSelected: selectedFilter == filter,
                        onTap: { selectedFilter = filter }
                    )
                }
            }
        }
    }
}

// MARK: - Filter Chip Button
struct FilterChipButton: View {
    let label: String
    let icon: String
    let color: Color
    let isSelected: Bool
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button {
            CosmicHaptics.shared.play(.selection)
            onTap()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .symbolEffect(.bounce, value: isSelected)

                Text(label)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(isSelected ? .white : (isHovered ? color : CosmoColors.textSecondary))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(isSelected ? color : (isHovered ? color.opacity(0.1) : CosmoColors.glassGrey.opacity(0.3)))
            )
            .overlay(
                Capsule()
                    .stroke(isSelected ? color : (isHovered ? color.opacity(0.3) : Color.clear), lineWidth: 1)
            )
            .scaleEffect(isHovered && !isSelected ? 1.03 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) {
                isHovered = hovering
            }
        }
        .animation(ProMotionSprings.snappy, value: isSelected)
    }
}

// MARK: - Library Loading View
struct LibraryLoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            // Shimmer card placeholders
            HStack(spacing: 12) {
                ForEach(0..<3) { index in
                    CosmicShimmerCard(
                        entityColor: [CosmoColors.lavender, CosmoColors.skyBlue, CosmoColors.emerald][index],
                        showThumbnail: index == 1,
                        cornerRadius: 12
                    )
                    .frame(width: 180, height: index == 1 ? 200 : 140)
                    .opacity(0.8)
                }
            }

            Text("Loading your knowledge...")
                .font(.system(size: 13))
                .foregroundColor(CosmoColors.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 16)
    }
}

// MARK: - Empty Library View
struct EmptyLibraryView: View {
    let filter: EntityType?
    let query: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: emptyIcon)
                .font(.system(size: 36, weight: .light))
                .foregroundColor(CosmoColors.textTertiary)

            Text(emptyTitle)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(CosmoColors.textSecondary)

            Text(emptySubtitle)
                .font(.system(size: 13))
                .foregroundColor(CosmoColors.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private var emptyIcon: String {
        if !query.isEmpty {
            return "magnifyingglass"
        }
        switch filter {
        case .idea: return "lightbulb"
        case .content: return "doc.text"
        case .research: return "globe"
        case .connection: return "link"
        case .project: return "folder"
        case .task: return "checkmark.circle"
        case .swipeFile: return "bookmark"
        default: return "tray"
        }
    }

    private var emptyTitle: String {
        if !query.isEmpty {
            return "No results for \"\(query)\""
        }
        switch filter {
        case .idea: return "No ideas yet"
        case .content: return "No content yet"
        case .research: return "No research saved"
        case .connection: return "No connections yet"
        case .project: return "No projects yet"
        case .task: return "No tasks yet"
        case .swipeFile: return "No swipe files saved"
        default: return "Your library is empty"
        }
    }

    private var emptySubtitle: String {
        if !query.isEmpty {
            return "Try a different search term or create something new"
        }
        switch filter {
        case .swipeFile:
            return "Press ⌘⇧S to save content from your clipboard"
        default:
            return "Click a Circle App above to create your first item"
        }
    }
}

// MARK: - Preview
#if DEBUG
struct LibraryBrowser_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            LibraryBrowser(
                query: "",
                selectedFilter: .constant(nil),
                onEntitySingleTap: { _ in },
                onEntityDoubleTap: { _ in },
                captureState: .idle,
                onCaptureAction: { _ in }
            )
        }
        .frame(width: 680, height: 400)
        .background(CosmoColors.softWhite)
    }
}
#endif
