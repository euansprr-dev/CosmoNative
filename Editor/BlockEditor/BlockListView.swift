import AppKit
import SwiftUI

struct BlockListView: View {
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
    var onSelectionChanged: ((EditorSelectionSnapshot) -> Void)? = nil
    var onContentHeightChange: ((CGFloat) -> Void)? = nil
    var onExitFinalEmptyTextRegion: (() -> Bool)? = nil
    var onDocumentChange: ((RichDocument, String) -> Void)? = nil

    @State private var ownedFocusCoordinator = BlockFocusCoordinator()

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            ForEach(regions) { region in
                regionView(for: region)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { newHeight in
            onContentHeightChange?(newHeight)
        }
    }

    @ViewBuilder
    private func regionView(for region: BlockRegion) -> some View {
        switch region.kind {
        case .text, .unsupported:
            textRegionView(for: region)
        case .element:
            if let block = region.blocks.first {
                ElementBlockView(
                    block: blockBinding(for: region, fallback: block),
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
                    onExitBody: { insertParagraph(after: region) },
                    onElementChange: emitDocumentChange
                )
            }
        }
    }

    private func textRegionView(for region: BlockRegion) -> some View {
        TextRegionView(
            document: $document,
            region: region,
            focusCoordinator: resolvedFocusCoordinator,
            fontSize: fontSize,
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
            autoFocus: false,
            onSelectionChanged: onSelectionChanged,
            onBoundaryCommand: handleBoundaryCommand,
            onDocumentChange: onDocumentChange
        )
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

    private func blockBinding(for region: BlockRegion, fallback: RichBlock) -> Binding<RichBlock> {
        Binding(
            get: {
                block(at: region.range.lowerBound) ?? fallback
            },
            set: { nextBlock in
                replaceBlock(at: region.range.lowerBound, with: nextBlock)
            }
        )
    }

    private func block(at index: Int) -> RichBlock? {
        guard document.blocks.indices.contains(index) else { return nil }
        return document.blocks[index]
    }

    private func replaceBlock(at index: Int, with nextBlock: RichBlock) {
        guard document.blocks.indices.contains(index),
              document.blocks[index] != nextBlock else {
            return
        }
        document.blocks[index] = nextBlock
    }

    private func emitDocumentChange() {
        onDocumentChange?(document, document.plainText)
    }

    private func handleBoundaryCommand(_ command: EditorBoundaryCommand, in region: BlockRegion) -> Bool {
        resolvedFocusCoordinator.focus(region.focusID)

        switch command {
        case .moveToPreviousBlock:
            return resolvedFocusCoordinator.focusPrevious()
        case .moveToNextBlock:
            return resolvedFocusCoordinator.focusNext()
        case .deleteBackwardAtStart:
            return handleDeleteBackwardAtStart(in: region)
        case .insertNewlineOnEmptyFinalLine:
            return onExitFinalEmptyTextRegion?() ?? false
        }
    }

    private func handleDeleteBackwardAtStart(in region: BlockRegion) -> Bool {
        guard region.kind == .text,
              let firstBlock = region.blocks.first,
              firstBlock.isEmptyParagraphBlock,
              region.range.lowerBound > 0,
              document.blocks.indices.contains(region.range.lowerBound) else {
            return false
        }

        let previousIndex = region.range.lowerBound - 1
        let previousID = document.blocks.indices.contains(previousIndex) ? document.blocks[previousIndex].id : nil
        document.blocks.remove(at: region.range.lowerBound)
        emitDocumentChange()
        resolvedFocusCoordinator.focus(previousID)
        return true
    }

    private func insertParagraph(after region: BlockRegion) {
        let paragraph = RichBlock.paragraph("")
        let insertionIndex = min(region.range.upperBound, document.blocks.count)
        document.blocks.insert(paragraph, at: insertionIndex)
        emitDocumentChange()
        resolvedFocusCoordinator.focus(paragraph.id)
    }
}

private extension RichBlock {
    var isEmptyParagraphBlock: Bool {
        guard kind == .paragraph, children.isEmpty else { return false }
        return inlines.allSatisfy { inline in
            switch inline.kind {
            case .text:
                return inline.text?.isEmpty ?? true
            case .mention, .imageRef:
                return false
            }
        }
    }
}
