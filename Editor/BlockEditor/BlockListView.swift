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
        case .callout, .code: return baseGap + 4
        case .bulletList, .numberedList, .checklist:
            return previousKind == kind ? max(4, baseGap - 2) : baseGap
        default:
            if previousKind == .divider { return baseGap + 6 }
            // Air below a tinted card before plain text resumes.
            if previousKind == .callout || previousKind == .code { return baseGap + 4 }
            return baseGap
        }
    }
}

/// Flattens a block tree into the visual (pre-order) sequence of block IDs an
/// element header comes before its children, which come before the next
/// sibling. This is the order ⬆/⬇ navigation follows.
enum BlockNavigationOrder {
    static func flatten(_ blocks: [RichBlock]) -> [UUID] {
        var result: [UUID] = []
        append(blocks, into: &result)
        return result
    }

    private static func append(_ blocks: [RichBlock], into result: inout [UUID]) {
        for block in blocks {
            result.append(block.id)
            if !block.children.isEmpty {
                append(block.children, into: &result)
            }
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
    /// The top-level list owns the visual block order it feeds the focus
    /// coordinator (its document already contains every nested child). Element
    /// bodies embed their own BlockListView on the SAME coordinator and pass
    /// `false` so they don't overwrite that full-document order with a subset.
    var providesNavigationOrder: Bool = true
    var autoFocusFirstTextRegion: Bool = false
    var onSelectionChanged: ((EditorSelectionSnapshot) -> Void)? = nil
    var onContentHeightChange: ((CGFloat) -> Void)? = nil
    var onExitFinalEmptyTextRegion: (() -> Bool)? = nil
    var onDocumentChange: ((RichDocument, String) -> Void)? = nil

    @State private var ownedFocusCoordinator = BlockFocusCoordinator()
    @State private var ownedSelectionCoordinator = BlockSelectionCoordinator()
    @State private var undoRegistrar = BlockUndoRegistrar()
    /// Hoists row editors' slash menus above every row (each row is its own
    /// AppKit text view — a menu inside one row draws/hit-tests under the
    /// rows below it). Only the top-level list presents; element-embedded
    /// lists inherit it through the environment.
    @State private var ownedOverlayPresenter = EditorOverlayPresenter()
    /// Cross-block drag selection: rows' text views route their selection
    /// drags here; frames come from the layout index (registered per row).
    @State private var ownedDragController = BlockDragSelectionController()
    @State private var selectionKeyMonitor = BlockSelectionKeyMonitor()
    @State private var listSize: CGSize = .zero
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
        .coordinateSpace(name: providesNavigationOrder
            ? EditorOverlayPresenter.coordinateSpaceName
            : "\(EditorOverlayPresenter.coordinateSpaceName).nested")
        .transformEnvironment(\.blockEditorOverlayPresenter) { presenter in
            if providesNavigationOrder {
                presenter = ownedOverlayPresenter
            }
        }
        .transformEnvironment(\.blockDragSelectionController) { controller in
            if providesNavigationOrder {
                controller = ownedDragController
            }
        }
        .overlay(alignment: .topLeading) {
            hoistedSlashMenuOverlay
        }
        .focusable(resolvedSelectionCoordinator.isActive)
        .focusEffectDisabled()
        .focused($selectionKeyboardFocused)
        .onKeyPress(phases: .down) { press in
            handleSelectionKeyPress(press)
        }
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { newSize in
            listSize = newSize
            onContentHeightChange?(newSize.height)
        }
        .onAppear {
            configureUndoRegistrar()
            scheduleEnsureEditableDocument()
            syncNavigationOrderIfNeeded()
            configureDragSelection()
        }
        .onChange(of: document.blocks.isEmpty) { _, isEmpty in
            if isEmpty {
                scheduleEnsureEditableDocument()
            }
        }
        .onChange(of: navigationOrderSignature) { _, _ in
            syncNavigationOrderIfNeeded()
        }
        .onChange(of: document.blocks.count) { _, _ in
            if resolvedSelectionCoordinator.isActive {
                resolvedSelectionCoordinator.prune(against: document)
                if !resolvedSelectionCoordinator.isActive {
                    deactivateSelectionKeyboard()
                }
            }
        }
        .onDisappear {
            selectionKeyMonitor.remove()
        }
    }

    /// A flattened, pre-order list of every block ID (descending into element
    /// children) — the document's visual top-to-bottom order. Only the IDs
    /// change with structure, so `.onChange` fires on real structural edits,
    /// not on every keystroke.
    private var navigationOrderSignature: [UUID] {
        BlockNavigationOrder.flatten(document.blocks)
    }

    private func syncNavigationOrderIfNeeded() {
        guard providesNavigationOrder else { return }
        resolvedFocusCoordinator.syncNavigationOrder(navigationOrderSignature)
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
            imageRow(for: block, at: path)
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
        case .callout:
            CalloutBlockRowView(
                style: block.callout ?? .default,
                darkMode: darkMode,
                onStyleChange: { newStyle in
                    var updated = block
                    updated.callout = newStyle
                    replaceBlock(at: path, with: updated)
                }
            ) {
                textBlockRow(for: block, at: path)
            }
        case .code:
            CodeBlockRowView(
                codeText: { (try? BlockOperations.currentBlock(in: document, at: path))?.plainInlineText ?? block.plainInlineText },
                darkMode: darkMode
            ) {
                textBlockRow(for: block, at: path)
            }
        case .toggle:
            toggleRow(for: block, at: path)
        case .sketch:
            SketchBlockView(
                block: blockBinding(at: path, fallback: block),
                darkMode: darkMode,
                onSketchChange: emitDocumentChange
            )
        default:
            textBlockRow(for: block, at: path)
        }
    }

