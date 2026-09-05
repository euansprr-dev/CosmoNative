// CosmoOS/UI/InlineAssistant/CosmoAssistantMarkdownRenderer.swift
// Markdown → attributed text for pane answers: headings, paragraphs, nested
// lists, block quotes, code, tables, inline emphasis and links — with the
// workspace's own document pills ([[uuid]] markers and title auto-links) woven
// in as attachments. ONE renderer serves the streaming row and the finalized
// row, so the finalize swap never reflows and raw Markdown never shows.
// September 2026

import AppKit
import Foundation
import SwiftUI

// MARK: - Rendered answer

struct CosmoAssistantRenderedAnswer: Equatable {
    /// Cache identity: content + refs + palette. Two renders with the same key
    /// are byte-identical, so views compare keys instead of attributed strings.
    let key: String
    let attributed: NSAttributedString
    /// Refs that became inline pills — the remainder renders as an "Also read"
    /// row instead of duplicating the citation.
    let linkedRefUUIDs: Set<String>

    static func == (lhs: CosmoAssistantRenderedAnswer, rhs: CosmoAssistantRenderedAnswer) -> Bool {
        lhs.key == rhs.key
    }

    static let empty = CosmoAssistantRenderedAnswer(key: "", attributed: NSAttributedString(), linkedRefUUIDs: [])
}

// MARK: - Custom attributes the layout manager decorates

extension NSAttributedString.Key {
    /// Block-level decoration (code block / quote) — value is a
    /// `CosmoProseBlockDecoration.rawValue`. The layout manager paints one
    /// rounded background per contiguous run.
    static let cosmoProseBlock = NSAttributedString.Key("cosmo.prose.block")
    /// Inline code chip — value is `true`. Painted per enclosing line rect.
    static let cosmoProseInlineCode = NSAttributedString.Key("cosmo.prose.inlineCode")
}

enum CosmoProseBlockDecoration: String {
    case code
    case quote
}

// MARK: - Renderer

enum CosmoAssistantMarkdownRenderer {
    // Typography shared with the old streaming `Text` so nothing reflows.
    static let bodySize: CGFloat = 15
    static let lineSpacing: CGFloat = 3
    static let paragraphGap: CGFloat = 9
    static let listItemGap: CGFloat = 4
    static let listIndent: CGFloat = 20
    static let listMarkerWidth: CGFloat = 18
    static let blockInset: CGFloat = 12
    static let blockVerticalPad: CGFloat = 8
    static let quoteBarWidth: CGFloat = 3
    static let cornerRadius: CGFloat = 8

    /// Stands in for a pill while the Markdown parser runs — the parser sees a
    /// single opaque character, never the marker grammar or the title.
    private static let pillPlaceholder: Character = "\u{FFFC}"

    struct Palette {
        var text: NSColor
        var secondary: NSColor
        var muted: NSColor
        var accent: NSColor
        var accentSoft: NSColor
        var blockFill: NSColor
        var blockBorder: NSColor
        var inlineCodeFill: NSColor

        /// The live theme's colors. Read at render time and at draw time (the
        /// layout manager paints decorations on the main thread but is not
        /// actor-annotated), so this stays nonisolated like the DS tokens it reads.
        static var current: Palette {
            Palette(
                text: NSColor(DS.text),
                secondary: NSColor(DS.textSecondary),
                muted: NSColor(DS.textMuted),
                accent: NSColor(DS.accent),
                accentSoft: NSColor(DS.accentSoft),
                blockFill: NSColor(DS.glassSectionFill),
                blockBorder: NSColor(DS.glassBorder),
                inlineCodeFill: NSColor(DS.surfaceHover)
            )
        }
    }

    // MARK: Entry points

    /// Cache identity for a message's render.
    @MainActor
    static func cacheKey(
        messageID: UUID?,
        content: String,
        sourceRefs: [CosmoAssistantSourceRef],
        isStreaming: Bool
    ) -> String {
        var hasher = Hasher()
        hasher.combine(content)
        for ref in sourceRefs {
            hasher.combine(ref.uuid)
            hasher.combine(ref.title)
        }
        return "\(messageID?.uuidString ?? "-")|\(content.utf16.count)|\(hasher.finalize())|\(isStreaming ? "s" : "f")|\(DS.palette.name)"
    }

