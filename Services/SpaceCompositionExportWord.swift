import Foundation

/// AppKit's Word writer flattens NSTextTable and drops image attachments. Build
/// the small OOXML vocabulary we actually author, keeping the package portable.
enum SpaceCompositionExportWord {
    static func document(_ snapshot: SpaceCompositionExportSnapshot) throws -> Data {
        try SpaceCompositionExportFormatter.validate(snapshot)
        var writer = Writer(snapshot: snapshot)
        return try writer.package()
    }

    private struct Writer {
        let snapshot: SpaceCompositionExportSnapshot
        var links: [(id: String, url: String)] = []
        var drawingID = 0
        var media: [String: (id: String, name: String, asset: SpaceCompositionExportSnapshot.Asset)] = [:]

        mutating func package() throws -> Data {
            for (index, key) in snapshot.assets.keys.sorted().enumerated() {
                guard let asset = snapshot.assets[key] else { continue }
                let ext = asset.mimeType == "image/jpeg" ? "jpg" : String(asset.mimeType.dropFirst(6))
                media[key] = ("image\(index + 1)", "image\(index + 1).\(ext)", asset)
            }
            var body = ""
            for section in snapshot.sections {
                body += paragraph([.text(section.title)], style: section.depth == 0 ? "Title" : "Heading\(min(6, section.depth))")
                body += blocks(section.document.blocks)
            }
            body += "<w:sectPr><w:pgSz w:w=\"11906\" w:h=\"16838\"/><w:pgMar w:top=\"1080\" w:right=\"1080\" w:bottom=\"1080\" w:left=\"1080\"/></w:sectPr>"
            let document = declaration + "<w:document xmlns:w=\"\(wordNS)\" xmlns:r=\"\(relationshipNS)\" xmlns:wp=\"http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing\" xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:pic=\"http://schemas.openxmlformats.org/drawingml/2006/picture\"><w:body>\(body)</w:body></w:document>"
            var files: [(String, Data)] = [
                ("[Content_Types].xml", Data(contentTypes.utf8)),
                ("_rels/.rels", Data((declaration + "<Relationships xmlns=\"\(packageRelationshipNS)\"><Relationship Id=\"document\" Type=\"\(relationshipNS)/officeDocument\" Target=\"word/document.xml\"/></Relationships>").utf8)),
                ("word/document.xml", Data(document.utf8)),
                ("word/styles.xml", Data(styles.utf8)),
                ("word/_rels/document.xml.rels", Data(relationships.utf8))
            ]
            files += media.values.sorted(by: { $0.name < $1.name }).map { ("word/media/" + $0.name, $0.asset.data) }
            return try SpaceCompositionExportZIP.encode(files)
        }

        mutating func blocks(_ values: [RichBlock]) -> String {
            var output = ""
            var number = 0
            for block in values {
                number = block.kind == .numberedList ? number + 1 : 0
                switch block.kind {
                case .table:
                    if let value = block.table { output += table(value) }
                case .sketch:
                    output += "<w:p>" + drawing(key: SpaceCompositionExportSnapshot.sketchKey(block)) + "</w:p>"
                case .divider:
                    output += "<w:p><w:pPr><w:pBdr><w:bottom w:val=\"single\" w:sz=\"4\" w:color=\"D5D5D0\"/></w:pBdr></w:pPr></w:p>"
                case .element:
                    output += paragraph([.text(block.element?.instanceTitleSnapshot ?? block.element?.titleSnapshot ?? block.plainInlineText)], style: "Heading3")
                default:
                    var nodes = block.inlines
                    let prefix: String
                    switch block.kind {
                    case .bulletList: prefix = "•  "
                    case .numberedList: prefix = "\(number).  "
                    case .checklist: prefix = (block.checked ?? false) ? "☑  " : "☐  "
                    default: prefix = ""
                    }
                    if !prefix.isEmpty { nodes.insert(.text(prefix), at: 0) }
                    let style: String
                    if let level = block.kind.headingLevelInt { style = "Heading\(min(6, level + 1))" }
                    else if [.section, .toggle].contains(block.kind) { style = "Heading3" }
                    else if [.quote, .callout].contains(block.kind) { style = "Quote" }
                    else if block.kind == .code { style = "Code" }
                    else if !prefix.isEmpty { style = "ListParagraph" }
                    else { style = "Normal" }
                    output += paragraph(nodes, style: style)
                }
                output += blocks(block.children)
                output += blocks(block.heading?.collapsedBlocks ?? [])
            }
            return output
        }

