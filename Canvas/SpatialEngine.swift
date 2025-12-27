// CosmoOS/Canvas/SpatialEngine.swift
// Voice-driven spatial placement and layout system

import Foundation
import SwiftUI
import GRDB

@MainActor
class SpatialEngine: ObservableObject {
    @Published var blocks: [CanvasBlock] = []
    @Published var isLoading = false

    private let database: CosmoDatabase
    private let localLLM: LocalLLM

    // Current document context
    var currentDocumentType: String = "home"
    var currentDocumentId: Int64 = 0
    var currentThinkspaceId: String? = nil

    convenience init() {
        self.init(database: .shared, localLLM: .shared)
    }

    init(database: CosmoDatabase, localLLM: LocalLLM) {
        self.database = database
        self.localLLM = localLLM
    }

    // MARK: - Load Blocks from Database
    func loadBlocks(for documentType: String = "home", documentId: Int64 = 0, thinkspaceId: String? = nil) async {
        isLoading = true
        currentDocumentType = documentType
        currentDocumentId = documentId
        currentThinkspaceId = thinkspaceId

        do {
            let tsId = thinkspaceId  // Capture for closure
            let savedBlocks: [CanvasBlockRecord] = try await database.asyncRead { db in
                var query = CanvasBlockRecord
                    .filter(Column("document_type") == documentType)
                    .filter(Column("document_id") == documentId)
                    .filter(Column("is_deleted") == false)

                // Filter by ThinkSpace if provided
                if let thinkspaceId = tsId {
                    query = query.filter(Column("thinkspace_id") == thinkspaceId)
                } else {
                    // If no thinkspace specified, only load blocks without a thinkspace
                    query = query.filter(Column("thinkspace_id") == nil)
                }

                return try query.order(Column("z_index")).fetchAll(db)
            }

            // Convert database records to CanvasBlocks
            var loadedBlocks: [CanvasBlock] = []
            for record in savedBlocks {
                // Build metadata from database record
                var metadata: [String: String] = [:]

                // For note and content blocks, restore content from note_content field
                // Both types use metadata-based storage rather than atoms table
                if (record.entityType == "note" || record.entityType == "content"),
                   let noteContent = record.noteContent {
                    metadata["content"] = noteContent
                }

                // For note and content blocks, also restore title in metadata
                // This is needed because the block views load title from metadata
                if (record.entityType == "note" || record.entityType == "content"),
                   let title = record.entityTitle, !title.isEmpty {
                    metadata["title"] = title
                }

                // Restore created timestamp if available
                if let createdAt = record.createdAt {
                    metadata["created"] = createdAt
                }
                
                let block = CanvasBlock(
                    id: record.id,
                    position: CGPoint(x: CGFloat(record.positionX), y: CGFloat(record.positionY)),
                    size: CGSize(width: CGFloat(record.width ?? 280), height: CGFloat(record.height ?? 180)),
                    isPinned: record.isPinned ?? false,  // Read pin state from database
                    zIndex: record.zIndex ?? 0,
                    entityType: EntityType(rawValue: record.entityType) ?? .idea,
                    entityId: Int64(record.entityId),
                    entityUuid: record.entityUuid ?? "",
                    title: record.entityTitle ?? "Untitled",
                    metadata: metadata
                )
                loadedBlocks.append(block)
            }

            self.blocks = loadedBlocks
            isLoading = false
            print("✅ Loaded \(loadedBlocks.count) canvas blocks for \(documentType)/\(documentId)")

        } catch {
            isLoading = false
            print("❌ Failed to load canvas blocks: \(error)")
        }
    }

    // MARK: - Save Block to Database
    func saveBlock(_ block: CanvasBlock) async {
        let docType = currentDocumentType
        let docId = currentDocumentId
        let tsId = currentThinkspaceId

        do {
            try await database.asyncWrite { db in
                // Extract content from metadata for note and content blocks (both use metadata-based storage)
                let noteContent: String? = (block.entityType == .note || block.entityType == .content)
                    ? block.metadata["content"]
                    : nil

                try db.execute(
                    sql: """
                    INSERT OR REPLACE INTO canvas_blocks
                    (id, document_type, document_id, entity_type, entity_id, entity_uuid, entity_title,
                     position_x, position_y, width, height, z_index, note_content, is_pinned, thinkspace_id, is_deleted, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
                    """,
                    arguments: [
                        block.id,
                        docType,
                        docId,
                        block.entityType.rawValue,
                        block.entityId,
                        block.entityUuid,
                        block.title,
                        Int(block.position.x),
                        Int(block.position.y),
                        Int(block.size.width),
                        Int(block.size.height),
                        block.zIndex,
                        noteContent,
                        block.isPinned,
                        tsId
                    ]
                )
            }
            print("💾 Saved block: \(block.title) to ThinkSpace: \(tsId ?? "none")")
        } catch {
            print("❌ Failed to save block: \(error)")
        }
    }

