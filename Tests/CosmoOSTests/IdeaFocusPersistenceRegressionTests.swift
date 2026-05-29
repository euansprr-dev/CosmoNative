import XCTest
@testable import CosmoOS

final class IdeaFocusPersistenceRegressionTests: XCTestCase {
    func testOutlineSlideNoteEditsScheduleAutoSave() throws {
        let source = try ideaFocusViewSource()

        XCTAssertTrue(
            source.contains("viewModel.updateOutlineSlideNote(slideId: slideId, note: newValue)"),
            "Outline slide note edits must go through the view model so every keystroke refreshes the autosave snapshot."
        )
    }

    func testIdeaFocusAsyncWritesRecheckFreshnessInsideDatabaseTransaction() throws {
        let source = try ideaFocusViewModelSource()

        XCTAssertTrue(
            source.contains("IdeaFocusWritePolicy.allowsWrite"),
            "Idea Focus writes must validate snapshot freshness inside the DB transaction so stale autosaves cannot overwrite newer close saves."
        )
    }

    func testIdeaFocusWritePolicyRejectsSnapshotOlderThanPersistedState() throws {
        let newerDate = Date(timeIntervalSince1970: 2_000)
        let staleDate = Date(timeIntervalSince1970: 1_000)
        let metadata = #"{"lastModifiedUnix":2000}"#

        XCTAssertFalse(IdeaFocusWritePolicy.allowsWrite(
            existingMetadata: metadata,
            snapshotLastModified: staleDate
        ))
        XCTAssertTrue(IdeaFocusWritePolicy.allowsWrite(
            existingMetadata: metadata,
            snapshotLastModified: newerDate
        ))
    }

    private func ideaFocusViewSource() throws -> String {
        try String(
            contentsOf: repositoryRoot().appendingPathComponent("UI/FocusMode/Ideas/IdeaFocusModeView.swift"),
            encoding: .utf8
        )
    }

    private func ideaFocusViewModelSource() throws -> String {
        try String(
            contentsOf: repositoryRoot().appendingPathComponent("UI/FocusMode/Ideas/IdeaFocusModeViewModel.swift"),
            encoding: .utf8
        )
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
