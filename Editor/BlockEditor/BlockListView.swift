import AppKit
import SwiftUI

/// Vertical rhythm between block rows. Headings carry extra air above and
/// stay tight to the content they introduce (space above > space below is
/// the single biggest "premium typography" signal in a block editor), and
/// list items of the same kind huddle. This lives at the row level because
/// each block is its own text view — TextKit ignores paragraphSpacingBefore
/// for the first paragraph in a container, so the serializer's heading
/// spacing never survives the per-block split.
enum BlockRhythmPolicy {
    static func topSpacing(
        for kind: RichBlockKind,
        following previousKind: RichBlockKind?,
        baseGap: CGFloat
    ) -> CGFloat {
        guard let previousKind else { return 0 }
        let previousIsHeading = previousKind.headingLevelInt != nil
        switch kind {
        case .heading1: return baseGap + (previousIsHeading ? 8 : 20)
        case .heading2: return baseGap + (previousIsHeading ? 6 : 15)
        case .heading3: return baseGap + (previousIsHeading ? 4 : 10)
        case .divider: return baseGap + 6
        case .bulletList, .numberedList, .checklist:
            return previousKind == kind ? max(4, baseGap - 2) : baseGap
        default:
            return previousKind == .divider ? baseGap + 6 : baseGap
        }
    }
}

struct BlockListView: View {
    @Environment(\.undoManager) private var undoManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Binding var document: RichDocument

    var fontSize: CGFloat = 17
    var fontDesign: NSFontDescriptor.SystemDesign = .default
    /// Per-document line-spacing delta from the Aa menu.
    var lineSpacingAdjustment: CGFloat = 0
    /// Base gap between block rows — scales with the line-spacing preset.
    var blockGap: CGFloat = DS.space6
    /// Paragraph focus: blocks outside the caret's block fade back but stay
    /// legible (the iA/Ulysses dimming model).
    var dimsInactiveBlocks: Bool = false
    var placeholder: String = "Start writing..."
    var darkMode: Bool = false
    var overrideTextColor: NSColor? = nil
    var allowSlashCommands: Bool = true
    var allowMentions: Bool = true
    var allowSelectionMenu: Bool = true
    var allowImages: Bool = true
    var typewriterMode: Bool = false
    var scrollsInternally: Bool = false
    var editorTargetID: String? = nil
    var navigationTargetID: UUID? = nil
    var focusCoordinator: BlockFocusCoordinator? = nil
    var selectionCoordinator: BlockSelectionCoordinator? = nil
    var autoFocusFirstTextRegion: Bool = false
    var onSelectionChanged: ((EditorSelectionSnapshot) -> Void)? = nil
    var onContentHeightChange: ((CGFloat) -> Void)? = nil
    var onExitFinalEmptyTextRegion: (() -> Bool)? = nil
    var onDocumentChange: ((RichDocument, String) -> Void)? = nil

