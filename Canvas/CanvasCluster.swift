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

    // 8-color muted palette
    static let palette: [Color] = [
        Color(hex: "#6366F1").opacity(0.7),  // Indigo
        Color(hex: "#8B5CF6").opacity(0.7),  // Violet
        Color(hex: "#EC4899").opacity(0.7),  // Pink
        Color(hex: "#F59E0B").opacity(0.7),  // Amber
        Color(hex: "#10B981").opacity(0.7),  // Emerald
        Color(hex: "#06B6D4").opacity(0.7),  // Cyan
        Color(hex: "#3B82F6").opacity(0.7),  // Blue
        Color(hex: "#F97316").opacity(0.7),  // Orange
    ]

    var color: Color { Self.palette[colorIndex % Self.palette.count] }

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

        boundingRect = CGRect(
            x: minX - padding,
            y: minY - padding,
            width: (maxX - minX) + padding * 2,
            height: (maxY - minY) + padding * 2
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

    init(from cluster: CanvasCluster) {
        self.id = cluster.id.uuidString
        self.name = cluster.name
        self.blockUUIDs = cluster.blockUUIDs
        self.colorIndex = cluster.colorIndex
        self.synthesis = cluster.synthesis
        self.synthesisUpdatedAt = cluster.synthesisUpdatedAt
    }

    func toCanvasCluster(blocks: [CanvasBlock], thinkspaceId: String?) -> CanvasCluster {
        var cluster = CanvasCluster(
            id: UUID(uuidString: id) ?? UUID(),
            name: name,
            blockUUIDs: blockUUIDs,
            colorIndex: colorIndex,
            boundingRect: .zero,
            isCollapsed: false,
            isUserCreated: true,
            thinkspaceId: thinkspaceId,
            synthesis: synthesis,
            synthesisUpdatedAt: synthesisUpdatedAt
        )
        cluster.updateBoundingRect(blocks: blocks)
        return cluster
    }
}
