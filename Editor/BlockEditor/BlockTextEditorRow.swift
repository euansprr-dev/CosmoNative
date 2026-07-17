import AppKit
import SwiftUI

/// Reconciles a text-view content parse with the row's existing document
/// block before it is spliced back into the document.
///
/// INVARIANT: the DOCUMENT owns a row's KIND — a content sync carries inline
/// text only, never a kind change (kind changes ride structural ops:
/// transform, split, markdown alias, slash command). A parse whose kind
/// disagrees with the document is a stale re-emission racing one of those
/// ops, and trusting it in EITHER direction corrupts the row: an empty
/// heading's first character parses as a paragraph and used to silently
/// revert the heading; worse, a just-deleted bullet's stale "• " snapshot
/// parsed as a bullet "upgrade" and resurrected the list kind over the fresh
/// paragraph — after which the old never-downgrade rule re-imposed the wrong
/// kind on every subsequent keystroke, leaving the row permanently desynced
/// (document: bullet, view: plain) and silently breaking every later
/// transform on it (slash-menu headings appeared to do nothing).
enum BlockRowSyncPolicy {
    static func reconciled(parsed nextBlocks: [RichBlock], existingBlock: RichBlock?) -> [RichBlock] {
        var result = nextBlocks
        guard let existingBlock,
              let first = result.first,
              first.kind != .element,
              existingBlock.kind != .element else {
            return result
        }
        if first.kind == existingBlock.kind {
            result[0].id = existingBlock.id
            restoreRowOnlyFields(&result[0], from: existingBlock)
            return result
        }
        result[0].id = existingBlock.id
        result[0].kind = existingBlock.kind
        result[0].heading = existingBlock.heading
        result[0].checked = existingBlock.kind == .checklist
            ? (result[0].checked ?? existingBlock.checked ?? false)
            : nil
        restoreRowOnlyFields(&result[0], from: existingBlock)
        return result
    }

    /// Fields the row's text serializer can't see — callout chrome, toggle
    /// state, and toggle children live only on the document block, so every
    /// re-emission from the text view must carry them forward or a keystroke
    /// silently deletes them.
    static func restoreRowOnlyFields(_ block: inout RichBlock, from existingBlock: RichBlock) {
        block.callout = existingBlock.callout
        block.toggleCollapsed = existingBlock.toggleCollapsed
        block.rawKind = existingBlock.rawKind
        if !existingBlock.children.isEmpty, block.children.isEmpty {
            block.children = existingBlock.children
        }
    }
}

struct BlockTextEditorRow: View, Equatable {
    @Environment(\.undoManager) private var undoManager

    @Binding var document: RichDocument

    let path: BlockPath
    let blockID: UUID
    /// Snapshot of the block this row renders, taken by the parent list's
    /// ForEach. Used ONLY for the Equatable render gate below — live reads
    /// always go through the document binding. Because every content change
    /// re-runs the list body with a fresh snapshot, comparing it is a sound
    /// proxy for "does this row need to re-render".
    let block: RichBlock
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