    // MARK: - Update Block Position
    func updateBlockPosition(_ blockId: String, position: CGPoint) {
        // Update in memory (instant)
        if let index = blocks.firstIndex(where: { $0.id == blockId }) {
            blocks[index].position = position
        }

        // Fire-and-forget database update
        let db = database
        Task.detached(priority: .background) {
            do {
                try await db.asyncWrite { database in
                    try database.execute(
                        sql: "UPDATE canvas_blocks SET position_x = ?, position_y = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?",
                        arguments: [Int(position.x), Int(position.y), blockId]
                    )
                }
            } catch {
                print("❌ Failed to update block position: \(error)")
            }
        }
    }

    // MARK: - Remove Block
    func removeBlock(_ blockId: String) async {
        // Remove from memory FIRST (instant UI update)
        withAnimation(.easeOut(duration: 0.15)) {
            blocks.removeAll { $0.id == blockId }
        }

        // Fire-and-forget database update (non-blocking)
        let db = database
        Task.detached(priority: .background) {
            do {
                try await db.asyncWrite { database in
                    try database.execute(
                        sql: "UPDATE canvas_blocks SET is_deleted = 1, updated_at = CURRENT_TIMESTAMP WHERE id = ?",
                        arguments: [blockId]
                    )
                }
                print("🗑️ Removed block: \(blockId)")
            } catch {
                print("❌ Failed to remove block: \(error)")
            }
        }
    }

    // MARK: - Add Block (with persistence)
    func addBlock(_ block: CanvasBlock, persist: Bool = true) async {
        blocks.append(block)

        if persist {
            await saveBlock(block)
        }
    }

    // MARK: - Voice-Driven Placement
    func placeBlocks(
        query: String,
        entityType: EntityType,
        quantity: Int,
        layout: LayoutStyle = .orbital,
        canvasSize: CGSize,
        centerOverride: CGPoint? = nil
    ) async throws {
        print("🎨 Placing \(quantity) \(entityType.rawValue)s with layout: \(layout)")

        // Search for entities
        let entities = try await searchEntities(
            query: query,
            type: entityType,
            limit: quantity
        )

        // Create blocks from entities
        var newBlocks: [CanvasBlock] = []

        for entity in entities {
            let block = createBlock(from: entity, type: entityType)
            newBlocks.append(block)
        }

        // Compute spatial layout
        let positions = computeLayout(
            count: newBlocks.count,
            style: layout,
            canvasSize: canvasSize,
            centerOverride: centerOverride
        )

        // Apply positions
        for (index, position) in positions.enumerated() {
            if index < newBlocks.count {
                newBlocks[index].position = position
                newBlocks[index].animateTo(position: position)
            }
        }

        // Add to canvas with animation
        for block in newBlocks {
            blocks.append(block)
        }

        print("✅ Placed \(newBlocks.count) blocks on canvas")
    }

