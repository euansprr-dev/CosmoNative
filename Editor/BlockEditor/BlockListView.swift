import AppKit
import SwiftUI

struct BlockListView: View {
    @Environment(\.undoManager) private var undoManager

    @Binding var document: RichDocument

    var fontSize: CGFloat = 17
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
    var autoFocusFirstTextRegion: Bool = false
    var onSelectionChanged: ((EditorSelectionSnapshot) -> Void)? = nil
    var onContentHeightChange: ((CGFloat) -> Void)? = nil
    var onExitFinalEmptyTextRegion: (() -> Bool)? = nil
    var onDocumentChange: ((RichDocument, String) -> Void)? = nil

    @State private var ownedFocusCoordinator = BlockFocusCoordinator()
    @State private var undoRegistrar = BlockUndoRegistrar()

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            ForEach(Array(document.blocks.enumerated()), id: \.element.id) { index, block in
                rowView(for: block, at: .root(index: index))
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
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
    }

    @ViewBuilder
    private func rowView(for block: RichBlock, at path: BlockPath) -> some View {
        BlockRowView(block: block, path: path, darkMode: darkMode, onMove: moveBlock) {
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
    }

    private func textBlockRow(for block: RichBlock, at path: BlockPath) -> some View {
        BlockTextEditorRow(
            document: $document,
            path: path,
            blockID: block.id,
            focusCoordinator: resolvedFocusCoordinator,
            fontSize: fontSize,
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
            onExitFinalEmptyTextRegion: onExitFinalEmptyTextRegion
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
                .font(.system(size: 11, weight: .medium))
            Text(kind == .content ? "Content" : "Research")
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(darkMode ? Color.white.opacity(0.58) : DS.documentTextMuted)
        .padding(.leading, 2)
    }

    private var regions: [BlockRegion] {
        let splitRegions = BlockSplitter.split(document.blocks)
        if splitRegions.isEmpty {
            return [BlockRegion(kind: .text, range: 0..<0, blocks: [])]
        }
        return splitRegions
    }

    private var resolvedFocusCoordinator: BlockFocusCoordinator {
        focusCoordinator ?? ownedFocusCoordinator
    }

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

    private func commit(_ result: BlockOperationResult, undoActionName: String) {
        let before = document
        document = result.document
        undoRegistrar.register(
            undoManager: undoManager,
            before: before,
            after: result.document,
            actionName: undoActionName
        )
        emitDocumentChange()
        if let focusPath = result.focusPath,
           let focusedBlock = try? BlockOperations.currentBlock(in: result.document, at: focusPath) {
            resolvedFocusCoordinator.focus(focusedBlock.id)
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
