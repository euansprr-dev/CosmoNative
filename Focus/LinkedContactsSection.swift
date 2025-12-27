// CosmoOS/Focus/LinkedContactsSection.swift
// "Link Related" section for research focus mode
// Discovers and links semantically related content using vector search
// macOS 26+ optimized

import SwiftUI
import GRDB

// MARK: - Knowledge Link

public struct KnowledgeLink: Identifiable, Codable, Sendable {
    public let id: UUID
    public let sourceType: String
    public let sourceId: Int64
    public let targetType: String
    public let targetId: Int64
    public let linkType: LinkType
    public let similarity: Float
    public let createdAt: Date

    public enum LinkType: String, Codable, Sendable {
        case semanticallySimilar = "semantic"
        case manual = "manual"
        case mentioned = "mentioned"
        case projectRelated = "project"
        case citation = "citation"
    }

    public init(
        id: UUID = UUID(),
        sourceType: String,
        sourceId: Int64,
        targetType: String,
        targetId: Int64,
        linkType: LinkType,
        similarity: Float = 1.0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sourceType = sourceType
        self.sourceId = sourceId
        self.targetType = targetType
        self.targetId = targetId
        self.linkType = linkType
        self.similarity = similarity
        self.createdAt = createdAt
    }
}

// MARK: - Linked Entity

public struct LinkedEntity: Identifiable, Sendable {
    public let id: String
    public let entityType: String
    public let entityId: Int64
    public let entityUUID: String?
    public let title: String
    public let preview: String?
    public let similarity: Float
    public let linkType: KnowledgeLink.LinkType

    public var displayIcon: String {
        switch entityType.lowercased() {
        case "idea": return "lightbulb"
        case "task": return "checkmark.circle"
        case "project": return "folder"
        case "research": return "magnifyingglass.circle"
        case "contact": return "person.circle"
        case "note": return "doc.text"
        default: return "doc"
        }
    }

    public var displayColor: Color {
        switch entityType.lowercased() {
        case "idea": return .yellow
        case "task": return .blue
        case "project": return .purple
        case "research": return .green
        case "contact": return .orange
        case "note": return .gray
        default: return .secondary
        }
    }
}

// MARK: - Linked Contacts Section View

public struct LinkedContactsSection: View {
    let researchId: Int64
    let researchContent: String

    @State private var relatedEntities: [LinkedEntity] = []
    @State private var isLinking = false
    @State private var isLoading = false
    @State private var showEntityPicker = false
    @State private var errorMessage: String?

    @EnvironmentObject var appState: AppState

    public init(researchId: Int64, researchContent: String) {
        self.researchId = researchId
        self.researchContent = researchContent
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            headerView

            // Content
            if isLoading {
                loadingView
            } else if relatedEntities.isEmpty {
                emptyView
            } else {
                linkedEntitiesGrid
            }

            // Manual link button
            manualLinkButton
        }
        .padding(20)
        .background(
            ZStack {
                // Premium solid background (Apple-style: no blur)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(CosmoColors.softWhite)
                // Subtle gradient for depth
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.5), Color.white.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 8, y: 2)
        .onAppear {
            loadExistingLinks()
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Linked Content")
                    .font(.system(size: 15, weight: .semibold))

                Text("\(relatedEntities.count) connections")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Auto-link button
            Button(action: {
                Task {
                    await autoLinkRelated()
                }
            }) {
                HStack(spacing: 4) {
                    if isLinking {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: "wand.and.stars")
                    }
                    Text("Link Related")
                }
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .disabled(isLinking)
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        HStack {
            Spacer()
            VStack(spacing: 12) {
                ProgressView()
                Text("Finding connections...")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(height: 100)
    }

    // MARK: - Empty View

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "link.circle")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)

