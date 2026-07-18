import XCTest
@testable import CosmoOS

final class FilePortalMetadataTests: XCTestCase {

    // MARK: - Lenient decode

    func testUnknownPortalKindDegradesToGeneric() throws {
        let json = """
        {"attachmentUUID":"abc","originalFilename":"a.dwg","fileExtension":"dwg","portalKind":"cad_drawing_from_the_future"}
        """
        let decoded = try JSONDecoder().decode(FilePortalMetadata.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.portalKind, .generic)
        XCTAssertEqual(decoded.attachmentUUID, "abc")
    }

    func testMissingFieldsDecodeToSafeDefaults() throws {
        let decoded = try JSONDecoder().decode(FilePortalMetadata.self, from: Data("{}".utf8))
        XCTAssertEqual(decoded.attachmentUUID, "")
        XCTAssertEqual(decoded.originalFilename, "")
        XCTAssertEqual(decoded.portalKind, .generic)
        XCTAssertNil(decoded.pageCount)
        XCTAssertNil(decoded.currentPage)
    }

    func testRoundTripPreservesAllFields() throws {
        let original = FilePortalMetadata(
            attachmentUUID: "att-1",
            originalFilename: "Budget 2026.xlsx",
            fileExtension: "xlsx",
            byteSize: 12_345,
            portalKind: .spreadsheet,
            pageCount: nil,
            sheetNames: ["Q1", "Q2"],
            currentPage: nil,
            currentSheetIndex: 1,
            thumbStamp: "2026-07-18T00:00:00Z"
        )
        let decoded = try JSONDecoder().decode(
            FilePortalMetadata.self,
            from: JSONEncoder().encode(original)
        )
        XCTAssertEqual(decoded, original)
    }

    // MARK: - Kind detection

    func testKindDetectionByExtension() {
        XCTAssertEqual(FilePortalMetadata.Kind.detect(fileExtension: "pdf"), .pdf)
        XCTAssertEqual(FilePortalMetadata.Kind.detect(fileExtension: "PDF"), .pdf)
        XCTAssertEqual(FilePortalMetadata.Kind.detect(fileExtension: "xlsx"), .spreadsheet)
        XCTAssertEqual(FilePortalMetadata.Kind.detect(fileExtension: "xls"), .spreadsheet)
        XCTAssertEqual(FilePortalMetadata.Kind.detect(fileExtension: "csv"), .csv)
        XCTAssertEqual(FilePortalMetadata.Kind.detect(fileExtension: "tsv"), .csv)
        XCTAssertEqual(FilePortalMetadata.Kind.detect(fileExtension: "docx"), .generic)
        XCTAssertEqual(FilePortalMetadata.Kind.detect(fileExtension: ""), .generic)
    }

    // MARK: - Merge-not-replace on the atom column

    func testMergingFilePortalMetadataPreservesSiblingKeys() throws {
        var atom = Atom.new(type: .file, title: "Report", body: "Report.pdf")
        atom.metadata = #"{"someOtherWriterKey":"must-survive","tags":["finance"]}"#

        let portal = FilePortalMetadata(
            attachmentUUID: "att-2",
            originalFilename: "Report.pdf",
            fileExtension: "pdf",
            portalKind: .pdf,
            pageCount: 9
        )
        let merged = atom.mergingFilePortalMetadata(portal)

        let dict = try XCTUnwrap(merged.metadataDict)
        XCTAssertEqual(dict["someOtherWriterKey"] as? String, "must-survive")
        XCTAssertEqual(dict["tags"] as? [String], ["finance"])
        XCTAssertEqual(merged.filePortalMetadata?.attachmentUUID, "att-2")
        XCTAssertEqual(merged.filePortalMetadata?.pageCount, 9)
    }

    func testViewStateUpdateReplacesOnlyThePortalKey() throws {
        var atom = Atom.new(type: .file, title: "Report", body: "Report.pdf")
        atom.metadata = #"{"unrelated":true}"#
        atom = atom.mergingFilePortalMetadata(FilePortalMetadata(
            attachmentUUID: "att-3",
            originalFilename: "Report.pdf",
            fileExtension: "pdf",
            portalKind: .pdf,
            pageCount: 4
        ))

        var updated = try XCTUnwrap(atom.filePortalMetadata)
        updated.currentPage = 2
        atom = atom.mergingFilePortalMetadata(updated)

        let roundTripped = try XCTUnwrap(atom.filePortalMetadata)
        XCTAssertEqual(roundTripped.currentPage, 2)
        XCTAssertEqual(roundTripped.pageCount, 4)
        XCTAssertEqual(atom.metadataDict?["unrelated"] as? Bool, true)
    }

    func testEnvelopeDecodeToleratesForeignMetadataShapes() {
        var atom = Atom.new(type: .file, title: "X", body: "x.bin")
        atom.metadata = #"{"filePortal":"not-an-object"}"#
        XCTAssertNil(atom.filePortalMetadata)
    }
}