    @State private var ownedFocusCoordinator = BlockFocusCoordinator()
    @State private var ownedSelectionCoordinator = BlockSelectionCoordinator()
    @State private var undoRegistrar = BlockUndoRegistrar()
    @FocusState private var selectionKeyboardFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(document.blocks.enumerated()), id: \.element.id) { index, block in
                rowView(for: block, at: .root(index: index))
                    .padding(.top, BlockRhythmPolicy.topSpacing(
                        for: block.kind,
                        following: index > 0 ? document.blocks[index - 1].kind : nil,
                        baseGap: blockGap
                    ))
                    .opacity(rowOpacity(for: block))
            }
        }
        .animation(
            reduceMotion ? nil : ProMotionSprings.gentle,
            value: dimsInactiveBlocks ? resolvedFocusCoordinator.focusedBlockID : nil
        )
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .focusable(resolvedSelectionCoordinator.isActive)
        .focusEffectDisabled()
        .focused($selectionKeyboardFocused)
        .onKeyPress(phases: .down) { press in
            handleSelectionKeyPress(press)
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { newHeight in
            onContentHeightChange?(newHeight)
        }
        .onAppear {
            configureUndoRegistrar()
            scheduleEnsureEditableDocument()
        }
        .onChange(of: document.blocks.isEmpty) { _, isEmpty in
            if isEmpty {
                scheduleEnsureEditableDocument()
            }
        }
        .onChange(of: document.blocks.count) { _, _ in
            if resolvedSelectionCoordinator.isActive {
                resolvedSelectionCoordinator.prune(against: document)
            }
        }
    }

    @ViewBuilder
    private func rowView(for block: RichBlock, at path: BlockPath) -> some View {
        BlockRowView(
            block: block,
            path: path,
            darkMode: darkMode,
            isSelected: resolvedSelectionCoordinator.isSelected(block.id),
            onMove: moveBlock,
            onInsertBelow: { insertParagraph(after: path) },
            onHandleClick: { handleClicked(block) },
            onHandleShiftClick: { resolvedSelectionCoordinator.selectRange(to: block.id, in: document) },
            handleMenu: { handleMenu(for: block) }
        ) {
            blockContent(for: block, at: path)
                .overlay { selectionClickCatcher(for: block) }
        }
    }

    @ViewBuilder
    private func blockContent(for block: RichBlock, at path: BlockPath) -> some View {
        switch block.kind {
        case .divider:
            dividerRow
        case .image:
            imageRow(for: block)
        case .element:
            ElementBlockView(
                block: blockBinding(at: path, fallback: block),
                focusCoordinator: resolvedFocusCoordinator,
                fontSize: fontSize,
                darkMode: darkMode,
                overrideTextColor: overrideTextColor,
                allowSlashCommands: allowSlashCommands,
                allowMentions: allowMentions,
                allowSelectionMenu: allowSelectionMenu,
                allowImages: allowImages,
                typewriterMode: typewriterMode,
                editorTargetID: editorTargetID,
                navigationTargetID: navigationTargetID,
                onSelectionChanged: onSelectionChanged,
                onExitBody: { insertParagraph(after: path) },
                onElementChange: emitDocumentChange
            )
        case .content, .research:
            VStack(alignment: .leading, spacing: 6) {
                blockKindBadge(for: block.kind)
                textBlockRow(for: block, at: path)
            }
        default:
            textBlockRow(for: block, at: path)
        }
    }

    private func textBlockRow(for block: RichBlock, at path: BlockPath) -> some View {
        BlockTextEditorRow(
            document: $document,
            path: path,
            blockID: block.id,
            focusCoordinator: resolvedFocusCoordinator,
            fontSize: fontSize,
            fontDesign: fontDesign,
            lineSpacingAdjustment: lineSpacingAdjustment,
            placeholder: BlockPlaceholderPolicy.shouldShowBodyPlaceholder(
                for: block,
                at: path,
                in: document
            ) ? placeholder : "",
            darkMode: darkMode,
            overrideTextColor: overrideTextColor,
            allowSlashCommands: allowSlashCommands,
            allowMentions: allowMentions,
            allowSelectionMenu: allowSelectionMenu,
            allowImages: allowImages,
            typewriterMode: typewriterMode,
            scrollsInternally: scrollsInternally,
            editorTargetID: editorTargetID,
            navigationTargetID: navigationTargetID,
            autoFocus: autoFocusFirstTextRegion && path.indices == [0],
            onSelectionChanged: onSelectionChanged,
            onDocumentChange: onDocumentChange,
            onExitFinalEmptyTextRegion: onExitFinalEmptyTextRegion,
            onSelectionCommand: { command in
                handleEditorSelectionCommand(block.id, command)
            }
        )
    }

    private var dividerRow: some View {
        Rectangle()
            .fill((darkMode ? Color.white : DS.documentTextSecondary).opacity(0.28))
            .frame(height: 1)
            .padding(.vertical, 10)
    }

    private func imageRow(for block: RichBlock) -> some View {
        Group {
            if let image = block.inlines.compactMap(\.image).first,
               let nsImage = ImageStore.load(path: image.path) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: min(680, image.width))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                Text("[Image]")
                    .font(.system(size: fontSize, weight: .medium))
                    .foregroundStyle(darkMode ? Color.white.opacity(0.62) : DS.documentTextSecondary)
                    .padding(.vertical, 8)
            }
        }
    }

    private func blockKindBadge(for kind: RichBlockKind) -> some View {
        HStack(spacing: 5) {
            Image(systemName: kind == .content ? "doc.text" : "magnifyingglass.circle")
                .font(DS.caption.weight(.medium))
            Text(kind == .content ? "Content" : "Research")
                .font(DS.caption.weight(.medium))
        }
        .foregroundStyle(darkMode ? Color.white.opacity(0.58) : DS.documentTextMuted)
        .padding(.leading, 2)
    }

    /// Paragraph-focus dimming: 1.0 for the caret's block, faded-but-legible
    /// for the rest. Suspended while block selection is active so selected
    /// rows never fight their selection wash.
    private func rowOpacity(for block: RichBlock) -> Double {
        guard dimsInactiveBlocks,
              !resolvedSelectionCoordinator.isActive,
              let focusedID = resolvedFocusCoordinator.focusedBlockID,
              focusedID != block.id else {
            return 1
        }
        return 0.4
    }

    private var resolvedFocusCoordinator: BlockFocusCoordinator {
        focusCoordinator ?? ownedFocusCoordinator
    }

    private var resolvedSelectionCoordinator: BlockSelectionCoordinator {
        selectionCoordinator ?? ownedSelectionCoordinator
    }

    // MARK: - Block Selection

    /// While block selection is active, clicks land on blocks instead of text
    /// (the Notion model): Shift+Click extends the range, a plain click exits
    /// selection and resumes editing the clicked block. The overlay only
    /// exists during selection, so normal editing pays nothing for it.
    @ViewBuilder
    private func selectionClickCatcher(for block: RichBlock) -> some View {
        if resolvedSelectionCoordinator.isActive {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    if NSEvent.modifierFlags.contains(.shift) {
                        resolvedSelectionCoordinator.selectRange(to: block.id, in: document)
                    } else {
                        resolvedSelectionCoordinator.clear()
                        BlockSelectionClipboardTarget.deactivate()
                        selectionKeyboardFocused = false
                        resolvedFocusCoordinator.focus(block.id)
                    }
                }
        }
    }

    private func handleClicked(_ block: RichBlock) {
        let selection = resolvedSelectionCoordinator
        if !(selection.isActive && selection.isSelected(block.id)) {
            selection.select(block.id)
        }
        activateSelectionKeyboard()
    }

    private func handleEditorSelectionCommand(_ blockID: UUID, _ command: BlockSelectionEditorCommand) -> Bool {
        let selection = resolvedSelectionCoordinator
        switch command {
        case .selectCurrentBlock:
            selection.select(blockID)
            activateSelectionKeyboard()
            return true
        case .selectAllBlocks:
            selection.selectAll(in: document)
            activateSelectionKeyboard()
            return true
        case .clearSelection:
            if selection.isActive {
                selection.clear()
                BlockSelectionClipboardTarget.deactivate()
            }
            return true
        }
    }

    private func handleSelectionKeyPress(_ press: KeyPress) -> KeyPress.Result {
        let selection = resolvedSelectionCoordinator
        guard selection.isActive else { return .ignored }

        switch press.key {
        case .escape:
            clearSelectionAndResumeEditing()
            return .handled
        case .upArrow, .downArrow:
            let direction: BlockSelectionDirection = press.key == .upArrow ? .up : .down
            if press.modifiers.contains(.shift) {
                selection.extend(direction, in: document)
            } else {
                selection.step(direction, in: document)
            }
            return .handled
        case .delete, .deleteForward:
            deleteSelectedBlocks(selection.selectedBlockIDs)
            return .handled
        case .return:
            beginEditingSelection()
            return .handled
        default:
            break
        }

        if press.modifiers.contains(.command) {
            switch press.characters {
            case "d":
                duplicateSelectedBlocks(selection.selectedBlockIDs)
                return .handled
            case "c":
                copySelectionToPasteboard()
                return .handled
            case "x":
                copySelectionToPasteboard()
                deleteSelectedBlocks(selection.selectedBlockIDs)
                return .handled
            case "a":
                selection.selectAll(in: document)
                return .handled
            default:
                break
            }
        }
        return .ignored
    }

    /// Moves AppKit first responder off the text views so arrow keys, delete,
    /// and shortcuts land on the block list while blocks are selected.
    private func activateSelectionKeyboard() {
        DispatchQueue.main.async {
            let window = NSApp.keyWindow
            FocusModeTextClipboardTarget.collapseActiveSelection(in: window, deactivate: true)
            NotificationCenter.default.post(name: .cosmoDismissEditorOverlays, object: nil)
            window?.makeFirstResponder(nil)
            BlockSelectionClipboardTarget.activate(
                isActive: { resolvedSelectionCoordinator.isActive },
                perform: handleBlockSelectionClipboardAction
            )
            selectionKeyboardFocused = true
        }
    }

    private func clearSelectionAndResumeEditing() {
        let anchor = resolvedSelectionCoordinator.anchorBlockID
        resolvedSelectionCoordinator.clear()
        BlockSelectionClipboardTarget.deactivate()
        selectionKeyboardFocused = false
        if let anchor {
            resolvedFocusCoordinator.focus(anchor)
        }
    }

    private func beginEditingSelection() {
        let target = resolvedSelectionCoordinator.leadBlockID ?? resolvedSelectionCoordinator.anchorBlockID
        resolvedSelectionCoordinator.clear()
        BlockSelectionClipboardTarget.deactivate()
        selectionKeyboardFocused = false
        if let target {
            resolvedFocusCoordinator.focus(target)
        }
    }

    @discardableResult
    private func copySelectionToPasteboard() -> Bool {
        let text = BlockOperations.plainText(
            ofBlocksWithIDs: resolvedSelectionCoordinator.selectedBlockIDs,
            in: document
        )
        guard !text.isEmpty else { return false }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        return true
    }

    private func handleBlockSelectionClipboardAction(_ action: BlockSelectionClipboardAction) -> Bool {
        guard resolvedSelectionCoordinator.isActive else {
            BlockSelectionClipboardTarget.deactivate()
            return false
        }

        switch action {
        case .copy:
            return copySelectionToPasteboard()
        case .cut:
            let didCopy = copySelectionToPasteboard()
            deleteSelectedBlocks(resolvedSelectionCoordinator.selectedBlockIDs)
            return didCopy
        case .selectAll:
            resolvedSelectionCoordinator.selectAll(in: document)
            activateSelectionKeyboard()
            return true
        }
    }

    // MARK: - Handle Menu

    private func handleMenu(for block: RichBlock) -> BlockHandleMenuView {
        let targets = menuTargetIDs(for: block)
        return BlockHandleMenuView(
            currentKind: sharedKind(of: targets),
            selectionCount: targets.count,
            onTransform: { kind in transformBlocks(targets, to: kind) },
            onDuplicate: { duplicateSelectedBlocks(targets) },
            onDelete: { deleteSelectedBlocks(targets) }
        )
    }

    private func menuTargetIDs(for block: RichBlock) -> Set<UUID> {
        let selection = resolvedSelectionCoordinator
        if selection.isActive, selection.isSelected(block.id) {
            return selection.selectedBlockIDs
        }
        return [block.id]
    }

    private func sharedKind(of ids: Set<UUID>) -> RichBlockKind? {
        let kinds = Set(document.blocks.filter { ids.contains($0.id) }.map(\.kind))
        return kinds.count == 1 ? kinds.first : nil
    }

    private func transformBlocks(_ ids: Set<UUID>, to kind: RichBlockKind) {
        guard let result = BlockOperations.transformBlocks(withIDs: ids, in: document, to: kind) else { return }
        commit(result, undoActionName: "Turn Into", focusAfterCommit: false)
    }

    private func duplicateSelectedBlocks(_ ids: Set<UUID>) {
        guard let (result, duplicatedIDs) = BlockOperations.duplicateBlocks(withIDs: ids, in: document) else { return }
        commit(result, undoActionName: "Duplicate Blocks", focusAfterCommit: false)
        resolvedSelectionCoordinator.setSelection(duplicatedIDs)
        activateSelectionKeyboard()
    }

    private func deleteSelectedBlocks(_ ids: Set<UUID>) {
        guard let result = BlockOperations.deleteBlocks(withIDs: ids, in: document) else { return }
        resolvedSelectionCoordinator.clear()
        BlockSelectionClipboardTarget.deactivate()
        selectionKeyboardFocused = false
        commit(result, undoActionName: "Delete Blocks")
    }

    // MARK: - Document Mutations

    private func blockBinding(at path: BlockPath, fallback: RichBlock) -> Binding<RichBlock> {
        Binding(
            get: {
                (try? BlockOperations.currentBlock(in: document, at: path)) ?? fallback
            },
            set: { nextBlock in
                replaceBlock(at: path, with: nextBlock)
            }
        )
    }

    private func replaceBlock(at path: BlockPath, with nextBlock: RichBlock) {
        guard let result = try? BlockOperations.replaceBlock(in: document, at: path, with: nextBlock),
              result.document != document else {
            return
        }
        commit(result, undoActionName: "Edit Block")
    }

    private func emitDocumentChange() {
        onDocumentChange?(document, document.plainText)
    }

    private func insertParagraph(after path: BlockPath) {
        let paragraph = RichBlock.paragraph("")
        guard let result = try? BlockOperations.insertBlock(paragraph, in: document, after: path) else {
            return
        }
        commit(result, undoActionName: "Insert Text Block")
    }

    private func moveBlock(_ payload: BlockDragPayload, target: BlockDropTarget) {
        guard let result = try? BlockOperations.moveBlock(in: document, from: payload.sourcePath, to: target) else {
            return
        }
        commit(result, undoActionName: "Move Block")
    }

    private func commit(_ result: BlockOperationResult, undoActionName: String, focusAfterCommit: Bool = true) {
        let before = document
        document = result.document
        undoRegistrar.register(
            undoManager: undoManager,
            before: before,
            after: result.document,
            actionName: undoActionName
        )
        emitDocumentChange()
        if focusAfterCommit,
           let focusPath = result.focusPath,
           let focusedBlock = try? BlockOperations.currentBlock(in: result.document, at: focusPath) {
            resolvedFocusCoordinator.focus(focusedBlock.id, caretOffsetFromEnd: result.caretOffsetFromEnd(for: focusedBlock))
        }
    }

    private func configureUndoRegistrar() {
        undoRegistrar.applyDocument = { nextDocument in
            document = nextDocument
            emitDocumentChange()
        }
    }

    private func scheduleEnsureEditableDocument() {
        DispatchQueue.main.async {
            ensureEditableDocument()
        }
    }

    private func ensureEditableDocument() {
        guard document.blocks.isEmpty else { return }
        document.blocks = [.paragraph("")]
    }
}

enum BlockPlaceholderPolicy {
    static func shouldShowBodyPlaceholder(
        for block: RichBlock,
        at path: BlockPath,
        in document: RichDocument
    ) -> Bool {
        guard path.indices == [0],
              document.blocks.first?.id == block.id,
              block.kind.isTextEditableBlock,
              block.plainInlineText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        return true
    }
}
