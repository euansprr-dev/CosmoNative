import AppKit
import SwiftUI

struct BlockTextEditorRow: View {
    @Environment(\.undoManager) private var undoManager

    @Binding var document: RichDocument

    let path: BlockPath
    let blockID: UUID
    let focusCoordinator: BlockFocusCoordinator
    var fontSize: CGFloat
    var placeholder: String
    var darkMode: Bool
    var overrideTextColor: NSColor?
    var allowSlashCommands: Bool
    var allowMentions: Bool
    var allowSelectionMenu: Bool
    var allowImages: Bool
    var typewriterMode: Bool
    var scrollsInternally: Bool
    var editorTargetID: String?
    var navigationTargetID: UUID?
    var autoFocus: Bool
    var onSelectionChanged: ((EditorSelectionSnapshot) -> Void)?
    var onDocumentChange: ((RichDocument, String) -> Void)?
    var onExitFinalEmptyTextRegion: (() -> Bool)?

    @State private var undoRegistrar = BlockUndoRegistrar()

    var body: some View {
        CosmoDocumentEditor(
            document: blockDocumentBinding,
            fontSize: fontSize,
            placeholder: placeholder,
            darkMode: darkMode,
            overrideTextColor: overrideTextColor,
            allowSlashCommands: allowSlashCommands,
            allowMentions: allowMentions,
            allowSelectionMenu: allowSelectionMenu,
            allowImages: allowImages,
            rendersElementChrome: false,
            typewriterMode: typewriterMode,
            scrollsInternally: scrollsInternally,
            onSelectionChanged: onSelectionChanged,
            editorTargetID: focusCoordinator.commandTargetID(for: blockID, baseTargetID: editorTargetID),
            navigationTargetID: navigationTargetID,
            onDocumentChange: handleBlockDocumentChange,
            onActivate: { focusCoordinator.focus(blockID) },
            onDeactivate: clearAbandonedSlashTrigger,
            onBoundaryCommand: handleBoundaryCommand,
            onSlashCommandSelected: executeSlashCommand,
            autoFocus: autoFocus || focusCoordinator.focusedBlockID == blockID
        )
        .onAppear {
            focusCoordinator.register(blockID)
            configureUndoRegistrar()
        }
        .onDisappear { focusCoordinator.unregister(blockID) }
    }

    private var currentBlock: RichBlock? {
        guard let currentPath else { return nil }
        return try? BlockOperations.currentBlock(in: document, at: currentPath)
    }

    private var currentPath: BlockPath? {
        BlockOperations.path(of: blockID, in: document)
    }

    private var blockDocumentBinding: Binding<RichDocument> {
        Binding(
            get: {
                RichDocument(blocks: currentBlock.map { [$0] } ?? [])
            },
            set: { nextDocument in
                applyReplacementBlocks(nextDocument.blocks)
            }
        )
    }

    private func handleBlockDocumentChange(_ updatedBlockDocument: RichDocument, _: String) {
        let mergedDocument = applyReplacementBlocks(updatedBlockDocument.blocks)
        onDocumentChange?(mergedDocument, mergedDocument.plainText)
    }

    @discardableResult
    private func applyReplacementBlocks(_ nextBlocks: [RichBlock]) -> RichDocument {
        guard !nextBlocks.isEmpty,
              let currentPath else { return document }
        let existingBlock = currentBlock
        let stableBlocks = preserveStableIDs(in: nextBlocks, existingBlock: existingBlock)
        guard let result = try? BlockOperations.replaceBlocks(in: document, at: currentPath, with: stableBlocks),
              result.document != document else {
            return document
        }

        document = result.document
        focusCoordinator.focus(stableBlocks.last?.id)
        return result.document
    }

    private func preserveStableIDs(in nextBlocks: [RichBlock], existingBlock: RichBlock?) -> [RichBlock] {
        var result = nextBlocks
        guard let existingBlock,
              let first = result.first,
              first.kind == existingBlock.kind,
              first.kind != .element else {
            return result
        }
        result[0].id = existingBlock.id
        return result
    }

    private func handleBoundaryCommand(_ command: EditorBoundaryCommand) -> Bool {
        focusCoordinator.focus(blockID)

        switch command {
        case .moveToPreviousBlock:
            return focusCoordinator.focusPrevious()
        case .moveToNextBlock:
            return focusCoordinator.focusNext()
        case .deleteBackwardAtStart:
            return deleteOrMergeBackward()
        case .insertNewlineOnEmptyFinalLine:
            return exitEmptyListOrFinalRegion()
        }
    }

