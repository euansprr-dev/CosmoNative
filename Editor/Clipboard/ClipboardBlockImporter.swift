import AppKit
import Foundation

/// What the pasteboard turned out to hold, from the editor's point of view.
enum ClipboardImport {
    case blocks([RichBlock])
    case inline([RichInlineNode])
    case table(RichTable)
    case text(String)
    case none
}

/// Reads the pasteboard in the app's priority order (after the internal
/// `com.cosmo.blocks` flavour and images, which the caller handles):
/// HTML → RTF → plain text (tabular first).
enum ClipboardBlockImporter {
    static func read(_ pasteboard: NSPasteboard) -> ClipboardImport {
        if let html = pasteboard.string(forType: .html), !html.isEmpty {
            let blocks = HTMLBlockImporter.blocks(fromHTML: html)
            if let result = classify(blocks) { return result }
        }
        if let rtfData = pasteboard.data(forType: .rtf),
           let attributed = NSAttributedString(rtf: rtfData, documentAttributes: nil) {
            let document = RichDocumentSerializer.document(from: attributed)
            let blocks = document.blocks.filter { block in
                block.kind != .paragraph || !block.inlines.allSatisfy { ($0.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.kind == .text }
            }
            if let result = classify(blocks) { return result }
        }
        if let string = pasteboard.string(forType: .string), !string.isEmpty {
            if let table = TabularTextImporter.table(fromPlainText: string) {
                return .table(table)
            }
            return .text(string)
        }
        return .none
    }

    private static func classify(_ blocks: [RichBlock]) -> ClipboardImport? {
        guard !blocks.isEmpty else { return nil }
        if blocks.count == 1, blocks[0].kind == .table, let table = blocks[0].table {
            return .table(table)
        }
        if HTMLBlockImporter.isSingleInlineParagraph(blocks) {
            return .inline(blocks[0].inlines)
        }
        return .blocks(blocks)
    }
}
