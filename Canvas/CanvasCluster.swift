// CosmoOS/Canvas/CanvasCluster.swift
// Data model for canvas clusters — both auto-chunked and user-created

import SwiftUI

/// Edge/corner used during cluster resize
enum ClusterResizeEdge: Hashable, Sendable {
    case top, bottom, left, right
    case topLeft, topRight, bottomLeft, bottomRight
}

extension ClusterResizeEdge {
    var resizesWidth: Bool {
        switch self {
        case .left, .right, .topLeft, .topRight, .bottomLeft, .bottomRight:
            return true
        case .top, .bottom:
            return false
        }
    }

    var resizesHeight: Bool {
        switch self {
        case .top, .bottom, .topLeft, .topRight, .bottomLeft, .bottomRight:
            return true
        case .left, .right:
            return false
        }
    }
}

/// How blocks inside a cluster are displayed
enum ClusterViewMode: String, Codable, CaseIterable, Hashable, Sendable {
    case canvas   // Default — blocks float freely at canvas positions
    case list     // Compact scannable rows inside the cluster zone
    case board    // Kanban columns grouped by status/phase/type
    case grid     // 4-column scrollable grid of compact block cells
}

/// Sort order for list mode rows
enum ClusterSortOrder: String, Codable, CaseIterable, Hashable, Sendable {
    case dateUpdated
    case type
    case status
}

/// Grouping strategy for board mode columns.
enum ClusterBoardGrouping: String, Codable, CaseIterable, Hashable, Sendable {
    case auto
    case type
    case pipeline
}

struct CanvasCluster: Identifiable {
    let id: UUID
    var name: String
    var blockUUIDs: [String]
    var colorIndex: Int
    var boundingRect: CGRect
    var isCollapsed: Bool

    // User-created cluster fields
    var isUserCreated: Bool
    var thinkspaceId: String?
    var synthesis: String?
    var synthesisUpdatedAt: String?

    /// Manual size override — when set, cluster won't auto-shrink below this size.
    /// Auto-expand still grows beyond it when blocks require more space.
    var manualSizeOverride: CGSize?

    /// Zone clusters persist even when empty (no blocks). Created via zone tool.
    var isZone: Bool = false

    /// Command Center zone type identifier — "welcomeHub", "planningDock", "goalForge", "questBoard"
    var zoneType: String? = nil

    /// Natural language intent — describes what this cluster collects (e.g. "Josh's content for review")
    var intent: String? = nil

    /// How member blocks are displayed (canvas/list/board)
    var viewMode: ClusterViewMode = .canvas

    /// Sort order for list mode
    var sortOrder: ClusterSortOrder = .dateUpdated

    /// Grouping mode for board columns
    var boardGrouping: ClusterBoardGrouping = .auto

    // 8-color premium palette. Keep these as opaque base colors and apply
    // opacity at render sites so interaction states can feel precise.
    static let paletteHexes = [
        "7B7EC0",  // Dusty indigo
        "9585C0",  // Lavender gray
        "C07B9E",  // Dusty rose
        "C4A870",  // Antique gold
        "6BAF8E",  // Sage
        "62AFC4",  // Muted cyan
        "7199C4",  // Steel blue
        "C48B6A",  // Warm clay
    ]

    static let palette: [Color] = paletteHexes.map { Color(hex: $0) }

    var color: Color { Self.palette[colorIndex % Self.palette.count] }

    /// Extra top padding to keep the cluster title above the highest block
    static let titleTopPadding: CGFloat = 48

    /// Minimum cluster dimensions during manual resize
    static let minimumSize = CGSize(width: 200, height: 150)

    /// Recompute bounding rect from current block positions.
    /// Canvas mode is grow-only by default so clusters don't jitter while dragging blocks.
    /// Non-canvas modes are explicitly fitted by the cluster engine.
    mutating func updateBoundingRect(blocks: [CanvasBlock], padding: CGFloat = 40, growOnly: Bool = true) {
        let memberBlocks = blocks.filter { blockUUIDs.contains($0.entityUuid) }
        guard !memberBlocks.isEmpty else { return }

        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude

        for block in memberBlocks {
            let left = block.position.x - block.size.width / 2
            let right = block.position.x + block.size.width / 2
            let top = block.position.y - block.size.height / 2
            let bottom = block.position.y + block.size.height / 2

            minX = min(minX, left)
            minY = min(minY, top)
            maxX = max(maxX, right)
            maxY = max(maxY, bottom)
        }

        // Extra top padding for the title label
        let topPadding = padding + Self.titleTopPadding

        let blockOriginX = minX - padding
        let blockOriginY = minY - topPadding
        let blockWidth = (maxX - minX) + padding * 2
        let blockHeight = (maxY - minY) + padding + topPadding

        // Grow-only merge to avoid shrinking during live block movement.
        var finalMinX = blockOriginX
        var finalMinY = blockOriginY
        var finalMaxX = blockOriginX + blockWidth
        var finalMaxY = blockOriginY + blockHeight

        let current = boundingRect
        if growOnly && current.width > 0 && current.height > 0 {
            finalMinX = min(finalMinX, current.minX)
            finalMinY = min(finalMinY, current.minY)
            finalMaxX = max(finalMaxX, current.maxX)
            finalMaxY = max(finalMaxY, current.maxY)
        }

        // Also respect manual size override as a floor
        if let manual = manualSizeOverride {
            let w = finalMaxX - finalMinX
            let h = finalMaxY - finalMinY
            if w < manual.width {
                let extra = manual.width - w
                finalMinX -= extra / 2
                finalMaxX += extra / 2
            }
            if h < manual.height {
                let extra = manual.height - h
                finalMinY -= extra / 2
                finalMaxY += extra / 2
            }
        }

        boundingRect = CGRect(
            x: finalMinX,
            y: finalMinY,
            width: finalMaxX - finalMinX,
            height: finalMaxY - finalMinY
        )
    }

