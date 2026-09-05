// TWIN FILE — byte-identical in CosmoOS-Swift/Editor/Clipboard and
// CosmoOS-iOS/CosmoCoreKit/Sources/Models. Verified by Tools/verify_twins.sh.
//
// HTML → blocks. Google Docs, Sheets, Excel, Numbers, Notion and web pages
// all arrive here through `CosmoHTMLReader`. The mapping is deliberately
// conservative: structure we can represent becomes real blocks, everything
// else becomes clean paragraphs, and nothing is ever dropped silently except
// whitespace-only paragraphs (Google Docs emits `<p>&nbsp;</p>` for blank
// lines; the page's own rhythm replaces them).

import Foundation

public enum HTMLBlockImporter {
    static func blocks(fromHTML html: String) -> [RichBlock] {
        blocks(from: CosmoHTMLReader.parse(html))
    }

    static func blocks(from root: HTMLNode) -> [RichBlock] {
        var builder = Builder()
        builder.walk(root, style: InlineStyle())
        builder.flushParagraph()
        return builder.blocks
    }

    /// Exactly one paragraph with nothing structural — an inline paste.
    static func isSingleInlineParagraph(_ blocks: [RichBlock]) -> Bool {
        blocks.count == 1 && blocks[0].kind == .paragraph
    }

    // MARK: Inline style accumulation

    struct InlineStyle {
        var bold = false
        var italic = false
        var underline = false
        var strikethrough = false
        var inkID: String? = nil
        var highlightID: String? = nil
        var href: String? = nil
        var preformatted = false

        var marks: Set<RichTextMark> {
            var set: Set<RichTextMark> = []
            if bold { set.insert(.bold) }
            if italic { set.insert(.italic) }
            if underline { set.insert(.underline) }
            if strikethrough { set.insert(.strikethrough) }
            return set
        }

        /// Applies a node's tag and inline CSS on top of the inherited style.
        func applying(_ node: HTMLNode) -> InlineStyle {
            var next = self
            switch node.name {
            case "b", "strong": next.bold = true
            case "i", "em", "cite", "var": next.italic = true
            case "u", "ins": next.underline = true
            case "s", "strike", "del": next.strikethrough = true
            case "pre", "code", "kbd", "samp": next.preformatted = node.name == "pre" ? true : next.preformatted
            case "a":
                if let href = node.attr("href")?.trimmingCharacters(in: .whitespacesAndNewlines),
                   let scheme = URL(string: href)?.scheme?.lowercased(),
                   ["http", "https", "mailto"].contains(scheme) {
                    next.href = href
                }
            default: break
            }
            let style = node.style
            if let weight = style["font-weight"] {
                let value = weight.trimmingCharacters(in: .whitespaces).lowercased()
                if value == "bold" || value == "bolder" {
                    next.bold = true
                } else if value == "normal" || value == "lighter" {
                    // Google Docs wraps the whole clip in <b style="font-weight:normal">.
                    next.bold = false
                } else if let number = Double(value.replacingOccurrences(of: "px", with: "")) {
                    next.bold = number >= 600
                }
            }
            if let fontStyle = style["font-style"] {
                let value = fontStyle.lowercased()
                if value.contains("italic") || value.contains("oblique") { next.italic = true }
                if value == "normal" { next.italic = false }
            }
            if let decoration = style["text-decoration"] ?? style["text-decoration-line"] {
                let value = decoration.lowercased()
                if value.contains("underline") { next.underline = true }
                if value.contains("line-through") { next.strikethrough = true }
                if value == "none" { next.underline = false; next.strikethrough = false }
            }
            if let color = style["color"] {
                next.inkID = RichInlineColor.nearestInkTone(for: color)
            }
            if let background = style["background-color"] ?? style["background"] {
                if let tone = RichInlineColor.nearestHighlightTone(for: background) {
                    next.highlightID = tone
                } else if RichInlineColor.parse(background) != nil {
                    next.highlightID = nil
                }
            }
            if node.name == "mark" { next.highlightID = next.highlightID ?? "gilt" }
            return next
        }
    }

