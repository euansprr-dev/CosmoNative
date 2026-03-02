// CosmoOS/Canvas/CanvasCluster.swift
// Data model for canvas clusters — both auto-chunked and user-created

import SwiftUI

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

    /// Recompute bounding rect from current block positions
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

        boundingRect = CGRect(
            x: minX - padding,
            y: minY - topPadding,
            width: (maxX - minX) + padding * 2,
            height: (maxY - minY) + padding + topPadding
        )
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
    }

    func toCanvasCluster(blocks: [CanvasBlock], thinkspaceId: String?) -> CanvasCluster {
        // Restore persisted rect as fallback
        let persistedRect: CGRect
        if let ox = originX, let oy = originY, let w = rectWidth, let h = rectHeight, w > 0, h > 0 {
            persistedRect = CGRect(x: ox, y: oy, width: w, height: h)
        } else {
            persistedRect = .zero
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
            synthesisUpdatedAt: synthesisUpdatedAt
        )
        // Recompute from blocks if matching members are found; otherwise keep persisted rect
        let memberBlocks = blocks.filter { blockUUIDs.contains($0.entityUuid) }
        if !memberBlocks.isEmpty {
            cluster.updateBoundingRect(blocks: blocks)
        }
        return cluster
    }
}