    /// Render gate: a keystroke in ONE block writes the whole document, which
    /// re-runs the list body and used to re-render (and re-run updateNSView
    /// for) every row's AppKit text view — O(rows) per keystroke, the long-note
    /// lag. Rows whose visible inputs are unchanged are skipped entirely.
    ///
    /// Closures and the document binding are deliberately excluded: they read
    /// live state through stable references, so a skipped row's old closures
    /// stay correct. Focus/caret/selection state is NOT compared here — row
    /// bodies read those from @Observable coordinators, and Observation
    /// invalidates the affected rows directly, bypassing this gate.
    static func == (lhs: BlockTextEditorRow, rhs: BlockTextEditorRow) -> Bool {
        lhs.blockID == rhs.blockID
            && lhs.path == rhs.path
            && lhs.block == rhs.block
            && lhs.fontSize == rhs.fontSize
            && lhs.fontDesign == rhs.fontDesign
            && lhs.lineSpacingAdjustment == rhs.lineSpacingAdjustment
            && lhs.placeholder == rhs.placeholder
            && lhs.darkMode == rhs.darkMode
            && lhs.overrideTextColor == rhs.overrideTextColor
            && lhs.allowSlashCommands == rhs.allowSlashCommands
            && lhs.allowMentions == rhs.allowMentions
            && lhs.allowSelectionMenu == rhs.allowSelectionMenu
            && lhs.allowImages == rhs.allowImages
            && lhs.typewriterMode == rhs.typewriterMode
            && lhs.scrollsInternally == rhs.scrollsInternally
            && lhs.editorTargetID == rhs.editorTargetID
            && lhs.navigationTargetID == rhs.navigationTargetID
            && lhs.autoFocus == rhs.autoFocus
            && lhs.focusCoordinator === rhs.focusCoordinator
    }

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
        // Fast path: the parent list rebuilt this row with its current path,
        // so the hint is almost always still valid — an O(depth) index walk
        // instead of an O(blocks) full-tree search per binding read.
        if let hinted = try? BlockOperations.currentBlock(in: document, at: path),
           hinted.id == blockID {
            return path
        }
        return BlockOperations.path(of: blockID, in: document)
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
        BlockRowSyncPolicy.reconciled(parsed: nextBlocks, existingBlock: existingBlock)
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
        case .blockShortcut(let shortcut, let livePlainText):
            return applyBlockShortcut(shortcut, livePlainText: livePlainText)
        }
    }

    /// Keyboard block manipulation (⌘D, ⌥⌘↑/↓, ⌥⌘1–3, ⇧⌘L) — the handle
    /// menu's actions without leaving the keyboard. Reconciles live text
    /// first so an in-flight keystroke never duplicates or moves stale.
    private func applyBlockShortcut(_ shortcut: BlockKeyboardShortcut, livePlainText: String) -> Bool {
        guard let block = currentBlock, let currentPath else { return false }

        var workingDocument = document
        let liveContent = block.kind.strippedRenderPrefix(from: livePlainText)
        if liveContent != block.plainInlineText, block.kind.isTextEditableBlock {
            var workingBlock = block
            workingBlock.inlines = [.text(liveContent)]
            guard let reconciled = try? BlockOperations.replaceBlock(
                in: workingDocument,
                at: currentPath,
                with: workingBlock
            ) else { return false }
            workingDocument = reconciled.document
        }

        switch shortcut {
        case .duplicate:
            guard let result = try? BlockOperations.duplicateBlock(in: workingDocument, at: currentPath) else { return false }
            apply(result, undoActionName: "Duplicate Block")
            return true
        case .moveUp, .moveDown:
            guard let result = try? BlockOperations.moveBlockVertically(
                in: workingDocument,
                at: currentPath,
                up: shortcut == .moveUp
            ) else { return false }
            apply(result, undoActionName: "Move Block")
            return true
        case .heading(let level):
            let target: RichBlockKind = level == 1 ? .heading1 : level == 2 ? .heading2 : .heading3
            return toggleTransform(to: target, in: workingDocument, at: currentPath, current: block.kind)
        case .checklistToggle:
            return toggleTransform(to: .checklist, in: workingDocument, at: currentPath, current: block.kind)
        }
    }

    /// Transform to the target kind, or back to a paragraph when the block
    /// already is that kind (shortcut toggles, like Apple Notes).
    private func toggleTransform(
        to target: RichBlockKind,
        in workingDocument: RichDocument,
        at path: BlockPath,
        current: RichBlockKind
    ) -> Bool {
        let destination = current == target ? RichBlockKind.paragraph : target
        guard let result = try? BlockOperations.transformBlock(in: workingDocument, at: path, to: destination) else {
            return false
        }
        apply(result, undoActionName: "Turn Into")
        return true
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
            BlockRowSyncPolicy.restoreRowOnlyFields(&parsed[0], from: block)
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

    /// Backspace at block start. A styled block sheds its style first and
    /// becomes plain text (the Notion/Craft model — backspace never jumps a
    /// heading straight into the previous paragraph); a plain block deletes
    /// (when empty) or merges into the previous one. Reconciles the block
    /// with the text view's live string first (the document binding lags by
    /// ~50ms) so characters deleted right before the merge don't resurrect.
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

        // Styled → paragraph first, caret staying at the start. Toggles hoist
        // their children through the same transform. Content/Research blocks
        // keep their identity — they are documents, not text styles.
        if block.kind.isTextEditableBlock,
           ![.paragraph, .content, .research].contains(block.kind) {
            guard let transformed = try? BlockOperations.transformBlock(
                in: workingDocument,
                at: currentPath,
                to: .paragraph
            ) else { return false }
            apply(
                BlockOperationResult(
                    document: transformed.document,
                    focusPath: currentPath,
                    caretUTF16Offset: 0
                ),
                undoActionName: "Turn Into Text"
            )
            return true
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
        if block.kind == .code,
           let result = try? BlockOperations.exitCodeBlock(in: document, at: currentPath) {
            apply(result, undoActionName: "Exit Code Block")
            return true
        }
        if [.bulletList, .numberedList, .checklist, .callout, .toggle].contains(block.kind),
           let result = try? BlockOperations.exitEmptyListBlock(in: document, at: currentPath) {
            apply(result, undoActionName: "Exit Block")
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
        case .transform, .transformHeading, .replaceOrInsert, .insertElement:
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