    // MARK: Builder

    struct Builder {
        var blocks: [RichBlock] = []
        private var paragraph: [RichInlineNode] = []
        private var paragraphKind: RichBlockKind = .paragraph
        private var paragraphChecked: Bool? = nil
        private var pendingSoftBreak = false
        private var listStack: [RichBlockKind] = []
        private var quoteDepth = 0

        static let blockTags: Set<String> = [
            "p", "div", "h1", "h2", "h3", "h4", "h5", "h6", "ul", "ol", "li", "table", "tr", "td", "th",
            "blockquote", "pre", "hr", "section", "article", "header", "footer", "nav", "aside", "figure",
            "figcaption", "main", "details", "summary", "dl", "dt", "dd", "address", "form", "fieldset", "center",
        ]

        static let droppedTags: Set<String> = ["script", "style", "head", "template", "noscript", "title", "meta", "link", "iframe", "object", "svg", "canvas", "button", "input", "select", "textarea", "nav"]

        mutating func walk(_ node: HTMLNode, style: InlineStyle) {
            if node.isText {
                appendText(node.text, style: style)
                return
            }
            if Builder.droppedTags.contains(node.name) { return }
            let inherited = style.applying(node)
            switch node.name {
            case "#document", "html", "body", "span", "font", "b", "strong", "i", "em", "u", "ins", "s", "strike", "del",
                 "a", "code", "kbd", "samp", "var", "cite", "mark", "small", "big", "sub", "sup", "abbr", "time", "label", "tt",
                 "bdi", "bdo", "q", "dfn", "wbr", "data", "output", "ruby", "rt", "rp":
                for child in node.children { walk(child, style: inherited) }
            case "br":
                pendingSoftBreak = true
            case "h1", "h2", "h3", "h4", "h5", "h6":
                openBlockBoundary()
                let level = Int(String(node.name.dropFirst())) ?? 3
                paragraphKind = level == 1 ? .heading1 : (level == 2 ? .heading2 : .heading3)
                for child in node.children { walk(child, style: inherited) }
                flushParagraph()
            case "p", "div", "section", "article", "header", "footer", "nav", "aside", "figure", "figcaption", "main",
                 "details", "summary", "dl", "dt", "dd", "address", "form", "fieldset", "center":
                let isBlockBoundary = node.name != "div" || !node.elementChildren.isEmpty || node.children.contains { $0.isText }
                if isBlockBoundary { openBlockBoundary() }
                if node.name == "p", node.hasClass("title") { paragraphKind = .heading1 }
                if node.name == "p", node.hasClass("subtitle") { paragraphKind = .heading2 }
                for child in node.children { walk(child, style: inherited) }
                if isBlockBoundary { flushParagraph() }
            case "ul", "ol":
                flushParagraph()
                listStack.append(node.name == "ol" ? .numberedList : .bulletList)
                for child in node.children { walk(child, style: inherited) }
                listStack.removeLast()
                flushParagraph()
            case "li":
                flushParagraph()
                let (kind, checked) = listItemKind(node)
                paragraphKind = kind
                paragraphChecked = checked
                for child in node.children {
                    // Nested lists flatten: close the item before them.
                    if child.name == "ul" || child.name == "ol" {
                        flushParagraph()
                        walk(child, style: inherited)
                        continue
                    }
                    walk(child, style: inherited)
                }
                flushParagraph()
            case "blockquote":
                flushParagraph()
                quoteDepth += 1
                for child in node.children { walk(child, style: inherited) }
                flushParagraph()
                quoteDepth -= 1
            case "pre":
                flushParagraph()
                appendCode(node)
            case "hr":
                flushParagraph()
                blocks.append(RichBlock(kind: .divider))
            case "img":
                if let image = imageBlock(node) {
                    flushParagraph()
                    blocks.append(image)
                }
            case "table":
                flushParagraph()
                if let table = TableImporter.table(from: node, style: inherited) {
                    blocks.append(RichBlock(kind: .table, table: table))
                }
            case "tr", "td", "th", "thead", "tbody", "tfoot", "caption", "colgroup", "col":
                // Stray table parts outside a table: treat as text.
                for child in node.children { walk(child, style: inherited) }
            default:
                for child in node.children { walk(child, style: inherited) }
            }
        }