    @MainActor
    static func render(
        markdown: String,
        sourceRefs: [CosmoAssistantSourceRef],
        isStreaming: Bool,
        messageID: UUID? = nil
    ) -> CosmoAssistantRenderedAnswer {
        render(
            markdown: markdown,
            sourceRefs: sourceRefs,
            isStreaming: isStreaming,
            palette: .current,
            key: cacheKey(messageID: messageID, content: markdown, sourceRefs: sourceRefs, isStreaming: isStreaming)
        )
    }

    /// Palette-explicit variant — pure, testable off the main actor.
    static func render(
        markdown: String,
        sourceRefs: [CosmoAssistantSourceRef],
        isStreaming: Bool,
        palette: Palette,
        key: String = ""
    ) -> CosmoAssistantRenderedAnswer {
        var source = markdown
        if isStreaming {
            source = hidingTrailingPartialMarker(in: source)
        }
        guard !source.isEmpty else {
            return CosmoAssistantRenderedAnswer(key: key, attributed: NSAttributedString(), linkedRefUUIDs: [])
        }

        // Pass 1 — explicit [[uuid]] markers become placeholders.
        let markerResult = CosmoAssistantProseParser.markerSegments(answer: source, sourceRefs: sourceRefs)
        var pills: [CosmoAssistantSourceRef] = []
        var joined = ""
        for segment in markerResult.segments {
            switch segment {
            case .text(let run):
                joined += run
            case .pill(let ref):
                pills.append(ref)
                joined.append(pillPlaceholder)
            }
        }
        var linked = markerResult.linkedRefUUIDs

        // Pass 2 — Markdown structure.
        let blocks = parseBlocks(from: joined)

        // Pass 3 — attributed text.
        let builder = Builder(palette: palette, pills: pills)
        let output = builder.build(blocks: blocks)

        // Pass 4 — title auto-link over the finished prose (never inside code,
        // links, or existing pills).
        autoLink(in: output, sourceRefs: sourceRefs, linked: &linked, palette: palette)

        return CosmoAssistantRenderedAnswer(key: key, attributed: output, linkedRefUUIDs: linked)
    }

    /// Hide an incomplete trailing marker ("…see [[a1b2" mid-stream) so raw
    /// grammar never flashes on screen.
    static func hidingTrailingPartialMarker(in text: String) -> String {
        if let lastOpen = text.range(of: "[[", options: .backwards),
           text.range(of: "]]", options: .backwards, range: lastOpen.upperBound..<text.endIndex) == nil {
            return String(text[..<lastOpen.lowerBound])
        }
        return text
    }

    // MARK: Block model

    enum BlockKind: Equatable {
        case paragraph
        case heading(level: Int)
        case listItem(depth: Int, ordinal: Int?)
        case quote
        case code
        case thematicBreak
        case tableCell(tableID: Int, rowID: Int, column: Int, isHeader: Bool, columnCount: Int)
    }

    struct InlineStyle: Equatable {
        static let none = InlineStyle(bold: false, italic: false, code: false, strikethrough: false)
        var bold: Bool
        var italic: Bool
        var code: Bool
        var strikethrough: Bool

        init(bold: Bool, italic: Bool, code: Bool, strikethrough: Bool) {
            self.bold = bold
            self.italic = italic
            self.code = code
            self.strikethrough = strikethrough
        }
    }

    enum Inline: Equatable {
        case text(String, InlineStyle, link: URL?)
        case pill(Int)
        case lineBreak
    }

    struct Block: Equatable {
        var kind: BlockKind
        var inlines: [Inline]
        /// True when a quote wraps this block (quotes carry paragraphs / lists).
        var inQuote: Bool
    }

