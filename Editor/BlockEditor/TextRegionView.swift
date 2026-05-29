import AppKit
import SwiftUI

struct TextRegionView: View {
    @Binding var document: RichDocument

    let region: BlockRegion
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
    var onBoundaryCommand: ((EditorBoundaryCommand, BlockRegion) -> Bool)?
    var onDocumentChange: ((RichDocument, String) -> Void)?

    @State private var structuralRefreshID = UUID()
    @State private var structuralEditTracker = TextRegionStructuralEditTracker()

    var body: some View {
        CosmoDocumentEditor(
            document: regionDocumentBinding,
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
            editorTargetID: focusCoordinator.commandTargetID(for: region.focusID, baseTargetID: editorTargetID),
            navigationTargetID: navigationTargetID,
            onDocumentChange: handleRegionDocumentChange,
            onActivate: { focusCoordinator.focus(region.focusID) },
            onBoundaryCommand: { command in
                onBoundaryCommand?(command, region) ?? false
            },
            autoFocus: autoFocus || focusCoordinator.focusedBlockID == region.focusID
        )
        .id(structuralRefreshID)
        .onAppear { focusCoordinator.register(region.focusID) }
        .onDisappear { focusCoordinator.unregister(region.focusID) }
    }

    private var regionDocumentBinding: Binding<RichDocument> {
        Binding(
            get: {
                RichDocument(blocks: currentRegionBlocks())
            },
            set: { nextDocument in
                structuralEditTracker.recordUpdate(
                    from: currentRegionBlocks(),
                    to: nextDocument.blocks
                )
                replaceRegionBlocks(with: nextDocument.blocks)
            }
        )
    }

    private func handleRegionDocumentChange(_ updatedRegion: RichDocument, _: String) {
        let existingBlocks = currentRegionBlocks()
        let insertedElementID = structuralEditTracker.consumeInsertedElementID()
            ?? TextRegionStructuralEditTracker.firstInsertedElementID(in: updatedRegion.blocks, comparedTo: existingBlocks)
        let mergedDocument = replaceRegionBlocks(with: updatedRegion.blocks)
        if let insertedElementID {
            structuralRefreshID = UUID()
            focusCoordinator.focus(insertedElementID)
        }
        onDocumentChange?(mergedDocument, mergedDocument.plainText)
    }

    @discardableResult
    private func replaceRegionBlocks(with nextBlocks: [RichBlock]) -> RichDocument {
        let range = safeRange(in: document.blocks)
        let existingBlocks = Array(document.blocks[range])
        let stableBlocks = preserveStableIDs(in: nextBlocks, matching: existingBlocks)
        let updatedBlocks = BlockRegionReplacement.replacingBlocks(
            in: document.blocks,
            range: range,
            with: stableBlocks
        )
        guard updatedBlocks != document.blocks else { return document }

        var updated = document
        updated.blocks = updatedBlocks
        document = updated
        return updated
    }

    private func currentRegionBlocks() -> [RichBlock] {
        let range = safeRange(in: document.blocks)
        return Array(document.blocks[range])
    }

    private func safeRange(in blocks: [RichBlock]) -> Range<Int> {
        BlockRegionReplacement.resolvedRange(for: region, in: blocks)
    }

    private func preserveStableIDs(in nextBlocks: [RichBlock], matching existingBlocks: [RichBlock]) -> [RichBlock] {
        var result = nextBlocks
        for index in result.indices {
            guard existingBlocks.indices.contains(index),
                  result[index].kind == existingBlocks[index].kind,
                  result[index].kind != .element else {
                continue
            }
            result[index].id = existingBlocks[index].id
        }
        return result
    }
}

struct TextRegionStructuralEditTracker {
    private var insertedElementID: UUID?

    mutating func recordUpdate(from existingBlocks: [RichBlock], to nextBlocks: [RichBlock]) {
        insertedElementID = Self.firstInsertedElementID(in: nextBlocks, comparedTo: existingBlocks)
    }

    mutating func consumeInsertedElementID() -> UUID? {
        defer { insertedElementID = nil }
        return insertedElementID
    }

    static func firstInsertedElementID(in nextBlocks: [RichBlock], comparedTo existingBlocks: [RichBlock]) -> UUID? {
        let existingElementIDs = Set(existingBlocks.filter { $0.kind == .element }.map(\.id))
        return nextBlocks.first { block in
            block.kind == .element && !existingElementIDs.contains(block.id)
        }?.id
    }
}
