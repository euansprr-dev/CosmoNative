// CosmoOS/Canvas/CanvasCluster.swift
// Data model for canvas clusters — both auto-chunked and user-created

import SwiftUI

/// Edge/corner used during cluster resize
enum ClusterResizeEdge: Sendable {
    case top, bottom, left, right
    case topLeft, topRight, bottomLeft, bottomRight
}

/// How blocks inside a cluster are displayed
enum ClusterViewMode: String, Codable, CaseIterable, Sendable {
    case canvas   // Default — blocks float freely at canvas positions
    case list     // Compact scannable rows inside the cluster zone
    case board    // Kanban columns grouped by status/phase/type
}

/// Sort order for list mode rows
enum ClusterSortOrder: String, Codable, CaseIterable, Sendable {
    case dateUpdated
    case type
    case status
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

    /// How member blocks are displayed (canvas/list/board)
    var viewMode: ClusterViewMode = .canvas

    /// Sort order for list mode
    var sortOrder: ClusterSortOrder = .dateUpdated

    // 8-color muted palette — visible on light canvas backgrounds
    static let palette: [Color] = [
        Color(hex: "6366F1").opacity(0.6),  // Indigo
        Color(hex: "8B5CF6").opacity(0.6),  // Violet
        Color(hex: "EC4899").opacity(0.6),  // Pink
        Color(hex: "D97706").opacity(0.6),  // Amber
        Color(hex: "2D6A4F").opacity(0.6),  // Forest green
        Color(hex: "06B6D4").opacity(0.6),  // Cyan
        Color(hex: "3B82F6").opacity(0.6),  // Blue
        Color(hex: "C4783A").opacity(0.6),  // Warm orange
    ]

    var color: Color { Self.palette[colorIndex % Self.palette.count] }

    /// Extra top padding to keep the cluster title above the highest block
    static let titleTopPadding: CGFloat = 48

    /// Minimum cluster dimensions during manual resize
    static let minimumSize = CGSize(width: 200, height: 150)

    /// Recompute bounding rect from current block positions.
    /// Respects `manualSizeOverride` — auto-expand grows beyond it but never shrinks below it.
    mutating func updateBoundingRect(blocks: [CanvasBlock], padding: CGFloat = 40) {
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

        var computedWidth = (maxX - minX) + padding * 2
        var computedHeight = (maxY - minY) + padding + topPadding
        var originX = minX - padding
        var originY = minY - topPadding

        // Respect manual size override — expand to at least the manual dimensions,
        // centering the extra space so blocks remain visually inside.
        if let manual = manualSizeOverride {
            if computedWidth < manual.width {
                let extra = manual.width - computedWidth
                originX -= extra / 2
                computedWidth = manual.width
            }
            if computedHeight < manual.height {
                let extra = manual.height - computedHeight
                originY -= extra / 2
                computedHeight = manual.height
            }
        }

        boundingRect = CGRect(
            x: originX,
            y: originY,
            width: computedWidth,
            height: computedHeight
        )
    }

    /// Clear the manual size override, allowing the cluster to auto-fit blocks again
    mutating func clearManualSize() {
        manualSizeOverride = nil
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

    // View mode persistence (nil → .canvas for backward compat)
    var viewMode: String?
    var sortOrder: String?

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
        self.viewMode = cluster.viewMode != .canvas ? cluster.viewMode.rawValue : nil
        self.sortOrder = cluster.sortOrder != .dateUpdated ? cluster.sortOrder.rawValue : nil
    }

    func toCanvasCluster(blocks: [CanvasBlock], thinkspaceId: String?) -> CanvasCluster {
        // Restore persisted rect as fallback
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
            viewMode: viewMode.flatMap { ClusterViewMode(rawValue: $0) } ?? .canvas,
            sortOrder: sortOrder.flatMap { ClusterSortOrder(rawValue: $0) } ?? .dateUpdated
        )
        // Recompute from blocks if matching members are found; otherwise keep persisted rect
        let memberBlocks = blocks.filter { blockUUIDs.contains($0.entityUuid) }
        if !memberBlocks.isEmpty {
            cluster.updateBoundingRect(blocks: blocks)
        }
        return cluster
    }
}