    /// Expand the cluster just enough to contain its current members, while preserving
    /// the existing rect when every member already fits inside it.
    mutating func expandBoundsToContainMembers(blocks: [CanvasBlock], padding: CGFloat = 40) {
        updateBoundingRect(blocks: blocks, padding: padding, growOnly: true)
    }

    /// Recompute bounding rect to tightly fit remaining members (allows shrinking).
    /// Respects `manualSizeOverride` as a floor so user-resized clusters don't shrink below their explicit size.
    mutating func shrinkToFitMembers(blocks: [CanvasBlock], padding: CGFloat = 40) {
        updateBoundingRect(blocks: blocks, padding: padding, growOnly: false)
    }

    /// Clear the manual size override, allowing the cluster to auto-fit blocks again
    mutating func clearManualSize() {
        manualSizeOverride = nil
    }
}

struct CanvasBlockGeometry: Equatable {
    var position: CGPoint
    var size: CGSize
}

enum CanvasClusterResizeMapper {
    static func previewGeometries(
        from startRect: CGRect,
        to currentRect: CGRect,
        edge: ClusterResizeEdge,
        members: [String: CanvasBlockGeometry]
    ) -> [String: CanvasBlockGeometry] {
        guard startRect.width > 0, startRect.height > 0 else { return members }

        let scaleX = edge.resizesWidth ? (currentRect.width / startRect.width) : 1
        let scaleY = edge.resizesHeight ? (currentRect.height / startRect.height) : 1
        let startAnchor = anchorPoint(for: startRect, edge: edge)
        let currentAnchor = anchorPoint(for: currentRect, edge: edge)

        return members.mapValues { geometry in
            var next = geometry

            if edge.resizesWidth {
                next.position.x = currentAnchor.x + ((geometry.position.x - startAnchor.x) * scaleX)
                next.size.width = geometry.size.width * scaleX
            }

            if edge.resizesHeight {
                next.position.y = currentAnchor.y + ((geometry.position.y - startAnchor.y) * scaleY)
                next.size.height = geometry.size.height * scaleY
            }

            return next
        }
    }

    private static func anchorPoint(for rect: CGRect, edge: ClusterResizeEdge) -> CGPoint {
        let x: CGFloat
        switch edge {
        case .left, .topLeft, .bottomLeft:
            x = rect.maxX
        case .right, .topRight, .bottomRight:
            x = rect.minX
        case .top, .bottom:
            x = rect.midX
        }

        let y: CGFloat
        switch edge {
        case .top, .topLeft, .topRight:
            y = rect.maxY
        case .bottom, .bottomLeft, .bottomRight:
            y = rect.minY
        case .left, .right:
            y = rect.midY
        }

        return CGPoint(x: x, y: y)
    }
}

// MARK: - Codable Persistence

/// Codable wrapper for persisting user-created clusters in ThinkspaceMetadata
struct CodableCluster: Codable, Sendable {
    let id: String
    var name: String
    var blockUUIDs: [String]
    var colorIndex: Int
    var synthesis: String?
    var synthesisUpdatedAt: String?

    // Persisted bounding rect — survives restarts even if block matching fails
    var originX: Double?
    var originY: Double?
    var rectWidth: Double?
    var rectHeight: Double?

    // Persisted manual size override
    var manualWidth: Double?
    var manualHeight: Double?

    // Zone clusters persist even when empty (nil decodes as false for backward compat)
    var isZone: Bool?

    // Command Center zone type (nil for non-zone clusters)
    var zoneType: String?

    // Cluster intent (NL automation description)
    var intent: String?

    // View mode persistence (nil → .canvas for backward compat)
    var viewMode: String?
    var sortOrder: String?
    var boardGrouping: String?

