// CosmoOS/Canvas/DocumentBlocksLayer.swift
// Document-scoped floating blocks layer for Focus Mode
// Uses SpatialEngine for block persistence, same block views as home canvas

import SwiftUI
import GRDB

/// Floating blocks layer for focus mode that uses the same block system as home canvas
/// Scoped by documentType/documentId for entity-specific blocks
/// Supports pinned (scrolls with content) vs unpinned (fixed on viewport) blocks
struct DocumentBlocksLayer: View {
    let documentType: String
    let documentId: Int64
    let canvasCenter: CGPoint
    /// Current canvas offset for calculating pinned vs unpinned block positions
    /// Pinned blocks move with the canvas, unpinned blocks stay fixed on screen
    var canvasOffset: CGSize = .zero

    @StateObject private var spatialEngine: SpatialEngine
    @StateObject private var expansionManager = BlockExpansionManager()
    @EnvironmentObject var database: CosmoDatabase

    // Drag state
    @State private var activeDragId: String?
    @State private var dragOffset: CGSize = .zero
    @State private var canvasSize: CGSize = .zero

    // Refresh trigger to force UI updates
    @State private var refreshId = UUID()

    init(documentType: String, documentId: Int64, canvasCenter: CGPoint, canvasOffset: CGSize = .zero) {
        self.documentType = documentType
        self.documentId = documentId
        self.canvasCenter = canvasCenter
        self.canvasOffset = canvasOffset
        _spatialEngine = StateObject(wrappedValue: SpatialEngine())
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Transparent hit target to ensure layer captures interactions
                Color.clear
                    .contentShape(Rectangle())
                    .allowsHitTesting(false) // Don't block clicks to editor behind

                ForEach(spatialEngine.blocks) { block in
                    blockView(for: block)
                }
            }
            .id(refreshId) // Force refresh when blocks are reloaded
            .frame(width: geometry.size.width, height: geometry.size.height)
            .onAppear {
                canvasSize = geometry.size
                Task {
                    await loadBlocks()
                }
            }
            // Listen for voice-driven placement commands (Focus Mode context)
            .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Canvas.placeBlocksOnCanvas)) { notification in
                handlePlaceBlocks(notification: notification)
            }
            // Listen for generic open focus mode (reload blocks if needed)
            .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Navigation.enterFocusMode)) { _ in
                Task { await loadBlocks() }
            }
            // Listen for block content updates (saves to database)
            .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Canvas.updateBlockContent)) { notification in
                handleUpdateBlockContent(notification: notification)
            }
            // Listen for block metadata updates (e.g., Note color)
            .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Canvas.updateBlockMetadata)) { notification in
                handleUpdateBlockMetadata(notification: notification)
            }
            // Listen for block size updates (e.g., Note resize)
            .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Canvas.updateBlockSize)) { notification in
                handleUpdateBlockSize(notification: notification)
            }
            // Listen for save block size (after resize ends)
            .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Canvas.saveBlockSize)) { notification in
                handleSaveBlockSize(notification: notification)
            }
            // Listen for block removal (from traffic light close button)
            .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Canvas.removeBlock)) { notification in
                handleRemoveBlock(notification: notification)
            }
            // Listen for database changes to reload blocks when added externally
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("com.cosmo.canvasBlocksChanged"))) { _ in
                Task { await loadBlocks() }
            }
            // Listen for toggle pin notifications
            .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Canvas.toggleBlockPin)) { notification in
                handleToggleBlockPin(notification: notification)
            }
        }
        .environmentObject(expansionManager)
    }

    // MARK: - Block Views
    
    @ViewBuilder
    private func blockView(for block: CanvasBlock) -> some View {
        Group {
            switch block.entityType {
            case .cosmoAI:
                CosmoAIBlockView(block: block)
            case .note:
                NoteBlockView(block: block)
            case .calendar:
                CalendarWindowView(block: block)
            case .research:
                ResearchBlockView(block: block)
            case .connection:
                ConnectionBlockView(block: block)
            case .idea:
                IdeaBlockView(block: block)
            case .content:
                ContentBlockView(block: block)
            case .task:
                TaskBlockView(block: block)
            default:
                // Fallback for unknown types
                DocumentBlockView(
                    block: block,
                    isSelected: block.isSelected,
                    onSelect: { selectBlock(block.id) },
                    onRemove: { removeBlock(block) },
                    onOpen: { openBlock(block) }
                )
            }
        }
        .position(blockPosition(block))
        .zIndex(Double(block.zIndex) + expansionManager.zIndex(for: block.id))
        .gesture(dragGesture(for: block))
        .onTapGesture(count: 1) {
            selectBlock(block.id)
        }
        .transition(.asymmetric(
            insertion: .scale(scale: 0.8).combined(with: .opacity),
            removal: .scale(scale: 0.9).combined(with: .opacity)
        ))
    }

    // MARK: - Selection

    private func selectBlock(_ blockId: String) {
        // CRITICAL: Batch update to avoid multiple @Published notifications
        // which can cause race conditions in Swift's type metadata system
        var updatedBlocks = spatialEngine.blocks
        for idx in updatedBlocks.indices {
            updatedBlocks[idx].isSelected = (updatedBlocks[idx].id == blockId)
        }
        spatialEngine.blocks = updatedBlocks
    }

    // MARK: - Update Block Position

    private func updateBlockPosition(_ blockId: String, to position: CGPoint) async {
        // Update in-memory position
        if let idx = spatialEngine.blocks.firstIndex(where: { $0.id == blockId }) {
            spatialEngine.blocks[idx].position = position
        }
    }

    // MARK: - Block Position

    /// Calculate block position based on pinned state:
    /// - Pinned: Position is relative to document content (moves with canvas scroll)
    /// - Unpinned: Position is fixed on viewport (subtracts canvas offset to stay in place)
    private func blockPosition(_ block: CanvasBlock) -> CGPoint {
        var position = block.position

        // Apply drag offset if this block is being dragged
        if activeDragId == block.id {
            position = CGPoint(
                x: position.x + dragOffset.width,
                y: position.y + dragOffset.height
            )
        }

        // If block is NOT pinned, subtract the canvas offset so it stays fixed on screen
        // (The parent view applies canvasOffset to all children, so we counter it here)
        if !block.isPinned {
            position = CGPoint(
                x: position.x - canvasOffset.width,
                y: position.y - canvasOffset.height
            )
        }
        // If pinned, keep the position as-is (it moves with the canvas offset from parent)

        return position
    }

    // MARK: - Drag Gesture

    private func dragGesture(for block: CanvasBlock) -> some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                if activeDragId == nil {
                    activeDragId = block.id
                }
                dragOffset = value.translation
            }
            .onEnded { value in
                let newPosition = CGPoint(
                    x: block.position.x + value.translation.width,
                    y: block.position.y + value.translation.height
                )

                Task {
                    await updateBlockPosition(block.id, to: newPosition)
                    await saveBlockPosition(block.id, position: newPosition)
                }

                activeDragId = nil
                dragOffset = .zero
            }
    }

    // MARK: - Load Blocks

    private func loadBlocks() async {
        await spatialEngine.loadBlocks(for: documentType, documentId: documentId)
        // Force UI refresh after loading
        await MainActor.run {
            refreshId = UUID()
        }
    }

    // MARK: - Voice Command Handlers

    private func handlePlaceBlocks(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let query = userInfo["query"] as? String,
              let entityTypeRaw = userInfo["entityType"] as? String,
              let entityType = EntityType(rawValue: entityTypeRaw),
              let quantity = userInfo["quantity"] as? Int else {
            return
        }

        let layout = LayoutStyle(rawValue: userInfo["layout"] as? String ?? "orbital") ?? .orbital
        
        // Only process if we are in a valid document context
        // NOTE: CanvasView handles home context. We handle Document context.
        // Ideally we should check if this view is actually active/visible? 
        // Since DocumentBlocksLayer is only mounted when FocusModeView is active, catching it here is correct.
        
        Task {
            try? await spatialEngine.placeBlocks(
                query: query,
                entityType: entityType,
                quantity: quantity,
                layout: layout,
                canvasSize: canvasSize,
                centerOverride: canvasCenter
            )
            
            // Persist the newly placed blocks
            for block in spatialEngine.blocks {
                await spatialEngine.saveBlock(block)
            }
        }
    }
    
    // MARK: - Add Block

    func addBlock(entityType: EntityType, title: String, at position: CGPoint? = nil) async {
        let blockPosition = position ?? CGPoint(
            x: canvasCenter.x + CGFloat.random(in: -100...100) + 350,
            y: canvasCenter.y + CGFloat.random(in: -100...100)
        )

        // Create entity in database first
        let entityId: Int64
        let entityUUID: String

        do {
            switch entityType {
            case .idea:
                let atom = try await AtomRepository.shared.createIdea(title: title, content: "")
                entityId = atom.id ?? -1
                entityUUID = atom.uuid
            case .task:
                let atom = try await AtomRepository.shared.createTask(title: title)
                entityId = atom.id ?? -1
                entityUUID = atom.uuid
            case .note:
                // For notes, we'll create a local block without a database entity
                entityId = -1
                entityUUID = UUID().uuidString
            default:
                entityId = -1
                entityUUID = UUID().uuidString
            }

            // Create block record
            // Default to unpinned (stays fixed on screen)
            let record = CanvasBlockRecord(
                id: UUID().uuidString,
                uuid: entityUUID,
                userId: nil,
                documentType: documentType,
                documentId: Int(documentId),
                documentUuid: nil,
                entityId: Int(entityId),
                entityUuid: entityUUID,
                entityType: entityType.rawValue,
                entityTitle: title,
                positionX: Int(blockPosition.x),
                positionY: Int(blockPosition.y),
                width: 280, // Standard size
                height: 180,
                isCollapsed: false,
                zone: nil,
                noteContent: nil,
                zIndex: spatialEngine.blocks.count + 10,
                isPinned: false,
                createdAt: ISO8601DateFormatter().string(from: Date()),
                updatedAt: ISO8601DateFormatter().string(from: Date()),
                syncedAt: nil,
                isDeleted: false,
                localVersion: 1,
                serverVersion: 0,
                syncVersion: 0,
                localPending: 0
            )

            try await database.asyncWrite { db in
                try record.insert(db)
            }

            // Reload blocks
            await loadBlocks()

        } catch {
            print("❌ Failed to add focus block: \(error)")
        }
    }

    // MARK: - Remove Block

    private func removeBlock(_ block: CanvasBlock) {
        Task {
            do {
                try await database.asyncWrite { db in
                    try db.execute(
                        sql: "UPDATE canvas_blocks SET is_deleted = 1 WHERE id = ?",
                        arguments: [block.id]
                    )
                }
                await loadBlocks()
            } catch {
                print("❌ Failed to remove block: \(error)")
            }
        }
    }

    /// Handle .removeBlock notification (from traffic light close button)
    private func handleRemoveBlock(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let blockId = userInfo["blockId"] as? String else {
            return
        }

        // Find the block and remove it
        if let block = spatialEngine.blocks.first(where: { $0.id == blockId }) {
            removeBlock(block)
        }
    }

    // MARK: - Open Block

    private func openBlock(_ block: CanvasBlock) {
        NotificationCenter.default.post(
            name: CosmoNotification.Navigation.enterFocusMode,
            object: nil,
            userInfo: ["type": block.entityType, "id": block.entityId]
        )
    }

    // MARK: - Save Block Position

    private func saveBlockPosition(_ blockId: String, position: CGPoint) async {
        do {
            try await database.asyncWrite { db in
                try db.execute(
                    sql: "UPDATE canvas_blocks SET position_x = ?, position_y = ?, updated_at = ? WHERE id = ?",
                    arguments: [Int(position.x), Int(position.y), ISO8601DateFormatter().string(from: Date()), blockId]
                )
            }
        } catch {
            print("❌ Failed to save block position: \(error)")
        }
    }

    // MARK: - Block Content Update Handler

    private func handleUpdateBlockContent(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let blockId = userInfo["blockId"] as? String,
              let content = userInfo["content"] as? String else {
            return
        }

        // Find the block
        guard let blockIndex = spatialEngine.blocks.firstIndex(where: { $0.id == blockId }) else {
            return
        }

        let block = spatialEngine.blocks[blockIndex]

        // If entityId is -1, save as note content in metadata
        if block.entityId == -1 && !content.isEmpty {
            Task {
                spatialEngine.blocks[blockIndex].metadata["content"] = content
                await spatialEngine.saveBlock(spatialEngine.blocks[blockIndex])
            }
        } else if block.entityId != -1 {
            // Update existing entity in database
            Task {
                await updateDatabaseEntry(block: block, content: content)
            }
        }
    }

    // MARK: - Block Metadata Update Handler

    private func handleUpdateBlockMetadata(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let blockId = userInfo["blockId"] as? String,
              let metadata = userInfo["metadata"] as? [String: String] else {
            return
        }

        // Find the block and update its metadata
        guard let blockIndex = spatialEngine.blocks.firstIndex(where: { $0.id == blockId }) else {
            return
        }

        // Merge new metadata with existing
        for (key, value) in metadata {
            spatialEngine.blocks[blockIndex].metadata[key] = value
        }

        // Persist to database
        Task {
            await spatialEngine.saveBlock(spatialEngine.blocks[blockIndex])
        }
    }

    // MARK: - Block Size Update Handler

    private func handleUpdateBlockSize(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let blockId = userInfo["blockId"] as? String,
              let size = userInfo["size"] as? CGSize else {
            return
        }

        // Find the block and update its size in memory
        guard let blockIndex = spatialEngine.blocks.firstIndex(where: { $0.id == blockId }) else {
            return
        }

        // Create updated block (struct copy) to ensure SwiftUI detects the change
        var updatedBlock = spatialEngine.blocks[blockIndex]
        updatedBlock.size = size

        // Also update position if provided (for anchored resizing)
        if let position = userInfo["position"] as? CGPoint {
            updatedBlock.position = position
        }

        // Replace the block to trigger @Published update
        spatialEngine.blocks[blockIndex] = updatedBlock
    }

    // MARK: - Save Block Size Handler

    private func handleSaveBlockSize(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let blockId = userInfo["blockId"] as? String else {
            return
        }

        // Find the block and persist to database
        guard let blockIndex = spatialEngine.blocks.firstIndex(where: { $0.id == blockId }) else {
            return
        }

        Task {
            await spatialEngine.saveBlock(spatialEngine.blocks[blockIndex])
        }
    }

    // MARK: - Toggle Block Pin Handler

    /// Handle toggle pin notification - updates block's isPinned state in memory and database
    private func handleToggleBlockPin(notification: Notification) {
        guard let payload = CosmoNotification.Canvas.ToggleBlockPinPayload(from: notification) else {
            return
        }

        // Find the block
        guard let blockIndex = spatialEngine.blocks.firstIndex(where: { $0.id == payload.blockId }) else {
            return
        }

        // Determine new pin state
        let newPinState: Bool
        if let explicitState = payload.isPinned {
            newPinState = explicitState
        } else {
            // Toggle current state
            newPinState = !spatialEngine.blocks[blockIndex].isPinned
        }

        // Update in memory
        spatialEngine.blocks[blockIndex].isPinned = newPinState

        // Persist to database
        Task {
            do {
                try await database.asyncWrite { db in
                    try db.execute(
                        sql: "UPDATE canvas_blocks SET is_pinned = ?, updated_at = ? WHERE id = ?",
                        arguments: [newPinState, ISO8601DateFormatter().string(from: Date()), payload.blockId]
                    )
                }
                print("📌 Block \(payload.blockId) pin state: \(newPinState ? "pinned" : "unpinned")")
            } catch {
                print("❌ Failed to save block pin state: \(error)")
            }
        }
    }

    // MARK: - Database Entry Update

    private func updateDatabaseEntry(block: CanvasBlock, content: String) async {
        do {
            switch block.entityType {
            case .idea:
                // Update idea using AtomRepository
                if let atom = try await AtomRepository.shared.fetch(id: block.entityId) {
                    _ = try await AtomRepository.shared.update(uuid: atom.uuid) { updatedAtom in
                        updatedAtom.body = content
                    }
                }

            case .note:
                // Notes are saved as metadata on the block
                if let index = spatialEngine.blocks.firstIndex(where: { $0.id == block.id }) {
                    spatialEngine.blocks[index].metadata["content"] = content
                    await spatialEngine.saveBlock(spatialEngine.blocks[index])
                }

            default:
                break
            }
        } catch {
            print("❌ Failed to update database entry: \(error)")
        }
    }
}

