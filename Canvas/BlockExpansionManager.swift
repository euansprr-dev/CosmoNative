// CosmoOS/Canvas/BlockExpansionManager.swift
// Manages inline expansion state across the canvas
// Ensures only one block is expanded at a time

import SwiftUI
import Combine

/// Manages the expansion state of floating blocks on the canvas.
/// Ensures only one block can be expanded at a time and handles
/// the visual dimming of non-expanded blocks.
@MainActor
class BlockExpansionManager: ObservableObject {

    // MARK: - Published State

    /// The ID of the currently expanded block, if any
    @Published var expandedBlockId: String?

    /// Whether the expansion transition is currently animating
    @Published var isTransitioning: Bool = false

    // MARK: - Computed Properties

    /// Returns true if any block is currently expanded
    var isAnyBlockExpanded: Bool {
        expandedBlockId != nil
    }

    /// The opacity that non-expanded blocks should have when a block is expanded
    var dimmedOpacity: Double {
        isAnyBlockExpanded ? 0.4 : 1.0
    }

    /// The scrim opacity for the canvas background
    var scrimOpacity: Double {
        isAnyBlockExpanded ? 0.15 : 0.0
    }

    // MARK: - Actions

    /// Expand a specific block by ID
    /// - Parameter blockId: The ID of the block to expand
    func expand(_ blockId: String) {
        guard expandedBlockId != blockId else { return }

        isTransitioning = true

        // If another block is expanded, collapse it first
        if expandedBlockId != nil {
            expandedBlockId = nil

            // Small delay before expanding the new block for smoother transition
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.expandedBlockId = blockId
                self?.finishTransition()
            }
        } else {
            expandedBlockId = blockId
            finishTransition()
        }

        // Post notification for other components
        NotificationCenter.default.post(
            name: .blockExpanded,
            object: nil,
            userInfo: ["blockId": blockId]
        )
    }

    /// Collapse the currently expanded block
    func collapse() {
        guard expandedBlockId != nil else { return }

        isTransitioning = true

        let collapsedId = expandedBlockId
        expandedBlockId = nil

        finishTransition()

        // Post notification
        if let id = collapsedId {
            NotificationCenter.default.post(
                name: .blockCollapsed,
                object: nil,
                userInfo: ["blockId": id]
            )
        }
    }

    /// Toggle expansion state for a block
    /// - Parameter blockId: The ID of the block to toggle
    func toggle(_ blockId: String) {
        if expandedBlockId == blockId {
            collapse()
        } else {
            expand(blockId)
        }
    }

    /// Check if a specific block is expanded
    /// - Parameter blockId: The ID of the block to check
    /// - Returns: True if the specified block is currently expanded
    func isExpanded(_ blockId: String) -> Bool {
        expandedBlockId == blockId
    }

    /// Check if a specific block should be dimmed
    /// - Parameter blockId: The ID of the block to check
    /// - Returns: True if the block should be dimmed (another block is expanded)
    func isDimmed(_ blockId: String) -> Bool {
        isAnyBlockExpanded && expandedBlockId != blockId
    }

    /// Get the opacity for a specific block
    /// - Parameter blockId: The ID of the block
    /// - Returns: The opacity value (1.0 for expanded or no expansion, dimmedOpacity otherwise)
    func opacity(for blockId: String) -> Double {
        if !isAnyBlockExpanded { return 1.0 }
        return expandedBlockId == blockId ? 1.0 : dimmedOpacity
    }

    /// Get the z-index for a specific block
    /// - Parameter blockId: The ID of the block
    /// - Returns: Higher z-index for expanded blocks
    func zIndex(for blockId: String) -> Double {
        expandedBlockId == blockId ? 1000 : 0
    }

    // MARK: - Private Methods

    private func finishTransition() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.isTransitioning = false
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    /// Posted when a block is expanded
    static let blockExpanded = Notification.Name("blockExpanded")

    /// Posted when a block is collapsed
    static let blockCollapsed = Notification.Name("blockCollapsed")
}

// MARK: - View Modifier for Block Dimming

/// A view modifier that applies expansion-aware dimming to blocks
struct BlockExpansionModifier: ViewModifier {
    let blockId: String
    @EnvironmentObject var expansionManager: BlockExpansionManager

    func body(content: Self.Content) -> some View {
        content
            .opacity(expansionManager.opacity(for: blockId))
            .zIndex(expansionManager.zIndex(for: blockId))
            .animation(BlockAnimations.expand, value: expansionManager.expandedBlockId)
    }
}

extension View {
    /// Apply expansion-aware styling to a block
    /// - Parameter blockId: The ID of the block
    /// - Returns: A view with expansion-aware opacity and z-index
    func expansionAware(blockId: String) -> some View {
        modifier(BlockExpansionModifier(blockId: blockId))
    }
}

// MARK: - Canvas Scrim View

/// A scrim overlay that appears when a block is expanded
struct ExpansionScrim: View {
    @EnvironmentObject var expansionManager: BlockExpansionManager

    var body: some View {
        Color.black
            .opacity(expansionManager.scrimOpacity)
            .animation(.easeInOut(duration: 0.3), value: expansionManager.isAnyBlockExpanded)
            .allowsHitTesting(expansionManager.isAnyBlockExpanded)
            .onTapGesture {
                withAnimation(BlockAnimations.collapse) {
                    expansionManager.collapse()
                }
            }
            .ignoresSafeArea()
    }
}

// MARK: - Keyboard Handler

/// Handles ESC key to collapse expanded blocks
struct ExpansionKeyboardHandler: ViewModifier {
    @EnvironmentObject var expansionManager: BlockExpansionManager

    func body(content: Self.Content) -> some View {
        content
            .onKeyPress(.escape) {
                if expansionManager.isAnyBlockExpanded {
                    withAnimation(BlockAnimations.collapse) {
                        expansionManager.collapse()
                    }
                    return .handled
                }
                return .ignored
            }
    }
}

extension View {
    /// Add keyboard handling for expansion (ESC to collapse)
    func expansionKeyboardHandler() -> some View {
        modifier(ExpansionKeyboardHandler())
    }
}
