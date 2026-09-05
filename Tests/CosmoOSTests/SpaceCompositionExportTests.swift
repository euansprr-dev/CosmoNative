import AppKit
import PDFKit
import XCTest
@testable import CosmoOS

final class SpaceCompositionExportTests: XCTestCase {
    func testCaptureKeepsAuthoredOrderAndOmitsExcludedBranchesAndSources() throws {
        let root = try page("Book", kind: .book)
        let first = try page("First", parent: root.uuid, order: 0)
        let last = try page("Last", parent: root.uuid, order: 2)
        let privateNote = try page("Private notes", parent: root.uuid, order: 1, included: false)
        let privateChild = try page("Never publish", parent: privateNote.uuid)
        let group = try page("References", kind: .group, parent: root.uuid)
        let source = Atom.new(type: .research, title: "Source")
        let composition = try SpaceCompositionSnapshot(spaceID: "space", atoms: [source, last, privateChild, root, group, first, privateNote])
        let snapshot = try SpaceCompositionExportSnapshot.capture(from: composition, rootUUID: root.uuid)
        XCTAssertEqual(snapshot.sections.map(\.title), ["Book", "First", "Last"])
        XCTAssertEqual(snapshot.sections.map(\.depth), [0, 1, 1])
        XCTAssertFalse(try SpaceCompositionExportFormatter.html(snapshot).contains("Never publish"))
    }

    func testSnapshotUsesRichWritingAndDoesNotChangeWithLiveAtom() throws {
        let rich = RichDocument(blocks: [RichBlock(kind: .paragraph, inlines: [.text("Original", marks: [.bold])])])
        var atom = try page("Chapter")
        atom.body = "Stale plain text"
        atom.metadata = RichDocumentMetadataStorage.writeDocument(rich, into: atom.metadata, key: RichDocumentMetadataKeys.bodyDocument)
        let composition = try SpaceCompositionSnapshot(spaceID: "space", atoms: [atom])
        let snapshot = try SpaceCompositionExportSnapshot.capture(from: composition, rootUUID: atom.uuid)
        atom.body = "Changed after preview opened"
        XCTAssertEqual(snapshot.sections.first?.document, rich)
        XCTAssertTrue(try SpaceCompositionExportFormatter.markdown(snapshot).contains("**Original**"))
        XCTAssertFalse(try SpaceCompositionExportFormatter.markdown(snapshot).contains("Stale"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(SpaceCompositionExportSnapshot.self, from: snapshot.encoded())
        XCTAssertEqual(restored.sections, snapshot.sections)
        XCTAssertEqual(restored.id, snapshot.id)
    }

    func testFoldedBlocksAndElementChildrenSurviveExport() throws {
        let heading = RichBlock(kind: .heading2, inlines: [.text("Folded")],
            heading: RichHeadingMetadata(isCollapsed: true, collapsedBlocks: [.paragraph("Hidden evidence")], isCollapsible: true))
        let toggle = RichBlock(kind: .toggle, inlines: [.text("Answer")], children: [.paragraph("Hidden answer")], toggleCollapsed: true)
        let section = RichBlock.section(title: "Exercise", children: [.paragraph("Practice here")])
        let snapshot = fixture([heading, toggle, section])
        for exported in [try SpaceCompositionExportFormatter.markdown(snapshot), try SpaceCompositionExportFormatter.html(snapshot)] {
            XCTAssertTrue(exported.contains("Hidden evidence"))
            XCTAssertTrue(exported.contains("Hidden answer"))
            XCTAssertTrue(exported.contains("Practice here"))
        }
    }

    func testHTMLNeverRunsInjectedMarkupOrUnsafeLinks() throws {
        let bad = RichInlineNode(kind: .text, text: "Unsafe", href: "javascript:alert(1)")
        let good = RichInlineNode(kind: .text, text: "Good", marks: [.bold], href: "https://example.com/?a=1&b=2")
        let snapshot = fixture([.paragraph("<script>alert('x')</script>"), RichBlock(kind: .paragraph, inlines: [bad, good])])
        let html = try SpaceCompositionExportFormatter.html(snapshot)
        XCTAssertFalse(html.contains("<script>"))
        XCTAssertFalse(html.contains("javascript:"))
        XCTAssertTrue(html.contains("&lt;script&gt;"))
        XCTAssertTrue(html.contains("https://example.com/?a=1&amp;b=2"))
        XCTAssertTrue(html.contains("default-src 'none'"))
        XCTAssertTrue(html.contains("<b>Good</b>"))
    }

    func testMarkdownEscapesAuthoredSyntaxAndPreservesCodeFence() throws {
        let snapshot = fixture([.paragraph("*literal* [text] <tag>"), RichBlock(kind: .code, inlines: [.text("```\nactual code\n```")])])
        let markdown = try SpaceCompositionExportFormatter.markdown(snapshot)
        XCTAssertTrue(markdown.contains("\\*literal\\*"))
        XCTAssertTrue(markdown.contains("\\<tag\\>"))
        XCTAssertTrue(markdown.contains("````\n```\nactual code\n```\n````"))
    }

    func testUnknownBlocksAndMissingImagesFailRatherThanDisappear() throws {
        var unknown = RichBlock.paragraph("Visible fallback")
        unknown.rawKind = "future-diagram"
        XCTAssertThrowsError(try SpaceCompositionExportFormatter.html(fixture([unknown])))
        let image = RichImageReference(path: "/missing/image.png", width: 10, height: 10)
        XCTAssertThrowsError(try SpaceCompositionExportFormatter.markdown(fixture([RichBlock(kind: .image, inlines: [.image(image)])])))
    }

    func testFilenameCannotIntroducePathComponents() {
        let name = SpaceCompositionExportFormatter.filename(title: "../../Book:\nCourse/Guide", format: .word)
        XCTAssertFalse(name.contains("/"))
        XCTAssertFalse(name.contains(":"))
        XCTAssertFalse(name.contains("\n"))
        XCTAssertTrue(name.hasSuffix(".docx"))
        XCTAssertEqual(SpaceCompositionExportFormatter.filename(title: " ... ", format: .pdf), "Untitled.pdf")
    }

    func testArchiveRetainsExactOutputAndRemovesFailedSaveReceipt() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SpaceExportTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = directory.appendingPathComponent("archive")
        let destination = directory.appendingPathComponent("book.md")
        let snapshot = fixture([.paragraph("Exact version")])
        let bytes = Data(try SpaceCompositionExportFormatter.markdown(snapshot).utf8)
        try SpaceCompositionExportArchive.write(data: bytes, format: .markdown, snapshot: snapshot, to: destination, archiveDirectory: archive)
        let entries = try FileManager.default.contentsOfDirectory(at: archive, includingPropertiesForKeys: nil)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(try Data(contentsOf: destination), bytes)
        XCTAssertEqual(try Data(contentsOf: entries[0].appendingPathComponent("output.md")), bytes)
        XCTAssertTrue(FileManager.default.fileExists(atPath: entries[0].appendingPathComponent("snapshot.json").path))
        XCTAssertThrowsError(try SpaceCompositionExportArchive.write(data: bytes, format: .markdown, snapshot: snapshot,
            to: directory.appendingPathComponent("missing/book.md"), archiveDirectory: archive))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(at: archive, includingPropertiesForKeys: nil).count, 1)
    }

