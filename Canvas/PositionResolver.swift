// CosmoOS/Canvas/PositionResolver.swift
// Converts position strings from LLM to actual CGPoint coordinates
// Supports relative positioning (right of selected, next to block X, etc.)

import Foundation
import SwiftUI

@MainActor
class PositionResolver {
    static let shared = PositionResolver()

    // Default block size for spacing calculations
    private let defaultBlockSize = CGSize(width: 280, height: 200)
    private let spacing: CGFloat = 40

    private init() {}

    // MARK: - Resolve Position String to CGPoint
    /// Converts a position string from the LLM to actual canvas coordinates
    /// - Parameters:
    ///   - position: Position string (e.g., "center", "top_right", "right_of_selected")
    ///   - targetBlockQuery: Optional query to find a specific block for relative positioning
    ///   - canvasSize: The size of the canvas
    ///   - selectedBlock: The currently selected block (for "right_of_selected" etc.)
    ///   - allBlocks: All blocks on canvas (for finding by query)
    /// - Returns: The resolved CGPoint position
    func resolve(
        _ position: String?,
        targetBlockQuery: String? = nil,
        canvasSize: CGSize,
        selectedBlock: CanvasBlock? = nil,
        allBlocks: [CanvasBlock] = []
    ) -> CGPoint {
        guard let position = position else {
            return centerPosition(canvasSize: canvasSize)
        }

        switch position.lowercased() {
        // Absolute positions
        case "center", "middle", "in front of me":
            return centerPosition(canvasSize: canvasSize)

        case "top_right", "top right", "upper right", "upper_right":
            return CGPoint(
                x: canvasSize.width - defaultBlockSize.width / 2 - spacing * 2,
                y: defaultBlockSize.height / 2 + spacing * 2
            )

        case "top_left", "top left", "upper left", "upper_left":
            return CGPoint(
                x: defaultBlockSize.width / 2 + spacing * 2,
                y: defaultBlockSize.height / 2 + spacing * 2
            )

        case "bottom_right", "bottom right", "lower right", "lower_right":
            return CGPoint(
                x: canvasSize.width - defaultBlockSize.width / 2 - spacing * 2,
                y: canvasSize.height - defaultBlockSize.height / 2 - spacing * 2
            )

        case "bottom_left", "bottom left", "lower left", "lower_left":
            return CGPoint(
                x: defaultBlockSize.width / 2 + spacing * 2,
                y: canvasSize.height - defaultBlockSize.height / 2 - spacing * 2
            )

        case "top", "top center":
            return CGPoint(
                x: canvasSize.width / 2,
                y: defaultBlockSize.height / 2 + spacing * 2
            )

        case "bottom", "bottom center":
            return CGPoint(
                x: canvasSize.width / 2,
                y: canvasSize.height - defaultBlockSize.height / 2 - spacing * 2
            )

        case "left", "left center":
            return CGPoint(
                x: defaultBlockSize.width / 2 + spacing * 2,
                y: canvasSize.height / 2
            )

        case "right", "right center":
            return CGPoint(
                x: canvasSize.width - defaultBlockSize.width / 2 - spacing * 2,
                y: canvasSize.height / 2
            )

        // Relative to selected block
        case "right_of_selected", "right of selected", "next to this", "right of this":
            if let block = selectedBlock {
                return CGPoint(
                    x: block.position.x + block.size.width / 2 + defaultBlockSize.width / 2 + spacing,
                    y: block.position.y
                )
            }
            return centerPosition(canvasSize: canvasSize)

        case "left_of_selected", "left of selected", "left of this":
            if let block = selectedBlock {
                return CGPoint(
                    x: block.position.x - block.size.width / 2 - defaultBlockSize.width / 2 - spacing,
                    y: block.position.y
                )
            }
            return centerPosition(canvasSize: canvasSize)

        case "above_selected", "above selected", "above this", "on top of this":
            if let block = selectedBlock {
                return CGPoint(
                    x: block.position.x,
                    y: block.position.y - block.size.height / 2 - defaultBlockSize.height / 2 - spacing
                )
            }
            return centerPosition(canvasSize: canvasSize)

        case "below_selected", "below selected", "below this", "under this":
            if let block = selectedBlock {
                return CGPoint(
                    x: block.position.x,
                    y: block.position.y + block.size.height / 2 + defaultBlockSize.height / 2 + spacing
                )
            }
            return centerPosition(canvasSize: canvasSize)

        // Relative to named block (requires targetBlockQuery)
        case "right_of", "right of":
            if let query = targetBlockQuery,
               let target = findBlock(byQuery: query, in: allBlocks) {
                return CGPoint(
                    x: target.position.x + target.size.width / 2 + defaultBlockSize.width / 2 + spacing,
                    y: target.position.y
                )
            }
            return centerPosition(canvasSize: canvasSize)

        case "left_of", "left of":
            if let query = targetBlockQuery,
               let target = findBlock(byQuery: query, in: allBlocks) {
                return CGPoint(
                    x: target.position.x - target.size.width / 2 - defaultBlockSize.width / 2 - spacing,
                    y: target.position.y
                )
            }
            return centerPosition(canvasSize: canvasSize)

        case "above", "above block":
            if let query = targetBlockQuery,
               let target = findBlock(byQuery: query, in: allBlocks) {
                return CGPoint(
                    x: target.position.x,
                    y: target.position.y - target.size.height / 2 - defaultBlockSize.height / 2 - spacing
                )
            }
            return centerPosition(canvasSize: canvasSize)

        case "below", "below block":
            if let query = targetBlockQuery,
               let target = findBlock(byQuery: query, in: allBlocks) {
                return CGPoint(
                    x: target.position.x,
                    y: target.position.y + target.size.height / 2 + defaultBlockSize.height / 2 + spacing
                )
            }
            return centerPosition(canvasSize: canvasSize)

        default:
            return centerPosition(canvasSize: canvasSize)
        }
    }