    private func toggleRow(for block: RichBlock, at path: BlockPath) -> some View {
        ToggleBlockRowView(
            isCollapsed: block.toggleCollapsed ?? false,
            hasChildren: !block.children.isEmpty,
            darkMode: darkMode,
            onToggleCollapse: {
                var updated = block
                updated.toggleCollapsed = !(block.toggleCollapsed ?? false)
                replaceBlock(at: path, with: updated)
            },
            onAddFirstChild: { addFirstToggleChild(at: path, block: block) },
            header: {
                textBlockRow(for: block, at: path)
            },
            children: {
                BlockListView(
                    document: toggleChildrenBinding(at: path, fallback: block),
                    fontSize: fontSize,
                    fontDesign: fontDesign,
                    lineSpacingAdjustment: lineSpacingAdjustment,
                    blockGap: blockGap,
                    placeholder: "",
                    darkMode: darkMode,
                    overrideTextColor: overrideTextColor,
                    allowSlashCommands: allowSlashCommands,
                    allowMentions: allowMentions,
                    allowSelectionMenu: allowSelectionMenu,
                    allowImages: allowImages,
                    typewriterMode: typewriterMode,
                    scrollsInternally: false,
                    editorTargetID: editorTargetID,
                    navigationTargetID: navigationTargetID,
                    focusCoordinator: resolvedFocusCoordinator,
                    providesNavigationOrder: false,
                    onSelectionChanged: onSelectionChanged,
                    onExitFinalEmptyTextRegion: { exitToggleBody(at: path) },
                    onDocumentChange: { _, _ in emitDocumentChange() }
                )
            }
        )
    }

    /// Binding into a toggle's children — the nested list edits them in
    /// place, exactly like an element body.
    private func toggleChildrenBinding(at path: BlockPath, fallback: RichBlock) -> Binding<RichDocument> {
        Binding(
            get: {
                let block = (try? BlockOperations.currentBlock(in: document, at: path)) ?? fallback
                return RichDocument(blocks: block.children)
            },
            set: { nextDocument in
                guard var block = try? BlockOperations.currentBlock(in: document, at: path) else { return }
                block.children = nextDocument.blocks
                guard let result = try? BlockOperations.replaceBlock(in: document, at: path, with: block),
                      result.document != document else { return }
                document = result.document
                emitDocumentChange()
            }
        )
    }

    private func addFirstToggleChild(at path: BlockPath, block: RichBlock) {
        var updated = (try? BlockOperations.currentBlock(in: document, at: path)) ?? block
        guard updated.children.isEmpty else { return }
        let paragraph = RichBlock.paragraph("")
        updated.children = [paragraph]
        updated.toggleCollapsed = false
        replaceBlock(at: path, with: updated)
        resolvedFocusCoordinator.focus(paragraph.id)
    }

