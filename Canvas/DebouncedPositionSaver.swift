// CosmoOS/Canvas/DebouncedPositionSaver.swift
// Debounced persistence for canvas block positions and sizes
// Reduces database writes from ~60/sec to ~10/sec during drag operations

import Foundation
import SwiftUI
import GRDB

// MARK: - Debounced Position Saver
/// Batches and debounces position/size updates to minimize database writes
/// during drag operations while maintaining smooth 120fps visual updates.
///
/// ## Performance Impact
/// - Without debouncing: ~60 DB writes/second during drag
/// - With debouncing: ~10-20 DB writes/second (50ms debounce)
/// - Visual updates remain at 120fps via in-memory state
@MainActor
final class DebouncedPositionSaver: ObservableObject {
    static let shared = DebouncedPositionSaver()

    // MARK: - Configuration

    /// Debounce interval for position updates (50ms = 20 writes/sec max)
    private let positionDebounceInterval: TimeInterval = 0.050

    /// Debounce interval for size updates (100ms = 10 writes/sec max)
    private let sizeDebounceInterval: TimeInterval = 0.100

    /// Maximum time before forcing a flush (prevents data loss on crash)
    private let maxPendingTime: TimeInterval = 2.0

    // MARK: - State

    private var pendingPositions: [String: CGPoint] = [:]
    private var pendingSizes: [String: CGSize] = [:]
    private var pendingContent: [String: String] = [:]

    private var positionDebounceTask: Task<Void, Never>?
    private var sizeDebounceTask: Task<Void, Never>?
    private var contentDebounceTask: Task<Void, Never>?

    private var lastFlushTime = Date()

    // MARK: - Database Reference

    private var database: CosmoDatabase { CosmoDatabase.shared }

    private init() {}

    // MARK: - Position Updates

    /// Queue a position update for debounced persistence
    /// - Parameters:
    ///   - blockId: The block's unique identifier
    ///   - position: The new position
    func queuePositionUpdate(blockId: String, position: CGPoint) {
        pendingPositions[blockId] = position

        // Cancel existing debounce task
        positionDebounceTask?.cancel()

        // Check if we need to force flush (prevent data loss)
        let timeSinceLastFlush = Date().timeIntervalSince(lastFlushTime)
        if timeSinceLastFlush > maxPendingTime {
            Task { await flushPositions() }
            return
        }

        // Schedule debounced flush
        positionDebounceTask = Task {
            try? await Task.sleep(for: .milliseconds(Int(positionDebounceInterval * 1000)))
            guard !Task.isCancelled else { return }
            await flushPositions()
        }
    }

    /// Immediately flush all pending position updates
    func flushPositions() async {
        guard !pendingPositions.isEmpty else { return }

        let updates = pendingPositions
        pendingPositions.removeAll()
        lastFlushTime = Date()

        do {
            try await database.asyncWrite { db in
                for (blockId, position) in updates {
                    try db.execute(
                        sql: """
                            UPDATE canvas_blocks
                            SET position_x = ?, position_y = ?, updated_at = ?
                            WHERE id = ?
                            """,
                        arguments: [
                            Int(position.x),
                            Int(position.y),
                            Date().iso8601String,
                            blockId
                        ]
                    )
                }
            }
        } catch {
            print("DebouncedPositionSaver: Failed to flush positions: \(error)")
            // Re-queue failed updates for retry
            for (blockId, position) in updates {
                if pendingPositions[blockId] == nil {
                    pendingPositions[blockId] = position
                }
            }
        }
    }

    // MARK: - Size Updates

    /// Queue a size update for debounced persistence
    /// - Parameters:
    ///   - blockId: The block's unique identifier
    ///   - size: The new size
    func queueSizeUpdate(blockId: String, size: CGSize) {
        pendingSizes[blockId] = size

        sizeDebounceTask?.cancel()

        sizeDebounceTask = Task {
            try? await Task.sleep(for: .milliseconds(Int(sizeDebounceInterval * 1000)))
            guard !Task.isCancelled else { return }
            await flushSizes()
        }
    }

    /// Immediately flush all pending size updates
    func flushSizes() async {
        guard !pendingSizes.isEmpty else { return }

        let updates = pendingSizes
        pendingSizes.removeAll()

        do {
            try await database.asyncWrite { db in
                for (blockId, size) in updates {
                    try db.execute(
                        sql: """
                            UPDATE canvas_blocks
                            SET width = ?, height = ?, updated_at = ?
                            WHERE id = ?
                            """,
                        arguments: [
                            Int(size.width),
                            Int(size.height),
                            Date().iso8601String,
                            blockId
                        ]
                    )
                }
            }
        } catch {
            print("DebouncedPositionSaver: Failed to flush sizes: \(error)")
        }
    }

