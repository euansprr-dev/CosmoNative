import AppKit
import SwiftUI

struct BlockTextEditorRow: View {
    @Environment(\.undoManager) private var undoManager

    @Binding var document: RichDocument

    let path: BlockPath
    let blockID: UUID
    let focusCoordinator: BlockFocusCoordinator
    var fontSize: CGFloat
    var fontDesign: NSFontDescriptor.SystemDesign = .default
    var lineSpacingAdjustment: CGFloat = 0
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
    var onSelectionCommand: ((BlockSelectionEditorCommand) -> Bool)? = nil

    @State private var undoRegistrar = BlockUndoRegistrar()
    @State private var typingUndoBurst = BlockTypingUndoBurst()

    var body: some View {
        CosmoDocumentEditor(
            document: blockDocumentBinding,
            fontSize: fontSize,
            fontDesign: fontDesign,
            lineSpacingAdjustment: lineSpacingAdjustment,
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
            onActivate: {
                focusCoordinator.focus(blockID)
                _ = onSelectionCommand?(.clearSelection)
            },
            onDeactivate: clearAbandonedSlashTrigger,
            onBoundaryCommand: handleBoundaryCommand,
            onSlashCommandSelected: executeSlashCommand,
            splitsOnReturn: true,
            rowBlockID: blockID,
            immediateDocumentSync: true,
            caretRequest: editorCaretRequest,
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

    /// The coordinator's one-shot caret request, narrowed to this block.
    private var editorCaretRequest: EditorCaretRequest? {
        guard let request = focusCoordinator.caretRequest, request.blockID == blockID else { return nil }
        return EditorCaretRequest(utf16OffsetFromEnd: request.utf16OffsetFromEnd, token: request.token)
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
        let before = document
        let mergedDocument = applyReplacementBlocks(updatedBlockDocument.blocks)
        if mergedDocument != before {
            registerTypingCheckpointIfNeeded(before: before)
        }
        onDocumentChange?(mergedDocument, mergedDocument.plainText)
    }

    /// One undo checkpoint per typing burst — block rows run without
    /// NSTextView's own undo (see configureTextView), so ⌘Z restores the
    /// document from the burst's start instead of resurrecting stale ranges.
    private func registerTypingCheckpointIfNeeded(before: RichDocument) {
        if !typingUndoBurst.isActive {
            typingUndoBurst.isActive = true
            undoRegistrar.registerCheckpoint(
                undoManager: undoManager,
                before: before,
                currentDocument: { document }
            )
        }
        typingUndoBurst.scheduleEnd()
    }

    @discardableResult
    private func applyReplacementBlocks(_ nextBlocks: [RichBlock]) -> RichDocument {
        guard !nextBlocks.isEmpty,
              let currentPath else { return document }
        // INVARIANT: a row holds exactly one block. Multi-line content is
        // handled structurally (pasteBlocks / normalizeHardNewlines) BEFORE
        // it can round-trip through the serializer, so a multi-block parse
        // arriving here is a stale re-emission of already-spliced content —
        // splicing it again is precisely the duplication bug. Refuse; the
        // editor's display self-heal rebuilds the row from the document.
        guard nextBlocks.count == 1 else {
            ConsoleLog.error(
                "[BLOCKS] Row \(blockID.uuidString.prefix(8)) emitted \(nextBlocks.count) blocks — invariant violation, splice refused",
                subsystem: .canvas
            )
            return document
        }
        let existingBlock = currentBlock
        let stableBlocks = preserveStableIDs(in: nextBlocks, existingBlock: existingBlock)
        guard let result = try? BlockOperations.replaceBlocks(in: document, at: currentPath, with: stableBlocks),
              result.document != document else {
            return document
        }

        // A single-block content sync must NOT move focus: right after a
        // Return-split this row re-syncs its (unchanged) block and, by
        // re-focusing itself, would yank the caret back out of the freshly
        // created block below. Structural edits own focus placement.
        document = result.document
        return result.document
    }

    private func preserveStableIDs(in nextBlocks: [RichBlock], existingBlock: RichBlock?) -> [RichBlock] {
        var result = nextBlocks
        guard let existingBlock,
              let first = result.first,
              first.kind != .element,
              existingBlock.kind != .element else {
            return result
        }
        if first.kind == existingBlock.kind {
            result[0].id = existingBlock.id
            return result
        }
        // The row owns its block's KIND — a content sync may upgrade a plain
        // paragraph (typing "# "/"• " converts via the parser), but it must
        // never DOWNGRADE a styled block back to a paragraph: an empty
        // heading has no attributed run for typing to inherit, so the first
        // character parses as a paragraph and used to silently revert the
        // heading (and swap the block's identity out from under the row).
        if existingBlock.kind != .paragraph {
            result[0].id = existingBlock.id
            result[0].kind = existingBlock.kind
            result[0].heading = existingBlock.heading
            result[0].checked = existingBlock.kind == .checklist
                ? (result[0].checked ?? existingBlock.checked ?? false)
                : nil
        }
        return result
    }

    private func handleBoundaryCommand(_ command: EditorBoundaryCommand) -> Bool {
        focusCoordinator.focus(blockID)

        switch command {
        case .moveToPreviousBlock:
            return focusCoordinator.focusPrevious()
        case .moveToNextBlock:
            return focusCoordinator.focusNext()
        case .deleteBackwardAtStart(let livePlainText):
            return deleteOrMergeBackward(livePlainText: livePlainText)
        case .insertNewlineOnEmptyFinalLine:
            return exitEmptyListOrFinalRegion()
        case .splitBlock(let caretUTF16OffsetFromEnd, let livePlainText):
            return splitCurrentBlock(caretOffsetFromEnd: caretUTF16OffsetFromEnd, livePlainText: livePlainText)
        case .escapeSelectBlock:
            return onSelectionCommand?(.selectCurrentBlock) ?? false
        case .selectAllBlocks:
            return onSelectionCommand?(.selectAllBlocks) ?? false
        case .pasteBlocks(let pastedText, let caretUTF16OffsetFromEnd, let livePlainText):
            return pasteMultiBlockText(
                pastedText,
                caretOffsetFromEnd: caretUTF16OffsetFromEnd,
                livePlainText: livePlainText
            )
        case .normalizeHardNewlines(let caretUTF16OffsetFromEnd, let livePlainText):
            return splitRowOnHardNewlines(
                caretOffsetFromEnd: caretUTF16OffsetFromEnd,
                livePlainText: livePlainText
            )
        case .applyMarkdownAlias(let kind, let checked, let aliasUTF16Length, let livePlainText):
            return applyMarkdownAlias(
                kind: kind,
                checked: checked,
                aliasUTF16Length: aliasUTF16Length,
                livePlainText: livePlainText
            )
        case .pasteBlockRun(let blocks, let caretUTF16OffsetFromEnd, let livePlainText):
            return pasteBlockRun(
                blocks,
                caretOffsetFromEnd: caretUTF16OffsetFromEnd,
                livePlainText: livePlainText
            )
        }
    }

    /// Live markdown alias ("# ", "- ", "> ", "[] ", "1. ", "---") completed
    /// at the start of a plain paragraph — convert the block in place.
    private func applyMarkdownAlias(
        kind: RichBlockKind,
        checked: Bool?,
        aliasUTF16Length: Int,
        livePlainText: String
    ) -> Bool {
        guard let block = currentBlock,
              let currentPath,
              block.kind == .paragraph else { return false }
        let nsLive = livePlainText as NSString
        guard aliasUTF16Length <= nsLive.length else { return false }
        let remainder = nsLive.substring(from: aliasUTF16Length)

        if kind == .divider {
            do {
                let replaced = try BlockOperations.replaceBlock(
                    in: document,
                    at: currentPath,
                    with: RichBlock(kind: .divider)
                )
                let inserted = try BlockOperations.insertBlock(
                    RichBlock(kind: .paragraph, inlines: [.text(remainder)]),
                    in: replaced.document,
                    after: currentPath
                )
                let result = BlockOperationResult(
                    document: inserted.document,
                    focusPath: inserted.focusPath,
                    caretUTF16Offset: 0
                )
                apply(result, undoActionName: "Turn into Divider")
                return true
            } catch {
                return false
            }
        }

        var working = block
        working.inlines = [.text(remainder)]
        working.checked = checked
        do {
            let replaced = try BlockOperations.replaceBlock(in: document, at: currentPath, with: working)
            let transformed = try BlockOperations.transformBlock(in: replaced.document, at: currentPath, to: kind)
            let result = BlockOperationResult(
                document: transformed.document,
                focusPath: currentPath,
                caretUTF16Offset: 0
            )
            apply(result, undoActionName: "Turn Into")
            return true
        } catch {
            return false
        }
    }

    /// Structured block paste (com.cosmo.blocks) — same reconcile-then-splice
    /// contract as the text flavor, but kinds and rich inlines survive.
    private func pasteBlockRun(
        _ blocks: [RichBlock],
        caretOffsetFromEnd: Int,
        livePlainText: String
    ) -> Bool {
        guard let block = currentBlock, let currentPath else { return false }

        var workingDocument = document
        var workingBlock = block
        let liveContent = block.kind.strippedRenderPrefix(from: livePlainText)
        if liveContent != workingBlock.plainInlineText {
            workingBlock.inlines = [.text(liveContent)]
            guard let reconciled = try? BlockOperations.replaceBlock(
                in: workingDocument,
                at: currentPath,
                with: workingBlock
            ) else {
                return false
            }
            workingDocument = reconciled.document
        }

        let contentLength = workingBlock.plainInlineText.utf16.count
        let offset = max(0, min(contentLength, contentLength - caretOffsetFromEnd))
        guard let result = try? BlockOperations.pasteParsedBlocks(
            in: workingDocument,
            at: currentPath,
            utf16Offset: offset,
            parsed: blocks
        ) else {
            return false
        }
        apply(result, undoActionName: "Paste")
        return true
    }

    /// Multi-line paste — reconcile with the live string (the document
    /// binding lags ~50ms), then splice the pasted lines into real blocks as
    /// one operation with one undo step.
    private func pasteMultiBlockText(
        _ pastedText: String,
        caretOffsetFromEnd: Int,
        livePlainText: String
    ) -> Bool {
        guard let block = currentBlock, let currentPath else { return false }

        var workingDocument = document
        var workingBlock = block
        let liveContent = block.kind.strippedRenderPrefix(from: livePlainText)
        if liveContent != workingBlock.plainInlineText {
            workingBlock.inlines = [.text(liveContent)]
            guard let reconciled = try? BlockOperations.replaceBlock(
                in: workingDocument,
                at: currentPath,
                with: workingBlock
            ) else {
                return false
            }
            workingDocument = reconciled.document
        }

        let contentLength = workingBlock.plainInlineText.utf16.count
        let offset = max(0, min(contentLength, contentLength - caretOffsetFromEnd))
        guard let result = try? BlockOperations.pasteBlocks(
            in: workingDocument,
            at: currentPath,
            utf16Offset: offset,
            pastedText: pastedText
        ) else {
            return false
        }
        apply(result, undoActionName: "Paste")
        return true
    }

    /// Backstop: hard newlines reached this row's text view (dictation, IME,
    /// RTF paste). Re-parse the live content into blocks synchronously.
    private func splitRowOnHardNewlines(
        caretOffsetFromEnd: Int,
        livePlainText: String
    ) -> Bool {
        guard let block = currentBlock, let currentPath else { return false }
        let liveContent = block.kind.strippedRenderPrefix(from: livePlainText)
        var parsed = BlockOperations.parsedPasteBlocks(from: liveContent)
        if parsed.isEmpty {
            parsed = [RichBlock(kind: .paragraph, inlines: [.text("")])]
        }
        // The row keeps its identity; a plain first line keeps the row's kind.
        parsed[0].id = block.id
        if parsed[0].kind == .paragraph, block.kind != .paragraph, block.kind.isTextEditableBlock {
            parsed[0].kind = block.kind
            parsed[0].checked = block.checked
            parsed[0].heading = block.heading
        }
        guard let replaced = try? BlockOperations.replaceBlocks(
            in: document,
            at: currentPath,
            with: parsed
        ) else {
            return false
        }

        let lines = liveContent.normalizingHardNewlines().components(separatedBy: "\n")
        let caret = Self.caretLocation(lines: lines, parsed: parsed, offsetFromEnd: caretOffsetFromEnd)
        let focusIndex = currentPath.indexInParent + caret.blockOffset
        let focusPath = currentPath.parent?.appendingChild(index: focusIndex) ?? .root(index: focusIndex)
        let focusedLength = parsed[caret.blockOffset].plainInlineText.utf16.count
        let result = BlockOperationResult(
            document: replaced.document,
            focusPath: focusPath,
            caretUTF16Offset: max(0, focusedLength - caret.caretOffsetFromEnd)
        )
        apply(result, undoActionName: "Paste")
        return true
    }

    /// Maps an offset-from-end measured on the raw multi-line string onto the
    /// parsed blocks: walk lines from the end, one "\n" between each.
    static func caretLocation(
        lines: [String],
        parsed: [RichBlock],
        offsetFromEnd: Int
    ) -> (blockOffset: Int, caretOffsetFromEnd: Int) {
        var remaining = max(0, offsetFromEnd)
        var index = min(lines.count, parsed.count) - 1
        while index > 0 {
            let lineLength = (lines[index] as NSString).length
            if remaining <= lineLength { break }
            remaining -= lineLength + 1
            index -= 1
        }
        let blockLength = parsed[index].plainInlineText.utf16.count
        return (index, min(remaining, blockLength))
    }

    /// Return pressed mid-block — split at the caret. Reconciles the block
    /// with the text view's live string first (the document binding lags by
    /// ~50ms) so fast typing right before Return is never lost.
    private func splitCurrentBlock(caretOffsetFromEnd: Int, livePlainText: String) -> Bool {
        guard let block = currentBlock, let currentPath else { return false }

        var workingDocument = document
        var workingBlock = block
        let liveContent = block.kind.strippedRenderPrefix(from: livePlainText)
        if liveContent != workingBlock.plainInlineText {
            workingBlock.inlines = [.text(liveContent)]
            guard let reconciled = try? BlockOperations.replaceBlock(
                in: workingDocument,
                at: currentPath,
                with: workingBlock
            ) else {
                return false
            }
            workingDocument = reconciled.document
        }

        let contentLength = workingBlock.plainInlineText.utf16.count
        let offset = max(0, min(contentLength, contentLength - caretOffsetFromEnd))
        guard let result = try? BlockOperations.splitTextBlock(
            in: workingDocument,
            at: currentPath,
            utf16Offset: offset
        ) else {
            return false
        }
        apply(result, undoActionName: "Split Block")
        return true
    }

    /// Backspace at block start — delete the empty block or merge into the
    /// previous one. Reconciles the block with the text view's live string
    /// first (the document binding lags by ~50ms) so characters deleted right
    /// before the merge don't resurrect in the previous block.
    private func deleteOrMergeBackward(livePlainText: String) -> Bool {
        guard let block = currentBlock,
              let currentPath else { return false }

        var workingDocument = document
        let liveContent = block.kind.strippedRenderPrefix(from: livePlainText)
        if liveContent != block.plainInlineText {
            var workingBlock = block
            workingBlock.inlines = [.text(liveContent)]
            guard let reconciled = try? BlockOperations.replaceBlock(
                in: workingDocument,
                at: currentPath,
                with: workingBlock
            ) else {
                return false
            }
            workingDocument = reconciled.document
        }

        let isEmpty = liveContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let result: BlockOperationResult?
        if isEmpty {
            result = try? BlockOperations.deleteEmptyBlockBackward(in: workingDocument, at: currentPath)
        } else {
            result = try? BlockOperations.mergeBackward(in: workingDocument, at: currentPath)
        }
        guard let result else { return false }
        apply(result, undoActionName: isEmpty ? "Delete Block" : "Merge Blocks")
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

        // Deliberately NOT apply(): this runs on blur, and apply()'s caret
        // request would yank first responder back from whatever the user
        // just focused (title bar, another block, a menu).
        document = result.document
        onDocumentChange?(result.document, result.document.plainText)
    }

    /// Slash command from the coordinator — the "/" trigger and query have
    /// already been removed from the text view AND livePlainText.
    private func executeSlashCommand(_ command: SlashCommand, livePlainText: String) -> Bool {
        let path = currentPath
        let action = BlockCommandCatalog.action(for: command)
        guard let block = currentBlock,
              let currentPath,
              let action else {
            return false
        }
        // The text view renders list/quote prefixes ("• ", "1. ", "☐ ", "│ ")
        // at the head of its string — map back to block content before the
        // live text becomes the block's inlines.
        let liveContent = block.kind.strippedRenderPrefix(from: livePlainText)

        switch action {
        case .transform, .replaceOrInsert, .insertElement:
            do {
                let result = try BlockOperations.apply(
                    action,
                    in: document,
                    at: currentPath,
                    livePlainText: liveContent,
                    triggerAlreadyRemoved: true
                )
                apply(result, undoActionName: action.undoActionName)
                return true
            } catch {
                return false
            }
        case .createElement, .openElementsSubmenu, .openWritingAI:
            return false
        }
    }

    private func apply(_ result: BlockOperationResult, undoActionName: String? = nil) {
        // A structural edit ends any typing burst so undo ordering stays
        // checkpoint → structural-op, each its own step.
        typingUndoBurst.end()
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
            focusCoordinator.focus(focusedBlock.id, caretOffsetFromEnd: result.caretOffsetFromEnd(for: focusedBlock))
        }
        onDocumentChange?(result.document, result.document.plainText)
    }

    private func configureUndoRegistrar() {
        undoRegistrar.applyDocument = { nextDocument in
            document = nextDocument
            onDocumentChange?(nextDocument, nextDocument.plainText)
        }
    }
}