    /// Return on the empty final child of a toggle exits the toggle — the
    /// empty child is given up and the caret lands in a fresh paragraph below.
    private func exitToggleBody(at path: BlockPath) -> Bool {
        guard var block = try? BlockOperations.currentBlock(in: document, at: path),
              block.kind == .toggle else { return false }
        if let last = block.children.last,
           last.kind == .paragraph,
           last.plainInlineText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            block.children.removeLast()
        }
        guard let replaced = try? BlockOperations.replaceBlock(in: document, at: path, with: block),
              let result = try? BlockOperations.insertBlock(.paragraph(""), in: replaced.document, after: path) else {
            return false
        }
        commit(result, undoActionName: "Exit Toggle")
        return true
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

    private func imageRow(for block: RichBlock, at path: BlockPath) -> some View {
        ResizableImageBlockView(
            image: block.inlines.compactMap(\.image).first ?? RichImageReference(path: "", width: 1, height: 1),
            darkMode: darkMode,
            onCommitWidth: { newWidth in
                setImageDisplayWidth(newWidth, at: path, block: block)
            }
        )
    }

    /// Persist a resized image's display width back into the block. One named undo step per
    /// gesture; never steals focus (image blocks have no text region to focus).
    private func setImageDisplayWidth(_ width: CGFloat?, at path: BlockPath, block: RichBlock) {
        guard let imageIndex = block.inlines.firstIndex(where: { $0.kind == .imageRef }),
              var image = block.inlines[imageIndex].image else { return }
        image.displayWidth = width
        var newBlock = block
        newBlock.inlines[imageIndex].image = image
        guard let result = try? BlockOperations.replaceBlock(in: document, at: path, with: newBlock),
              result.document != document else { return }
        commit(result, undoActionName: "Resize Image", focusAfterCommit: false)
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

    // MARK: - Hoisted Slash Menu

    /// The single slash menu for every row in this list, rendered above all
    /// row text views. Position is caret-anchored (published by the row) and
    /// clamped against the list's own bounds — a row is only ~1 line tall, so
    /// clamping there pins the menu to nonsense positions.
    @ViewBuilder
    private var hoistedSlashMenuOverlay: some View {
        if providesNavigationOrder {
            if let session = ownedOverlayPresenter.slashSession {
                SlashCommandMenu(
                    position: clampedOverlayPosition(for: session.anchorInList, menuSize: CGSize(width: 300, height: 380)),
                    query: session.query,
                    commands: session.commands,
                    selectedIndex: session.selectedIndex,
                    onHighlight: session.onHighlight,
                    onSelect: session.onSelect,
                    onDismiss: session.onDismiss,
                    darkMode: session.darkMode
                )
                .zIndex(1000)
                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .topLeading)))
            }
            if let session = ownedOverlayPresenter.elementCreationSession {
                ElementCreationMenu(
                    position: clampedOverlayPosition(for: session.anchorInList, menuSize: CGSize(width: 320, height: 352)),
                    onCreate: session.onCreate,
                    onDismiss: session.onDismiss,
                    darkMode: session.darkMode
                )
                .zIndex(1001)
                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .topLeading)))
            }
            if ownedOverlayPresenter.slashSession == nil,
               let session = ownedOverlayPresenter.selectionSession {
                SelectionFormattingMenu(
                    anchor: session.anchorInList,
                    container: listSize,
                    traits: session.traits,
                    compact: session.compact,
                    darkMode: session.darkMode,
                    onDismiss: session.onDismiss,
                    onAIAction: session.onAIAction,
                    onCustomPrompt: session.onCustomPrompt,
                    onWritingAIRequest: session.onWritingAIRequest
                )
                .zIndex(990)
                .transition(.opacity)
            }
        }
    }

    private func clampedOverlayPosition(for anchor: CGPoint, menuSize: CGSize) -> CGPoint {
        // Clamp horizontally only. NEVER flip above the caret based on the
        // list's own height: the list ends right after its last block, so a
        // caret near the end flipped the menu ~370pt above the cursor — the
        // user never saw it. Below the caret is always right in notes: the
        // scroll-past-end padding leaves room, and overlays don't clip.
        var origin = anchor
        origin.x = max(0, min(origin.x, listSize.width - menuSize.width - 8))
        return origin
    }

    // MARK: - Cross-Block Drag Selection

    private func configureDragSelection() {
        guard providesNavigationOrder else { return }
        ownedDragController.handleDrag = { windowPoint, phase, textView in
            handleBlockDrag(windowPoint: windowPoint, phase: phase, textView: textView)
        }
        ownedDragController.handleShiftClick = { windowPoint, textView in
            handleBlockShiftClick(windowPoint: windowPoint, textView: textView)
        }
    }

    /// The Notion drag model: inside the origin block the text view keeps
    /// native character selection (.textLocal); crossing into ANOTHER
    /// block's text view escalates to whole-block range selection; dragging
    /// back into the origin de-escalates. Blocks are resolved by AppKit
    /// hit-testing on the actual text views (each knows its rowBlockID) —
    /// never by converting between AppKit and SwiftUI coordinate spaces,
    /// which drifts by the titlebar height and misfires at row boundaries.
    private func handleBlockDrag(
        windowPoint: NSPoint,
        phase: BlockDragPhase,
        textView: NSTextView
    ) -> BlockDragResolution {
        let controller = ownedDragController

        switch phase {
        case .began:
            controller.originBlockID = ((textView as? CosmoTextView)?.rowBlockID).flatMap(rootBlockID(containing:))
            controller.isEscalated = false
            controller.dragCandidateViews = Self.collectBlockRowTextViews(in: textView.window?.contentView)
            return .textLocal
        case .changed:
            guard let origin = controller.originBlockID else { return .textLocal }
            // Hysteresis: anywhere inside (or within a few points of) the
            // origin view stays native text selection — you can slightly
            // overshoot a line without the selection jumping to whole-block.
            let pointInOrigin = textView.convert(windowPoint, from: nil)
            if textView.bounds.insetBy(dx: 0, dy: -6).contains(pointInOrigin) {
                if controller.isEscalated {
                    controller.isEscalated = false
                    resolvedSelectionCoordinator.clear()
                }
                return .textLocal
            }
            guard let hit = dragTargetBlockID(at: windowPoint),
                  let target = rootBlockID(containing: hit),
                  target != origin else {
                // Nothing resolvable — keep whatever mode we're in (sticky)
                // so the selection doesn't flicker.
                return controller.isEscalated ? .escalated : .textLocal
            }
            if !controller.isEscalated {
                controller.isEscalated = true
                resolvedSelectionCoordinator.select(origin)
            }
            resolvedSelectionCoordinator.selectRange(to: target, in: document)
            return .escalated
        case .ended:
            defer {
                controller.originBlockID = nil
                controller.dragCandidateViews = []
            }
            if controller.isEscalated {
                controller.isEscalated = false
                activateSelectionKeyboard()
                return .escalated
            }
            return .textLocal
        }
    }

    /// Resolves the drag target by VERTICAL-band geometry against the row
    /// text views snapshotted at drag start: the row whose y-band contains
    /// the pointer wins; otherwise the nearest row (dragging above the first
    /// or below the last block clamps, and horizontal position is ignored —
    /// the Notion model).
    private func dragTargetBlockID(at windowPoint: NSPoint) -> UUID? {
        var best: (id: UUID, distance: CGFloat)?
        for view in ownedDragController.dragCandidateViews {
            guard view.window != nil, let id = view.rowBlockID else { continue }
            let local = view.convert(windowPoint, from: nil)
            if local.y >= 0, local.y <= view.bounds.height {
                return id
            }
            let distance = local.y < 0 ? -local.y : local.y - view.bounds.height
            if best == nil || distance < best!.distance {
                best = (id, distance)
            }
        }
        return best?.id
    }

    /// Every mounted block-row text view in the window (the block list uses
    /// a plain VStack, so all rows are mounted). Snapshotted once per drag.
    private static func collectBlockRowTextViews(in root: NSView?) -> [CosmoTextView] {
        guard let root else { return [] }
        var result: [CosmoTextView] = []
        var stack: [NSView] = [root]
        while let view = stack.popLast() {
            if let textView = view as? CosmoTextView, textView.rowBlockID != nil {
                result.append(textView)
                continue
            }
            stack.append(contentsOf: view.subviews)
        }
        return result
    }

    /// Shift+Click inside a block while ANOTHER block holds focus (or a
    /// selection is active) — extend into a block-range selection.
    /// Shift+Click within the focused block returns false so native
    /// text-selection extension runs.
    private func handleBlockShiftClick(windowPoint: NSPoint, textView: NSTextView) -> Bool {
        guard let hit = (textView as? CosmoTextView)?.rowBlockID,
              let target = rootBlockID(containing: hit) else { return false }

        let selection = resolvedSelectionCoordinator
        if selection.isActive {
            selection.selectRange(to: target, in: document)
            activateSelectionKeyboard()
            return true
        }
        guard let origin = resolvedFocusCoordinator.focusedBlockID,
              origin != target,
              BlockSelectionCoordinator.rootOrder(in: document).contains(origin) else {
            return false
        }
        selection.select(origin)
        selection.selectRange(to: target, in: document)
        activateSelectionKeyboard()
        return true
    }

    /// Selection operates on ROOT blocks — a hit inside an element's nested
    /// row selects the whole element.
    private func rootBlockID(containing blockID: UUID) -> UUID? {
        guard let path = BlockOperations.path(of: blockID, in: document),
              let rootIndex = path.indices.first,
              document.blocks.indices.contains(rootIndex) else { return nil }
        return document.blocks[rootIndex].id
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
                        deactivateSelectionKeyboard()
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
                deactivateSelectionKeyboard()
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
    /// and shortcuts land on the block list while blocks are selected. Keys
    /// are handled by an AppKit-level monitor — the SwiftUI focus handoff
    /// races makeFirstResponder(nil) and drops keys (⌘A then ⌫ did nothing).
    private func activateSelectionKeyboard() {
        selectionKeyMonitor.install { event in
            handleSelectionKeyEvent(event)
        }
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

    private func deactivateSelectionKeyboard() {
        selectionKeyMonitor.remove()
        BlockSelectionClipboardTarget.deactivate()
        selectionKeyboardFocused = false
    }

    /// AppKit-level key routing while blocks are selected. Returns true when
    /// the event was consumed. ⌘C/⌘X stay on the clipboard-target path.
    private func handleSelectionKeyEvent(_ event: NSEvent) -> Bool {
        let selection = resolvedSelectionCoordinator
        guard selection.isActive else { return false }
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])

        switch event.keyCode {
        case 51, 117: // delete / forward delete
            guard flags.isEmpty else { return false }
            deleteSelectedBlocks(selection.selectedBlockIDs)
            return true
        case 126, 125: // up / down
            let direction: BlockSelectionDirection = event.keyCode == 126 ? .up : .down
            if flags == .shift {
                selection.extend(direction, in: document)
            } else if flags.isEmpty {
                selection.step(direction, in: document)
            } else {
                return false
            }
            return true
        case 36: // return
            guard flags.isEmpty else { return false }
            beginEditingSelection()
            return true
        case 53: // escape
            guard flags.isEmpty else { return false }
            clearSelectionAndResumeEditing()
            return true
        default:
            break
        }

        if flags == .command, let characters = event.charactersIgnoringModifiers?.lowercased() {
            switch characters {
            case "d":
                duplicateSelectedBlocks(selection.selectedBlockIDs)
                return true
            case "a":
                selection.selectAll(in: document)
                return true
            default:
                break
            }
        }
        return false
    }

    private func clearSelectionAndResumeEditing() {
        let anchor = resolvedSelectionCoordinator.anchorBlockID
        resolvedSelectionCoordinator.clear()
        deactivateSelectionKeyboard()
        if let anchor {
            resolvedFocusCoordinator.focus(anchor)
        }
    }

    private func beginEditingSelection() {
        let target = resolvedSelectionCoordinator.leadBlockID ?? resolvedSelectionCoordinator.anchorBlockID
        resolvedSelectionCoordinator.clear()
        deactivateSelectionKeyboard()
        if let target {
            resolvedFocusCoordinator.focus(target)
        }
    }

    /// Block copy writes two flavors: markdown as the plain-text
    /// representation (kinds survive into other apps AND round-trip through
    /// this app's paste parser), plus the structured com.cosmo.blocks JSON
    /// (exact kinds, checked state, rich inlines) preferred by block paste.
    @discardableResult
    private func copySelectionToPasteboard() -> Bool {
        let ids = resolvedSelectionCoordinator.selectedBlockIDs
        let markdown = BlockOperations.markdown(ofBlocksWithIDs: ids, in: document)
        guard !markdown.isEmpty else { return false }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
        let blocks = BlockOperations.blocks(withIDs: ids, in: document)
        if let data = try? JSONEncoder().encode(blocks) {
            NSPasteboard.general.setData(data, forType: .cosmoBlocks)
        }
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
        deactivateSelectionKeyboard()
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