    // MARK: - Content Updates

    /// Queue a content update for debounced persistence
    /// - Parameters:
    ///   - blockId: The block's unique identifier
    ///   - content: The new content
    func queueContentUpdate(blockId: String, content: String) {
        pendingContent[blockId] = content

        contentDebounceTask?.cancel()

        contentDebounceTask = Task {
            try? await Task.sleep(for: .milliseconds(300))  // 300ms for content
            guard !Task.isCancelled else { return }
            await flushContent()
        }
    }

    /// Immediately flush all pending content updates
    func flushContent() async {
        guard !pendingContent.isEmpty else { return }

        let updates = pendingContent
        pendingContent.removeAll()

        do {
            try await database.asyncWrite { db in
                for (blockId, content) in updates {
                    try db.execute(
                        sql: """
                            UPDATE canvas_blocks
                            SET note_content = ?, updated_at = ?
                            WHERE id = ?
                            """,
                        arguments: [
                            content,
                            Date().iso8601String,
                            blockId
                        ]
                    )
                }
            }
        } catch {
            print("DebouncedPositionSaver: Failed to flush content: \(error)")
        }
    }

    // MARK: - Combined Flush

    /// Flush all pending updates immediately (call on app background/terminate)
    func flushAll() async {
        positionDebounceTask?.cancel()
        sizeDebounceTask?.cancel()
        contentDebounceTask?.cancel()

        await flushPositions()
        await flushSizes()
        await flushContent()
    }

    // MARK: - State Queries

    /// Check if there are pending updates
    var hasPendingUpdates: Bool {
        !pendingPositions.isEmpty || !pendingSizes.isEmpty || !pendingContent.isEmpty
    }

    /// Get the current pending position for a block (for immediate visual feedback)
    func pendingPosition(for blockId: String) -> CGPoint? {
        pendingPositions[blockId]
    }

    /// Get the current pending size for a block
    func pendingSize(for blockId: String) -> CGSize? {
        pendingSizes[blockId]
    }
}

// MARK: - Drag Gesture Wrapper

/// A wrapper view that provides debounced position updates during drag
struct DebouncedDragWrapper<Content: View>: View {
    let blockId: String
    @Binding var position: CGPoint
    let onDragEnd: ((CGPoint) -> Void)?
    let content: Content

    @State private var dragOffset: CGSize = .zero
    @State private var isDragging = false

    init(
        blockId: String,
        position: Binding<CGPoint>,
        onDragEnd: ((CGPoint) -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.blockId = blockId
        self._position = position
        self.onDragEnd = onDragEnd
        self.content = content()
    }

    var body: some View {
        content
            .offset(x: dragOffset.width, y: dragOffset.height)
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        isDragging = true
                        dragOffset = value.translation

                        // Calculate new position
                        let newPosition = CGPoint(
                            x: position.x + value.translation.width,
                            y: position.y + value.translation.height
                        )

                        // Queue debounced update
                        DebouncedPositionSaver.shared.queuePositionUpdate(
                            blockId: blockId,
                            position: newPosition
                        )
                    }
                    .onEnded { value in
                        isDragging = false

                        // Commit final position
                        let finalPosition = CGPoint(
                            x: position.x + value.translation.width,
                            y: position.y + value.translation.height
                        )

                        position = finalPosition
                        dragOffset = .zero

                        // Force immediate flush on drag end
                        Task {
                            await DebouncedPositionSaver.shared.flushPositions()
                        }

                        onDragEnd?(finalPosition)
                    }
            )
            .animation(isDragging ? nil : Animation.spring(response: 0.3, dampingFraction: 0.8), value: dragOffset)
    }
}

extension View {
    /// Apply debounced drag handling to a block
    /// - Parameters:
    ///   - blockId: The block's unique identifier
    ///   - position: Binding to the block's position
    ///   - onDragEnd: Optional callback when drag ends
    func debouncedDrag(
        blockId: String,
        position: Binding<CGPoint>,
        onDragEnd: ((CGPoint) -> Void)? = nil
    ) -> some View {
        DebouncedDragWrapper(
            blockId: blockId,
            position: position,
            onDragEnd: onDragEnd
        ) {
            self
        }
    }
}

// MARK: - App Lifecycle Integration

extension DebouncedPositionSaver {
    /// Setup app lifecycle observers to flush on background/terminate
    func setupLifecycleObservers() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.flushAll()
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.flushAll()
            }
        }
    }
}
