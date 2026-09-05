#if os(macOS)
import AppKit
import CryptoKit
import Foundation
import PDFKit

/// AppKit is confined to preparation/rendering. The captured document remains a
/// portable value and can be archived or rendered independently on another device.
@MainActor
enum SpaceCompositionExportRenderer {
    static let paperSize = CGSize(width: 595.28, height: 841.89)
    static let margin: CGFloat = 54
    static let contentWidth = paperSize.width - margin * 2
    static let contentHeight = paperSize.height - margin * 2 - 24

    static func prepare(_ snapshot: SpaceCompositionExportSnapshot) async throws -> SpaceCompositionExportSnapshot {
        var assets = snapshot.assets
        var references: [(String, RichImageReference)] = []
        var sketches: [RichBlock] = []
        for section in snapshot.sections {
            try SpaceCompositionExportFormatter.visit(section.document.blocks) { block in
                if block.rawKind != nil { throw SpaceCompositionExportError.unsupportedBlock(section.title) }
                let nodes = block.inlines + (block.table?.rows.flatMap { $0.cells.flatMap(\.inlines) } ?? [])
                references.append(contentsOf: nodes.compactMap { node in node.image.map { (section.title, $0) } })
                if block.kind == .sketch { sketches.append(block) }
            }
        }
        var totalBytes = assets.values.reduce(0) { $0 + $1.data.count }
        for (title, reference) in references {
            try Task.checkCancellation()
            let key = SpaceCompositionExportSnapshot.imageKey(reference)
            guard assets[key] == nil else { continue }
            guard let image = await ImageStore.resolve(reference), let data = pngData(image) else {
                throw SpaceCompositionExportError.missingImage(title)
            }
            totalBytes += data.count
            guard totalBytes <= 200_000_000 else { throw SpaceCompositionExportError.assetTooLarge }
            assets[key] = .init(data: data, mimeType: "image/png", width: image.size.width, height: image.size.height)
        }
        for block in sketches {
            try Task.checkCancellation()
            let key = SpaceCompositionExportSnapshot.sketchKey(block)
            guard assets[key] == nil else { continue }
            guard let data = sketchPNG(block.sketch ?? RichSketchDrawing()) else {
                throw SpaceCompositionExportError.renderingFailed
            }
            totalBytes += data.count
            guard totalBytes <= 200_000_000 else { throw SpaceCompositionExportError.assetTooLarge }
            let size = NSImage(data: data)?.size
            assets[key] = .init(data: data, mimeType: "image/png", width: size.map { Double($0.width) }, height: size.map { Double($0.height) })
        }
        let result = snapshot.replacingAssets(assets)
        try SpaceCompositionExportFormatter.validate(result)
        for asset in assets.values {
            guard NSImage(data: asset.data) != nil else { throw SpaceCompositionExportError.renderingFailed }
        }
        return result
    }

    static func data(for snapshot: SpaceCompositionExportSnapshot, format: SpaceCompositionExportFormat) async throws -> Data {
        try SpaceCompositionExportFormatter.validate(snapshot)
        switch format {
        case .pdf: return try await pdf(snapshot)
        case .word:
            return try await Task.detached(priority: .userInitiated) {
                try SpaceCompositionExportWord.document(snapshot)
            }.value
        case .html: return try await Task.detached(priority: .userInitiated) {
            Data(try SpaceCompositionExportFormatter.html(snapshot).utf8)
        }.value
        case .markdown: return try await Task.detached(priority: .userInitiated) {
            Data(try SpaceCompositionExportFormatter.markdown(snapshot).utf8)
        }.value
        }
    }

    static func attributedDocument(_ snapshot: SpaceCompositionExportSnapshot) throws -> NSAttributedString {
        try SpaceCompositionExportFormatter.validate(snapshot)
        let text = NSMutableAttributedString(string: "")
        for section in snapshot.sections {
            appendParagraph(
                inline([.text(section.title)], size: section.depth == 0 ? 25 : max(14, 21 - CGFloat(section.depth) * 2), bold: true, snapshot: snapshot),
                to: text, heading: min(6, section.depth + 1)
            )
            appendBlocks(section.document.blocks, to: text, snapshot: snapshot)
        }
        return text
    }