        private func listItemKind(_ node: HTMLNode) -> (RichBlockKind, Bool?) {
            let base = listStack.last ?? .bulletList
            if node.attr("role")?.lowercased() == "checkbox" {
                let checked = (node.attr("aria-checked") ?? "false").lowercased() == "true"
                return (.checklist, checked)
            }
            let text = node.innerText.trimmingCharacters(in: .whitespaces)
            if text.hasPrefix("☐") || text.hasPrefix("[ ]") { return (.checklist, false) }
            if text.hasPrefix("☑") || text.hasPrefix("☒") || text.lowercased().hasPrefix("[x]") { return (.checklist, true) }
            if node.style["list-style-type"]?.lowercased() == "decimal" { return (.numberedList, nil) }
            return (base, nil)
        }

        mutating func appendText(_ raw: String, style: InlineStyle) {
            guard !raw.isEmpty else { return }
            var text: String
            if style.preformatted {
                text = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\n", with: "\u{2028}")
            } else {
                // Collapse runs to one space but KEEP a single boundary space
                // on either end — "Just " + "<b>one</b>" + " line" must not
                // fuse into "Justoneline". Paragraph edges are trimmed at
                // flush time.
                text = Builder.collapsedKeepingEdges(raw)
                if paragraph.isEmpty, !pendingSoftBreak {
                    text = String(text.drop { $0 == " " })
                } else if text.hasPrefix(" "), let last = paragraph.last, last.kind == .text, (last.text ?? "").hasSuffix(" ") {
                    text = String(text.dropFirst())
                }
            }
            guard !text.isEmpty else { return }
            if pendingSoftBreak {
                if !paragraph.isEmpty { paragraph.append(.text("\u{2028}")) }
                pendingSoftBreak = false
            }
            let node = RichInlineNode(
                kind: .text,
                text: text,
                marks: style.marks,
                inkID: style.inkID,
                highlightID: style.highlightID,
                href: style.href
            )
            if let last = paragraph.last, last.kind == .text, last.styling == node.styling {
                var merged = last
                merged.text = (last.text ?? "") + text
                paragraph[paragraph.count - 1] = merged
            } else {
                paragraph.append(node)
            }
        }

        static func collapsedKeepingEdges(_ raw: String) -> String {
            var result = ""
            result.reserveCapacity(raw.utf8.count)
            var pendingSpace = false
            for scalar in raw.unicodeScalars {
                if HTMLNode.isCollapsibleWhitespace(scalar) {
                    pendingSpace = true
                } else {
                    if pendingSpace { result.append(" ") }
                    pendingSpace = false
                    result.unicodeScalars.append(scalar)
                }
            }
            if pendingSpace { result.append(" ") }
            return result
        }

        /// Opens a block boundary: text already gathered becomes its own
        /// block, but an EMPTY gathering keeps its kind — a Google Docs
        /// `<li><p>…</p></li>` must not lose the list kind to the inner <p>.
        private mutating func openBlockBoundary() {
            if !paragraph.isEmpty { flushParagraph() }
        }

        mutating func flushParagraph() {
            pendingSoftBreak = false
            defer {
                paragraph = []
                paragraphKind = .paragraph
                paragraphChecked = nil
            }
            // Trim trailing whitespace and drop whitespace-only paragraphs.
            while let last = paragraph.last, last.kind == .text {
                let trimmed = (last.text ?? "").replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
                if trimmed.isEmpty {
                    paragraph.removeLast()
                } else {
                    paragraph[paragraph.count - 1].text = trimmed
                    break
                }
            }
            let plain = paragraph.map(\.plainText).joined()
            guard !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || paragraph.contains(where: { $0.kind != .text }) else { return }
            let kind: RichBlockKind = quoteDepth > 0 && paragraphKind == .paragraph ? .quote : paragraphKind
            blocks.append(RichBlock(kind: kind, inlines: paragraph, checked: kind == .checklist ? (paragraphChecked ?? false) : nil))
        }