        mutating func paragraph(_ nodes: [RichInlineNode], style: String = "Normal", properties: String = "", imageWidth: Double = 487) -> String {
            "<w:p><w:pPr><w:pStyle w:val=\"\(style)\"/>\(properties)</w:pPr>"
                + nodes.map { run($0, imageWidth: imageWidth) }.joined() + "</w:p>"
        }

        mutating func run(_ node: RichInlineNode, imageWidth: Double) -> String {
            if let image = node.image {
                return drawing(key: SpaceCompositionExportSnapshot.imageKey(image), width: min(Double(image.displayWidth ?? image.width), imageWidth), ratio: Double(image.height / max(1, image.width)))
            }
            var properties = ""
            if node.marks.contains(.bold) { properties += "<w:b/>" }
            if node.marks.contains(.italic) { properties += "<w:i/>" }
            if node.marks.contains(.underline) { properties += "<w:u w:val=\"single\"/>" }
            if node.marks.contains(.strikethrough) { properties += "<w:strike/>" }
            if let ink = hex(node.inkID) { properties += "<w:color w:val=\"\(ink)\"/>" }
            if let fill = hex(node.highlightID) { properties += "<w:shd w:val=\"clear\" w:fill=\"\(fill)\"/>" }
            let parts = node.plainText.replacingOccurrences(of: "\u{2028}", with: "\n").components(separatedBy: "\n")
            let text = parts.map { "<w:t xml:space=\"preserve\">\(xml($0))</w:t>" }.joined(separator: "<w:br/>")
            let result = "<w:r><w:rPr>\(properties)</w:rPr>\(text)</w:r>"
            if let url = node.href.flatMap(SpaceCompositionExportFormatter.safeLink) {
                let id = "link\(links.count + 1)"
                links.append((id, url))
                return "<w:hyperlink r:id=\"\(id)\">\(result)</w:hyperlink>"
            }
            return result
        }

        mutating func drawing(key: String, width: Double = 487, ratio: Double = 0.5) -> String {
            guard let image = media[key] else { return "" }
            drawingID += 1
            let capturedRatio = image.asset.width.flatMap { w in image.asset.height.map { $0 / max(1, w) } } ?? ratio
            let safeRatio = capturedRatio.isFinite && capturedRatio > 0 ? capturedRatio : 0.5
            let w = min(487, max(1, width))
            let scale = min(1, 680 / (w * safeRatio))
            let cx = Int(w * scale * 12_700), cy = Int(w * safeRatio * scale * 12_700)
            return """
            <w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0"><wp:extent cx="\(cx)" cy="\(cy)"/><wp:docPr id="\(drawingID)" name="Image \(drawingID)"/><a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:pic><pic:nvPicPr><pic:cNvPr id="\(drawingID)" name="\(image.name)"/><pic:cNvPicPr/></pic:nvPicPr><pic:blipFill><a:blip r:embed="\(image.id)"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill><pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="\(cx)" cy="\(cy)"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r>
            """
        }