    /// Splits `text` into blocks using Foundation's Markdown parser. Block
    /// boundaries come from `presentationIntent` identities — the string itself
    /// carries no newlines between blocks.
    static func parseBlocks(from text: String) -> [Block] {
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: false,
            interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        guard let attributed = try? AttributedString(markdown: text, options: options) else {
            return [Block(kind: .paragraph, inlines: plainInlines(from: text), inQuote: false)]
        }

        var blocks: [Block] = []
        var currentID: String?
        var pillCursor = 0

        for run in attributed.runs {
            let runText = String(attributed[run.range].characters)
            let components = run.presentationIntent?.components ?? []
            let blockID = components.map { "\($0.identity)" }.joined(separator: ":")
            let kind = blockKind(for: components)
            let inQuote = components.contains { if case .blockQuote = $0.kind { return true }; return false }

            if blockID != currentID || blocks.isEmpty {
                blocks.append(Block(kind: kind, inlines: [], inQuote: inQuote))
                currentID = blockID
            }

            let intent = run.inlinePresentationIntent ?? []
            if intent.contains(.lineBreak) || intent.contains(.softBreak) {
                blocks[blocks.count - 1].inlines.append(.lineBreak)
                continue
            }

            let style = InlineStyle(
                bold: intent.contains(.stronglyEmphasized),
                italic: intent.contains(.emphasized),
                code: intent.contains(.code) || kind == .code,
                strikethrough: intent.contains(.strikethrough)
            )
            let link = run.link

            // Placeholders inside the run become pills in document order.
            var buffer = ""
            for character in runText {
                if character == pillPlaceholder {
                    if !buffer.isEmpty {
                        blocks[blocks.count - 1].inlines.append(.text(buffer, style, link: link))
                        buffer = ""
                    }
                    blocks[blocks.count - 1].inlines.append(.pill(pillCursor))
                    pillCursor += 1
                } else {
                    buffer.append(character)
                }
            }
            if !buffer.isEmpty {
                blocks[blocks.count - 1].inlines.append(.text(buffer, style, link: link))
            }
        }

        return blocks.filter { !$0.inlines.isEmpty || $0.kind == .thematicBreak }
    }

    private static func plainInlines(from text: String) -> [Inline] {
        var inlines: [Inline] = []
        var pillCursor = 0
        var buffer = ""
        for character in text {
            if character == pillPlaceholder {
                if !buffer.isEmpty { inlines.append(.text(buffer, .none, link: nil)); buffer = "" }
                inlines.append(.pill(pillCursor))
                pillCursor += 1
            } else {
                buffer.append(character)
            }
        }
        if !buffer.isEmpty { inlines.append(.text(buffer, .none, link: nil)) }
        return inlines
    }

    /// Block kind from an intent's components. Order-agnostic: Foundation
    /// documents no ordering guarantee, so leaf kinds are matched by presence
    /// and list nesting by counting list-item components.
    static func blockKind(for components: [PresentationIntent.IntentType]) -> BlockKind {
        var listDepth = 0
        var innermostOrdinal: Int?
        var listKinds: [Bool] = []   // true = ordered, in component order
        var listItemPositions: [Int] = []
        var header: Int?
        var isCode = false
        var isBreak = false
        var tableCell: Int?
        var tableRow: Int?
        var tableHeader = false
        var tableID: Int?
        var columnCount = 0

        for (index, component) in components.enumerated() {
            switch component.kind {
            case .header(let level):
                header = level
            case .codeBlock:
                isCode = true
            case .thematicBreak:
                isBreak = true
            case .listItem(let ordinal):
                listDepth += 1
                listItemPositions.append(index)
                if innermostOrdinal == nil { innermostOrdinal = ordinal }
            case .orderedList:
                listKinds.append(true)
            case .unorderedList:
                listKinds.append(false)
            case .tableCell(let column):
                tableCell = column
            case .tableRow(let rowIndex):
                tableRow = rowIndex
            case .tableHeaderRow:
                tableHeader = true
                tableRow = -1
            case .table(let columns):
                tableID = component.identity
                columnCount = columns.count
            default:
                break
            }
        }

        if let tableCell, let tableID, let tableRow {
            return .tableCell(tableID: tableID, rowID: tableRow, column: tableCell, isHeader: tableHeader, columnCount: columnCount)
        }
        if isCode { return .code }
        if isBreak { return .thematicBreak }
        if let header { return .heading(level: header) }
        if listDepth > 0 {
            // The innermost list item is the first one encountered when
            // components run innermost-first, the last one otherwise; its
            // list kind sits in the matching position.
            let innermostFirst = (listItemPositions.first ?? 0) < (components.firstIndex { if case .orderedList = $0.kind { return true }; if case .unorderedList = $0.kind { return true }; return false } ?? Int.max)
            let ordered = innermostFirst ? (listKinds.first ?? false) : (listKinds.last ?? false)
            let ordinalForInnermost: Int?
            if innermostFirst {
                ordinalForInnermost = innermostOrdinal
            } else if case .listItem(let ordinal) = components[listItemPositions.last ?? 0].kind {
                ordinalForInnermost = ordinal
            } else {
                ordinalForInnermost = innermostOrdinal
            }
            return .listItem(depth: listDepth - 1, ordinal: ordered ? ordinalForInnermost : nil)
        }
        return .paragraph
    }