            Text("No linked content yet")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            Text("Click 'Link Related' to discover connections")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 100)
    }

    // MARK: - Linked Entities Grid

    private var linkedEntitiesGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ], spacing: 12) {
            ForEach(relatedEntities) { entity in
                LinkedEntityCard(
                    entity: entity,
                    onTap: {
                        openEntity(entity)
                    },
                    onRemove: {
                        removeLink(entity)
                    }
                )
            }
        }
    }

    // MARK: - Manual Link Button

    private var manualLinkButton: some View {
        Button(action: { showEntityPicker = true }) {
            HStack {
                Image(systemName: "plus.circle")
                Text("Link Specific Item")
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showEntityPicker) {
            EntityPickerSheet(
                onSelect: { entityType, entityId in
                    Task {
                        await createManualLink(entityType: entityType, entityId: entityId)
                    }
                }
            )
        }
    }

    // MARK: - Actions

    private func autoLinkRelated() async {
        isLinking = true
        errorMessage = nil

        do {
            // 1. Get embedding for research content
            let vectorDB = VectorDatabase.shared

            // 2. Search for semantically similar content
            let results = try await vectorDB.search(
                query: researchContent,
                limit: 10,
                minSimilarity: 0.6
            )

            // 3. Filter out self and already linked
            let existingIds = Set(relatedEntities.map { "\($0.entityType):\($0.entityId)" })
            let newResults = results.filter { result in
                let key = "\(result.entityType):\(result.entityId)"
                return key != "research:\(researchId)" && !existingIds.contains(key)
            }

            // 4. Convert to LinkedEntity
            let newEntities = newResults.map { result in
                LinkedEntity(
                    id: "\(result.entityType):\(result.entityId)",
                    entityType: result.entityType,
                    entityId: result.entityId,
                    entityUUID: result.entityUUID,
                    title: result.text?.prefix(50).description ?? "Untitled",
                    preview: result.text?.prefix(100).description,
                    similarity: result.similarity,
                    linkType: .semanticallySimilar
                )
            }

            // 5. Store links in database
            for entity in newEntities {
                await createLink(
                    sourceType: "research",
                    sourceId: researchId,
                    targetType: entity.entityType,
                    targetId: entity.entityId,
                    linkType: .semanticallySimilar,
                    similarity: entity.similarity
                )
            }

            // 6. Update UI
            await MainActor.run {
                relatedEntities.append(contentsOf: newEntities)
                isLinking = false
            }

            print("LinkedContactsSection: Linked \(newEntities.count) related entities")

        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLinking = false
            }
        }
    }

    private func loadExistingLinks() {
        isLoading = true

        Task {
            // Load from database
            let links = await loadLinksFromDatabase()

            await MainActor.run {
                relatedEntities = links
                isLoading = false
            }
        }
    }

    private func loadLinksFromDatabase() async -> [LinkedEntity] {
        // TODO: Query knowledge_links table for this research ID
        // For now, return empty - will be connected to actual database
        return []
    }

    private func createManualLink(entityType: String, entityId: Int64) async {
        // Create link with manual type
        await createLink(
            sourceType: "research",
            sourceId: researchId,
            targetType: entityType,
            targetId: entityId,
            linkType: .manual,
            similarity: 1.0
        )

        // Add to UI
        let entity = LinkedEntity(
            id: "\(entityType):\(entityId)",
            entityType: entityType,
            entityId: entityId,
            entityUUID: nil,
            title: "Linked Item",  // Would fetch actual title
            preview: nil,
            similarity: 1.0,
            linkType: .manual
        )

        await MainActor.run {
            relatedEntities.append(entity)
        }
    }

    private func createLink(
        sourceType: String,
        sourceId: Int64,
        targetType: String,
        targetId: Int64,
        linkType: KnowledgeLink.LinkType,
        similarity: Float
    ) async {
        let _ = KnowledgeLink(
            sourceType: sourceType,
            sourceId: sourceId,
            targetType: targetType,
            targetId: targetId,
            linkType: linkType,
            similarity: similarity
        )

        // TODO: Store in database
        print("LinkedContactsSection: Created link \(sourceType):\(sourceId) -> \(targetType):\(targetId)")
    }

    private func removeLink(_ entity: LinkedEntity) {
        // TODO: Remove from database
        relatedEntities.removeAll { $0.id == entity.id }
    }

    private func openEntity(_ entity: LinkedEntity) {
        // Navigate to entity
        NotificationCenter.default.post(
            name: .openEntity,
            object: nil,
            userInfo: [
                "entityType": entity.entityType,
                "entityId": entity.entityId
            ]
        )
    }
}

