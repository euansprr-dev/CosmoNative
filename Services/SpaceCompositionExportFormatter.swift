import Foundation

/// Semantic export of RichDocument, including folded content. No source cards or
/// linked references are appended: inclusion belongs to the authored structure.
enum SpaceCompositionExportFormatter {
    static func html(_ snapshot: SpaceCompositionExportSnapshot) throws -> String {
        try validate(snapshot)
        var body: [String] = []
        for section in snapshot.sections {
            let level = min(6, max(1, section.depth + 1))
            body.append("<section><h\(level)>\(escape(section.title))</h\(level)>")
            body.append(try htmlBlocks(section.document.blocks, snapshot: snapshot))
            body.append("</section>")
        }
        return """
        <!doctype html>
        <html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src 'unsafe-inline'">
        <title>\(escape(snapshot.title))</title>
        <style>
        body{max-width:46rem;margin:3rem auto;padding:0 2rem;color:#242521;background:#fff;font:17px/1.65 Georgia,serif}
        h1,h2,h3,h4,h5,h6{line-height:1.2;font-family:-apple-system,BlinkMacSystemFont,sans-serif;break-after:avoid}
        h1{font-size:2.1rem;margin:0 0 1.5rem}h2{font-size:1.55rem;margin:2.5rem 0 1rem}h3{font-size:1.2rem}
        p{margin:.75rem 0}li{margin:.25rem 0}blockquote{border-left:2px solid #a8afa6;margin:1.2rem 0;padding-left:1.2rem}
        a{color:#2d6a4f}img{max-width:100%;height:auto;break-inside:avoid}figure{margin:1.5rem 0}
        table{width:100%;border-collapse:collapse;font:14px/1.5 -apple-system,BlinkMacSystemFont,sans-serif;overflow-wrap:anywhere}
        th,td{padding:.5rem;border:1px solid #ddd;text-align:left}pre{white-space:pre-wrap;overflow-wrap:anywhere;background:#f6f6f4;padding:1rem}
        code{font-family:ui-monospace,monospace}hr{border:0;border-top:1px solid #ddd;margin:2rem 0}
        @media print{body{margin:0;max-width:none;padding:0;font-size:11pt}a{color:inherit}h1,h2,h3{break-after:avoid}tr{break-inside:avoid}}
        </style></head><body>
        \(body.joined(separator: "\n"))
        </body></html>
        """
    }