    // MARK: Attributed builder

    private final class Builder {
        let palette: Palette
        let pills: [CosmoAssistantSourceRef]
        let output = NSMutableAttributedString()

        init(palette: Palette, pills: [CosmoAssistantSourceRef]) {
            self.palette = palette
            self.pills = pills
        }

        func build(blocks: [Block]) -> NSMutableAttributedString {
            var index = 0
            while index < blocks.count {
                let block = blocks[index]
                if case .tableCell(let tableID, _, _, _, let columnCount) = block.kind {
                    // Consume the whole table.
                    var cells: [Block] = []
                    while index < blocks.count, case .tableCell(let id, _, _, _, _) = blocks[index].kind, id == tableID {
                        cells.append(blocks[index])
                        index += 1
                    }
                    appendTable(cells: cells, columnCount: max(columnCount, 1), isLast: index >= blocks.count)
                    continue
                }
                let isLast = index == blocks.count - 1
                appendBlock(block, isLast: isLast)
                index += 1
            }
            return output
        }

        // MARK: Fonts

        func font(for style: InlineStyle, base: NSFont) -> NSFont {
            if style.code {
                return NSFont.monospacedSystemFont(ofSize: base.pointSize - 1.5, weight: style.bold ? .semibold : .regular)
            }
            var traits: NSFontDescriptor.SymbolicTraits = []
            if style.bold { traits.insert(.bold) }
            if style.italic { traits.insert(.italic) }
            guard !traits.isEmpty else { return base }
            let descriptor = base.fontDescriptor.withSymbolicTraits(traits)
            if style.bold, !style.italic {
                // System semibold reads cleaner than the synthesized bold trait.
                return NSFont.systemFont(ofSize: base.pointSize, weight: .semibold)
            }
            return NSFont(descriptor: descriptor, size: base.pointSize) ?? base
        }

        func baseFont(for kind: BlockKind) -> NSFont {
            switch kind {
            case .heading(let level):
                switch level {
                case 1: return NSFont.systemFont(ofSize: 20, weight: .semibold)
                case 2: return NSFont.systemFont(ofSize: 17, weight: .semibold)
                case 3: return NSFont.systemFont(ofSize: 15, weight: .semibold)
                default: return NSFont.systemFont(ofSize: 15, weight: .medium)
                }
            case .code:
                return NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
            case .tableCell(_, _, _, let isHeader, _):
                return NSFont.systemFont(ofSize: 13.5, weight: isHeader ? .semibold : .regular)
            default:
                return NSFont.systemFont(ofSize: CosmoAssistantMarkdownRenderer.bodySize)
            }
        }

        // MARK: Paragraph styles

