// CosmoOS/Focus/FocusBlocksEngine.swift
// Manages document-scoped floating blocks within focus mode
// Blocks persist with the parent entity as JSON metadata

import Foundation
import SwiftUI
import GRDB

/// A floating block that exists within focus mode context
/// Stored as relative positions to the document center
struct FocusBlock: Identifiable, Codable {
    let id: String
    let entityType: EntityType
    var entityId: Int64
    var title: String
    var content: String?

    // Position relative to center (0,0 = center)
    var relativeX: CGFloat
    var relativeY: CGFloat

    // Size
    var width: CGFloat
    var height: CGFloat

    // Visual state
    var isMinimized: Bool
    var zIndex: Int

    // Metadata
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        entityType: EntityType,
        entityId: Int64 = -1,
        title: String,
        content: String? = nil,
        relativeX: CGFloat,
        relativeY: CGFloat,
        width: CGFloat = 240,
        height: CGFloat = 180
    ) {
        self.id = id
        self.entityType = entityType
        self.entityId = entityId
        self.title = title
        self.content = content
        self.relativeX = relativeX
        self.relativeY = relativeY
        self.width = width
        self.height = height
        self.isMinimized = false
        self.zIndex = 0
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    /// Calculate absolute position given canvas center
    func absolutePosition(canvasCenter: CGPoint) -> CGPoint {
        CGPoint(
            x: canvasCenter.x + relativeX,
            y: canvasCenter.y + relativeY
        )
    }

    /// Update relative position from absolute position
    mutating func updatePosition(absolutePosition: CGPoint, canvasCenter: CGPoint) {
        relativeX = absolutePosition.x - canvasCenter.x
        relativeY = absolutePosition.y - canvasCenter.y
        updatedAt = Date()
    }
}

// MARK: - Focus Blocks Engine
@MainActor
class FocusBlocksEngine: ObservableObject {
    @Published var blocks: [FocusBlock] = []
    @Published var isLoading = false
    @Published var selectedBlockId: String?

    let documentId: Int64
    let documentType: EntityType

    private let database = CosmoDatabase.shared
    private var hasUnsavedChanges = false
    private var debouncedSaveTask: Task<Void, Never>?

    init(documentId: Int64, documentType: EntityType) {
        self.documentId = documentId
        self.documentType = documentType
    }

    /// Debounced save for frequent updates (like dragging)
    private func debouncedSave() {
        debouncedSaveTask?.cancel()
        debouncedSaveTask = Task {
            do {
                try await Task.sleep(nanoseconds: 500_000_000)  // 0.5 second debounce
                guard !Task.isCancelled else { return }
                await saveBlocks()
            } catch {
                // Cancelled
            }
        }
    }

    // MARK: - Load Blocks
    func loadBlocks() async {
        isLoading = true

        do {
            // Load focus blocks from entity's metadata
            let blocksJson = try await fetchFocusBlocksMetadata()

            if let blocksJson = blocksJson,
               let data = blocksJson.data(using: .utf8) {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                blocks = try decoder.decode([FocusBlock].self, from: data)
                print("✅ Loaded \(blocks.count) focus blocks for \(documentType.rawValue) \(documentId)")
            }
        } catch {
            print("⚠️ Failed to load focus blocks: \(error)")
            blocks = []
        }

        isLoading = false
    }