    static func pdf(_ snapshot: SpaceCompositionExportSnapshot) async throws -> Data {
        let text = try attributedDocument(snapshot)
        let storage = NSTextStorage(attributedString: text)
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        var pages: [(NSTextContainer, NSRange)] = []
        var previousEnd = 0
        repeat {
            try Task.checkCancellation()
            let container = NSTextContainer(size: CGSize(width: contentWidth, height: contentHeight))
            container.lineFragmentPadding = 0
            layout.addTextContainer(container)
            layout.ensureLayout(for: container)
            let range = layout.glyphRange(for: container)
            guard NSMaxRange(range) > previousEnd || (pages.isEmpty && text.length == 0) else {
                throw SpaceCompositionExportError.paginationFailed
            }
            pages.append((container, range))
            previousEnd = NSMaxRange(range)
            if pages.count % 4 == 0 { await Task.yield() }
            guard pages.count <= 5_000 else { throw SpaceCompositionExportError.paginationFailed }
        } while previousEnd < layout.numberOfGlyphs

        let bytes = NSMutableData()
        guard let consumer = CGDataConsumer(data: bytes as CFMutableData) else { throw SpaceCompositionExportError.renderingFailed }
        var box = CGRect(origin: .zero, size: paperSize)
        guard let context = CGContext(consumer: consumer, mediaBox: &box, [kCGPDFContextTitle: snapshot.title] as CFDictionary) else {
            throw SpaceCompositionExportError.renderingFailed
        }
        for (index, page) in pages.enumerated() {
            try Task.checkCancellation()
            context.beginPDFPage(nil)
            context.setFillColor(NSColor.white.cgColor)
            context.fill(box)
            context.saveGState()
            context.translateBy(x: margin, y: paperSize.height - margin)
            context.scaleBy(x: 1, y: -1)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
            layout.drawBackground(forGlyphRange: page.1, at: .zero)
            layout.drawGlyphs(forGlyphRange: page.1, at: .zero)
            let footer = NSAttributedString(string: "\(index + 1)", attributes: [
                .font: NSFont.systemFont(ofSize: 9), .foregroundColor: NSColor.gray
            ])
            footer.draw(at: CGPoint(x: (contentWidth - footer.size().width) / 2, y: contentHeight + 16))
            NSGraphicsContext.restoreGraphicsState()
            context.restoreGState()
            context.endPDFPage()
            if index % 4 == 0 { await Task.yield() }
        }
        context.closePDF()
        let data = bytes as Data
        guard PDFDocument(data: data)?.pageCount == pages.count else { throw SpaceCompositionExportError.renderingFailed }
        return data
    }