    private func deleteOrMergeBackward() -> Bool {
        guard let block = currentBlock,
              let currentPath else { return false }
        let result: BlockOperationResult?
        if block.plainInlineText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result = try? BlockOperations.deleteEmptyBlockBackward(in: document, at: currentPath)
        } else {
            result = try? BlockOperations.mergeBackward(in: document, at: currentPath)
        }
        guard let result else { return false }
        apply(result, undoActionName: block.plainInlineText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Delete Block" : "Merge Blocks")
        return true
    }

    private func exitEmptyListOrFinalRegion() -> Bool {
        guard let block = currentBlock,
              let currentPath else { return false }
        if [.bulletList, .numberedList, .checklist].contains(block.kind),
           let result = try? BlockOperations.exitEmptyListBlock(in: document, at: currentPath) {
            apply(result, undoActionName: "Exit List")
            return true
        }
        return onExitFinalEmptyTextRegion?() ?? false
    }

    private func clearAbandonedSlashTrigger() {
        guard let currentPath,
              let result = try? BlockOperations.clearAbandonedSlashTrigger(in: document, at: currentPath),
              result.document != document else {
            return
        }

        apply(result)
    }

    private func executeSlashCommand(_ command: SlashCommand, livePlainText: String) -> Bool {
        guard currentBlock != nil,
              let currentPath,
              let action = BlockCommandCatalog.action(for: command) else {
            return false
        }

        switch action {
        case .transform, .replaceOrInsert, .insertElement:
            guard let result = try? BlockOperations.apply(
                action,
                in: document,
                at: currentPath,
                livePlainText: livePlainText
            ) else {
                return false
            }
            apply(result, undoActionName: action.undoActionName)
            return true
        case .createElement, .openElementsSubmenu, .openWritingAI:
            return false
        }
    }

    private func transformCurrentBlock(to kind: RichBlockKind, livePlainText: String) -> Bool {
        guard var block = currentBlock,
              let currentPath else { return false }
        block.inlines = slashCommandInlines(from: livePlainText, fallback: block.inlines)
        guard var result = try? BlockOperations.replaceBlock(in: document, at: currentPath, with: block),
              let transformed = try? BlockOperations.transformBlock(in: result.document, at: currentPath, to: kind) else {
            return false
        }
        result = transformed
        apply(result, undoActionName: "Transform Block")
        return true
    }

    private func replaceCurrentBlockWithStandalone(_ replacement: RichBlock) -> Bool {
        guard let currentPath,
              var result = try? BlockOperations.replaceBlock(in: document, at: currentPath, with: replacement) else {
            return false
        }
        if let inserted = try? BlockOperations.insertBlock(.paragraph(""), in: result.document, after: currentPath) {
            result = inserted
        }
        apply(result, undoActionName: "Insert Block")
        return true
    }

    private func apply(_ result: BlockOperationResult, undoActionName: String? = nil) {
        let before = document
        document = result.document
        if let undoActionName {
            undoRegistrar.register(
                undoManager: undoManager,
                before: before,
                after: result.document,
                actionName: undoActionName
            )
        }
        if let focusPath = result.focusPath,
           let focusedBlock = try? BlockOperations.currentBlock(in: result.document, at: focusPath) {
            focusCoordinator.focus(focusedBlock.id)
        }
        onDocumentChange?(result.document, result.document.plainText)
    }

    private func configureUndoRegistrar() {
        undoRegistrar.applyDocument = { nextDocument in
            document = nextDocument
            onDocumentChange?(nextDocument, nextDocument.plainText)
        }
    }

    private func slashCommandInlines(
        from livePlainText: String,
        fallback: [RichInlineNode]
    ) -> [RichInlineNode] {
        let withoutTrigger = livePlainText.removingSlashCommandTrigger()
        if withoutTrigger != livePlainText || fallback.plainText != livePlainText {
            return [.text(withoutTrigger)]
        }
        return fallback.removingSlashCommandTrigger()
    }
}

private extension Array where Element == RichInlineNode {
    var plainText: String {
        map(\.plainText).joined()
    }

    func removingSlashCommandTrigger() -> [RichInlineNode] {
        var result = self
        for index in result.indices.reversed() where result[index].kind == .text {
            guard var text = result[index].text,
                  let slashIndex = text.lastIndex(of: "/") else {
                continue
            }
            text.remove(at: slashIndex)
            result[index].text = text
            return result
        }
        return result
    }
}

private extension String {
    func removingSlashCommandTrigger() -> String {
        guard let slashIndex = lastIndex(of: "/") else { return self }
        var result = self
        result.remove(at: slashIndex)
        return result
    }
}