    /// Direct memberwise init for programmatic construction (e.g., Command Center zone creation)
    init(
        id: String,
        name: String,
        blockUUIDs: [String] = [],
        colorIndex: Int = 0,
        synthesis: String? = nil,
        synthesisUpdatedAt: String? = nil,
        originX: Double? = nil,
        originY: Double? = nil,
        rectWidth: Double? = nil,
        rectHeight: Double? = nil,
        manualWidth: Double? = nil,
        manualHeight: Double? = nil,
        isZone: Bool? = nil,
        zoneType: String? = nil,
        intent: String? = nil,
        viewMode: String? = nil,
        sortOrder: String? = nil,
        boardGrouping: String? = nil
    ) {
        self.id = id
        self.name = name
        self.blockUUIDs = blockUUIDs
        self.colorIndex = colorIndex
        self.synthesis = synthesis
        self.synthesisUpdatedAt = synthesisUpdatedAt
        self.originX = originX
        self.originY = originY
        self.rectWidth = rectWidth
        self.rectHeight = rectHeight
        self.manualWidth = manualWidth
        self.manualHeight = manualHeight
        self.isZone = isZone
        self.zoneType = zoneType
        self.intent = intent
        self.viewMode = viewMode
        self.sortOrder = sortOrder
        self.boardGrouping = boardGrouping
    }

    init(from cluster: CanvasCluster) {
        self.id = cluster.id.uuidString
        self.name = cluster.name
        self.blockUUIDs = cluster.blockUUIDs
        self.colorIndex = cluster.colorIndex
        self.synthesis = cluster.synthesis
        self.synthesisUpdatedAt = cluster.synthesisUpdatedAt
        // Persist bounding rect
        self.originX = cluster.boundingRect.origin.x
        self.originY = cluster.boundingRect.origin.y
        self.rectWidth = cluster.boundingRect.size.width
        self.rectHeight = cluster.boundingRect.size.height
        // Persist manual size override
        if let manual = cluster.manualSizeOverride {
            self.manualWidth = Double(manual.width)
            self.manualHeight = Double(manual.height)
        }
        self.isZone = cluster.isZone ? true : nil
        self.zoneType = cluster.zoneType
        self.intent = cluster.intent
        self.viewMode = cluster.viewMode.rawValue
        self.sortOrder = cluster.sortOrder.rawValue
        self.boardGrouping = cluster.boardGrouping.rawValue
    }

    func toCanvasCluster(blocks: [CanvasBlock], thinkspaceId: String?) -> CanvasCluster {
        // Restore persisted rect as fallback / authoritative container geometry for user clusters
        let persistedRect: CGRect
        if let ox = originX, let oy = originY, let w = rectWidth, let h = rectHeight, w > 0, h > 0 {
            persistedRect = CGRect(x: ox, y: oy, width: w, height: h)
        } else {
            persistedRect = .zero
        }

        // Restore manual size override
        let manualSize: CGSize?
        if let mw = manualWidth, let mh = manualHeight, mw > 0, mh > 0 {
            manualSize = CGSize(width: mw, height: mh)
        } else {
            manualSize = nil
        }

        var cluster = CanvasCluster(
            id: UUID(uuidString: id) ?? UUID(),
            name: name,
            blockUUIDs: blockUUIDs,
            colorIndex: colorIndex,
            boundingRect: persistedRect,
            isCollapsed: false,
            isUserCreated: true,
            thinkspaceId: thinkspaceId,
            synthesis: synthesis,
            synthesisUpdatedAt: synthesisUpdatedAt,
            manualSizeOverride: manualSize,
            isZone: isZone ?? false,
            zoneType: zoneType,
            intent: intent,
            viewMode: viewMode.flatMap { ClusterViewMode(rawValue: $0) } ?? .canvas,
            sortOrder: sortOrder.flatMap { ClusterSortOrder(rawValue: $0) } ?? .dateUpdated,
            boardGrouping: boardGrouping.flatMap { ClusterBoardGrouping(rawValue: $0) } ?? .auto
        )

        let memberBlocks = blocks.filter { blockUUIDs.contains($0.entityUuid) }
        if !memberBlocks.isEmpty {
            if cluster.viewMode == .canvas {
                // Canvas mode: size from block positions
                if persistedRect.width > 0, persistedRect.height > 0 {
                    cluster.expandBoundsToContainMembers(blocks: blocks)
                } else {
                    cluster.updateBoundingRect(blocks: blocks, growOnly: false)
                }
            }
            // Non-canvas modes (board/list/grid): keep persisted rect as-is.
            // Block canvas positions are irrelevant — these modes use internal layouts.
            // loadUserClusters() only refits adaptive modes; grid keeps its fixed scroll container.
        }
        return cluster
    }
}