    private static func appendBlocks(_ blocks: [RichBlock], to output: NSMutableAttributedString, snapshot: SpaceCompositionExportSnapshot) {
        var numberedPosition = 0
        for block in blocks {
            numberedPosition = block.kind == .numberedList ? numberedPosition + 1 : 0
            switch block.kind {
            case .table:
                if let table = block.table { appendTable(table, to: output, snapshot: snapshot) }
            case .sketch:
                appendParagraph(attachment(SpaceCompositionExportSnapshot.sketchKey(block), snapshot: snapshot), to: output)
            case .divider:
                appendParagraph(NSAttributedString(string: "────────────────────────", attributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.lightGray]), to: output)
            case .element:
                let title = block.element?.instanceTitleSnapshot ?? block.element?.titleSnapshot ?? block.plainInlineText
                appendParagraph(inline([.text(title)], size: 15, bold: true, snapshot: snapshot), to: output, heading: 4)
            default:
                let heading = block.kind.headingLevelInt.map { min(6, $0 + 2) } ?? ([.section, .toggle].contains(block.kind) ? 4 : 0)
                let size: CGFloat = heading > 0 ? max(14, 21 - CGFloat(heading)) : 12
                let content = NSMutableAttributedString(string: "")
                let prefix: String
                switch block.kind {
                case .bulletList: prefix = "•  "
                case .numberedList: prefix = "\(numberedPosition).  "
                case .checklist: prefix = (block.checked ?? false) ? "☑  " : "☐  "
                default: prefix = ""
                }
                content.append(inline([.text(prefix)], size: size, snapshot: snapshot))
                content.append(inline(block.inlines, size: size, bold: heading > 0, monospaced: block.kind == .code, snapshot: snapshot))
                appendParagraph(content, to: output, heading: heading, isQuote: [.quote, .callout].contains(block.kind), isList: !prefix.isEmpty)
            }
            appendBlocks(block.children, to: output, snapshot: snapshot)
            appendBlocks(block.heading?.collapsedBlocks ?? [], to: output, snapshot: snapshot)
        }
    }

    private static func appendParagraph(
        _ value: NSAttributedString, to output: NSMutableAttributedString,
        heading: Int = 0, isQuote: Bool = false, isList: Bool = false
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        paragraph.paragraphSpacing = heading > 0 ? 10 : (isList ? 4 : 9)
        paragraph.paragraphSpacingBefore = heading > 0 && output.length > 0 ? 15 : 0
        paragraph.headerLevel = heading
        if isQuote { paragraph.headIndent = 18; paragraph.firstLineHeadIndent = 18; paragraph.tailIndent = -18 }
        if isList { paragraph.headIndent = 20; paragraph.firstLineHeadIndent = 0 }
        let run = NSMutableAttributedString(attributedString: value)
        run.append(NSAttributedString(string: "\n"))
        run.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: run.length))
        output.append(run)
    }

    private static func inline(
        _ nodes: [RichInlineNode], size: CGFloat, bold: Bool = false,
        monospaced: Bool = false, maxWidth: CGFloat? = nil, snapshot: SpaceCompositionExportSnapshot
    ) -> NSAttributedString {
        let result = NSMutableAttributedString(string: "")
        let availableWidth = maxWidth ?? contentWidth
        for node in nodes {
            if let image = node.image {
                result.append(attachment(SpaceCompositionExportSnapshot.imageKey(image), snapshot: snapshot,
                                         preferredWidth: min(image.displayWidth ?? availableWidth, availableWidth)))
                continue
            }
            var font = monospaced ? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
                : (NSFont(name: "Georgia", size: size) ?? .systemFont(ofSize: size))
            if bold || node.marks.contains(.bold) { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
            if node.marks.contains(.italic) { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
            var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor(calibratedWhite: 0.13, alpha: 1)]
            if node.marks.contains(.underline) { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            if node.marks.contains(.strikethrough) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            if let color = color(node.inkID) { attributes[.foregroundColor] = color }
            if let color = color(node.highlightID) { attributes[.backgroundColor] = color.withAlphaComponent(0.2) }
            if let link = node.href.flatMap(SpaceCompositionExportFormatter.safeLink) { attributes[.link] = link }
            result.append(NSAttributedString(string: node.plainText.replacingOccurrences(of: "\u{2028}", with: "\n"), attributes: attributes))
        }
        return result
    }

    private static func attachment(_ key: String, snapshot: SpaceCompositionExportSnapshot, preferredWidth: CGFloat? = nil) -> NSAttributedString {
        guard let asset = snapshot.assets[key], let image = NSImage(data: asset.data) else { return NSAttributedString(string: "") }
        let width = min(contentWidth, max(1, preferredWidth ?? image.size.width))
        let aspect = image.size.height / max(1, image.size.width)
        let scale = min(1, (contentHeight - 32) / max(1, width * aspect))
        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = CGRect(x: 0, y: 0, width: width * scale, height: width * aspect * scale)
        let wrapper = FileWrapper(regularFileWithContents: asset.data)
        wrapper.preferredFilename = "image-" + SHA256.hash(data: asset.data).prefix(6).map { String(format: "%02x", $0) }.joined() + ".png"
        attachment.fileWrapper = wrapper
        return NSAttributedString(attachment: attachment)
    }

    private static func appendTable(_ table: RichTable, to output: NSMutableAttributedString, snapshot: SpaceCompositionExportSnapshot) {
        let native = NSTextTable()
        native.numberOfColumns = table.columnCount
        native.layoutAlgorithm = .fixedLayoutAlgorithm
        native.collapsesBorders = true
        native.setContentWidth(contentWidth, type: .absoluteValueType)
        let totalWeight = table.columns.reduce(0) { $0 + $1.weight }
        for (rowIndex, row) in table.rows.enumerated() {
            for (column, cell) in row.cells.enumerated() where !cell.isCovered {
                let nativeCell = NSTextTableBlock(table: native, startingRow: rowIndex, rowSpan: cell.rowSpan, startingColumn: column, columnSpan: cell.colSpan)
                let end = min(table.columnCount, column + cell.colSpan)
                let weight = table.columns[column..<end].reduce(0) { $0 + $1.weight }
                nativeCell.setContentWidth(contentWidth * weight / max(1, totalWeight), type: .absoluteValueType)
                nativeCell.setWidth(5, type: .absoluteValueType, for: .padding)
                nativeCell.setWidth(0.5, type: .absoluteValueType, for: .border)
                nativeCell.setBorderColor(.lightGray)
                if let tone = color(cell.toneID) { nativeCell.backgroundColor = tone.withAlphaComponent(0.15) }
                let paragraph = NSMutableParagraphStyle()
                paragraph.textBlocks = [nativeCell]
                paragraph.lineSpacing = 2
                let alignment = cell.alignment ?? table.columns[column].alignment
                paragraph.alignment = alignment == .center ? .center : (alignment == .trailing ? .right : .left)
                let header = (table.hasHeaderRow && rowIndex == 0) || (table.hasHeaderColumn && column == 0)
                let cellWidth = max(32, contentWidth * weight / max(1, totalWeight) - 10)
                let text = NSMutableAttributedString(attributedString: inline(cell.inlines, size: 10, bold: header, maxWidth: cellWidth, snapshot: snapshot))
                text.append(NSAttributedString(string: "\n"))
                text.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: text.length))
                output.append(text)
            }
        }
        output.append(NSAttributedString(string: "\n"))
    }

    private static func color(_ toneID: String?) -> NSColor? {
        guard let toneID, let hex = RichInlineColor.toneInks.first(where: { $0.id == toneID })?.hex,
              let value = UInt32(hex, radix: 16) else { return nil }
        return NSColor(calibratedRed: CGFloat((value >> 16) & 255) / 255,
                       green: CGFloat((value >> 8) & 255) / 255,
                       blue: CGFloat(value & 255) / 255, alpha: 1)
    }

    private static func pngData(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation, let representation = NSBitmapImageRep(data: tiff) else { return nil }
        return representation.representation(using: .png, properties: [:])
    }

    private static func sketchPNG(_ drawing: RichSketchDrawing) -> Data? {
        let width = max(680, (drawing.strokes.flatMap(\.points).map(\.x).max() ?? 0) + 12)
        let height = max(120, min(600, drawing.height))
        guard width.isFinite, height.isFinite, width <= 20_000 else { return nil }
        let image = NSImage(size: CGSize(width: width, height: height), flipped: true) { rect in
            NSColor.white.setFill()
            rect.fill()
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            for stroke in drawing.strokes {
                let ink = color(stroke.inkID) ?? NSColor(calibratedWhite: 0.13, alpha: 1)
                context.setStrokeColor(ink.withAlphaComponent(stroke.isHighlighter ? 0.35 : 1).cgColor)
                context.setLineWidth(stroke.width)
                context.setLineCap(.round)
                context.setLineJoin(.round)
                context.addPath(SketchGeometry.smoothedPath(for: stroke.points).cgPath)
                context.strokePath()
            }
            return true
        }
        return pngData(image)
    }
}

/// Keep the exact rich snapshot and output bytes together locally. The returned
/// URL is the user's saved file; an interrupted/failed save never records success.
enum SpaceCompositionExportArchive {
    struct Receipt: Codable, Sendable {
        let snapshotID: UUID
        let format: String
        let exportedAt: Date
        let fileName: String
        let sha256: String
    }

    static func write(
        data: Data, format: SpaceCompositionExportFormat,
        snapshot: SpaceCompositionExportSnapshot, to destination: URL,
        archiveDirectory: URL? = nil
    ) throws {
        let base = archiveDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Cosmo/SpaceExports", isDirectory: true)
        let directory = base.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            try snapshot.encoded().write(to: directory.appendingPathComponent("snapshot.json"), options: .atomic)
            try data.write(to: directory.appendingPathComponent("output." + format.fileExtension), options: .atomic)
            let receipt = Receipt(snapshotID: snapshot.id, format: format.rawValue, exportedAt: Date(), fileName: destination.lastPathComponent,
                                  sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
            try JSONEncoder().encode(receipt).write(to: directory.appendingPathComponent("receipt.json"), options: .atomic)
            try data.write(to: destination, options: .atomic)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }
}
#endif