        func paragraphStyle(
            for block: Block,
            isFirstLine: Bool,
            isLastLine: Bool,
            isLastBlock: Bool
        ) -> NSParagraphStyle {
            let style = NSMutableParagraphStyle()
            style.lineSpacing = CosmoAssistantMarkdownRenderer.lineSpacing
            style.lineBreakMode = .byWordWrapping
            let quoteInset: CGFloat = block.inQuote && block.kind != .quote
                ? CosmoAssistantMarkdownRenderer.blockInset + CosmoAssistantMarkdownRenderer.quoteBarWidth
                : 0

            switch block.kind {
            case .paragraph, .quote:
                if block.inQuote || block.kind == .quote {
                    style.firstLineHeadIndent = CosmoAssistantMarkdownRenderer.blockInset + CosmoAssistantMarkdownRenderer.quoteBarWidth
                    style.headIndent = style.firstLineHeadIndent
                    style.tailIndent = -CosmoAssistantMarkdownRenderer.blockInset
                    style.paragraphSpacingBefore = isFirstLine ? CosmoAssistantMarkdownRenderer.blockVerticalPad : 0
                    style.paragraphSpacing = isLastLine ? CosmoAssistantMarkdownRenderer.blockVerticalPad : 0
                } else {
                    style.paragraphSpacing = isLastLine && !isLastBlock ? CosmoAssistantMarkdownRenderer.paragraphGap : 0
                }
            case .heading(let level):
                style.paragraphSpacingBefore = isFirstLine ? (level <= 2 ? 6 : 4) : 0
                style.paragraphSpacing = isLastLine ? (level <= 2 ? 4 : 2) : 0
            case .listItem(let depth, _):
                let marker = CosmoAssistantMarkdownRenderer.listIndent * CGFloat(depth) + quoteInset
                let textStart = marker + CosmoAssistantMarkdownRenderer.listMarkerWidth
                style.firstLineHeadIndent = isFirstLine ? marker : textStart
                style.headIndent = textStart
                style.tabStops = [NSTextTab(textAlignment: .left, location: textStart, options: [:])]
                style.defaultTabInterval = textStart
                style.paragraphSpacing = isLastLine ? (isLastBlock ? 0 : CosmoAssistantMarkdownRenderer.listItemGap) : 0
                if block.inQuote { style.tailIndent = -CosmoAssistantMarkdownRenderer.blockInset }
            case .code:
                style.firstLineHeadIndent = CosmoAssistantMarkdownRenderer.blockInset
                style.headIndent = CosmoAssistantMarkdownRenderer.blockInset
                style.tailIndent = -CosmoAssistantMarkdownRenderer.blockInset
                style.lineBreakMode = .byCharWrapping
                style.paragraphSpacingBefore = isFirstLine ? CosmoAssistantMarkdownRenderer.blockVerticalPad : 0
                style.paragraphSpacing = isLastLine ? CosmoAssistantMarkdownRenderer.blockVerticalPad : 0
                style.lineSpacing = 2
            case .thematicBreak:
                style.paragraphSpacingBefore = 6
                style.paragraphSpacing = 6
            case .tableCell:
                style.lineSpacing = 1
            }
            return style
        }

        // MARK: Blocks

        func appendBlock(_ block: Block, isLast: Bool) {
            let start = output.length
            if start > 0 {
                output.append(NSAttributedString(string: "\n", attributes: lastLineAttributes()))
            }
            let blockStart = output.length

            switch block.kind {
            case .thematicBreak:
                output.append(NSAttributedString(string: "\u{2009}", attributes: [
                    .font: NSFont.systemFont(ofSize: 4),
                    .foregroundColor: NSColor.clear,
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                    .strikethroughColor: palette.blockBorder
                ]))
            case .listItem(let depth, let ordinal):
                let marker: String
                if let ordinal {
                    marker = "\(ordinal)."
                } else {
                    marker = ["•", "◦", "▪"][min(depth, 2)]
                }
                let markerFont = ordinal != nil
                    ? NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
                    : NSFont.systemFont(ofSize: CosmoAssistantMarkdownRenderer.bodySize, weight: .semibold)
                output.append(NSAttributedString(string: marker + "\t", attributes: [
                    .font: markerFont,
                    .foregroundColor: palette.accent
                ]))
                appendInlines(block.inlines, block: block)
            default:
                appendInlines(block.inlines, block: block)
            }

            let blockRange = NSRange(location: blockStart, length: output.length - blockStart)
            applyParagraphStyles(block: block, range: blockRange, isLastBlock: isLast)

            let decoration: CosmoProseBlockDecoration? = block.kind == .code ? .code : ((block.inQuote || block.kind == .quote) ? .quote : nil)
            if let decoration, blockRange.length > 0 {
                output.addAttribute(.cosmoProseBlock, value: decoration.rawValue, range: blockRange)
            }
        }

