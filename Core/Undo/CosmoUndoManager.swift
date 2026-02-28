// CosmoOS/Core/Undo/CosmoUndoManager.swift
// Central undo/redo manager for canvas operations

import Foundation
import Combine

@MainActor
final class CosmoUndoManager: ObservableObject {
    static let shared = CosmoUndoManager()

    // MARK: - Stacks

    private var undoStack: [UndoableAction] = []
    private var redoStack: [UndoableAction] = []

    /// Maximum number of actions to keep (memory-bounded)
    private let maxActions = 50

    /// Coalescing window — rapid actions within this interval merge into one
    private let coalesceInterval: TimeInterval = 0.3

    // MARK: - Published State (for UI observation)

    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    @Published private(set) var undoActionName: String?
    @Published private(set) var redoActionName: String?

    /// Suppresses registration while an undo/redo is in progress
    /// (prevents undo's own mutations from being re-recorded)
    private var isUndoingOrRedoing = false

    private init() {}

    // MARK: - Register

    /// Record an action that has already been performed.
    /// Clears the redo stack (new edit branch).
    func register(_ action: UndoableAction) {
        guard !isUndoingOrRedoing else { return }

        // Try to coalesce with the top of the undo stack
        if let top = undoStack.last,
           top.canCoalesce(with: action),
           action.timestamp.timeIntervalSince(top.timestamp) < coalesceInterval {
            top.coalesce(with: action)
            updatePublishedState()
            return
        }

        undoStack.append(action)

        // Trim oldest actions if over capacity
        if undoStack.count > maxActions {
            undoStack.removeFirst(undoStack.count - maxActions)
        }

        // New edit invalidates the redo branch
        redoStack.removeAll()

        updatePublishedState()
    }

    // MARK: - Undo / Redo

    func undo() async {
        guard let action = undoStack.popLast() else { return }

        isUndoingOrRedoing = true
        await action.undo()
        isUndoingOrRedoing = false

        redoStack.append(action)
        updatePublishedState()
    }

    func redo() async {
        guard let action = redoStack.popLast() else { return }

        isUndoingOrRedoing = true
        await action.redo()
        isUndoingOrRedoing = false

        undoStack.append(action)
        updatePublishedState()
    }

    // MARK: - Clear

    /// Wipe all history (called on thinkspace switch)
    func clearHistory() {
        undoStack.removeAll()
        redoStack.removeAll()
        updatePublishedState()
    }

    // MARK: - Private

    private func updatePublishedState() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
        undoActionName = undoStack.last?.actionDescription
        redoActionName = redoStack.last?.actionDescription
    }
}