        private mutating func appendCode(_ node: HTMLNode) {
            let raw = node.innerTextPreservingLines
            let lines = raw.replacingOccurrences(of: "\r\n", with: "\n")
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)
            var trimmed = lines
            while let first = trimmed.first, first.trimmingCharacters(in: .whitespaces).isEmpty { trimmed.removeFirst() }
            while let last = trimmed.last, last.trimmingCharacters(in: .whitespaces).isEmpty { trimmed.removeLast() }
            guard !trimmed.isEmpty else { return }
            blocks.append(RichBlock(kind: .code, inlines: [.text(trimmed.joined(separator: "\u{2028}"))]))
        }

        private func imageBlock(_ node: HTMLNode) -> RichBlock? {
            guard let source = node.attr("src")?.trimmingCharacters(in: .whitespacesAndNewlines), !source.isEmpty else { return nil }
            let width = Double(node.attr("width") ?? "") ?? 0
            let height = Double(node.attr("height") ?? "") ?? 0
            let reference = RichImageReference(
                path: "",
                width: CGFloat(width),
                height: CGFloat(height),
                remoteURL: source
            )
            return RichBlock(kind: .image, inlines: [.image(reference)])
        }
    }

    // MARK: Tables

    enum TableImporter {
        static func table(from node: HTMLNode, style: InlineStyle) -> RichTable? {
            let rowNodes = tableRows(node)
            guard !rowNodes.isEmpty else { return nil }

            // Occupancy map: row → column → anchor id (spans fill later).
            var grid: [[RichTableCell?]] = []
            var occupancy: [[Bool]] = []
            var columnCount = 0
            var headerRowCount = 0
            var sawBodyRow = false
            var pendingSpans: [(row: Int, column: Int, rowSpan: Int, colSpan: Int, id: UUID)] = []

            for (rowIndex, entry) in rowNodes.enumerated() {
                var row: [RichTableCell?] = []
                var occupied: [Bool] = []
                var column = 0
                func ensure(_ count: Int) {
                    while row.count < count { row.append(nil); occupied.append(false) }
                }
                // Cells covered by spans from rows above.
                let coveredHere = pendingSpans.filter { $0.row < rowIndex && rowIndex < $0.row + $0.rowSpan }
                for cellNode in entry.cells {
                    while true {
                        let covered = coveredHere.contains { $0.column <= column && column < $0.column + $0.colSpan }
                        if covered {
                            ensure(column + 1)
                            occupied[column] = true
                            column += 1
                        } else { break }
                    }
                    let colSpan = max(1, Int(cellNode.attr("colspan") ?? "") ?? 1)
                    let rowSpan = max(1, Int(cellNode.attr("rowspan") ?? "") ?? 1)
                    var cell = cell(from: cellNode, style: style)
                    cell.rowSpan = rowSpan
                    cell.colSpan = colSpan
                    ensure(column + colSpan)
                    row[column] = cell
                    occupied[column] = true
                    for extra in 1..<max(1, colSpan) where column + extra < row.count {
                        occupied[column + extra] = true
                    }
                    if rowSpan > 1 || colSpan > 1 {
                        pendingSpans.append((rowIndex, column, rowSpan, colSpan, cell.id))
                    }
                    column += colSpan
                }
                if entry.isHeader, !sawBodyRow { headerRowCount += 1 } else { sawBodyRow = true }
                columnCount = max(columnCount, row.count, coveredHere.map { $0.column + $0.colSpan }.max() ?? 0)
                grid.append(row)
                occupancy.append(occupied)
            }
            guard columnCount > 0 else { return nil }

            var rows: [RichTableRow] = []
            for (rowIndex, row) in grid.enumerated() {
                var cells: [RichTableCell] = []
                for column in 0..<columnCount {
                    if column < row.count, let cell = row[column] {
                        cells.append(cell)
                    } else if let span = pendingSpans.first(where: { $0.row <= rowIndex && rowIndex < $0.row + $0.rowSpan && $0.column <= column && column < $0.column + $0.colSpan && !($0.row == rowIndex && $0.column == column) }) {
                        cells.append(.covered(by: span.id))
                    } else {
                        cells.append(RichTableCell())
                    }
                }
                rows.append(RichTableRow(cells: cells))
            }

            var table = RichTable(
                columns: (0..<columnCount).map { _ in RichTableColumn() },
                rows: rows,
                hasHeaderRow: headerRowCount >= 1,
                hasHeaderColumn: false
            )
            // Google Docs marks no headers: an all-bold, fully filled first
            // row above at least one body row reads as one.
            if headerRowCount == 0, table.rowCount >= 2 {
                let first = table.rows[0].cells.filter { !$0.isCovered }
                let allFilled = !first.isEmpty && first.allSatisfy { !$0.isEmptyContent }
                let allBold = first.allSatisfy { cell in
                    cell.inlines.filter { $0.kind == .text && !($0.text ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
                        .allSatisfy { $0.marks.contains(.bold) }
                }
                if allFilled, allBold { table.hasHeaderRow = true }
            }
            // Header column: every body row starts with <th>.
            if rowNodes.count > headerRowCount {
                let bodyRows = rowNodes.dropFirst(headerRowCount)
                if !bodyRows.isEmpty, bodyRows.allSatisfy({ $0.cells.first?.name == "th" }) {
                    table.hasHeaderColumn = true
                }
            }
            applyColumnWeights(node, rowNodes: rowNodes, to: &table)
            applyColumnAlignments(rowNodes: rowNodes, to: &table)
            let repaired = table.repaired()
            assert(repaired.validate().isEmpty, "HTML table import produced an invalid grid")
            return repaired.isEmptyContent && repaired.rowCount == 1 && repaired.columnCount == 1 ? nil : repaired
        }

        private struct RowEntry {
            var cells: [HTMLNode]
            var isHeader: Bool
        }

        private static func tableRows(_ table: HTMLNode) -> [RowEntry] {
            var entries: [RowEntry] = []
            func collect(_ node: HTMLNode, inHead: Bool) {
                for child in node.elementChildren {
                    switch child.name {
                    case "thead": collect(child, inHead: true)
                    case "tbody", "tfoot": collect(child, inHead: false)
                    case "tr":
                        let cells = child.elementChildren.filter { $0.name == "td" || $0.name == "th" }
                        let allHeaders = !cells.isEmpty && cells.allSatisfy { $0.name == "th" }
                        entries.append(RowEntry(cells: cells, isHeader: inHead || (entries.isEmpty && allHeaders)))
                    case "table":
                        continue // nested tables flatten inside their cell
                    default:
                        collect(child, inHead: inHead)
                    }
                }
            }
            collect(table, inHead: false)
            return entries
        }

        private static func cell(from node: HTMLNode, style: InlineStyle) -> RichTableCell {
            let cellStyle = style.applying(node)
            var builder = Builder()
            // Everything inside a cell is one paragraph; block children
            // become soft-break separated lines.
            var lines: [[RichInlineNode]] = []
            func flushLine() {
                builder.flushParagraph()
                for block in builder.blocks {
                    var inlines = block.inlines
                    switch block.kind {
                    case .bulletList: inlines.insert(.text("• "), at: 0)
                    case .numberedList: inlines.insert(.text("\(lines.count + 1). "), at: 0)
                    case .checklist: inlines.insert(.text((block.checked ?? false) ? "☑ " : "☐ "), at: 0)
                    case .table:
                        if let nested = block.table { inlines = [.text(nested.tsv().replacingOccurrences(of: "\n", with: "\u{2028}"))] }
                    default: break
                    }
                    if !inlines.isEmpty { lines.append(inlines) }
                }
                builder = Builder()
            }
            for child in node.children {
                builder.walk(child, style: cellStyle)
            }
            flushLine()
            var inlines: [RichInlineNode] = []
            for (index, line) in lines.enumerated() {
                if index > 0 { inlines.append(.text("\u{2028}")) }
                inlines.append(contentsOf: line)
            }
            var cell = RichTableCell(inlines: inlines)
            if let background = node.style["background-color"] ?? node.style["background"] {
                cell.toneID = RichInlineColor.nearestHighlightTone(for: background)
            }
            let innerParagraph = node.elementChildren.first { $0.name == "p" || $0.name == "div" }
            if let align = (node.style["text-align"] ?? node.attr("align") ?? innerParagraph?.style["text-align"])?.lowercased() {
                if align.contains("center") { cell.alignment = .center }
                else if align.contains("right") || align.contains("end") { cell.alignment = .trailing }
            }
            if let valign = (node.style["vertical-align"] ?? node.attr("valign"))?.lowercased() {
                if valign.contains("middle") { cell.verticalAlignment = .middle }
                else if valign.contains("bottom") { cell.verticalAlignment = .bottom }
            }
            return cell
        }

        private static func applyColumnWeights(_ table: HTMLNode, rowNodes: [RowEntry], to result: inout RichTable) {
            var widths: [Double] = Array(repeating: 0, count: result.columnCount)
            let cols = table.descendants(named: "col")
            if !cols.isEmpty {
                for (index, col) in cols.enumerated() where index < widths.count {
                    widths[index] = numericWidth(col.attr("width") ?? col.style["width"])
                }
            }
            if widths.allSatisfy({ $0 <= 0 }), let first = rowNodes.first {
                var column = 0
                for cell in first.cells where column < widths.count {
                    let span = max(1, Int(cell.attr("colspan") ?? "") ?? 1)
                    if span == 1 {
                        widths[column] = numericWidth(cell.attr("width") ?? cell.style["width"])
                    }
                    column += span
                }
            }
            guard widths.contains(where: { $0 > 0 }) else { return }
            let fallback = widths.filter { $0 > 0 }.reduce(0, +) / Double(max(1, widths.filter { $0 > 0 }.count))
            for index in result.columns.indices {
                let width = widths[index] > 0 ? widths[index] : fallback
                result.columns[index].weight = max(0.05, width / max(fallback, 1))
            }
        }

        private static func numericWidth(_ raw: String?) -> Double {
            guard let raw = raw?.trimmingCharacters(in: .whitespaces).lowercased(), !raw.isEmpty else { return 0 }
            let digits = raw.replacingOccurrences(of: "px", with: "").replacingOccurrences(of: "pt", with: "").replacingOccurrences(of: "%", with: "")
            return Double(digits) ?? 0
        }

        private static func applyColumnAlignments(rowNodes: [RowEntry], to result: inout RichTable) {
            for column in result.columns.indices {
                var counts: [RichTableAlignment: Int] = [:]
                for row in result.rows {
                    guard row.cells.indices.contains(column), let alignment = row.cells[column].alignment else { continue }
                    counts[alignment, default: 0] += 1
                }
                guard let (alignment, count) = counts.max(by: { $0.value < $1.value }), count * 2 > result.rowCount else { continue }
                result.columns[column].alignment = alignment
                for rowIndex in result.rows.indices where result.rows[rowIndex].cells[column].alignment == alignment {
                    result.rows[rowIndex].cells[column].alignment = nil
                }
            }
        }
    }
}

extension HTMLNode {
    /// Text with hard line breaks preserved (`<br>` and block boundaries →
    /// "\n") — for `<pre>` blocks.
    var innerTextPreservingLines: String {
        var output = ""
        func walk(_ node: HTMLNode) {
            if node.isText {
                output += node.text
                return
            }
            if node.name == "br" { output += "\n"; return }
            let isBlock = HTMLBlockImporter.Builder.blockTags.contains(node.name)
            if isBlock, !output.isEmpty, !output.hasSuffix("\n") { output += "\n" }
            for child in node.children { walk(child) }
            if isBlock, !output.hasSuffix("\n") { output += "\n" }
        }
        walk(self)
        return output
    }
}