    // MARK: - Entity Search (FTS5 Enabled)
    private func searchEntities(
        query: String,
        type: EntityType,
        limit: Int
    ) async throws -> [Any] {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        switch type {
        case .idea:
            return try await database.asyncRead { db in
                if !cleanQuery.isEmpty {
                    // FTS5 search for relevant ideas
                    let ftsQuery = cleanQuery.split(separator: " ").map { "\($0)*" }.joined(separator: " ")
                    return try Idea.fetchAll(db, sql: """
                        SELECT ideas.* FROM ideas
                        LEFT JOIN ideas_fts ON ideas.id = ideas_fts.rowid
                        WHERE ideas.is_deleted = 0
                        AND (
                            ideas_fts MATCH ?
                            OR ideas.title LIKE ?
                            OR ideas.content LIKE ?
                        )
                        ORDER BY
                            CASE WHEN ideas_fts MATCH ? THEN 0 ELSE 1 END,
                            ideas.updated_at DESC
                        LIMIT ?
                    """, arguments: [ftsQuery, "%\(cleanQuery)%", "%\(cleanQuery)%", ftsQuery, limit])
                } else {
                    return try Atom
                        .filter(Column("type") == AtomType.idea.rawValue)
                        .filter(Column("is_deleted") == false)
                        .order(Column("updated_at").desc)
                        .limit(limit)
                        .fetchAll(db)
                        .map { IdeaWrapper(atom: $0) }
                }
            }

        case .content:
            return try await database.asyncRead { db in
                if !cleanQuery.isEmpty {
                    // Use simple LIKE search on atoms table
                    return try Atom
                        .filter(Column("type") == AtomType.content.rawValue)
                        .filter(Column("is_deleted") == false)
                        .filter(Column("title").like("%\(cleanQuery)%") || Column("body").like("%\(cleanQuery)%"))
                        .order(Column("updated_at").desc)
                        .limit(limit)
                        .fetchAll(db)
                        .map { ContentWrapper(atom: $0) }
                } else {
                    return try Atom
                        .filter(Column("type") == AtomType.content.rawValue)
                        .filter(Column("is_deleted") == false)
                        .order(Column("updated_at").desc)
                        .limit(limit)
                        .fetchAll(db)
                        .map { ContentWrapper(atom: $0) }
                }
            }

        case .task:
            return try await database.asyncRead { db in
                if !cleanQuery.isEmpty {
                    return try Atom
                        .filter(Column("type") == AtomType.task.rawValue)
                        .filter(Column("is_deleted") == false)
                        .filter(Column("title").like("%\(cleanQuery)%") || Column("body").like("%\(cleanQuery)%"))
                        .order(Column("updated_at").desc)
                        .limit(limit)
                        .fetchAll(db)
                        .map { TaskWrapper(atom: $0) }
                } else {
                    return try Atom
                        .filter(Column("type") == AtomType.task.rawValue)
                        .filter(Column("is_deleted") == false)
                        .order(Column("updated_at").desc)
                        .limit(limit)
                        .fetchAll(db)
                        .map { TaskWrapper(atom: $0) }
                }
            }

        case .connection:
            return try await database.asyncRead { db in
                if !cleanQuery.isEmpty {
                    return try Atom
                        .filter(Column("type") == AtomType.connection.rawValue)
                        .filter(Column("is_deleted") == false)
                        .filter(Column("title").like("%\(cleanQuery)%"))
                        .order(Column("updated_at").desc)
                        .limit(limit)
                        .fetchAll(db)
                        .map { ConnectionWrapper(atom: $0) }
                } else {
                    return try Atom
                        .filter(Column("type") == AtomType.connection.rawValue)
                        .filter(Column("is_deleted") == false)
                        .order(Column("updated_at").desc)
                        .limit(limit)
                        .fetchAll(db)
                        .map { ConnectionWrapper(atom: $0) }
                }
            }

        case .research:
            return try await database.asyncRead { db in
                if !cleanQuery.isEmpty {
                    return try Atom
                        .filter(Column("type") == AtomType.research.rawValue)
                        .filter(Column("is_deleted") == false)
                        .filter(Column("title").like("%\(cleanQuery)%") || Column("body").like("%\(cleanQuery)%"))
                        .order(Column("updated_at").desc)
                        .limit(limit)
                        .fetchAll(db)
                        .map { ResearchWrapper(atom: $0) }
                } else {
                    return try Atom
                        .filter(Column("type") == AtomType.research.rawValue)
                        .filter(Column("is_deleted") == false)
                        .order(Column("updated_at").desc)
                        .limit(limit)
                        .fetchAll(db)
                        .map { ResearchWrapper(atom: $0) }
                }
            }

        case .project:
            return try await database.asyncRead { db in
                if !cleanQuery.isEmpty {
                    return try Atom
                        .filter(Column("type") == AtomType.project.rawValue)
                        .filter(Column("is_deleted") == false)
                        .filter(Column("title").like("%\(cleanQuery)%") || Column("body").like("%\(cleanQuery)%"))
                        .order(Column("updated_at").desc)
                        .limit(limit)
                        .fetchAll(db)
                        .map { ProjectWrapper(atom: $0) }
                } else {
                    return try Atom
                        .filter(Column("type") == AtomType.project.rawValue)
                        .filter(Column("is_deleted") == false)
                        .order(Column("updated_at").desc)
                        .limit(limit)
                        .fetchAll(db)
                        .map { ProjectWrapper(atom: $0) }
                }
            }

        default:
            return []
        }
    }