        mutating func table(_ table: RichTable) -> String {
            let total = max(1, table.columns.reduce(0) { $0 + $1.weight })
            let widths = table.columns.map { max(1, Int(9746 * $0.weight / total)) }
            var output = "<w:tbl><w:tblPr><w:tblW w:w=\"9746\" w:type=\"dxa\"/><w:tblLayout w:type=\"fixed\"/><w:tblBorders>"
            for edge in ["top", "left", "bottom", "right", "insideH", "insideV"] {
                output += "<w:\(edge) w:val=\"single\" w:sz=\"4\" w:color=\"D5D5D0\"/>"
            }
            output += "</w:tblBorders><w:tblCellMar><w:top w:w=\"100\" w:type=\"dxa\"/><w:left w:w=\"100\" w:type=\"dxa\"/><w:bottom w:w=\"100\" w:type=\"dxa\"/><w:right w:w=\"100\" w:type=\"dxa\"/></w:tblCellMar></w:tblPr><w:tblGrid>"
            output += widths.map { "<w:gridCol w:w=\"\($0)\"/>" }.joined() + "</w:tblGrid>"
            for (rowIndex, row) in table.rows.enumerated() {
                output += "<w:tr>" + ((table.hasHeaderRow && rowIndex == 0) ? "<w:trPr><w:tblHeader/></w:trPr>" : "")
                for (columnIndex, storedCell) in row.cells.enumerated() {
                    let address = RichTableCellAddress(row: rowIndex, column: columnIndex)
                    let anchor = table.anchorAddress(of: address)
                    guard anchor.column == columnIndex else { continue }
                    guard let cell = table.cell(at: anchor) else { continue }
                    let span = min(cell.colSpan, table.columnCount - columnIndex)
                    let width = widths[columnIndex..<(columnIndex + span)].reduce(0, +)
                    output += "<w:tc><w:tcPr><w:tcW w:w=\"\(width)\" w:type=\"dxa\"/>"
                    if span > 1 { output += "<w:gridSpan w:val=\"\(span)\"/>" }
                    if cell.rowSpan > 1 { output += rowIndex == anchor.row ? "<w:vMerge w:val=\"restart\"/>" : "<w:vMerge/>" }
                    if let fill = hex(cell.toneID) { output += "<w:shd w:val=\"clear\" w:fill=\"\(fill)\"/>" }
                    output += "<w:vAlign w:val=\"\(cell.verticalAlignment == .bottom ? "bottom" : (cell.verticalAlignment == .middle ? "center" : "top"))\"/></w:tcPr>"
                    let alignment = cell.alignment ?? table.columns[columnIndex].alignment
                    let align = alignment == .center ? "center" : (alignment == .trailing ? "right" : "left")
                    var nodes = storedCell.isCovered ? [] : cell.inlines
                    if (table.hasHeaderRow && rowIndex == 0) || (table.hasHeaderColumn && columnIndex == 0) {
                        nodes = nodes.map { var n = $0; n.marks.insert(.bold); return n }
                    }
                    output += paragraph(nodes, style: "TableText", properties: "<w:jc w:val=\"\(align)\"/>", imageWidth: max(24, Double(width) / 20 - 10))
                    output += "</w:tc>"
                }
                output += "</w:tr>"
            }
            return output + "</w:tbl><w:p/>"
        }

        var relationships: String {
            var body = "<Relationship Id=\"styles\" Type=\"\(relationshipNS)/styles\" Target=\"styles.xml\"/>"
            body += media.values.sorted(by: { $0.id < $1.id }).map { "<Relationship Id=\"\($0.id)\" Type=\"\(relationshipNS)/image\" Target=\"media/\($0.name)\"/>" }.joined()
            body += links.map { "<Relationship Id=\"\($0.id)\" Type=\"\(relationshipNS)/hyperlink\" Target=\"\(xml($0.url))\" TargetMode=\"External\"/>" }.joined()
            return declaration + "<Relationships xmlns=\"\(packageRelationshipNS)\">\(body)</Relationships>"
        }

        var contentTypes: String {
            var types = "<Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/>"
            let mimeTypes = Set(media.values.map { $0.asset.mimeType }).sorted()
            for mime in mimeTypes {
                types += "<Default Extension=\"\(mime == "image/jpeg" ? "jpg" : String(mime.dropFirst(6)))\" ContentType=\"\(mime)\"/>"
            }
            types += "<Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/><Override PartName=\"/word/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml\"/>"
            return declaration + "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">\(types)</Types>"
        }

        var styles: String {
            var body = "<w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii=\"Georgia\" w:hAnsi=\"Georgia\"/><w:sz w:val=\"24\"/><w:color w:val=\"212121\"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:after=\"160\" w:line=\"300\" w:lineRule=\"auto\"/></w:pPr></w:pPrDefault></w:docDefaults>"
            body += "<w:style w:type=\"paragraph\" w:default=\"1\" w:styleId=\"Normal\"><w:name w:val=\"Normal\"/></w:style>"
            body += style("Title", size: 50, paragraph: "<w:keepNext/><w:spacing w:after=\"240\"/>", run: "<w:b/>")
            for level in 1...6 { body += style("Heading\(level)", size: max(28, 42 - level * 4), paragraph: "<w:keepNext/><w:outlineLvl w:val=\"\(level - 1)\"/><w:spacing w:before=\"300\" w:after=\"180\"/>", run: "<w:b/>") }
            body += style("Quote", size: 24, paragraph: "<w:ind w:left=\"360\" w:right=\"360\"/>", run: "<w:i/>")
            body += style("Code", size: 21, paragraph: "", run: "<w:rFonts w:ascii=\"Menlo\" w:hAnsi=\"Menlo\"/>")
            body += style("ListParagraph", size: 24, paragraph: "<w:ind w:left=\"360\" w:hanging=\"360\"/><w:spacing w:after=\"80\"/>", run: "")
            body += style("TableText", size: 20, paragraph: "<w:spacing w:after=\"0\"/>", run: "")
            return declaration + "<w:styles xmlns:w=\"\(wordNS)\">\(body)</w:styles>"
        }

