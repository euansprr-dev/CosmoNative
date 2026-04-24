import Foundation

@MainActor
final class InlineUndoAction: UndoableAction {
    let actionDescription: String
    let timestamp: Date

    private let undoHandler: @MainActor () async -> Void
    private let redoHandler: @MainActor () async -> Void

    init(
        actionDescription: String,
        timestamp: Date = Date(),
        undo: @escaping @MainActor () async -> Void,
        redo: @escaping @MainActor () async -> Void
    ) {
        self.actionDescription = actionDescription
        self.timestamp = timestamp
        self.undoHandler = undo
        self.redoHandler = redo
    }

    func undo() async {
        await undoHandler()
    }

    func redo() async {
        await redoHandler()
    }
}
