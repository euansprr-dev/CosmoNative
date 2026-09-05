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
        // Boxed structure gets a divider's air on both sides.
        case .table, .section: return baseGap + 6
        case .callout, .code: return baseGap + 4
        case .bulletList, .numberedList, .checklist:
            return previousKind == kind ? max(4, baseGap - 2) : baseGap
        default:
            if previousKind == .divider || previousKind == .table || previousKind == .section { return baseGap + 6 }
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
    /// Progressive open for long documents: only the first chunk of rows
    /// mounts live editors on first render; the rest draw as cheap static
    /// text and hydrate in chunks over the next few runloop ticks. SwiftUI
    /// subtree instantiation (AttributeGraph node building) dominates a long
    /// note's open — ~200 live rows cost around a second of blocked main
    /// thread, while a static row is near-free. Within ~a second every row
    /// is live and the all-rows-mounted invariants hold exactly as before.
    /// Off by default: short lists (canvas blocks, toggle children, element
    /// bodies) must keep single-pass mounting.
    var progressiveHydration: Bool = false
    var autoFocusFirstTextRegion: Bool = false
    /// Writing hosts share one blank-tail interaction; embedded block bodies
    /// keep their compact size by leaving these at zero.
    var minimumWritingHeight: CGFloat = 0
    var minimumTailHeight: CGFloat = 0
    /// Jump-to-sentence landing: the block that holds a search match wears a
    /// soft accent wash while set (the host scrolls to it and clears this
    /// after the pulse). Rows also carry `.id(block.id)` scroll anchors so a
    /// host ScrollViewReader can bring any block into view.
    var landingHighlightBlockID: UUID? = nil
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
    /// Cross-container drops: nested lists forward payloads they can't
    /// resolve in their own sub-document to the root's whole-document mover.
    @State private var ownedDropRouter = BlockDropRouter()
    @Environment(\.blockDropRouter) private var inheritedDropRouter
    @State private var selectionKeyMonitor = BlockSelectionKeyMonitor()
    /// The list's frame in the hosting view's space, updated off the render
    /// path (see onGeometryChange) — read only by the outside-click monitor.
    @State private var listGeometry = BlockListGeometryBox()
    /// Rows below this index render as static placeholders until the
    /// hydration pump raises it (progressiveHydration only). `.max` = fully
    /// hydrated; the non-progressive path never consults it.
    @State private var hydratedRowLimit = BlockHydrationPolicy.initialChunk
    /// Set on disappear so the hydration pump's runloop recursion stops
    /// re-scheduling against a closed document; re-armed on appear.
    @State private var hydrationCancelled = false
    @Environment(\.cosmoFloatingPanelIsVisible) private var floatingPanelIsVisible

    var body: some View {
        let fingerprint = rowEnvironmentFingerprint
        let listOrdinals = Self.numberedListOrdinals(for: document.blocks)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(document.blocks.enumerated()), id: \.element.id) { index, block in
                rowView(index: index, block: block, fingerprint: fingerprint, listOrdinals: listOrdinals)
            }
            if minimumTailHeight > 0 {
                Button(action: continueWritingAtEnd) {
                    Color.clear
                        .frame(maxWidth: .infinity, minHeight: minimumTailHeight, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Continue writing")
                .help("Continue writing at the end of the page")
            }
        }
        .frame(minHeight: minimumWritingHeight, alignment: .topLeading)
        .onAppear { startHydrationPumpIfNeeded() }
        // Paragraph-focus dim animation lives on each row (scoped to its own
        // rowOpacity) — animating on focusedBlockID here read the coordinator
        // from the LIST body, re-running the whole list per focus move.
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
        .transformEnvironment(\.blockDropRouter) { router in
            if providesNavigationOrder {
                router = ownedDropRouter
            }
        }
        .overlay(alignment: .topLeading) {
            // Invalidation firewall: the child view reads the presenter's
            // sessions in ITS body, so a session write (every slash query
            // keystroke, every highlight move) re-renders the small overlay
            // — reading them here re-ran this whole list body, deep-comparing
            // every block, to move a menu highlight one row.
            if providesNavigationOrder {
                BlockEditorHoistedOverlays(presenter: ownedOverlayPresenter, geometry: listGeometry)
            }
        }
        .background { BlockListWindowReader(geometry: listGeometry).frame(width: 0, height: 0) }
        .onChange(of: resolvedSelectionCoordinator.isActive) { _, active in
            if active {
                // A text drag keeps its origin responder until mouse-up.
                if !ownedDragController.isEscalated { activateSelectionKeyboard() }
            } else { deactivateSelectionKeyboard() }
        }
        .onChange(of: floatingPanelIsVisible) { _, visible in
            if visible {
                startHydrationPumpIfNeeded()
            } else {
                hydrationCancelled = true
                resolvedSelectionCoordinator.clear()
                deactivateSelectionKeyboard()
            }
        }
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { newFrame in
            // Frame goes into a plain reference box — it changes every frame
            // during scrolling and must not invalidate the list body. Only a
            // real size change touches @State.
            // Size also stays in the box: a split/merge always changes list
            // height, and a `listSize` @State write here re-ran the whole
            // list body once more per structural edit. The overlay clamp
            // reads the box at menu-present time instead.
            listGeometry.globalFrame = newFrame
            if listGeometry.lastPublishedSize != newFrame.size {
                listGeometry.lastPublishedSize = newFrame.size
                onContentHeightChange?(newFrame.size.height)
            }
        }
        .onAppear {
            configureUndoRegistrar()
            scheduleEnsureEditableDocument()
            syncNavigationOrderIfNeeded()
            configureDragSelection()
            configureDropRouter()
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
            deactivateSelectionKeyboard()
            hydrationCancelled = true
            // Drop the closed document's undo entries from the window
            // UndoManager: cross-document ⌘Z was already broken (the
            // registrar applies into a dead view's @State), so retaining the
            // stack only pinned every superseded document copy in memory.
            // Only the OWNING list clears — nested element lists share the
            // window stack but not ownership.
            if providesNavigationOrder {
                (undoManager ?? listGeometry.hostView?.window?.undoManager)?.removeAllActions(withTarget: undoRegistrar)
            }
        }
    }

    /// One row of the list — extracted so the ForEach closure stays small
    /// enough for the type checker and the row construction reads clearly.
    @ViewBuilder
    private func rowView(
        index: Int,
        block: RichBlock,
        fingerprint: BlockRowEnvironmentFingerprint,
        listOrdinals: [Int]
    ) -> some View {
        let path = BlockPath.root(index: index)
        let topSpacing = BlockRhythmPolicy.topSpacing(
            for: block.kind,
            following: index > 0 ? document.blocks[index - 1].kind : nil,
            baseGap: blockGap
        )
        if progressiveHydration && index >= hydratedRowLimit {
            BlockStaticRowPlaceholder(
                block: block,
                topSpacing: topSpacing,
                listOrdinal: listOrdinals[index],
                fontSize: fingerprint.fontSize,
                fontDesign: fingerprint.fontDesign,
                darkMode: fingerprint.darkMode,
                overrideTextColor: fingerprint.overrideTextColor,
                onTap: {
                    // A click on a not-yet-hydrated row hydrates up to
                    // it and hands it the caret — the row registers
                    // with the focus coordinator as it mounts.
                    hydratedRowLimit = max(hydratedRowLimit, index + 1)
                    resolvedFocusCoordinator.focus(block.id, caretOffsetFromEnd: 0,
                                                   windowPoint: NSApp.currentEvent?.locationInWindow)
                }
            )
            .id(block.id)
        } else {
            BlockRowContainer(
                block: block,
                path: path,
                topSpacing: topSpacing,
                listOrdinal: listOrdinals[index],
                isSelected: resolvedSelectionCoordinator.isSelected(block.id),
                landingActive: landingHighlightBlockID == block.id,
                dimsInactiveBlocks: dimsInactiveBlocks,
                environment: fingerprint,
                focusCoordinator: resolvedFocusCoordinator,
                selectionCoordinator: resolvedSelectionCoordinator,
                onMove: moveBlock,
                onInsertBelow: { insertParagraph(after: block.id, hint: path) },
                onHandleClick: { handleClicked(block) },
                onHandleShiftClick: {
                    resolvedSelectionCoordinator.selectRange(to: block.id, in: document)
                    activateSelectionKeyboard()
                },
                handleMenu: { handleMenu(for: block) },
                onSelectionCatcherTap: { shiftPressed in
                    if shiftPressed {
                        resolvedSelectionCoordinator.selectRange(to: block.id, in: document)
                        activateSelectionKeyboard()
                    } else {
                        resolvedSelectionCoordinator.clear()
                        deactivateSelectionKeyboard()
                        resolvedFocusCoordinator.focus(block.id, caretOffsetFromEnd: 0,
                                                       windowPoint: NSApp.currentEvent?.locationInWindow)
                    }
                }
            ) {
                blockContent(for: block, at: path, listOrdinal: listOrdinals[index])
            }
            // The row's Equatable gate — a keystroke in one block must
            // not rebuild and re-diff every row's chrome + editor subtree.
            .equatable()
            .id(block.id)
        }
    }

    private func continueWritingAtEnd() {
        resolvedSelectionCoordinator.clear()
        deactivateSelectionKeyboard()
        let continuation = BlockWritingTailPolicy.continuation(in: document)
        if continuation.document != document {
            commit(continuation, undoActionName: "Continue Writing")
        } else if let path = continuation.focusPath,
                  let block = try? BlockOperations.currentBlock(in: document, at: path) {
            resolvedFocusCoordinator.focus(block.id, caretOffsetFromEnd: 0)
        }
    }

    /// A flattened, pre-order list of every block ID (descending into element
    /// children) — the document's visual top-to-bottom order. Only the IDs
    /// change with structure, so `.onChange` fires on real structural edits,
    /// not on every keystroke.
    private var navigationOrderSignature: [UUID] {
        BlockNavigationOrder.flatten(document.blocks)
    }

    /// Per-block position within a contiguous numbered run (0 for the first
    /// item and every non-numbered block) — the serializer seed each row needs
    /// because it can only see its own single-block document. O(n) once per
    /// body evaluation, same order as the ForEach itself.
    static func numberedListOrdinals(for blocks: [RichBlock]) -> [Int] {
        var ordinals: [Int] = []
        ordinals.reserveCapacity(blocks.count)
        var run = 0
        for block in blocks {
            if block.kind == .numberedList {
                ordinals.append(run)
                run += 1
            } else {
                ordinals.append(0)
                run = 0
            }
        }
        return ordinals
    }

    private func syncNavigationOrderIfNeeded() {
        guard providesNavigationOrder else { return }
        resolvedFocusCoordinator.syncNavigationOrder(navigationOrderSignature)
    }

    /// Everything a row's CONTENT closure captures that can change between
    /// renders. The row container's Equatable gate compares this alongside
    /// the block itself — any new style/config input the rows render from
    /// MUST be added here, or a change to it won't reach skipped rows.
    private var rowEnvironmentFingerprint: BlockRowEnvironmentFingerprint {
        BlockRowEnvironmentFingerprint(
            fontSize: fontSize,
            fontDesign: fontDesign,
            lineSpacingAdjustment: lineSpacingAdjustment,
            blockGap: blockGap,
            placeholder: placeholder,
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
            autoFocusFirstTextRegion: autoFocusFirstTextRegion,
            firstBlockID: document.blocks.first?.id
        )
    }

    @ViewBuilder
    private func blockContent(for block: RichBlock, at path: BlockPath, listOrdinal: Int = 0) -> some View {
        switch block.kind {
        case .divider:
            dividerRow
        case .image:
            imageRow(for: block, at: path)
        case .element:
            ElementBlockView(
                block: blockBinding(for: block.id, hint: path, fallback: block),
                focusCoordinator: resolvedFocusCoordinator,
                fontSize: fontSize,
                fontDesign: fontDesign,
                lineSpacingAdjustment: lineSpacingAdjustment,
                blockGap: blockGap,
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
                onExitBody: { insertParagraph(after: block.id, hint: path) },
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
                    guard let livePath = livePath(of: block.id, hint: path),
                          var updated = try? BlockOperations.currentBlock(in: document, at: livePath) else { return }
                    updated.callout = newStyle
                    replaceBlock(at: livePath, with: updated)
                }
            ) {
                textBlockRow(for: block, at: path)
            }
        case .code:
            CodeBlockRowView(
                codeText: {
                    livePath(of: block.id, hint: path)
                        .flatMap { try? BlockOperations.currentBlock(in: document, at: $0) }?
                        .plainInlineText ?? block.plainInlineText
                },
                darkMode: darkMode
            ) {
                textBlockRow(for: block, at: path)
            }
        case .toggle:
            toggleRow(for: block, at: path)
        case .sketch:
            SketchBlockView(
                block: blockBinding(for: block.id, hint: path, fallback: block),
                darkMode: darkMode,
                onSketchChange: emitDocumentChange
            )
        case .section:
            sectionRow(for: block, at: path)
        case .table:
            tableBlockRow(for: block, at: path)
        default:
            textBlockRow(for: block, at: path, listOrdinal: listOrdinal)
        }
    }

    /// The Section box. Its TITLE is the block's own text row (semibold,
    /// slash menu off, mentions on); its body is a nested list over the
    /// children, sharing this list's focus coordinator.
    private func sectionRow(for block: RichBlock, at path: BlockPath) -> some View {
        SectionBlockView(
            block: sectionBlockBinding(for: block.id, hint: path, fallback: block),
            focusCoordinator: resolvedFocusCoordinator,
            fontSize: fontSize,
            fontDesign: fontDesign,
            lineSpacingAdjustment: lineSpacingAdjustment,
            blockGap: blockGap,
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
            onStyleChange: { style in updateSectionStyle(style, blockID: block.id, hint: path) },
            onExitBody: { insertParagraph(after: block.id, hint: path) },
            onSectionChange: emitDocumentChange
        ) {
            textBlockRow(
                for: block,
                at: path,
                placeholderOverride: "Section title",
                slashCommandsEnabled: false,
                fontWeight: .semibold
            )
        }
    }

    /// Binding for a section's body/style writes. Replaces WITHOUT moving
    /// focus (the toggle-children contract): every keystroke in a child row
    /// writes the section back through here, and a focusing `commit` would
    /// yank the caret to the title row per keystroke. Body typing undo rides
    /// the nested rows' own checkpoints; style changes register through
    /// `updateSectionStyle`. ID-resolving — the captured path is a hint.
    private func sectionBlockBinding(for blockID: UUID, hint: BlockPath, fallback: RichBlock) -> Binding<RichBlock> {
        Binding(
            get: {
                guard let path = livePath(of: blockID, hint: hint) else { return fallback }
                return (try? BlockOperations.currentBlock(in: document, at: path)) ?? fallback
            },
            set: { nextBlock in
                guard let path = livePath(of: blockID, hint: hint),
                      let result = try? BlockOperations.replaceBlock(in: document, at: path, with: nextBlock),
                      result.document != document else { return }
                document = result.document
                emitDocumentChange()
            }
        )
    }

    /// Tone / appearance / icon / collapse — one undoable step, no focus move.
    private func updateSectionStyle(_ style: RichSectionStyle, blockID: UUID, hint: BlockPath?) {
        guard let path = livePath(of: blockID, hint: hint),
              var block = try? BlockOperations.currentBlock(in: document, at: path),
              block.kind == .section, block.section != style else { return }
        block.section = style
        guard let result = try? BlockOperations.replaceBlock(in: document, at: path, with: block) else { return }
        commit(result, undoActionName: "Change Section Style", focusAfterCommit: false)
    }

    /// The table block. ONE live cell editor, static cells elsewhere; the
    /// block-level contracts (selection, ↑/↓ exits, delete, convert) route
    /// back through this list so a table behaves like any other block.
    private func tableBlockRow(for block: RichBlock, at path: BlockPath) -> some View {
        TableBlockView(
            block: blockBinding(for: block.id, hint: path, fallback: block),
            focusCoordinator: resolvedFocusCoordinator,
            typography: TableCellTypography(
                fontSize: fontSize,
                fontDesign: fontDesign,
                lineSpacingAdjustment: lineSpacingAdjustment,
                darkMode: darkMode,
                overrideTextColor: overrideTextColor
            ),
            allowMentions: allowMentions,
            editorTargetID: editorTargetID,
            onSelectBlock: { _ = handleEditorSelectionCommand(block.id, .selectCurrentBlock) },
            onSelectAllBlocks: { handleEditorSelectionCommand(block.id, .selectAllBlocks) },
            onExitUp: { _ = resolvedFocusCoordinator.focusPrevious() },
            onExitDown: {
                if !resolvedFocusCoordinator.focusNext() {
                    insertParagraph(after: block.id, hint: path)
                }
            },
            onDeleteTable: { deleteTableBlock(block.id) },
            onReplaceWithBlocks: { replacement in replaceTableBlock(block.id, hint: path, with: replacement) },
            onEdit: { updated, name in replaceBlock(of: block.id, hint: path, with: updated, undoActionName: name) }
        )
    }

    private func deleteTableBlock(_ blockID: UUID) {
        guard let result = BlockOperations.deleteBlocks(withIDs: [blockID], in: document) else { return }
        commit(result, undoActionName: "Delete Table")
    }

    /// "Convert to text": the table becomes paragraphs in its place.
    private func replaceTableBlock(_ blockID: UUID, hint: BlockPath?, with replacement: [RichBlock]) {
        guard let path = livePath(of: blockID, hint: hint),
              let result = try? BlockOperations.replaceBlocks(in: document, at: path, with: replacement) else { return }
        commit(result, undoActionName: "Convert Table to Text")
    }

    private func toggleRow(for block: RichBlock, at path: BlockPath) -> some View {
        ToggleBlockRowView(
            isCollapsed: block.toggleCollapsed ?? false,
            hasChildren: !block.children.isEmpty,
            darkMode: darkMode,
            onToggleCollapse: {
                guard let livePath = livePath(of: block.id, hint: path),
                      var updated = try? BlockOperations.currentBlock(in: document, at: livePath) else { return }
                updated.toggleCollapsed = !(updated.toggleCollapsed ?? false)
                replaceBlock(at: livePath, with: updated)
            },
            onAddFirstChild: { addFirstToggleChild(blockID: block.id, hint: path, block: block) },
            header: {
                textBlockRow(for: block, at: path)
            },
            children: {
                BlockListView(
                    document: toggleChildrenBinding(for: block.id, hint: path, fallback: block),
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
                    onExitFinalEmptyTextRegion: { exitToggleBody(blockID: block.id, hint: path) },
                    onDocumentChange: { _, _ in emitDocumentChange() }
                )
            }
        )
    }

    /// Binding into a toggle's children — the nested list edits them in
    /// place, exactly like an element body. ID-resolving: the captured path
    /// is only a hint (rows skip re-renders across structural shifts).
    private func toggleChildrenBinding(for blockID: UUID, hint: BlockPath, fallback: RichBlock) -> Binding<RichDocument> {
        Binding(
            get: {
                guard let path = livePath(of: blockID, hint: hint),
                      let block = try? BlockOperations.currentBlock(in: document, at: path) else {
                    return RichDocument(blocks: fallback.children)
                }
                return RichDocument(blocks: block.children)
            },
            set: { nextDocument in
                guard let path = livePath(of: blockID, hint: hint),
                      var block = try? BlockOperations.currentBlock(in: document, at: path) else { return }
                block.children = nextDocument.blocks
                guard let result = try? BlockOperations.replaceBlock(in: document, at: path, with: block),
                      result.document != document else { return }
                document = result.document
                emitDocumentChange()
            }
        )
    }

    private func addFirstToggleChild(blockID: UUID, hint: BlockPath?, block: RichBlock) {
        guard let path = livePath(of: blockID, hint: hint) else { return }
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
    private func exitToggleBody(blockID: UUID, hint: BlockPath?) -> Bool {
        guard let path = livePath(of: blockID, hint: hint),
              var block = try? BlockOperations.currentBlock(in: document, at: path),
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

    /// The ONE construction site for text rows. `placeholderOverride`,
    /// `slashCommandsEnabled`, and `fontWeight` exist for container title
    /// rows (a section's title is semibold, always placeholdered, and never
    /// opens the slash menu).
    private func textBlockRow(
        for block: RichBlock,
        at path: BlockPath,
        listOrdinal: Int = 0,
        placeholderOverride: String? = nil,
        slashCommandsEnabled: Bool? = nil,
        fontWeight: NSFont.Weight = .regular
    ) -> some View {
        BlockTextEditorRow(
            document: $document,
            path: path,
            blockID: block.id,
            block: block,
            focusCoordinator: resolvedFocusCoordinator,
            fontSize: fontSize,
            fontDesign: fontDesign,
            lineSpacingAdjustment: lineSpacingAdjustment,
            numberedListSeed: listOrdinal,
            baseFontWeight: fontWeight,
            placeholder: placeholderOverride ?? (BlockPlaceholderPolicy.shouldShowBodyPlaceholder(
                for: block,
                at: path,
                in: document
            ) ? placeholder : ""),
            darkMode: darkMode,
            overrideTextColor: overrideTextColor,
            allowSlashCommands: slashCommandsEnabled ?? allowSlashCommands,
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
        // Skips idle rows on document-driven re-renders (see the row's ==).
        .equatable()
    }

    private var dividerRow: some View {
        // Border tokens, not raw white/ink alphas — the page's one rule weight.
        Rectangle()
            .fill(darkMode ? DS.focusImmersiveBorder : DS.documentBorder)
            .frame(height: 0.5)
            .padding(.vertical, 10)
    }

    private func imageRow(for block: RichBlock, at path: BlockPath) -> some View {
        ResizableImageBlockView(
            image: block.inlines.compactMap(\.image).first ?? RichImageReference(path: "", width: 1, height: 1),
            darkMode: darkMode,
            onCommitWidth: { newWidth in
                setImageDisplayWidth(newWidth, blockID: block.id, hint: path)
            }
        )
    }

    /// Persist a resized image's display width back into the block. One named undo step per
    /// gesture; never steals focus (image blocks have no text region to focus).
    /// ID-resolving: reads the LIVE block so a stale row snapshot can't
    /// resurrect old inlines alongside the new width.
    private func setImageDisplayWidth(_ width: CGFloat?, blockID: UUID, hint: BlockPath?) {
        guard let path = livePath(of: blockID, hint: hint),
              let block = try? BlockOperations.currentBlock(in: document, at: path),
              let imageIndex = block.inlines.firstIndex(where: { $0.kind == .imageRef }),
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

    private var resolvedFocusCoordinator: BlockFocusCoordinator {
        focusCoordinator ?? ownedFocusCoordinator
    }

    private var resolvedSelectionCoordinator: BlockSelectionCoordinator {
        selectionCoordinator ?? ownedSelectionCoordinator
    }

    // (Hoisted menus render through BlockEditorHoistedOverlays below — an
    // invalidation firewall so presenter-session writes never re-run this
    // list's body.)

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

    /// Moves AppKit first responder off the text views so arrow keys, delete,
    /// and shortcuts land on the block list while blocks are selected. Keys
    /// are handled by an AppKit-level monitor — the SwiftUI focus handoff
    /// races makeFirstResponder(nil) and drops keys (⌘A then ⌫ did nothing).
    private func activateSelectionKeyboard() {
        guard let window = listGeometry.hostView?.window else { return }
        selectionKeyMonitor.install(in: window) { event in
            handleSelectionKeyEvent(event)
        }
        BlockSelectionClipboardTarget.activate(
            in: window,
            owner: selectionKeyMonitor,
            isActive: { resolvedSelectionCoordinator.isActive },
            perform: handleBlockSelectionClipboardAction
        )
        DispatchQueue.main.async { [weak window] in
            guard let window, resolvedSelectionCoordinator.isActive else { return }
            FocusModeTextClipboardTarget.collapseActiveSelection(in: window, deactivate: true)
            NotificationCenter.default.post(name: .cosmoDismissEditorOverlays, object: nil)
            window.makeFirstResponder(nil)
            selectionKeyMonitor.installMouseObserver { [weak window] event in
                handleSelectionOutsideClick(event, hostWindow: window)
            }
        }
    }

    /// Blur-clears block selection: with selection active, a click that lands
    /// outside the block list (page margins, toolbar, another surface in the
    /// same window) drops the selection so the wash never outlives the menu.
    /// Clicks in OTHER windows — the handle-menu popover above all — pass
    /// untouched so menu actions still see an active selection. Clicks inside
    /// the list stay owned by the per-row click-catchers.
    private func handleSelectionOutsideClick(_ event: NSEvent, hostWindow: NSWindow?) {
        let selection = resolvedSelectionCoordinator
        guard selection.isActive,
              let hostWindow,
              event.window === hostWindow,
              let contentView = hostWindow.contentView else { return }
        var point = contentView.convert(event.locationInWindow, from: nil)
        if !contentView.isFlipped {
            point.y = contentView.bounds.height - point.y
        }
        guard !listGeometry.globalFrame.contains(point) else { return }
        selection.clear()
        deactivateSelectionKeyboard()
    }

    private func deactivateSelectionKeyboard() {
        selectionKeyMonitor.remove()
        BlockSelectionClipboardTarget.deactivate(owner: selectionKeyMonitor)
    }

    /// AppKit-level key routing while blocks are selected. Returns true when
    /// the event was consumed. ⌘C/⌘X must be handled here: the menu's
    /// clipboard-target path never sees the keystroke because block-row text
    /// views claim clipboard key equivalents during the window's hierarchy
    /// traversal (and, with block selection active, their text selection is
    /// collapsed — so the copy wrote nothing).
    private func handleSelectionKeyEvent(_ event: NSEvent) -> Bool {
        let selection = resolvedSelectionCoordinator
        guard selection.isActive else { return false }
        if let action = BlockSelectionClipboardTarget.action(for: event) {
            return handleBlockSelectionClipboardAction(action)
        }
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])

        switch event.keyCode {
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
        copyBlocksToPasteboard(resolvedSelectionCoordinator.selectedBlockIDs)
    }

    @discardableResult
    private func copyBlocksToPasteboard(_ ids: Set<UUID>) -> Bool {
        let blocks = BlockOperations.blocks(withIDs: ids, in: document)
        guard !blocks.isEmpty, let data = try? JSONEncoder().encode(blocks) else { return false }
        let item = NSPasteboardItem()
        item.setString(BlockOperations.markdown(ofBlocksWithIDs: ids, in: document), forType: .string)
        item.setData(data, forType: .cosmoBlocks)
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.writeObjects([item])
    }

    private func handleBlockSelectionClipboardAction(_ action: BlockSelectionClipboardAction) -> Bool {
        guard resolvedSelectionCoordinator.isActive else {
            BlockSelectionClipboardTarget.deactivate(owner: selectionKeyMonitor)
            return false
        }

        switch action {
        case .copy:
            return copySelectionToPasteboard()
        case .cut:
            guard copySelectionToPasteboard() else { return false }
            deleteSelectedBlocks(resolvedSelectionCoordinator.selectedBlockIDs)
            return true
        case .delete:
            deleteSelectedBlocks(resolvedSelectionCoordinator.selectedBlockIDs)
            return true
        case .selectAll:
            resolvedSelectionCoordinator.selectAll(in: document)
            activateSelectionKeyboard()
            return true
        }
    }

    // MARK: - Handle Menu

    private func handleMenu(for block: RichBlock) -> BlockHandleMenuView {
        let targets = menuTargetIDs(for: block)
        let kind = sharedKind(of: targets)
        return BlockHandleMenuView(
            currentKind: kind,
            selectionCount: targets.count,
            onTransform: { kind in transformBlocks(targets, to: kind) },
            onDuplicate: { duplicateSelectedBlocks(targets) },
            onDelete: { deleteSelectedBlocks(targets) },
            onCopy: { copyBlocksToPasteboard(targets) },
            onCut: {
                if copyBlocksToPasteboard(targets) { deleteSelectedBlocks(targets) }
            },
            onUngroup: kind == .section ? { ungroupSections(targets) } : nil
        )
    }

    /// Hoist the children, drop the box — the selection's sections in place.
    private func ungroupSections(_ ids: Set<UUID>) {
        guard let result = BlockOperations.ungroupSections(withIDs: ids, in: document) else { return }
        resolvedSelectionCoordinator.clear()
        deactivateSelectionKeyboard()
        commit(result, undoActionName: "Ungroup Section", focusAfterCommit: false)
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
        // "Turn N blocks into → Section" wraps them: first block = title,
        // the rest = body. A single block simply becomes a titled section.
        if kind == .section, ids.count > 1 {
            guard let result = BlockOperations.wrapInSection(blockIDs: ids, in: document) else { return }
            resolvedSelectionCoordinator.clear()
            deactivateSelectionKeyboard()
            commit(result, undoActionName: "Turn Into Section", focusAfterCommit: false)
            return
        }
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

    /// A block's LIVE path, resolved by ID with the row's construction-time
    /// path as a hint. Rows skip re-renders across structural shifts (their
    /// `==` deliberately ignores `path`), so any captured BlockPath may be
    /// stale — every closure that mutates the document MUST resolve through
    /// this first or it can hit the wrong sibling after a split/merge above.
    private func livePath(of blockID: UUID, hint: BlockPath?) -> BlockPath? {
        if let hint,
           let hinted = try? BlockOperations.currentBlock(in: document, at: hint),
           hinted.id == blockID {
            return hint
        }
        return BlockOperations.path(of: blockID, in: document)
    }

    private func blockBinding(for blockID: UUID, hint: BlockPath, fallback: RichBlock) -> Binding<RichBlock> {
        Binding(
            get: {
                guard let path = livePath(of: blockID, hint: hint) else { return fallback }
                return (try? BlockOperations.currentBlock(in: document, at: path)) ?? fallback
            },
            set: { nextBlock in
                guard let path = livePath(of: blockID, hint: hint) else { return }
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

    /// ID-resolving variant for closures captured by skippable rows.
    private func replaceBlock(of blockID: UUID, hint: BlockPath?, with nextBlock: RichBlock) {
        guard let path = livePath(of: blockID, hint: hint) else { return }
        replaceBlock(at: path, with: nextBlock)
    }

    /// Same, with the action's own undo name (table edits: "Merge Cells",
    /// "Sort Rows" …) and no focus move — the table owns its focus.
    private func replaceBlock(of blockID: UUID, hint: BlockPath?, with nextBlock: RichBlock, undoActionName: String) {
        guard let path = livePath(of: blockID, hint: hint),
              let result = try? BlockOperations.replaceBlock(in: document, at: path, with: nextBlock),
              result.document != document else { return }
        commit(result, undoActionName: undoActionName, focusAfterCommit: false)
    }

    private func emitDocumentChange() {
        onDocumentChange?(document, document.plainText)
    }

    /// ID-resolving: `hint` may be stale (rows skip re-renders across
    /// structural shifts), so the insertion point is re-derived by block ID.
    private func insertParagraph(after blockID: UUID, hint: BlockPath?) {
        guard let path = livePath(of: blockID, hint: hint) else { return }
        let paragraph = RichBlock.paragraph("")
        guard let result = try? BlockOperations.insertBlock(paragraph, in: document, after: path) else {
            return
        }
        commit(result, undoActionName: "Insert Text Block")
    }

    /// Drop commit. Source AND target positions are resolved by block ID at
    /// commit time — the drag payload's `sourcePath` and the drop row's
    /// captured path can both be stale by the time the drop lands.
    private func moveBlock(_ payload: BlockDragPayload, position: BlockDropPosition, targetBlockID: UUID) {
        guard let sourcePath = livePath(of: payload.blockID, hint: payload.sourcePath) else {
            // The dragged block lives outside this list's sub-document (a
            // drop INTO a section/element body from the page, or between
            // two containers) — only the root can see both ends.
            inheritedDropRouter?.moveAcrossContainers?(payload, position, targetBlockID)
            return
        }
        guard let targetPath = livePath(of: targetBlockID, hint: nil) else { return }
        let target = BlockDropController.target(for: position, path: targetPath)
        guard BlockDropController.canMove(from: sourcePath, to: target),
              let result = try? BlockOperations.moveBlock(in: document, from: sourcePath, to: target) else {
            return
        }
        commit(result, undoActionName: "Move Block")
    }

    /// The root list owns the whole document, so it is the one mover that
    /// can resolve BOTH ends of a cross-container drop by ID.
    private func configureDropRouter() {
        guard providesNavigationOrder else { return }
        ownedDropRouter.moveAcrossContainers = { payload, position, targetBlockID in
            guard let result = try? BlockOperations.moveBlock(
                withID: payload.blockID,
                relativeTo: targetBlockID,
                position: position,
                in: document
            ) else { return }
            commit(result, undoActionName: "Move Block")
        }
    }

    private func commit(_ result: BlockOperationResult, undoActionName: String, focusAfterCommit: Bool = true) {
        let before = document
        document = result.document
        undoRegistrar.register(
            undoManager: undoManager ?? listGeometry.hostView?.window?.undoManager,
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

    // MARK: - Progressive Hydration

    private func startHydrationPumpIfNeeded() {
        guard progressiveHydration else { return }
        hydrationCancelled = false
        pumpHydration()
    }

    /// Raises the hydrated-row limit one chunk per runloop turn until every
    /// row is live, then parks it at .max so blocks appended later always
    /// mount live. Chunks grow geometrically: the first ticks stay small so
    /// the main thread breathes right after first paint, then the pump
    /// accelerates so long documents don't pay hundreds of list-body passes.
    private func pumpHydration(chunk: Int = BlockHydrationPolicy.chunk) {
        guard !hydrationCancelled else { return }
        guard hydratedRowLimit < document.blocks.count else {
            hydratedRowLimit = .max
            return
        }
        DispatchQueue.main.async {
            hydratedRowLimit += chunk
            pumpHydration(chunk: BlockHydrationPolicy.nextChunk(after: chunk))
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

/// Chunk sizes for progressive hydration. The initial chunk covers a bit
/// more than one viewport of text so the first paint looks fully live; the
/// pump chunk keeps each hydration tick well under a frame's worth of
/// blocking work at Debug-build speeds.
enum BlockHydrationPolicy {
    static let initialChunk = 28
    static let chunk = 24
    /// Geometric growth per pump tick, capped: 24 → 38 → 60 → 96 → 96 …
    /// The cap keeps a single tick's row mounts under a frame's worth of
    /// blocking work; the growth keeps 500-block documents from paying a
    /// full list-body pass every 24 rows.
    static let growth = 1.6
    static let maxChunk = 96
    static func nextChunk(after current: Int) -> Int {
        min(maxChunk, max(chunk, Int(Double(current) * growth)))
    }
}

/// Off-render-path frame storage: the block list's frame in the hosting
/// view's coordinate space. A plain reference so per-scroll-frame geometry
/// updates never invalidate the SwiftUI body — only the selection
/// outside-click monitor reads it, at click time.
@MainActor
final class BlockListGeometryBox {
    weak var hostView: NSView?
    var globalFrame: CGRect = .zero
    /// Last size published through onContentHeightChange — dedup lives here
    /// so height reporting never touches @State (which would re-run the list
    /// body once more per structural edit).
    var lastPublishedSize: CGSize = .zero
}

/// Capture the actual hosting window, including a nonactivating panel.
/// Selection must never borrow NSApp.keyWindow from a different surface.
private struct BlockListWindowReader: NSViewRepresentable {
    let geometry: BlockListGeometryBox
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        geometry.hostView = view
        return view
    }
    func updateNSView(_ view: NSView, context: Context) {}
}

/// The hoisted slash / new-element / selection menus for a block list.
/// A separate view ON PURPOSE: it reads the presenter's sessions in its own
/// body, so Observation invalidates just this overlay when a session changes
/// (every slash query keystroke, every arrow/hover highlight move) — reading
/// the sessions from BlockListView.body re-ran the entire list, rebuilding
/// and deep-comparing every row, to move a menu highlight one row.
private struct BlockEditorHoistedOverlays: View {
    let presenter: EditorOverlayPresenter
    let geometry: BlockListGeometryBox

    var body: some View {
        if let session = presenter.slashSession {
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
        if let session = presenter.elementCreationSession {
            ElementCreationMenu(
                position: clampedOverlayPosition(for: session.anchorInList, menuSize: CGSize(width: 320, height: 352)),
                onCreate: session.onCreate,
                onDismiss: session.onDismiss,
                darkMode: session.darkMode
            )
            .zIndex(1001)
            .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .topLeading)))
        }
        if presenter.slashSession == nil,
           let session = presenter.selectionSession {
            SelectionFormattingMenu(
                anchor: session.anchorInList,
                container: geometry.globalFrame.size,
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

    private func clampedOverlayPosition(for anchor: CGPoint, menuSize: CGSize) -> CGPoint {
        // Clamp horizontally only. NEVER flip above the caret based on the
        // list's own height: the list ends right after its last block, so a
        // caret near the end flipped the menu ~370pt above the cursor — the
        // user never saw it. Below the caret is always right in notes: the
        // scroll-past-end padding leaves room, and overlays don't clip.
        var origin = anchor
        origin.x = max(0, min(origin.x, geometry.globalFrame.size.width - menuSize.width - 8))
        return origin
    }
}

/// The static stand-in a not-yet-hydrated row renders during a progressive
/// open: the block's text at editor-matched fonts, inset by the handle
/// gutter, with no editor machinery behind it. Lives on screen for well
/// under a second — visual parity matters, interactive parity does not
/// (a tap hydrates the row and hands it focus).
struct BlockStaticRowPlaceholder: View {
    let block: RichBlock
    let topSpacing: CGFloat
    var listOrdinal: Int = 0
    let fontSize: CGFloat
    let fontDesign: NSFontDescriptor.SystemDesign
    let darkMode: Bool
    let overrideTextColor: NSColor?
    let onTap: () -> Void

    var body: some View {
        Group {
            if block.kind == .divider {
                // GUARD-TWIN of dividerRow above — the same rule must not
                // change weight when its row hydrates.
                Rectangle()
                    .fill(darkMode ? DS.focusImmersiveBorder : DS.documentBorder)
                    .frame(height: 0.5)
                    .padding(.vertical, 10)
            } else if block.kind == .table || block.kind == .section {
                // Structured blocks hydrate from the read-only renderer —
                // the same grid/box the live views draw, minus chrome.
                CosmoDocumentRenderer(
                    document: RichDocument(blocks: [block]),
                    fontSize: fontSize,
                    darkMode: darkMode
                )
                .padding(.horizontal, block.kind == .table ? TableChromeLayer.apron : 0)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            } else if block.kind == .quote {
                // GUARD-TWIN of the serializer's quote prefix (semibold on
                // border tokens) — the bar must not change voice at hydration.
                // (Text interpolation, not `+` — deprecated on macOS 26.)
                Text("\(quoteBarText)\(Text(block.plainInlineText).font(Font(editorFont)).foregroundStyle(inkColor))")
                    .lineSpacing(6)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            } else if block.kind == .checklist {
                // GUARD-TWIN of the serializer's checklist styling — "done"
                // must look done in every one of the three render paths.
                Text("\(checklistGlyphText)\(checklistContentText)")
                    .lineSpacing(6)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            } else {
                Text(displayText)
                    .font(Font(editorFont))
                    .foregroundStyle(inkColor)
                    .lineSpacing(6)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .padding(.leading, BlockInteractionPolicy.gutterWidth)
        .padding(.top, topSpacing)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    private var inkColor: Color {
        Color(nsColor: overrideTextColor ?? (darkMode ? .white : NSColor(DS.documentText)))
    }

    private var quoteBarText: Text {
        Text("│ ")
            .font(Font(NSFont.systemFont(ofSize: fontSize, weight: .semibold)))
            .foregroundStyle(darkMode ? DS.focusImmersiveBorder : DS.documentBorder)
    }

    private var checklistGlyphText: Text {
        Text((block.checked ?? false) ? "☑ " : "☐ ")
            .font(Font(editorFont))
            .foregroundStyle((block.checked ?? false) ? CosmoColors.cosmoAI : inkColor.opacity(0.55))
    }

    private var checklistContentText: Text {
        Text(block.plainInlineText)
            .font(Font(editorFont))
            .strikethrough(block.checked ?? false)
            .foregroundStyle((block.checked ?? false) ? inkColor.opacity(0.55) : inkColor)
    }

    /// Mirrors the serializer's rendered line: list/quote prefixes at the
    /// head, heading text bare (size carries the hierarchy).
    private var displayText: String {
        let text = block.plainInlineText
        switch block.kind {
        case .bulletList: return "• " + text
        case .numberedList: return "\(listOrdinal + 1). " + text
        // .quote and .checklist render as styled concatenations in body —
        // these fallbacks are unreachable for them.
        case .checklist: return ((block.checked ?? false) ? "☑ " : "☐ ") + text
        case .quote: return "│ " + text
        case .toggle: return "▸ " + text
        case .section: return "▣ " + text
        case .image: return "[Image]"
        case .sketch: return "[Sketch]"
        case .table: return "[Table]"
        default: return text
        }
    }

    /// Matches the serializer's heading/body font metrics so hydration does
    /// not shift layout noticeably.
    private var editorFont: NSFont {
        // GUARD-TWIN of RichDocumentSerializer.blockFont's heading ladder
        // (with TextKitCoordinator's applyHeading and
        // seedTypingAttributesForEmptyRow) — change all FOUR together.
        switch block.kind.headingLevelInt {
        case 1: return EditorFontPolicy.font(ofSize: min(34, (fontSize * 1.85).rounded()), weight: .semibold, design: fontDesign)
        case 2: return EditorFontPolicy.font(ofSize: (fontSize * 1.45).rounded(), weight: .semibold, design: fontDesign)
        case 3: return EditorFontPolicy.font(ofSize: (fontSize * 1.20).rounded(), weight: .medium, design: fontDesign)
        default:
            // Code and toggle placeholders match their serializer voices so
            // hydration doesn't re-typeset the row.
            if block.kind == .code {
                return NSFont.monospacedSystemFont(ofSize: max(11, fontSize - 3), weight: .regular)
            }
            if block.kind == .toggle {
                return EditorFontPolicy.font(ofSize: fontSize, weight: .medium, design: fontDesign)
            }
            return EditorFontPolicy.font(ofSize: fontSize, weight: .regular, design: fontDesign)
        }
    }
}

/// Everything a row's content closure captures that can change between list
/// renders. Compared by BlockRowContainer's Equatable gate — a value change
/// here re-renders every row (style switches are rare and must propagate);
/// a value MISSING from here silently never reaches skipped rows.
struct BlockRowEnvironmentFingerprint: Equatable {
    var fontSize: CGFloat
    var fontDesign: NSFontDescriptor.SystemDesign
    var lineSpacingAdjustment: CGFloat
    var blockGap: CGFloat
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
    var autoFocusFirstTextRegion: Bool
    /// The placeholder policy renders differently for the document's first
    /// block, so first-block identity is part of the render environment.
    var firstBlockID: UUID?
}

/// One row of the block list — rhythm padding, gutter chrome, block content,
/// and selection affordances — behind a single Equatable render gate.
///
/// THE load-bearing perf structure for long notes: a keystroke writes the
/// whole document and re-runs the list body, and without this gate SwiftUI
/// rebuilt and re-diffed every row's deep subtree (gutter buttons, drag/drop
/// modifiers, popover, the NSTextView representable) on every keystroke —
/// tens of milliseconds per keystroke at ~200 blocks. With it, unchanged
/// rows cost one shallow struct + one == compare.
///
/// Closures and the content builder are deliberately excluded from ==: they
/// read live state through stable references, so a skipped row's previous
/// closures remain correct. Focus/caret/selection state is read from the
/// @Observable coordinators inside body, so Observation invalidates affected
/// rows directly, bypassing this gate.
struct BlockRowContainer<Content: View>: View, Equatable {
    let block: RichBlock
    let path: BlockPath
    let topSpacing: CGFloat
    /// Numbered-run position — part of the render gate: transforming a block
    /// ABOVE this row can change this row's number without touching its block
    /// or path, and a skipped row would keep a stale "3.".
    let listOrdinal: Int
    let isSelected: Bool
    let landingActive: Bool
    let dimsInactiveBlocks: Bool
    let environment: BlockRowEnvironmentFingerprint
    let focusCoordinator: BlockFocusCoordinator
    let selectionCoordinator: BlockSelectionCoordinator
    let onMove: (BlockDragPayload, BlockDropPosition, UUID) -> Void
    let onInsertBelow: () -> Void
    let onHandleClick: () -> Void
    let onHandleShiftClick: () -> Void
    let handleMenu: () -> BlockHandleMenuView
    /// Tap on the selection click-catcher; the Bool is "shift was held".
    let onSelectionCatcherTap: (Bool) -> Void
    @ViewBuilder let content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// `path` is deliberately NOT compared — it embeds the sibling index, so a
    /// split/merge above would re-render every row below it. The stored path
    /// is a lookup hint only; every consumer (row bindings, drag/drop, insert)
    /// resolves the live position by block ID at call time.
    static func == (lhs: BlockRowContainer, rhs: BlockRowContainer) -> Bool {
        (lhs.block == rhs.block
            || rhs.focusCoordinator.isSelfAuthoredEcho(previous: lhs.block, next: rhs.block))
            && lhs.topSpacing == rhs.topSpacing
            && lhs.listOrdinal == rhs.listOrdinal
            && lhs.isSelected == rhs.isSelected
            && lhs.landingActive == rhs.landingActive
            && lhs.dimsInactiveBlocks == rhs.dimsInactiveBlocks
            && lhs.environment == rhs.environment
            && lhs.focusCoordinator === rhs.focusCoordinator
            && lhs.selectionCoordinator === rhs.selectionCoordinator
    }

    var body: some View {
        BlockRowView(
            block: block,
            path: path,
            darkMode: environment.darkMode,
            isSelected: isSelected,
            onMove: onMove,
            onInsertBelow: onInsertBelow,
            onHandleClick: onHandleClick,
            onHandleShiftClick: onHandleShiftClick,
            handleMenu: handleMenu
        ) {
            content()
                .overlay { selectionClickCatcher }
        }
        .padding(.top, topSpacing)
        .opacity(rowOpacity)
        // Scoped to this row's own dim value — the old list-level animation
        // on focusedBlockID re-ran the whole list body per focus move.
        .animation(reduceMotion ? nil : ProMotionSprings.gentle, value: rowOpacity)
        .overlay { landingWash }
    }

    /// Paragraph-focus dimming: 1.0 for the caret's block, faded-but-legible
    /// for the rest. Suspended while block selection is active so selected
    /// rows never fight their selection wash. Coordinator reads stay behind
    /// the dims guard so the feature costs nothing when off — and they read
    /// `hasFocusedBlock` + the row's OWN focus state, so a focus move re-dims
    /// two rows instead of re-rendering every container.
    private var rowOpacity: Double {
        guard dimsInactiveBlocks,
              !selectionCoordinator.isActive,
              focusCoordinator.hasFocusedBlock,
              !focusCoordinator.rowState(for: block.id).isFocused else {
            return 1
        }
        return 0.4
    }

    /// Soft accent wash on the block a search landing points at — a reveal,
    /// not a selection: non-interactive, and it fades with the host clearing
    /// its landing highlight after the pulse.
    @ViewBuilder
    private var landingWash: some View {
        if landingActive {
            RoundedRectangle(cornerRadius: DS.radiusSmall, style: .continuous)
                .fill(DS.accent.opacity(0.10))
                .padding(.horizontal, -DS.space6)
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }

    /// While block selection is active, clicks land on blocks instead of text
    /// (the Notion model): Shift+Click extends the range, a plain click exits
    /// selection and resumes editing the clicked block. The overlay only
    /// exists during selection, so normal editing pays nothing for it.
    @ViewBuilder
    private var selectionClickCatcher: some View {
        if selectionCoordinator.isActive {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    onSelectionCatcherTap(NSEvent.modifierFlags.contains(.shift))
                }
        }
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

enum BlockWritingTailPolicy {
    static func continuation(in document: RichDocument) -> BlockOperationResult {
        if let last = document.blocks.last,
           last.kind.isTextEditableBlock,
           last.plainInlineText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return BlockOperationResult(document: document, focusPath: .root(index: document.blocks.count - 1), caretUTF16Offset: 0)
        }
        var updated = document
        updated.blocks.append(.paragraph(""))
        return BlockOperationResult(document: updated, focusPath: .root(index: updated.blocks.count - 1), caretUTF16Offset: 0)
    }
}
