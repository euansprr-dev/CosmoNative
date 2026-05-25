import XCTest
@testable import CosmoOS

final class ContentFocusPersistenceRegressionTests: XCTestCase {
    func testPolishHighlightsAreOnlyEnabledDuringPolishStep() throws {
        XCTAssertFalse(ContentStep.brainstorm.enablesPolishHighlights)
        XCTAssertFalse(ContentStep.draft.enablesPolishHighlights)
        XCTAssertTrue(ContentStep.polish.enablesPolishHighlights)
    }

    func testContentFocusEditorHighlightsFollowCurrentStep() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let packageRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let focusViewURL = packageRoot.appendingPathComponent("UI/FocusMode/Content/ContentFocusModeView.swift")
        let source = try String(contentsOf: focusViewURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("polishHighlights: viewModel.state.currentStep.enablesPolishHighlights ? polishAnalysis : nil"),
            "The content editor must clear polish highlights as soon as the user returns to Draft."
        )
    }

    func testAsyncContentFocusWriteRechecksFreshnessInsideDatabaseTransaction() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let packageRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let focusViewURL = packageRoot.appendingPathComponent("UI/FocusMode/Content/ContentFocusModeView.swift")
        let source = try String(contentsOf: focusViewURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("ContentFocusWritePolicy.allowsWrite"),
            "Content Focus async writes must validate snapshot freshness inside the DB transaction so stale snapshots cannot overwrite newer draft saves."
        )
    }

    func testContentFocusWritePolicyRejectsSnapshotOlderThanPersistedState() throws {
        let newerDate = Date(timeIntervalSince1970: 2_000)
        let staleDate = Date(timeIntervalSince1970: 1_000)
        let metadata = #"{"lastModifiedUnix":2000}"#

        XCTAssertFalse(ContentFocusWritePolicy.allowsWrite(
            existingMetadata: metadata,
            snapshotLastModified: staleDate
        ))
        XCTAssertTrue(ContentFocusWritePolicy.allowsWrite(
            existingMetadata: metadata,
            snapshotLastModified: newerDate
        ))
    }

    func testContentFocusStatePersistsSubsecondModifiedTimestamp() throws {
        var state = ContentFocusModeState(atomUUID: "content-1")
        state.draftContent = "Draft that must survive"
        state.lastModified = Date(timeIntervalSince1970: 1_000.25)

        let fields = state.toAtomFields(existingMetadata: nil)
        let metadata = try XCTUnwrap(fields.metadata)
        let data = try XCTUnwrap(metadata.data(using: .utf8))
        let dict = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        let timestamp = try XCTUnwrap(dict["lastModifiedUnix"] as? Double)
        XCTAssertEqual(timestamp, 1_000.25, accuracy: 0.000001)
    }
}
