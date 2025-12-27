// CosmoOS/Voice/VoiceContextStore.swift
// Shared snapshot of the user's current UI context for voice commands
// (focused entity, selected entity, selected block, current section, glass results, etc.)

import Foundation

@MainActor
final class VoiceContextStore: ObservableObject {
    static let shared = VoiceContextStore()

    @Published var selectedSection: NavigationSection = .home
    @Published var selectedEntity: EntitySelection? = nil
    @Published var focusedEntity: EntitySelection? = nil
    @Published var selectedBlockId: String? = nil

    // Glass selection context for voice follow-ups ("place this one", "the second one")
    @Published var glassResults: [GlassResultEntity] = []
    @Published var glassSelectedIndex: Int? = nil
    @Published var glassResultsTimestamp: Date? = nil

    private var blockSelectionObserver: NSObjectProtocol?
    private var glassCardObserver: NSObjectProtocol?

    private init() {
        // Track selected canvas block (for "this block" / relative placement)
        blockSelectionObserver = NotificationCenter.default.addObserver(
            forName: .blockSelected,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let blockId = notification.userInfo?["blockId"] as? String
            Task { @MainActor [self] in
                self?.selectedBlockId = blockId
            }
        }

        // Track glass card results for follow-up references
        glassCardObserver = NotificationCenter.default.addObserver(
            forName: .glassCardPresented,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let entities = notification.userInfo?["entities"] as? [GlassResultEntity]
            Task { @MainActor [self] in
                if let entities {
                self?.glassResults = entities
                self?.glassSelectedIndex = entities.isEmpty ? nil : 0
                self?.glassResultsTimestamp = Date()
                }
            }
        }
    }

    // MARK: - Glass Results Management

    func setGlassResults(_ results: [CosmoGlassEntityRef]) {
        glassResults = results.map { ref in
            GlassResultEntity(
                uuid: ref.id,
                entityType: ref.entityType,
                entityId: ref.entityId,
                title: ref.title,
                index: ref.index
            )
        }
        glassSelectedIndex = results.isEmpty ? nil : 0
        glassResultsTimestamp = Date()
    }

    func clearGlassResults() {
        glassResults = []
        glassSelectedIndex = nil
        glassResultsTimestamp = nil
    }

    /// Check if glass results are still valid (within 5 minutes)
    var hasValidGlassResults: Bool {
        guard let timestamp = glassResultsTimestamp else { return false }
        return Date().timeIntervalSince(timestamp) < 300 && !glassResults.isEmpty
    }

    func snapshot() -> VoiceContextSnapshot {
        // Get editing context from tracker
        let editingContext = EditingContextTracker.shared.snapshot()

        return VoiceContextSnapshot(
            selectedSection: selectedSection,
            selectedEntity: selectedEntity,
            focusedEntity: focusedEntity,
            selectedBlockId: selectedBlockId,
            glassResults: hasValidGlassResults ? glassResults : [],
            glassSelectedIndex: glassSelectedIndex,
            // Editing context for semantic search
            editingEntityType: editingContext.entityType,
            editingEntityId: editingContext.entityId,
            editingTitle: editingContext.title,
            editingCursorContext: editingContext.cursorContext,
            extractedConcepts: editingContext.extractedConcepts,
            contextVector: editingContext.contextVector
        )
    }
}

// MARK: - Glass Result Entity (Sendable for snapshot)

public struct GlassResultEntity: Sendable, Equatable {
    public let uuid: String
    public let entityType: String
    public let entityId: Int64
    public let title: String
    public let index: Int  // 1-based index for "first", "second", etc.

    public init(uuid: String, entityType: String, entityId: Int64, title: String, index: Int) {
        self.uuid = uuid
        self.entityType = entityType
        self.entityId = entityId
        self.title = title
        self.index = index
    }
}

public struct VoiceContextSnapshot: Sendable {
    public let selectedSection: NavigationSection
    public let selectedEntity: EntitySelection?
    public let focusedEntity: EntitySelection?
    public let selectedBlockId: String?

    // Glass results for follow-up voice commands
    public let glassResults: [GlassResultEntity]
    public let glassSelectedIndex: Int?

    // Editing context for semantic search (telepathic context awareness)
    public let editingEntityType: EntityType?
    public let editingEntityId: Int64?
    public let editingTitle: String?
    public let editingCursorContext: String?
    public let extractedConcepts: [String]
    public let contextVector: [Float]?

    public init(
        selectedSection: NavigationSection,
        selectedEntity: EntitySelection?,
        focusedEntity: EntitySelection?,
        selectedBlockId: String?,
        glassResults: [GlassResultEntity] = [],
        glassSelectedIndex: Int? = nil,
        editingEntityType: EntityType? = nil,
        editingEntityId: Int64? = nil,
        editingTitle: String? = nil,
        editingCursorContext: String? = nil,
        extractedConcepts: [String] = [],
        contextVector: [Float]? = nil
    ) {
        self.selectedSection = selectedSection
        self.selectedEntity = selectedEntity
        self.focusedEntity = focusedEntity
        self.selectedBlockId = selectedBlockId
        self.glassResults = glassResults
        self.glassSelectedIndex = glassSelectedIndex
        self.editingEntityType = editingEntityType
        self.editingEntityId = editingEntityId
        self.editingTitle = editingTitle
        self.editingCursorContext = editingCursorContext
        self.extractedConcepts = extractedConcepts
        self.contextVector = contextVector
    }

    /// Get entity by ordinal reference ("first", "second", etc.)
    func glassEntity(at ordinal: Int) -> GlassResultEntity? {
        guard ordinal > 0, ordinal <= glassResults.count else { return nil }
        return glassResults[ordinal - 1]
    }

    /// Get currently selected glass entity
    var selectedGlassEntity: GlassResultEntity? {
        guard let idx = glassSelectedIndex, idx >= 0, idx < glassResults.count else { return nil }
        return glassResults[idx]
    }

    // MARK: - Editing Context Helpers

    /// Whether there's active editing context
    var hasEditingContext: Bool {
        editingEntityType != nil && editingEntityId != nil
    }

    /// Whether a pre-computed context vector is available
    var hasContextVector: Bool {
        contextVector != nil && !(contextVector?.isEmpty ?? true)
    }

    /// Combined editing context text for fallback queries
    var editingContextText: String? {
        guard hasEditingContext else { return nil }
        return [editingTitle, editingCursorContext]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

