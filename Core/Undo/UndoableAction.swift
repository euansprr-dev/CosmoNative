// CosmoOS/Core/Undo/UndoableAction.swift
// Protocol for undoable canvas operations

import Foundation

/// Protocol for command-pattern undo actions.
/// Each concrete action captures the state needed to reverse and replay a mutation.
@MainActor
protocol UndoableAction: AnyObject {
    /// Human-readable description (e.g. "Move Block", "Delete Connection")
    var actionDescription: String { get }

    /// When this action was registered
    var timestamp: Date { get }

    /// Reverse the mutation
    func undo() async

    /// Replay the mutation
    func redo() async

    /// Whether this action can merge with a subsequent action of the same kind
    /// (e.g. rapid micro-moves during a drag). Default: false.
    func canCoalesce(with other: UndoableAction) -> Bool

    /// Merge `other` into this action (absorb its final state).
    /// Only called when `canCoalesce` returns true. Default: no-op.
    func coalesce(with other: UndoableAction)
}

// MARK: - Default Implementations

extension UndoableAction {
    func canCoalesce(with other: UndoableAction) -> Bool { false }
    func coalesce(with other: UndoableAction) {}
}