    // MARK: - Save Blocks
    func saveBlocks() async {
        guard hasUnsavedChanges else { return }

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(blocks)
            let json = String(data: data, encoding: .utf8) ?? "[]"

            try await saveFocusBlocksMetadata(json)
            hasUnsavedChanges = false
            print("✅ Saved \(blocks.count) focus blocks")
        } catch {
            print("❌ Failed to save focus blocks: \(error)")
        }
    }

    // MARK: - Add Block
    func addBlock(at relativePosition: CGPoint, type: EntityType, title: String = "New Block") {
        let block = FocusBlock(
            entityType: type,
            title: title,
            relativeX: relativePosition.x,
            relativeY: relativePosition.y
        )

        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            blocks.append(block)
        }

        hasUnsavedChanges = true
        selectedBlockId = block.id

        print("✨ Added focus block: \(type.rawValue) at (\(relativePosition.x), \(relativePosition.y))")

        // Save immediately to persist the block
        Task {
            await saveBlocks()
        }
    }

    /// Add a block with content from an existing entity (e.g., from @mention click)
    func addBlockWithContent(
        at relativePosition: CGPoint,
        type: EntityType,
        entityId: Int64,
        title: String,
        content: String?
    ) {
        let block = FocusBlock(
            entityType: type,
            entityId: entityId,
            title: title,
            content: content,
            relativeX: relativePosition.x,
            relativeY: relativePosition.y
        )

        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            blocks.append(block)
        }

        hasUnsavedChanges = true
        selectedBlockId = block.id

        print("✨ Added focus block from @mention: \(type.rawValue) id=\(entityId) at (\(relativePosition.x), \(relativePosition.y))")

        // Save immediately to persist the block
        Task {
            await saveBlocks()
        }
    }

    // MARK: - Update Block Position
    func updateBlockPosition(_ blockId: String, to absolutePosition: CGPoint, canvasCenter: CGPoint) {
        guard let index = blocks.firstIndex(where: { $0.id == blockId }) else { return }

        blocks[index].updatePosition(absolutePosition: absolutePosition, canvasCenter: canvasCenter)
        hasUnsavedChanges = true
        debouncedSave()  // Use debounced save during drag
    }

    // MARK: - Update Block Content
    func updateBlockContent(_ blockId: String, title: String? = nil, content: String? = nil) {
        guard let index = blocks.firstIndex(where: { $0.id == blockId }) else { return }

        if let title = title {
            blocks[index].title = title
        }
        if let content = content {
            blocks[index].content = content
        }
        blocks[index].updatedAt = Date()
        hasUnsavedChanges = true
        debouncedSave()  // Debounced save for content edits
    }

    // MARK: - Remove Block
    func removeBlock(_ blockId: String) {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            blocks.removeAll { $0.id == blockId }
        }

        if selectedBlockId == blockId {
            selectedBlockId = nil
        }

        hasUnsavedChanges = true
        print("🗑️ Removed focus block: \(blockId)")

        // Save immediately
        Task {
            await saveBlocks()
        }
    }

    // MARK: - Select Block
    func selectBlock(_ blockId: String?) {
        selectedBlockId = blockId

        // Bring to front
        if let blockId = blockId,
           let index = blocks.firstIndex(where: { $0.id == blockId }) {
            let maxZ = blocks.map(\.zIndex).max() ?? 0
            blocks[index].zIndex = maxZ + 1
        }
    }

    // MARK: - Private: Fetch/Save Metadata
    private func fetchFocusBlocksMetadata() async throws -> String? {
        // Fetch the atom directly - focus blocks are stored in the structured field
        return try await database.asyncRead { db in
            let atom = try Atom.filter(Column("id") == self.documentId).fetchOne(db)
            guard let atom = atom else { return nil }

            // Get focus blocks from structured data based on type
            switch atom.type {
            case .idea:
                return atom.structuredData(as: FocusBlocksStructured.self)?.focusBlocks
            case .content:
                return atom.structuredData(as: ContentStructured.self)?.focusBlocks
            case .research:
                return atom.structuredData(as: ResearchStructured.self)?.focusBlocks
            default:
                return nil
            }
        }
    }

    private func saveFocusBlocksMetadata(_ json: String) async throws {
        let now = ISO8601DateFormatter().string(from: Date())

        switch documentType {
        case .idea:
            try await database.asyncWrite { db in
                try db.execute(
                    sql: "UPDATE ideas SET focus_blocks = ?, updated_at = ?, _local_version = _local_version + 1 WHERE id = ?",
                    arguments: [json, now, self.documentId]
                )
            }
        case .content:
            try await database.asyncWrite { db in
                try db.execute(
                    sql: "UPDATE content SET focus_blocks = ?, updated_at = ?, _local_version = _local_version + 1 WHERE id = ?",
                    arguments: [json, now, self.documentId]
                )
            }
        case .research:
            try await database.asyncWrite { db in
                try db.execute(
                    sql: "UPDATE research SET focus_blocks = ?, updated_at = ?, _local_version = _local_version + 1 WHERE id = ?",
                    arguments: [json, now, self.documentId]
                )
            }
        default:
            break
        }
    }

    // MARK: - Force Save (for immediate persistence)
    func forceSave() {
        hasUnsavedChanges = true
        Task {
            await saveBlocks()
        }
    }
}