        func lastLineAttributes() -> [NSAttributedString.Key: Any] {
            guard output.length > 0 else { return [:] }
            var attributes = output.attributes(at: output.length - 1, effectiveRange: nil)
            attributes.removeValue(forKey: .attachment)
            attributes.removeValue(forKey: .link)
            attributes.removeValue(forKey: .cosmoProseInlineCode)
            return attributes
        }

        func appendInlines(_ inlines: [Inline], block: Block) {
            let base = baseFont(for: block.kind)
            let isReceipt = CosmoAssistantMarkdownRenderer.isReceiptParagraph(block)
            let plainText = CosmoAssistantMarkdownRenderer.plainText(of: block)
            let bodyColor: NSColor
            if isReceipt {
                bodyColor = palette.muted
            } else if plainText.hasPrefix("Current:") {
                bodyColor = palette.secondary
            } else if case .tableCell(_, _, _, let isHeader, _) = block.kind, isHeader {
                bodyColor = palette.secondary
            } else {
                bodyColor = palette.text
            }

            for inline in inlines {
                switch inline {
                case .lineBreak:
                    output.append(NSAttributedString(string: "\n", attributes: [.font: base, .foregroundColor: bodyColor]))
                case .pill(let index):
                    guard index < pills.count else { continue }
                    let attachment = CosmoMentionPillAttachment(sourceRef: pills[index])
                    let pill = NSMutableAttributedString(attachment: attachment)
                    pill.addAttributes([
                        .link: pills[index].uuid as NSString,
                        // Baseline math in the cell assumes the surrounding font.
                        .font: NSFont.systemFont(ofSize: CosmoAssistantMarkdownRenderer.bodySize)
                    ], range: NSRange(location: 0, length: pill.length))
                    output.append(pill)
                case .text(let text, let style, let link):
                    var attributes: [NSAttributedString.Key: Any] = [
                        .font: isReceipt
                            ? NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
                            : font(for: style, base: base),
                        .foregroundColor: bodyColor
                    ]
                    if style.strikethrough {
                        attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                        attributes[.foregroundColor] = palette.muted
                    }
                    if style.code, block.kind != .code {
                        attributes[.cosmoProseInlineCode] = true
                    }
                    if let link {
                        attributes[.link] = link
                        attributes[.foregroundColor] = palette.accent
                    }
                    output.append(NSAttributedString(string: text, attributes: attributes))
                }
            }
        }

        func applyParagraphStyles(block: Block, range: NSRange, isLastBlock: Bool) {
            guard range.length > 0 else { return }
            let nsString = output.string as NSString
            var location = range.location
            var lineRanges: [NSRange] = []
            while location < NSMaxRange(range) {
                let paragraph = nsString.paragraphRange(for: NSRange(location: location, length: 0))
                let clipped = NSIntersectionRange(paragraph, range)
                lineRanges.append(clipped)
                location = NSMaxRange(paragraph)
                if paragraph.length == 0 { break }
            }
            for (index, lineRange) in lineRanges.enumerated() {
                let style = paragraphStyle(
                    for: block,
                    isFirstLine: index == 0,
                    isLastLine: index == lineRanges.count - 1,
                    isLastBlock: isLastBlock
                )
                output.addAttribute(.paragraphStyle, value: style, range: lineRange)
            }
        }

        // MARK: Tables

