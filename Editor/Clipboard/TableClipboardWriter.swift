// TWIN FILE — byte-identical in CosmoOS-Swift/Editor/Clipboard and
// CosmoOS-iOS/CosmoCoreKit/Sources/Models. Verified by Tools/verify_twins.sh.
//
// Outbound clipboard shapes for tables and blocks: HTML that Google Docs,
// Sheets, Numbers and Excel paste faithfully, TSV for spreadsheets, and
// Markdown for everything else.

import Foundation

public enum TableClipboardWriter {
    // MARK: HTML

    public static func html(for table: RichTable, rect: RichTableRect? = nil) -> String {
        let region = rect ?? RichTableSelection.table.rect(in: table)
        guard let region else { return "" }
        let clipped = rect != nil
        var output = "<table style=\"border-collapse:collapse;\">"
        output += "<colgroup>"
        for column in region.columns where table.columns.indices.contains(column) {
            let weight = table.columns[column].weight
            let total = region.columns.reduce(0.0) { $0 + (table.columns.indices.contains($1) ? table.columns[$1].weight : 1) }
            let percent = total > 0 ? Int((weight / total * 100).rounded()) : 0
            output += "<col width=\"\(percent)%\">"
        }
        output += "</colgroup>"
        let headerRows = table.hasHeaderRow && region.rows.lowerBound == 0 ? 1 : 0
        if headerRows > 0 { output += "<thead>" }
        var openedBody = false
        for rowIndex in region.rows {
            if rowIndex == headerRows, !openedBody {
                if headerRows > 0 { output += "</thead>" }
                output += "<tbody>"
                openedBody = true
            }
            if rowIndex < headerRows, !openedBody {
                // still in thead
            }
            output += "<tr>"
            for columnIndex in region.columns {
                let address = RichTableCellAddress(row: rowIndex, column: columnIndex)
                guard let cell = table.cell(at: address) else { continue }
                if cell.isCovered {
                    // Inside a span: emitted by the anchor unless the span is
                    // clipped by the region, in which case the cell stands alone.
                    let anchor = table.anchorAddress(of: address)
                    let span = table.spanRect(ofAnchorAt: anchor)
                    if !clipped || region.contains(span) { continue }
                    output += cellHTML(RichTableCell(), address: address, table: table, isHeader: isHeader(address, table: table), spanOverride: nil)
                    continue
                }
                var spanOverride: (rows: Int, columns: Int)? = nil
                if clipped {
                    let span = table.spanRect(ofAnchorAt: address)
                    if !region.contains(span) { spanOverride = (1, 1) }
                }
                output += cellHTML(cell, address: address, table: table, isHeader: isHeader(address, table: table), spanOverride: spanOverride)
            }
            output += "</tr>"
        }
        if !openedBody {
            if headerRows > 0 { output += "</thead>" }
            output += "<tbody>"
        }
        output += "</tbody></table>"
        return output
    }

    private static func isHeader(_ address: RichTableCellAddress, table: RichTable) -> Bool {
        (table.hasHeaderRow && address.row == 0) || (table.hasHeaderColumn && address.column == 0)
    }

    private static func cellHTML(
        _ cell: RichTableCell,
        address: RichTableCellAddress,
        table: RichTable,
        isHeader: Bool,
        spanOverride: (rows: Int, columns: Int)?
    ) -> String {
        let tag = isHeader ? "th" : "td"
        var attributes: [String] = []
        let rowSpan = spanOverride?.rows ?? cell.rowSpan
        let colSpan = spanOverride?.columns ?? cell.colSpan
        if rowSpan > 1 { attributes.append("rowspan=\"\(rowSpan)\"") }
        if colSpan > 1 { attributes.append("colspan=\"\(colSpan)\"") }
        var styles: [String] = ["border:0.5pt solid #d9d4c8", "padding:5pt", "vertical-align:\(verticalAlign(cell))"]
        let alignment = cell.alignment ?? (table.columns.indices.contains(address.column) ? table.columns[address.column].alignment : .leading)
        styles.append("text-align:\(cssAlign(alignment))")
        if let toneID = cell.toneID, let hex = RichInlineColor.toneInks.first(where: { $0.id == toneID })?.hex {
            styles.append("background-color:#\(hex)29")
        }
        if isHeader { styles.append("font-weight:600") }
        attributes.append("style=\"\(styles.joined(separator: ";"))\"")
        return "<\(tag) \(attributes.joined(separator: " "))>\(inlineHTML(cell.inlines))</\(tag)>"
    }