    static func markdown(_ snapshot: SpaceCompositionExportSnapshot) throws -> String {
        try validate(snapshot)
        var output: [String] = []
        for section in snapshot.sections {
            output.append(String(repeating: "#", count: min(6, max(1, section.depth + 1))) + " " + markdownEscape(section.title))
            output.append(try markdownBlocks(section.document.blocks, snapshot: snapshot))
        }
        return output.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    static func safeLink(_ value: String) -> String? {
        guard let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              ["https", "http", "mailto"].contains(scheme),
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
        if scheme != "mailto", components.host?.isEmpty != false { return nil }
        return value
    }

    static func escape(_ value: String) -> String { TableClipboardWriter.escape(value) }

    static func filename(title: String, format: SpaceCompositionExportFormat) -> String {
        let cleaned = title.unicodeScalars.map { scalar -> String in
            if CharacterSet.controlCharacters.contains(scalar) { return " " }
            if "/\\:".unicodeScalars.contains(scalar) { return "-" }
            return String(scalar)
        }.joined().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return String((cleaned.isEmpty ? "Untitled" : cleaned).prefix(100)) + "." + format.fileExtension
    }

    static func validate(_ snapshot: SpaceCompositionExportSnapshot) throws {
        guard !snapshot.sections.isEmpty else { throw SpaceCompositionExportError.nothingIncluded }
        for asset in snapshot.assets.values {
            guard ["image/png", "image/jpeg", "image/gif", "image/webp"].contains(asset.mimeType), !asset.data.isEmpty else {
                throw SpaceCompositionExportError.renderingFailed
            }
        }
        for section in snapshot.sections {
            try visit(section.document.blocks) { block in
                if block.rawKind != nil { throw SpaceCompositionExportError.unsupportedBlock(section.title) }
                if block.kind == .image && !block.inlines.contains(where: { $0.image != nil }) {
                    throw SpaceCompositionExportError.missingImage(section.title)
                }
                let nodes = block.inlines + (block.table?.rows.flatMap { $0.cells.flatMap(\.inlines) } ?? [])
                for node in nodes where node.kind == .imageRef {
                    guard let ref = node.image, snapshot.assets[SpaceCompositionExportSnapshot.imageKey(ref)] != nil else {
                        throw SpaceCompositionExportError.missingImage(section.title)
                    }
                }
                if block.kind == .sketch, snapshot.assets[SpaceCompositionExportSnapshot.sketchKey(block)] == nil {
                    throw SpaceCompositionExportError.missingImage(section.title)
                }
            }
        }
    }

    static func visit(_ blocks: [RichBlock], action: (RichBlock) throws -> Void) rethrows {
        for block in blocks {
            try action(block)
            try visit(block.children, action: action)
            try visit(block.heading?.collapsedBlocks ?? [], action: action)
        }
    }

    private static func htmlBlocks(_ blocks: [RichBlock], snapshot: SpaceCompositionExportSnapshot) throws -> String {
        var result = ""
        var listTag: String?
        func closeList() {
            if let tag = listTag { result += "</\(tag)>\n"; listTag = nil }
        }
        for block in blocks {
            let text = try htmlInlines(block.inlines, snapshot: snapshot)
            if [.bulletList, .numberedList, .checklist].contains(block.kind) {
                let tag = block.kind == .numberedList ? "ol" : "ul"
                if listTag != tag { closeList(); result += "<\(tag)>"; listTag = tag }
                let prefix = block.kind == .checklist ? ((block.checked ?? false) ? "☑ " : "☐ ") : ""
                let children = try htmlBlocks(block.children, snapshot: snapshot)
                result += "<li>\(prefix)\(text)\(children)</li>\n"
                continue
            }
            closeList()
            switch block.kind {
            case .heading1, .heading2, .heading3:
                let level = min(6, (block.kind.headingLevelInt ?? 1) + 2)
                result += "<h\(level)>\(text)</h\(level)>\n"
            case .divider: result += "<hr>\n"
            case .quote, .callout: result += "<blockquote>\(text)</blockquote>\n"
            case .code: result += "<pre><code>\(escape(block.plainInlineText).replacingOccurrences(of: "\u{2028}", with: "\n"))</code></pre>\n"
            case .image: result += "<figure>\(text)</figure>\n"
            case .sketch:
                result += try imageHTML(key: SpaceCompositionExportSnapshot.sketchKey(block), snapshot: snapshot, alt: "Drawing")
            case .table:
                if var table = block.table {
                    // The shared clipboard writer preserves merged cells and ink.
                    // Sanitize links before handing it user-controlled inlines.
                    var images: [String: String] = [:]
                    for row in table.rows.indices {
                        for column in table.rows[row].cells.indices {
                            table.rows[row].cells[column].inlines = try table.rows[row].cells[column].inlines.map { node in
                                if let image = node.image {
                                    let token = "COSMO_IMAGE_" + node.id.uuidString
                                    images[token] = try imageHTML(key: SpaceCompositionExportSnapshot.imageKey(image), snapshot: snapshot, alt: "Image", width: image.displayWidth ?? image.width)
                                    return .text(token)
                                }
                                return sanitized(node)
                            }
                        }
                    }
                    var html = TableClipboardWriter.html(for: table)
                    for (token, image) in images { html = html.replacingOccurrences(of: token, with: image) }
                    result += html + "\n"
                }
            case .section, .toggle:
                result += "<h4>\(text)</h4>\n"
            case .element:
                result += "<h4>\(escape(block.element?.instanceTitleSnapshot ?? block.element?.titleSnapshot ?? block.plainInlineText))</h4>\n"
            default: result += "<p>\(text)</p>\n"
            }
            result += try htmlBlocks(block.children, snapshot: snapshot)
            result += try htmlBlocks(block.heading?.collapsedBlocks ?? [], snapshot: snapshot)
        }
        closeList()
        return result
    }

    private static func sanitized(_ node: RichInlineNode) -> RichInlineNode {
        var result = node
        result.href = node.href.flatMap(safeLink)
        return result
    }

    private static func htmlInlines(_ inlines: [RichInlineNode], snapshot: SpaceCompositionExportSnapshot) throws -> String {
        try inlines.map { node in
            if let ref = node.image {
                return try imageHTML(key: SpaceCompositionExportSnapshot.imageKey(ref), snapshot: snapshot, alt: "Image", width: ref.displayWidth ?? ref.width)
            }
            return TableClipboardWriter.inlineHTML([sanitized(node)])
                .replacingOccurrences(of: "\n", with: "<br>")
        }.joined()
    }

    private static func imageHTML(key: String, snapshot: SpaceCompositionExportSnapshot, alt: String, width: CGFloat? = nil) throws -> String {
        guard let asset = snapshot.assets[key] else { throw SpaceCompositionExportError.missingImage(snapshot.title) }
        let sizing = width.flatMap { $0.isFinite && $0 > 0 ? " width=\"\(Int(min(16_384, $0)))\"" : nil } ?? ""
        return "<img src=\"\(asset.dataURL)\" alt=\"\(alt)\"\(sizing)>"
    }

    private static func markdownBlocks(_ blocks: [RichBlock], snapshot: SpaceCompositionExportSnapshot) throws -> String {
        var result: [String] = []
        var listNumber = 0
        for block in blocks {
            listNumber = block.kind == .numberedList ? listNumber + 1 : 0
            let text = try markdownInlines(block.inlines, snapshot: snapshot)
            switch block.kind {
            case .heading1, .heading2, .heading3:
                result.append(String(repeating: "#", count: min(6, (block.kind.headingLevelInt ?? 1) + 2)) + " " + text)
            case .divider: result.append("---")
            case .quote, .callout: result.append(text.components(separatedBy: "\n").map { "> " + $0 }.joined(separator: "\n"))
            case .bulletList: result.append("- " + text)
            case .numberedList: result.append("\(listNumber). " + text)
            case .checklist: result.append((block.checked ?? false) ? "- [x] " + text : "- [ ] " + text)
            case .code:
                let code = block.plainInlineText.replacingOccurrences(of: "\u{2028}", with: "\n")
                let longestRun = code.split(whereSeparator: { $0 != "`" }).map(\.count).max() ?? 0
                let fence = String(repeating: "`", count: max(3, longestRun + 1))
                result.append(fence + "\n" + code + "\n" + fence)
            case .table:
                // HTML inside Markdown preserves merged cells and rich cell marks.
                result.append(try htmlBlocks([block], snapshot: snapshot))
            case .section, .toggle: result.append("#### " + text)
            case .element:
                result.append("#### " + markdownEscape(block.element?.instanceTitleSnapshot ?? block.element?.titleSnapshot ?? block.plainInlineText))
            case .sketch:
                result.append(try imageHTML(key: SpaceCompositionExportSnapshot.sketchKey(block), snapshot: snapshot, alt: "Drawing"))
            default: result.append(text)
            }
            if block.kind != .table {
                let child = try markdownBlocks(block.children, snapshot: snapshot)
                if !child.isEmpty {
                    let nested = [.bulletList, .numberedList, .checklist].contains(block.kind)
                    result.append(nested ? child.components(separatedBy: "\n").map { "    " + $0 }.joined(separator: "\n") : child)
                }
            }
            let folded = try markdownBlocks(block.heading?.collapsedBlocks ?? [], snapshot: snapshot)
            if !folded.isEmpty { result.append(folded) }
        }
        return result.joined(separator: "\n\n")
    }

    private static func markdownInlines(_ nodes: [RichInlineNode], snapshot: SpaceCompositionExportSnapshot) throws -> String {
        try nodes.map { node in
            if let image = node.image {
                return try imageHTML(key: SpaceCompositionExportSnapshot.imageKey(image), snapshot: snapshot, alt: "Image", width: image.displayWidth ?? image.width)
            }
            var text = markdownEscape(node.plainText).replacingOccurrences(of: "\u{2028}", with: "  \n")
            if node.marks.contains(.bold) { text = "**" + text + "**" }
            if node.marks.contains(.italic) { text = "*" + text + "*" }
            if node.marks.contains(.strikethrough) { text = "~~" + text + "~~" }
            if node.marks.contains(.underline) { text = "<u>" + text + "</u>" }
            if let href = node.href.flatMap(safeLink) {
                text = "[" + text + "](<" + href.replacingOccurrences(of: ">", with: "%3E").replacingOccurrences(of: "<", with: "%3C") + ">)"
            }
            return text
        }.joined()
    }

    private static func markdownEscape(_ value: String) -> String {
        var result = ""
        for character in value {
            if "\\`*_{}[]<>()#+-.!|~>".contains(character) { result.append("\\") }
            result.append(character)
        }
        return result
    }
}