    // MARK: - Block Creation
    private func createBlock(from entity: Any, type: EntityType) -> CanvasBlock {
        let center = CGPoint(x: 960, y: 540)  // Start at center

        switch type {
        case .idea:
            return CanvasBlock.fromIdea(entity as! Idea, position: center)
        case .content:
            return CanvasBlock.fromContent(entity as! CosmoContent, position: center)
        case .task:
            return CanvasBlock.fromTask(entity as! CosmoTask, position: center)
        case .connection:
            return CanvasBlock.fromConnection(entity as! Connection, position: center)
        case .research:
            return CanvasBlock.fromResearch(entity as! Research, position: center)
        case .project:
            return CanvasBlock.fromProject(entity as! Project, position: center)
        default:
            fatalError("Unsupported entity type: \(type)")
        }
    }

    // MARK: - Layout Computation
    private func computeLayout(
        count: Int,
        style: LayoutStyle,
        canvasSize: CGSize,
        centerOverride: CGPoint? = nil
    ) -> [CGPoint] {
        let center = centerOverride ?? CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)

        switch style {
        case .orbital:
            return computeOrbitalLayout(count: count, center: center)

        case .grid:
            return computeGridLayout(count: count, center: center)

        case .linear:
            return computeLinearLayout(count: count, center: center)

        case .clustered:
            return computeClusteredLayout(count: count, center: center)

        case .llmDriven:
            // Use local LLM for semantic placement
            return computeLLMLayout(count: count, center: center)

        // NEW: Magical arrangements
        case .snake:
            return computeSnakeLayout(count: count, center: center)

        case .spiral:
            return computeSpiralLayout(count: count, center: center)

        case .wave:
            return computeWaveLayout(count: count, center: center)

        case .diamond:
            return computeDiamondLayout(count: count, center: center)

        case .tree:
            return computeTreeLayout(count: count, center: center)

        case .flow:
            return computeFlowLayout(count: count, center: center)
        }
    }

    private func computeOrbitalLayout(count: Int, center: CGPoint) -> [CGPoint] {
        let radius: CGFloat = 300
        var positions: [CGPoint] = []

        for i in 0..<count {
            let angle = (CGFloat(i) / CGFloat(count)) * 2 * .pi
            let x = center.x + cos(angle) * radius
            let y = center.y + sin(angle) * radius
            positions.append(CGPoint(x: x, y: y))
        }

        return positions
    }

    private func computeGridLayout(count: Int, center: CGPoint) -> [CGPoint] {
        let columns = Int(ceil(sqrt(Double(count))))
        let spacing: CGFloat = 320
        var positions: [CGPoint] = []

        let startX = center.x - (CGFloat(columns) * spacing / 2)
        let startY = center.y - (CGFloat(count / columns) * spacing / 2)

        for i in 0..<count {
            let col = i % columns
            let row = i / columns

            let x = startX + CGFloat(col) * spacing
            let y = startY + CGFloat(row) * spacing

            positions.append(CGPoint(x: x, y: y))
        }

        return positions
    }

    private func computeLinearLayout(count: Int, center: CGPoint) -> [CGPoint] {
        let spacing: CGFloat = 320
        var positions: [CGPoint] = []

        let startX = center.x - (CGFloat(count - 1) * spacing / 2)

        for i in 0..<count {
            let x = startX + CGFloat(i) * spacing
            positions.append(CGPoint(x: x, y: center.y))
        }

        return positions
    }

    private func computeClusteredLayout(count: Int, center: CGPoint) -> [CGPoint] {
        // Random cluster with slight randomness
        var positions: [CGPoint] = []
        let maxOffset: CGFloat = 200

        for _ in 0..<count {
            let x = center.x + CGFloat.random(in: -maxOffset...maxOffset)
            let y = center.y + CGFloat.random(in: -maxOffset...maxOffset)
            positions.append(CGPoint(x: x, y: y))
        }

        return positions
    }

    private func computeLLMLayout(count: Int, center: CGPoint) -> [CGPoint] {
        // TODO: Use LocalLLM.computeSpatialPlacement for semantic layouts
        // For now, fallback to orbital
        return computeOrbitalLayout(count: count, center: center)
    }

    // MARK: - Block Movement
    func moveBlocks(
        direction: Direction,
        distance: CGFloat = 100
    ) {
        let selectedBlocks = blocks.filter { $0.isSelected || !blocks.contains(where: { $0.isSelected }) }

        for index in blocks.indices {
            guard selectedBlocks.contains(where: { $0.id == blocks[index].id }) else { continue }

            var newPosition = blocks[index].position

            switch direction {
            case .left:
                newPosition.x -= distance
            case .right:
                newPosition.x += distance
            case .up:
                newPosition.y -= distance
            case .down:
                newPosition.y += distance
            }

            blocks[index].animateTo(position: newPosition)
        }

        print("✅ Moved \(selectedBlocks.count) blocks \(direction)")
    }

    // MARK: - Block Selection
    func selectBlock(at point: CGPoint) -> CanvasBlock? {
        // Find topmost block at point
        let hitBlocks = blocks.filter { block in
            let frame = CGRect(
                origin: block.position,
                size: CGSize(
                    width: block.size.width * block.scale,
                    height: block.size.height * block.scale
                )
            )
            return frame.contains(point)
        }

        return hitBlocks.max(by: { $0.zIndex < $1.zIndex })
    }

    // MARK: - Clear Canvas
    func clearCanvas() {
        blocks.removeAll()
        print("🗑️  Canvas cleared")
    }

    // MARK: - Magical Spatial Arrangements (INSTANT!)

    /// Rearrange all blocks (or selected blocks) into a new pattern
    func arrangeBlocks(style: LayoutStyle, canvasSize: CGSize? = nil) {
        let targetBlocks = blocks.filter { $0.isSelected }
        let blocksToArrange = targetBlocks.isEmpty ? blocks : targetBlocks

        guard !blocksToArrange.isEmpty else { return }

        let size = canvasSize ?? CGSize(width: 1920, height: 1080)

        let positions = computeLayout(count: blocksToArrange.count, style: style, canvasSize: size)

        // Animate blocks to new positions with staggered timing
        for (index, block) in blocksToArrange.enumerated() {
            if let blockIndex = blocks.firstIndex(where: { $0.id == block.id }),
               index < positions.count {
                // Staggered animation for magical effect
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.05) {
                    self.blocks[blockIndex].animateTo(position: positions[index])
                }
            }
        }

        print("✨ Arranged \(blocksToArrange.count) blocks in \(style.rawValue) pattern")
    }

    // MARK: - Snake Layout (Sinusoidal serpent)
    private func computeSnakeLayout(count: Int, center: CGPoint) -> [CGPoint] {
        var positions: [CGPoint] = []
        let amplitude: CGFloat = 120
        let frequency: CGFloat = 0.4
        let spacing: CGFloat = 180

        let startX = center.x - (CGFloat(count - 1) * spacing / 2)

        for i in 0..<count {
            let x = startX + CGFloat(i) * spacing
            let y = center.y + sin(CGFloat(i) * frequency * .pi) * amplitude
            positions.append(CGPoint(x: x, y: y))
        }

        return positions
    }

    // MARK: - Spiral Layout (Outward golden spiral)
    private func computeSpiralLayout(count: Int, center: CGPoint) -> [CGPoint] {
        var positions: [CGPoint] = []
        let angleIncrement: CGFloat = 2.4  // Golden angle in radians
        let radiusGrowth: CGFloat = 40

        for i in 0..<count {
            let angle = CGFloat(i) * angleIncrement
            let radius = radiusGrowth * sqrt(CGFloat(i + 1))

            let x = center.x + cos(angle) * radius
            let y = center.y + sin(angle) * radius
            positions.append(CGPoint(x: x, y: y))
        }

        return positions
    }

    // MARK: - Wave Layout (Horizontal flowing wave)
    private func computeWaveLayout(count: Int, center: CGPoint) -> [CGPoint] {
        var positions: [CGPoint] = []
        let amplitude: CGFloat = 80
        let wavelength: CGFloat = 250
        let verticalSpacing: CGFloat = 140

        let rows = Int(ceil(Double(count) / 4.0))
        let itemsPerRow = Int(ceil(Double(count) / Double(rows)))
        let startX = center.x - CGFloat(itemsPerRow - 1) * wavelength / 2
        let startY = center.y - CGFloat(rows - 1) * verticalSpacing / 2

        var index = 0
        for row in 0..<rows {
            for col in 0..<itemsPerRow {
                guard index < count else { break }

                let x = startX + CGFloat(col) * wavelength
                let waveOffset = sin(CGFloat(col) * 0.8 + CGFloat(row) * 0.5) * amplitude
                let y = startY + CGFloat(row) * verticalSpacing + waveOffset

                positions.append(CGPoint(x: x, y: y))
                index += 1
            }
        }

        return positions
    }

    // MARK: - Diamond Layout (Rhombus arrangement)
    private func computeDiamondLayout(count: Int, center: CGPoint) -> [CGPoint] {
        var positions: [CGPoint] = []
        let spacing: CGFloat = 180

        // Diamond pattern: 1, 2, 3, 2, 1 (or similar based on count)
        var currentY = center.y
        var remaining = count
        var row = 0
        var widths: [Int] = []

        // Calculate row widths for diamond shape
        while remaining > 0 {
            let width = min(remaining, row + 1)
            widths.append(width)
            remaining -= width
            row += 1
        }

        // Mirror for bottom half (not used in current implementation)

        // Place blocks
        var blockIndex = 0
        currentY = center.y - CGFloat(widths.count - 1) * spacing / 2

        for (_, width) in widths.enumerated() {
            let startX = center.x - CGFloat(width - 1) * spacing / 2

            for col in 0..<width {
                guard blockIndex < count else { break }
                let x = startX + CGFloat(col) * spacing
                positions.append(CGPoint(x: x, y: currentY))
                blockIndex += 1
            }

            currentY += spacing
        }

        return positions
    }

    // MARK: - Tree Layout (Hierarchical)
    private func computeTreeLayout(count: Int, center: CGPoint) -> [CGPoint] {
        var positions: [CGPoint] = []
        let horizontalSpacing: CGFloat = 200
        let verticalSpacing: CGFloat = 150

        // Root at top, branching down
        let levels = Int(ceil(log2(Double(count + 1))))
        var nodeIndex = 0

        for level in 0..<levels {
            let nodesAtLevel = min(Int(pow(2.0, Double(level))), count - nodeIndex)
            let levelWidth = CGFloat(nodesAtLevel - 1) * horizontalSpacing
            let startX = center.x - levelWidth / 2
            let y = center.y - CGFloat(levels - 1) * verticalSpacing / 2 + CGFloat(level) * verticalSpacing

            for i in 0..<nodesAtLevel {
                guard nodeIndex < count else { break }
                let x = startX + CGFloat(i) * horizontalSpacing
                positions.append(CGPoint(x: x, y: y))
                nodeIndex += 1
            }
        }

        return positions
    }

    // MARK: - Flow Layout (River-like flowing path)
    private func computeFlowLayout(count: Int, center: CGPoint) -> [CGPoint] {
        var positions: [CGPoint] = []
        let baseSpacing: CGFloat = 200

        // Bezier-like flowing path
        var x = center.x - CGFloat(count) * baseSpacing / 3
        var y = center.y - 200
        var direction: CGFloat = 1

        for i in 0..<count {
            positions.append(CGPoint(x: x, y: y))

            // Flow forward with gentle curves
            x += baseSpacing * 0.7
            y += sin(CGFloat(i) * 0.6) * 60 + (direction * 30)

            // Occasionally change direction
            if i % 3 == 0 {
                direction *= -0.8
            }
        }

        return positions
    }
}

// MARK: - Layout Styles
enum LayoutStyle: String, CaseIterable, Sendable {
    case orbital    // Circle around center
    case grid       // Evenly spaced grid
    case linear     // Horizontal line
    case clustered  // Random cluster
    case llmDriven  // AI semantic placement

    // NEW: Magical spatial arrangements
    case snake      // Sinusoidal serpent pattern
    case spiral     // Outward spiral from center
    case wave       // Horizontal wave pattern
    case diamond    // Diamond/rhombus shape
    case tree       // Hierarchical tree layout
    case flow       // Flowing river pattern
}

// MARK: - Direction
enum Direction: String {
    case left, right, up, down
}