    private static func cssAlign(_ alignment: RichTableAlignment) -> String {
        switch alignment {
        case .leading: return "left"
        case .center: return "center"
        case .trailing: return "right"
        }
    }

    private static func verticalAlign(_ cell: RichTableCell) -> String {
        switch cell.verticalAlignment ?? .top {
        case .top: return "top"
        case .middle: return "middle"
        case .bottom: return "bottom"
        }
    }

    public static func inlineHTML(_ inlines: [RichInlineNode]) -> String {
        var output = ""
        for node in inlines {
            switch node.kind {
            case .text:
                output += styledSpan(escape(node.text ?? "").replacingOccurrences(of: "\u{2028}", with: "<br>"), node: node)
            case .mention:
                output += styledSpan(escape(node.mention?.displayText ?? ""), node: node)
            case .imageRef:
                continue
            }
        }
        return output
    }

    private static func styledSpan(_ text: String, node: RichInlineNode) -> String {
        var result = text
        if node.marks.contains(.bold) { result = "<b>\(result)</b>" }
        if node.marks.contains(.italic) { result = "<i>\(result)</i>" }
        if node.marks.contains(.underline) { result = "<u>\(result)</u>" }
        if node.marks.contains(.strikethrough) { result = "<s>\(result)</s>" }
        var styles: [String] = []
        if let inkID = node.inkID, let hex = RichInlineColor.toneInks.first(where: { $0.id == inkID })?.hex {
            styles.append("color:#\(hex)")
        }
        if let highlightID = node.highlightID, let hex = RichInlineColor.toneInks.first(where: { $0.id == highlightID })?.hex {
            styles.append("background-color:#\(hex)33")
        }
        if !styles.isEmpty { result = "<span style=\"\(styles.joined(separator: ";"))\">\(result)</span>" }
        if let href = node.href { result = "<a href=\"\(escapeAttribute(href))\">\(result)</a>" }
        return result
    }

    // MARK: Blocks

    static func html(forBlocks blocks: [RichBlock]) -> String {
        var output = ""
        var listKind: RichBlockKind? = nil
        func closeList() {
            if let kind = listKind {
                output += kind == .numberedList ? "</ol>" : "</ul>"
                listKind = nil
            }
        }
        for block in blocks {
            switch block.kind {
            case .bulletList, .checklist, .numberedList:
                let kind: RichBlockKind = block.kind == .numberedList ? .numberedList : .bulletList
                if listKind != kind {
                    closeList()
                    output += kind == .numberedList ? "<ol>" : "<ul>"
                    listKind = kind
                }
                if block.kind == .checklist {
                    let checked = block.checked ?? false
                    output += "<li role=\"checkbox\" aria-checked=\"\(checked)\">\(checked ? "☑ " : "☐ ")\(inlineHTML(block.inlines))</li>"
                } else {
                    output += "<li>\(inlineHTML(block.inlines))</li>"
                }
                continue
            default:
                closeList()
            }
            switch block.kind {
            case .heading1: output += "<h1>\(inlineHTML(block.inlines))</h1>"
            case .heading2: output += "<h2>\(inlineHTML(block.inlines))</h2>"
            case .heading3: output += "<h3>\(inlineHTML(block.inlines))</h3>"
            case .quote: output += "<blockquote><p>\(inlineHTML(block.inlines))</p></blockquote>"
            case .code: output += "<pre><code>\(escape(block.inlines.map(\.plainText).joined()).replacingOccurrences(of: "\u{2028}", with: "\n"))</code></pre>"
            case .divider: output += "<hr>"
            case .table: output += html(for: block.table ?? RichTable())
            case .section:
                output += "<section><h2>\(inlineHTML(block.inlines))</h2>\(html(forBlocks: block.children))</section>"
            case .toggle, .element:
                output += "<p>\(inlineHTML(block.inlines))</p>\(html(forBlocks: block.children))"
            case .image, .sketch:
                continue
            default:
                output += "<p>\(inlineHTML(block.inlines))</p>"
            }
        }
        closeList()
        return output
    }

    // MARK: TSV / Markdown

    public static func tsv(for table: RichTable, rect: RichTableRect? = nil) -> String {
        table.tsv(rect)
    }

    public static func markdown(for table: RichTable) -> String {
        table.markdown
    }

    // MARK: Escaping

    public static func escape(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            default: result.append(character)
            }
        }
        return result
    }

    static func escapeAttribute(_ text: String) -> String {
        escape(text).replacingOccurrences(of: "'", with: "&#39;")
    }
}