        func appendTable(cells: [Block], columnCount: Int, isLast: Bool) {
            if output.length > 0 {
                output.append(NSAttributedString(string: "\n", attributes: lastLineAttributes()))
            }
            let table = NSTextTable()
            table.numberOfColumns = columnCount
            table.layoutAlgorithm = .automaticLayoutAlgorithm
            table.collapsesBorders = true
            table.hidesEmptyCells = false

            // Row ids in document order → 0-based row numbers.
            var rowOrder: [Int] = []
            for cell in cells {
                if case .tableCell(_, let rowID, _, _, _) = cell.kind, !rowOrder.contains(rowID) {
                    rowOrder.append(rowID)
                }
            }

            for (cellIndex, cell) in cells.enumerated() {
                guard case .tableCell(_, let rowID, let column, let isHeader, _) = cell.kind,
                      let row = rowOrder.firstIndex(of: rowID) else { continue }
                let block = NSTextTableBlock(table: table, startingRow: row, rowSpan: 1, startingColumn: column, columnSpan: 1)
                block.setWidth(1, type: .absoluteValueType, for: .border)
                block.setBorderColor(palette.blockBorder)
                block.setWidth(7, type: .absoluteValueType, for: .padding)
                block.verticalAlignment = .topAlignment
                if isHeader {
                    block.backgroundColor = palette.blockFill
                }

                let cellStart = output.length
                appendInlines(cell.inlines, block: cell)
                if output.length == cellStart {
                    output.append(NSAttributedString(string: " ", attributes: [.font: baseFont(for: cell.kind)]))
                }
                let isLastCell = cellIndex == cells.count - 1
                // Every table cell paragraph ends with a newline, including the
                // last one when more content follows; the final cell of the
                // final block ends the document without one.
                if !(isLastCell && isLast) {
                    output.append(NSAttributedString(string: "\n", attributes: [.font: baseFont(for: cell.kind)]))
                }
                let cellRange = NSRange(location: cellStart, length: output.length - cellStart)
                let style = NSMutableParagraphStyle()
                style.textBlocks = [block]
                style.lineSpacing = 1
                style.paragraphSpacing = 0
                output.addAttribute(.paragraphStyle, value: style, range: cellRange)
            }
        }
    }

    // MARK: Helpers

    static func plainText(of block: Block) -> String {
        block.inlines.map { inline -> String in
            if case .text(let text, _, _) = inline { return text }
            if case .lineBreak = inline { return "\n" }
            return ""
        }.joined()
    }

    /// The craft skills end answers with an italic cost receipt
    /// ("_≈$0.28 · 13.3K in (0% cached) · 7.1K out_") — muted caption, not prose.
    static func isReceiptParagraph(_ block: Block) -> Bool {
        guard block.kind == .paragraph else { return false }
        let textInlines = block.inlines.compactMap { inline -> (String, InlineStyle)? in
            if case .text(let text, let style, _) = inline { return (text, style) }
            return nil
        }
        guard !textInlines.isEmpty, textInlines.allSatisfy({ $0.1.italic }) else { return false }
        let text = textInlines.map(\.0).joined()
        return text.contains(" out") || text.contains(" cached")
    }

    // MARK: Auto-link pass

    /// The first word-bounded occurrence of each remaining source title becomes
    /// a pill — longest titles first so overlaps resolve deterministically.
    /// Ranges inside code, links, or existing attachments are never linked.
    static func autoLink(
        in output: NSMutableAttributedString,
        sourceRefs: [CosmoAssistantSourceRef],
        linked: inout Set<String>,
        palette: Palette
    ) {
        let candidates = sourceRefs
            .filter { ref in
                guard !linked.contains(ref.uuid) else { return false }
                let title = ref.title.trimmingCharacters(in: .whitespacesAndNewlines)
                return title.count >= CosmoAssistantProseParser.minimumAutoLinkTitleLength
                    && title.caseInsensitiveCompare("Untitled") != .orderedSame
            }
            .sorted { $0.title.count > $1.title.count }

        for ref in candidates {
            let title = ref.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let range = firstLinkableOccurrence(of: title, in: output) else { continue }
            let font = (output.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont)
                ?? NSFont.systemFont(ofSize: bodySize)
            let paragraph = output.attribute(.paragraphStyle, at: range.location, effectiveRange: nil)
            let attachment = CosmoMentionPillAttachment(sourceRef: ref)
            let pill = NSMutableAttributedString(attachment: attachment)
            var attributes: [NSAttributedString.Key: Any] = [
                .link: ref.uuid as NSString,
                .font: NSFont.systemFont(ofSize: font.pointSize)
            ]
            if let paragraph { attributes[.paragraphStyle] = paragraph }
            pill.addAttributes(attributes, range: NSRange(location: 0, length: pill.length))
            output.replaceCharacters(in: range, with: pill)
            linked.insert(ref.uuid)
        }
    }