    // MARK: - Helper Functions

    private func centerPosition(canvasSize: CGSize) -> CGPoint {
        CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
    }

    /// Find a block by title/content query (fuzzy matching)
    private func findBlock(byQuery query: String, in blocks: [CanvasBlock]) -> CanvasBlock? {
        let queryLower = query.lowercased()

        // Exact title match first
        if let exact = blocks.first(where: { $0.title.lowercased() == queryLower }) {
            return exact
        }

        // Contains match
        if let contains = blocks.first(where: { $0.title.lowercased().contains(queryLower) }) {
            return contains
        }

        // Fuzzy match - any word matches
        let queryWords = queryLower.split(separator: " ").map(String.init)
        return blocks.first { block in
            let titleWords = block.title.lowercased().split(separator: " ").map(String.init)
            return queryWords.contains { queryWord in
                titleWords.contains { titleWord in
                    titleWord.contains(queryWord) || queryWord.contains(titleWord)
                }
            }
        }
    }

    // MARK: - Compute Orbital Layout
    /// Compute positions for multiple blocks in an orbital (circular) pattern
    func computeOrbitalLayout(
        count: Int,
        center: CGPoint,
        radius: CGFloat = 250
    ) -> [CGPoint] {
        guard count > 0 else { return [] }

        if count == 1 {
            return [center]
        }

        var positions: [CGPoint] = []
        let angleStep = (2 * Double.pi) / Double(count)

        for i in 0..<count {
            let angle = angleStep * Double(i) - Double.pi / 2 // Start from top
            let x = center.x + radius * cos(angle)
            let y = center.y + radius * sin(angle)
            positions.append(CGPoint(x: x, y: y))
        }

        return positions
    }

    // MARK: - Compute Grid Layout
    /// Compute positions for multiple blocks in a grid pattern
    func computeGridLayout(
        count: Int,
        topLeft: CGPoint,
        columns: Int = 3,
        blockSize: CGSize? = nil,
        spacing: CGFloat = 40
    ) -> [CGPoint] {
        guard count > 0 else { return [] }

        let size = blockSize ?? defaultBlockSize
        var positions: [CGPoint] = []

        for i in 0..<count {
            let col = i % columns
            let row = i / columns

            let x = topLeft.x + CGFloat(col) * (size.width + spacing) + size.width / 2
            let y = topLeft.y + CGFloat(row) * (size.height + spacing) + size.height / 2

            positions.append(CGPoint(x: x, y: y))
        }

        return positions
    }

    // MARK: - Find Non-Overlapping Position
    /// Find a position that doesn't overlap with existing blocks
    func findNonOverlappingPosition(
        near preferredPosition: CGPoint,
        existingBlocks: [CanvasBlock],
        canvasSize: CGSize
    ) -> CGPoint {
        let blockSize = defaultBlockSize

        // Check if preferred position is free
        if !overlapsAnyBlock(position: preferredPosition, size: blockSize, blocks: existingBlocks) {
            return preferredPosition
        }

        // Try spiral outward from preferred position
        let spiralSteps = 20
        let spiralSpacing: CGFloat = 50

        for i in 1...spiralSteps {
            let angle = Double(i) * 0.5
            let distance = spiralSpacing * CGFloat(i) * 0.3

            let candidate = CGPoint(
                x: preferredPosition.x + distance * CGFloat(cos(angle)),
                y: preferredPosition.y + distance * CGFloat(sin(angle))
            )

            // Check bounds
            if candidate.x - blockSize.width / 2 > 0 &&
               candidate.x + blockSize.width / 2 < canvasSize.width &&
               candidate.y - blockSize.height / 2 > 0 &&
               candidate.y + blockSize.height / 2 < canvasSize.height &&
               !overlapsAnyBlock(position: candidate, size: blockSize, blocks: existingBlocks) {
                return candidate
            }
        }

        // Fallback: just offset from preferred position
        return CGPoint(
            x: preferredPosition.x + 50,
            y: preferredPosition.y + 50
        )
    }

    private func overlapsAnyBlock(position: CGPoint, size: CGSize, blocks: [CanvasBlock]) -> Bool {
        let rect = CGRect(
            x: position.x - size.width / 2,
            y: position.y - size.height / 2,
            width: size.width,
            height: size.height
        )

        return blocks.contains { block in
            let blockRect = CGRect(
                x: block.position.x - block.size.width / 2,
                y: block.position.y - block.size.height / 2,
                width: block.size.width,
                height: block.size.height
            )
            return rect.intersects(blockRect)
        }
    }
}