// MARK: - Document Block View (Fallback)

struct DocumentBlockView: View {
    let block: CanvasBlock
    let isSelected: Bool
    let onSelect: () -> Void
    let onRemove: () -> Void
    let onOpen: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: block.entityType.icon)
                    .font(.system(size: 12))
                    .foregroundColor(entityColor)

                Text(block.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Spacer()

                if isHovered {
                    HStack(spacing: 4) {
                        Button(action: onOpen) {
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)

                        Button(action: onRemove) {
                            Image(systemName: "xmark")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Content preview
            if let subtitle = block.subtitle {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(12)
        .frame(width: block.size.width, height: block.size.height, alignment: .topLeading)
        .background(
            ZStack {
                // Premium solid background (Apple-style: no blur)
                RoundedRectangle(cornerRadius: 12)
                    .fill(CosmoColors.softWhite)
                // Subtle gradient for depth
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.5), entityColor.opacity(0.03)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isSelected ? entityColor : Color.white.opacity(0.5),
                    lineWidth: isSelected ? 2 : 1
                )
        )
        // Optimized single shadow (Apple-style)
        .shadow(
            color: Color.black.opacity(isHovered ? 0.12 : 0.08),
            radius: isHovered ? 12 : 8,
            y: isHovered ? 4 : 2
        )
        // 3D tilt effect on hover
        .cosmoTiltSimple(isHovered, amount: 2.0)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .offset(y: isHovered ? -2 : 0)
        .animation(ProMotionSprings.hover, value: isHovered)
        .animation(.spring(response: 0.2), value: isSelected)
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            onSelect()
        }
    }

    private var entityColor: Color {
        switch block.entityType {
        case .idea: return CosmoColors.lavender
        case .task: return CosmoColors.coral
        case .content: return CosmoColors.skyBlue
        case .research: return CosmoColors.emerald
        case .note: return CosmoColors.note
        default: return CosmoColors.glassGrey
        }
    }
}