    private static func firstLinkableOccurrence(of title: String, in output: NSAttributedString) -> NSRange? {
        let nsString = output.string as NSString
        var searchLocation = 0
        while searchLocation < nsString.length {
            let searchRange = NSRange(location: searchLocation, length: nsString.length - searchLocation)
            let found = nsString.range(of: title, options: [.caseInsensitive], range: searchRange)
            guard found.location != NSNotFound else { return nil }
            if isWordBounded(found, in: nsString), isLinkable(found, in: output) {
                return found
            }
            searchLocation = found.location + max(found.length, 1)
        }
        return nil
    }

    private static func isLinkable(_ range: NSRange, in output: NSAttributedString) -> Bool {
        var linkable = true
        output.enumerateAttributes(in: range, options: []) { attributes, _, stop in
            if attributes[.link] != nil
                || attributes[.attachment] != nil
                || attributes[.cosmoProseInlineCode] != nil
                || (attributes[.cosmoProseBlock] as? String) == CosmoProseBlockDecoration.code.rawValue {
                linkable = false
                stop.pointee = true
            }
        }
        return linkable
    }

    private static func isWordBounded(_ range: NSRange, in text: NSString) -> Bool {
        func isWordCharacter(at location: Int) -> Bool {
            guard location >= 0, location < text.length else { return false }
            let character = text.substring(with: NSRange(location: location, length: 1))
            guard let scalar = character.unicodeScalars.first else { return false }
            return CharacterSet.alphanumerics.contains(scalar) || character == "_"
        }
        return !isWordCharacter(at: range.location - 1)
            && !isWordCharacter(at: range.location + range.length)
    }
}

// MARK: - Render cache

/// Finalized answers render once per (content, refs, palette) and are served
/// from here on every later body evaluation — the transcript re-evaluates its
/// rows on every store publish, and re-parsing every answer's Markdown per
/// publish was O(transcript) main-thread work per streamed token.
@MainActor
final class CosmoAssistantAnswerRenderCache {
    static let shared = CosmoAssistantAnswerRenderCache()

    private var entries: [String: CosmoAssistantRenderedAnswer] = [:]
    private var order: [String] = []
    private let capacity: Int

    init(capacity: Int = 96) {
        self.capacity = capacity
    }

    func rendered(for message: CosmoInlineAssistantPaneMessage) -> CosmoAssistantRenderedAnswer {
        rendered(content: message.content, sourceRefs: message.sourceRefs ?? [], messageID: message.id)
    }

    func rendered(
        content: String,
        sourceRefs: [CosmoAssistantSourceRef],
        messageID: UUID
    ) -> CosmoAssistantRenderedAnswer {
        let key = CosmoAssistantMarkdownRenderer.cacheKey(
            messageID: messageID,
            content: content,
            sourceRefs: sourceRefs,
            isStreaming: false
        )
        if let hit = entries[key] { return hit }
        let rendered = CosmoAssistantMarkdownRenderer.render(
            markdown: content,
            sourceRefs: sourceRefs,
            isStreaming: false,
            messageID: messageID
        )
        entries[key] = rendered
        order.append(key)
        if order.count > capacity, let evicted = order.first {
            order.removeFirst()
            entries.removeValue(forKey: evicted)
        }
        return rendered
    }

    var count: Int { entries.count }

    func removeAll() {
        entries.removeAll()
        order.removeAll()
    }
}

// MARK: - Inline Markdown for short model strings

extension Text {
    /// Proposal summaries, rationales, and other one-liners the model writes
    /// may carry inline Markdown; render it instead of showing the asterisks.
    init(cosmoInlineMarkdown source: String) {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        if source.contains("*") || source.contains("_") || source.contains("`") || source.contains("~~"),
           let attributed = try? AttributedString(markdown: source, options: options) {
            self.init(attributed)
        } else {
            self.init(verbatim: source)
        }
    }
}