    @MainActor func testNativePDFPaginatesLongWorkWithoutLosingFirstOrLastParagraph() async throws {
        let blocks = (0..<150).map { RichBlock.paragraph("Paragraph \($0): " + String(repeating: "A thoughtful manuscript keeps every sentence. ", count: 7)) }
        let snapshot = fixture(blocks)
        let data = try await SpaceCompositionExportRenderer.pdf(snapshot)
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertGreaterThan(pdf.pageCount, 2)
        try saveProof(data, name: "paginated-manuscript.pdf")
        let text = pdf.string ?? ""
        XCTAssertTrue(text.contains("Paragraph 0:"))
        XCTAssertTrue(text.contains("Paragraph 149:"))
        for index in 0..<150 { XCTAssertTrue(text.contains("Paragraph \(index):"), "Missing paragraph \(index)") }
    }

    @MainActor func testNativeWordRoundTripKeepsFormattingAndTableText() async throws {
        var table = RichTable()
        table.rows[0].cells[0].inlines = [.text("Cell content", marks: [.bold])]
        let snapshot = fixture([RichBlock(kind: .paragraph, inlines: [.text("Styled words", marks: [.bold, .italic])]), .table(table)])
        let data = try await SpaceCompositionExportRenderer.data(for: snapshot, format: .word)
        try saveProof(data, name: "editable-manuscript.docx")
        XCTAssertEqual(Array(data.prefix(2)), [0x50, 0x4B], "DOCX must be an actual OpenXML package")
        let restored = try NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.officeOpenXML], documentAttributes: nil)
        XCTAssertTrue(restored.string.contains("Styled words"))
        XCTAssertTrue(restored.string.contains("Cell content"))
        let range = (restored.string as NSString).range(of: "Styled words")
        let font = try XCTUnwrap(restored.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(NSFontManager.shared.traits(of: font).contains(.boldFontMask))
        XCTAssertTrue(NSFontManager.shared.traits(of: font).contains(.italicFontMask))
    }

    @MainActor func testPreparedImagesRemainAvailableAfterOriginalFileDisappears() async throws {
        let image = NSImage(size: NSSize(width: 32, height: 24), flipped: false) { rect in
            NSColor.systemGreen.setFill()
            rect.fill()
            return true
        }
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        try png.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let reference = RichImageReference(path: url.path, width: 32, height: 24)
        let snapshot = try await SpaceCompositionExportRenderer.prepare(fixture([RichBlock(kind: .image, inlines: [.image(reference)])]))
        try FileManager.default.removeItem(at: url)
        XCTAssertEqual(snapshot.assets.count, 1)
        XCTAssertTrue(try SpaceCompositionExportFormatter.html(snapshot).contains("data:image/png;base64,"))
        XCTAssertTrue(try SpaceCompositionExportFormatter.html(snapshot).contains("width=\"32\""))
        let bytes = try await SpaceCompositionExportRenderer.data(for: snapshot, format: .word)
        try saveProof(bytes, name: "image-manuscript.docx")
        let document = try XMLDocument(data: zipEntry("word/document.xml", in: bytes), options: [])
        XCTAssertEqual(try document.nodes(forXPath: "//*[local-name()='blip']").count, 1)
        let embedded = try zipEntry("word/media/image1.png", in: bytes)
        XCTAssertEqual(embedded, snapshot.assets.values.first?.data, "Word must contain the exact frozen image bytes")
        let relationships = String(decoding: try zipEntry("word/_rels/document.xml.rels", in: bytes), as: UTF8.self)
        XCTAssertTrue(relationships.contains("Target=\"media/image1.png\""))
    }

    @MainActor func testMergedTableStructureSurvivesHTMLWordAndPDF() async throws {
        var table = RichTable()
        let anchor = table.rows[0].cells[0].id
        table.rows[0].cells[0].inlines = [.text("A complete approach", marks: [.bold])]
        table.rows[0].cells[0].colSpan = 2
        table.rows[0].cells[1] = .covered(by: anchor)
        table.rows[1].cells[0].inlines = [.text("Collect what matters")]
        table.rows[1].cells[1].inlines = [.text("Make it your own")]
        let snapshot = fixture([
            .paragraph("A thoughtful practice begins with a question worth following."),
            .table(table),
            RichBlock(kind: .quote, inlines: [.text("The purpose of a collection is the thinking it makes possible.", marks: [.italic])]),
            RichBlock(kind: .checklist, inlines: [.text("Choose one idea to explore today")], checked: false)
        ])
        let html = try SpaceCompositionExportFormatter.html(snapshot)
        XCTAssertTrue(html.contains("colspan=\"2\""))
        let word = try await SpaceCompositionExportRenderer.data(for: snapshot, format: .word)
        try saveProof(word, name: "mixed-reading-copy.docx")
        let document = try XMLDocument(data: zipEntry("word/document.xml", in: word), options: [])
        XCTAssertEqual(try document.nodes(forXPath: "//*[local-name()='tbl']").count, 1)
        let spans = try document.nodes(forXPath: "//*[local-name()='gridSpan']").compactMap { ($0 as? XMLElement)?.attribute(forName: "w:val")?.stringValue }
        XCTAssertTrue(spans.contains("2"), "The Word package must retain the merged cell, not flatten it to text")
        let pdfData = try await SpaceCompositionExportRenderer.pdf(snapshot)
        let pdf = try XCTUnwrap(PDFDocument(data: pdfData))
        XCTAssertTrue(pdf.string?.contains("Make it your own") == true)
        try saveProof(pdfData, name: "mixed-reading-copy.pdf")
        try saveProof(Data(html.utf8), name: "mixed-reading-copy.html")
        if let page = pdf.page(at: 0), let tiff = page.thumbnail(of: NSSize(width: 900, height: 1273), for: .mediaBox).tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try saveProof(png, name: "mixed-reading-copy.png")
        }
    }

    private func saveProof(_ data: Data, name: String) throws {
        guard let path = ProcessInfo.processInfo.environment["COSMO_SPACE_EXPORT_PROOF_DIR"] else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent(name), options: .atomic)
    }

    /// Use an independent ZIP reader to check the actual OpenXML package. The
    /// AppKit DOCX importer flattens tables/images, so it cannot validate fidelity.
    private func zipEntry(_ entry: String, in data: Data) throws -> Data {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".docx")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", url.path, entry]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        let content = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "The exported Word package must be a readable ZIP archive")
        return content
    }

    private func fixture(_ blocks: [RichBlock]) -> SpaceCompositionExportSnapshot {
        .init(spaceID: "space", rootUUID: "book", title: "The Book", capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
              sections: [.init(id: "book", title: "The Book", depth: 0, document: RichDocument(blocks: blocks))])
    }

    private func page(_ title: String, kind: SpaceCompositionKind = .page, parent: String? = nil,
                      order: Double = 0, included: Bool = true) throws -> Atom {
        try Atom.new(type: .note, title: title, body: "Writing in \(title)")
            .replacingSpaceComposition(.init(kind: kind, parentUUID: parent, sortOrder: order, includeInExport: included))
    }
}