// MARK: - Linked Entity Card

struct LinkedEntityCard: View {
    let entity: LinkedEntity
    let onTap: () -> Void
    let onRemove: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: entity.displayIcon)
                    .font(.system(size: 12))
                    .foregroundColor(entity.displayColor)

                Text(entity.entityType.capitalized)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer()

                // Similarity badge
                Text("\(Int(entity.similarity * 100))%")
                    .font(.system(size: 9, weight: .medium))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(entity.displayColor.opacity(0.2))
                    .clipShape(Capsule())

                // Remove button (on hover)
                if isHovered {
                    Button(action: onRemove) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Title
            Text(entity.title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(2)

            // Preview
            if let preview = entity.preview {
                Text(preview)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            // Link type badge
            HStack(spacing: 4) {
                Image(systemName: linkTypeIcon)
                    .font(.system(size: 8))
                Text(entity.linkType.rawValue)
                    .font(.system(size: 9))
            }
            .foregroundStyle(.tertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.background)
                .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    isHovered ? entity.displayColor.opacity(0.5) : Color.primary.opacity(0.1),
                    lineWidth: 1
                )
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            onTap()
        }
    }

    private var linkTypeIcon: String {
        switch entity.linkType {
        case .semanticallySimilar: return "brain"
        case .manual: return "hand.point.right"
        case .mentioned: return "text.quote"
        case .projectRelated: return "folder"
        case .citation: return "quote.bubble"
        }
    }
}

// MARK: - Entity Picker Sheet

struct EntityPickerSheet: View {
    let onSelect: (String, Int64) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedType = "all"
    @State private var searchResults: [LinkedEntity] = []

    private let entityTypes = ["all", "idea", "task", "project", "research", "contact"]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Link to Item")
                    .font(.headline)

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
            }
            .padding()

            Divider()

            // Search and filter
            HStack(spacing: 12) {
                // Search field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(8)
                .background(Color.primary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                // Type picker
                Picker("Type", selection: $selectedType) {
                    ForEach(entityTypes, id: \.self) { type in
                        Text(type.capitalized).tag(type)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 120)
            }
            .padding()

            Divider()

            // Results
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(searchResults) { entity in
                        Button(action: {
                            onSelect(entity.entityType, entity.entityId)
                            dismiss()
                        }) {
                            HStack {
                                Image(systemName: entity.displayIcon)
                                    .foregroundColor(entity.displayColor)

                                VStack(alignment: .leading) {
                                    Text(entity.title)
                                        .font(.system(size: 13, weight: .medium))

                                    Text(entity.entityType.capitalized)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(12)
                            .background(Color.primary.opacity(0.02))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
        }
        .frame(width: 400, height: 500)
        .onChange(of: searchText) { _, _ in
            performSearch()
        }
        .onChange(of: selectedType) { _, _ in
            performSearch()
        }
    }

    private func performSearch() {
        // TODO: Implement actual search
        // Would query database based on searchText and selectedType
        searchResults = []
    }
}

// MARK: - Notification Names

extension Notification.Name {
    // Note: openEntity is already defined in Cosmo/CosmoChatView.swift
    static let linkEntities = Notification.Name("com.cosmo.linkEntities")
}

// MARK: - Voice Command Integration

extension LinkedContactsSection {
    /// Handle "link everything related" voice command
    public static func handleVoiceCommand(researchId: Int64, command: String) async {
        let lowercased = command.lowercased()

        if lowercased.contains("link") && (lowercased.contains("related") || lowercased.contains("everything")) {
            // Trigger auto-link via notification
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .triggerAutoLink,
                    object: nil,
                    userInfo: ["researchId": researchId]
                )
            }
        }
    }
}

extension Notification.Name {
    static let triggerAutoLink = Notification.Name("com.cosmo.triggerAutoLink")
}