        func style(_ id: String, size: Int, paragraph: String, run: String) -> String {
            "<w:style w:type=\"paragraph\" w:styleId=\"\(id)\"><w:name w:val=\"\(id)\"/><w:basedOn w:val=\"Normal\"/><w:pPr>\(paragraph)</w:pPr><w:rPr><w:sz w:val=\"\(size)\"/>\(run)</w:rPr></w:style>"
        }
        func hex(_ toneID: String?) -> String? { RichInlineColor.toneInks.first { $0.id == toneID }?.hex }
        func xml(_ value: String) -> String {
            let valid = String(value.unicodeScalars.filter { $0.value >= 32 || $0 == "\n" || $0 == "\t" || $0 == "\r" })
            return SpaceCompositionExportFormatter.escape(valid).replacingOccurrences(of: "'", with: "&apos;")
        }
        let declaration = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
        let wordNS = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
        let relationshipNS = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
        let packageRelationshipNS = "http://schemas.openxmlformats.org/package/2006/relationships"
    }
}

/// ZIP's stored entries avoid a platform-only archive process or a dependency.
/// PNG/JPEG media is already compressed. All package paths are generated above.
enum SpaceCompositionExportZIP {
    static func encode(_ entries: [(String, Data)]) throws -> Data {
        guard entries.count <= Int(UInt16.max) else { throw SpaceCompositionExportError.renderingFailed }
        var output = Data(), central = Data()
        for (name, bytes) in entries {
            let path = Data(name.utf8)
            guard path.count <= Int(UInt16.max), bytes.count <= Int(UInt32.max), output.count <= Int(UInt32.max) else { throw SpaceCompositionExportError.renderingFailed }
            let offset = UInt32(output.count), size = UInt32(bytes.count), crc = crc32(bytes)
            output.le32(0x04034B50); output.le16(20); output.le16(0x0800); output.le16(0)
            output.le16(0); output.le16(0x0021); output.le32(crc); output.le32(size); output.le32(size)
            output.le16(UInt16(path.count)); output.le16(0); output.append(path); output.append(bytes)
            central.le32(0x02014B50); central.le16(20); central.le16(20); central.le16(0x0800); central.le16(0)
            central.le16(0); central.le16(0x0021); central.le32(crc); central.le32(size); central.le32(size)
            central.le16(UInt16(path.count)); central.le16(0); central.le16(0); central.le16(0); central.le16(0)
            central.le32(0); central.le32(offset); central.append(path)
        }
        guard output.count <= Int(UInt32.max), central.count <= Int(UInt32.max) else { throw SpaceCompositionExportError.renderingFailed }
        let offset = UInt32(output.count)
        output.append(central)
        output.le32(0x06054B50); output.le16(0); output.le16(0)
        output.le16(UInt16(entries.count)); output.le16(UInt16(entries.count))
        output.le32(UInt32(central.count)); output.le32(offset); output.le16(0)
        return output
    }

    private static let crcTable: [UInt32] = (0..<256).map { value in
        var crc = UInt32(value)
        for _ in 0..<8 { crc = crc & 1 == 1 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1 }
        return crc
    }
    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data { crc = (crc >> 8) ^ crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] }
        return crc ^ 0xFFFFFFFF
    }
}

private extension Data {
    mutating func le16(_ value: UInt16) { append(UInt8(value & 0xFF)); append(UInt8(value >> 8)) }
    mutating func le32(_ value: UInt32) { le16(UInt16(value & 0xFFFF)); le16(UInt16(value >> 16)) }
}
